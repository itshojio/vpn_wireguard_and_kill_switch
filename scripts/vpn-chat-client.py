#!/usr/bin/env python3
"""Interactive Victim chat client; TCP traffic is routed through wg0."""
import argparse
import socket
import threading


def receive_messages(conn: socket.socket) -> None:
    buffer = bytearray()
    while True:
        try:
            chunk = conn.recv(4096)
        except OSError:
            break
        if not chunk:
            print("\n[INFO] VPN Server đã đóng kết nối.", flush=True)
            break
        buffer.extend(chunk)
        while b"\n" in buffer:
            raw, _, remainder = buffer.partition(b"\n")
            buffer = bytearray(remainder)
            message = raw.decode("utf-8", errors="replace")
            print(f"\n[VPN Server] {message}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Victim chat client qua WireGuard")
    parser.add_argument("--host", default="10.200.0.1", help="IP tunnel của VPN Server")
    parser.add_argument("--port", type=int, default=9000)
    args = parser.parse_args()

    try:
        with socket.create_connection((args.host, args.port), timeout=10) as conn:
            conn.settimeout(None)
            print(f"[Victim] Đã kết nối VPN Server {args.host}:{args.port}", flush=True)
            print("Nhập nội dung rồi Enter để gửi; nhập /quit để thoát.", flush=True)
            receiver = threading.Thread(target=receive_messages, args=(conn,), daemon=True)
            receiver.start()
            try:
                while True:
                    message = input("Victim> ")
                    if message == "/quit":
                        break
                    conn.sendall(message.encode("utf-8") + b"\n")
            except (EOFError, KeyboardInterrupt):
                pass
    except OSError as exc:
        raise SystemExit(f"[ERROR] Không kết nối được VPN Server: {exc}")


if __name__ == "__main__":
    main()
