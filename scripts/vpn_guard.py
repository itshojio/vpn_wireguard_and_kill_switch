#!/usr/bin/env python3
"""IPv4 WireGuard Kill Switch plus IPv6 fail-closed rules for namespace v."""
import argparse
import subprocess
import sys
import time

OUT_CHAIN = "VPN_GUARD_OUT"
IN_CHAIN = "VPN_GUARD_IN"
OUT6_CHAIN = "VPN_GUARD6_OUT"
IN6_CHAIN = "VPN_GUARD6_IN"


def run(args, check=True, capture=False):
    return subprocess.run(
        args, check=check, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def exists(tool, chain):
    return run([tool, "-S", chain], check=False, capture=True).returncode == 0


def ensure_chain(tool, chain):
    if not exists(tool, chain):
        run([tool, "-N", chain])
    run([tool, "-F", chain])


def ensure_jump(tool, parent, chain):
    if run([tool, "-C", parent, "-j", chain], check=False).returncode:
        run([tool, "-I", parent, "1", "-j", chain])


def remove_jump(tool, parent, chain):
    while run([tool, "-D", parent, "-j", chain], check=False).returncode == 0:
        pass


def install(server_ip, port):
    ensure_chain("iptables", OUT_CHAIN)
    ensure_chain("iptables", IN_CHAIN)
    out_rules = [
        ["-o", "lo", "-j", "ACCEPT"],
        ["-o", "wg0", "-j", "ACCEPT"],
        ["-o", "eth0", "-d", server_ip, "-p", "udp", "--dport", str(port), "-j", "ACCEPT"],
        ["-j", "DROP"],
    ]
    for rule in out_rules:
        run(["iptables", "-A", OUT_CHAIN] + rule)

    in_rules = [
        ["-i", "lo", "-j", "ACCEPT"],
        ["-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"],
        ["-i", "wg0", "-j", "ACCEPT"],
        ["-i", "eth0", "-s", server_ip, "-p", "udp", "--sport", str(port), "-j", "ACCEPT"],
        ["-j", "DROP"],
    ]
    for rule in in_rules:
        run(["iptables", "-A", IN_CHAIN] + rule)
    ensure_jump("iptables", "OUTPUT", OUT_CHAIN)
    ensure_jump("iptables", "INPUT", IN_CHAIN)

    # This lab uses IPv4 only. Block all IPv6 in V so applications cannot bypass the tunnel.
    ensure_chain("ip6tables", OUT6_CHAIN)
    ensure_chain("ip6tables", IN6_CHAIN)
    run(["ip6tables", "-A", OUT6_CHAIN, "-o", "lo", "-j", "ACCEPT"])
    run(["ip6tables", "-A", OUT6_CHAIN, "-j", "DROP"])
    run(["ip6tables", "-A", IN6_CHAIN, "-i", "lo", "-j", "ACCEPT"])
    run(["ip6tables", "-A", IN6_CHAIN, "-j", "DROP"])
    ensure_jump("ip6tables", "OUTPUT", OUT6_CHAIN)
    ensure_jump("ip6tables", "INPUT", IN6_CHAIN)
    print("[OK] Kill Switch installed: IPv4 direct egress blocked; IPv6 blocked in V.")


def remove():
    for tool, parent, chain in (
        ("iptables", "OUTPUT", OUT_CHAIN), ("iptables", "INPUT", IN_CHAIN),
        ("ip6tables", "OUTPUT", OUT6_CHAIN), ("ip6tables", "INPUT", IN6_CHAIN),
    ):
        remove_jump(tool, parent, chain)
        if exists(tool, chain):
            run([tool, "-F", chain], check=False)
            run([tool, "-X", chain], check=False)
    print("[OK] Kill Switch removed.")


def handshake():
    r = run(["wg", "show", "wg0", "latest-handshakes"], check=False, capture=True)
    if r.returncode:
        return "WireGuard interface/status unavailable"
    stamps = []
    for line in r.stdout.splitlines():
        try:
            stamps.append(int(line.split()[-1]))
        except (ValueError, IndexError):
            pass
    if not stamps or max(stamps) == 0:
        return "Handshake: not received yet"
    age = max(0, int(time.time()) - max(stamps))
    return "Handshake: {} seconds ago{}".format(age, " (active)" if age <= 180 else " (stale)")


def status():
    checks = [
        ("IPv4 OUTPUT", "iptables", "OUTPUT", OUT_CHAIN),
        ("IPv4 INPUT", "iptables", "INPUT", IN_CHAIN),
        ("IPv6 OUTPUT", "ip6tables", "OUTPUT", OUT6_CHAIN),
        ("IPv6 INPUT", "ip6tables", "INPUT", IN6_CHAIN),
    ]
    print(handshake())
    for label, tool, parent, chain in checks:
        active = run([tool, "-C", parent, "-j", chain], check=False).returncode == 0
        print("Kill Switch {}: {}".format(label, "INSTALLED" if active else "NOT INSTALLED"))


def watch(interval):
    print("Theo dõi WireGuard; Ctrl+C để dừng. Kill Switch vẫn được giữ.")
    try:
        while True:
            print(time.strftime("%H:%M:%S"), handshake(), flush=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\nĐã dừng theo dõi.")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("install")
    p.add_argument("--server-ip", required=True)
    p.add_argument("--port", type=int, required=True)
    sub.add_parser("remove")
    sub.add_parser("status")
    p = sub.add_parser("watch")
    p.add_argument("--interval", type=float, default=2.0)
    args = parser.parse_args()
    try:
        if args.cmd == "install":
            install(args.server_ip, args.port)
        elif args.cmd == "remove":
            remove()
        elif args.cmd == "status":
            status()
        else:
            watch(max(0.5, args.interval))
    except FileNotFoundError as exc:
        print("[ERROR] Thiếu công cụ: {}".format(exc), file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as exc:
        print("[ERROR] Lệnh thất bại: {}".format(exc), file=sys.stderr)
        if exc.stderr:
            print(exc.stderr, file=sys.stderr)
        sys.exit(exc.returncode or 1)


if __name__ == "__main__":
    main()
