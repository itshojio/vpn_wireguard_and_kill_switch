#!/usr/bin/env python3
"""Kill Switch and WireGuard status helper for namespace v."""
import argparse
import subprocess
import sys
import time

OUT_CHAIN = "VPN_GUARD_OUT"
IN_CHAIN = "VPN_GUARD_IN"


def run(args, check=True, capture=False):
    return subprocess.run(
        args, check=check, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def exists(chain):
    return run(["iptables", "-S", chain], check=False, capture=True).returncode == 0


def ensure_chain(chain):
    if not exists(chain):
        run(["iptables", "-N", chain])
    run(["iptables", "-F", chain])


def ensure_jump(parent, chain):
    if run(["iptables", "-C", parent, "-j", chain], check=False).returncode:
        run(["iptables", "-I", parent, "1", "-j", chain])


def remove_jump(parent, chain):
    while run(["iptables", "-D", parent, "-j", chain], check=False).returncode == 0:
        pass


def install(server_ip, port):
    ensure_chain(OUT_CHAIN)
    ensure_chain(IN_CHAIN)

    # Only application traffic through wg0 is allowed. The sole eth0
    # exception is the encrypted WireGuard transport to the known endpoint.
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

    ensure_jump("OUTPUT", OUT_CHAIN)
    ensure_jump("INPUT", IN_CHAIN)
    print("[OK] Kill Switch installed: direct traffic over eth0 is blocked.")


def remove():
    remove_jump("OUTPUT", OUT_CHAIN)
    remove_jump("INPUT", IN_CHAIN)
    for chain in (OUT_CHAIN, IN_CHAIN):
        if exists(chain):
            run(["iptables", "-F", chain], check=False)
            run(["iptables", "-X", chain], check=False)
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
    out_on = run(["iptables", "-C", "OUTPUT", "-j", OUT_CHAIN], check=False).returncode == 0
    in_on = run(["iptables", "-C", "INPUT", "-j", IN_CHAIN], check=False).returncode == 0
    print(handshake())
    print("Kill Switch OUTPUT:", "INSTALLED" if out_on else "NOT INSTALLED")
    print("Kill Switch INPUT: ", "INSTALLED" if in_on else "NOT INSTALLED")


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
