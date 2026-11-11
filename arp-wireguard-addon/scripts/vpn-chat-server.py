#!/usr/bin/env python3
"""Interactive chat server bound to the VPN tunnel address."""
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
            print("\n[INFO] Victim đã ngắt kết nối.", flush=True)
            break
        buffer.extend(chunk)
        while b"\n" in buffer:
            raw, _, remainder = buffer.partition(b"\n")
            buffer = bytearray(remainder)
            message = raw.decode("utf-8", errors="replace")
            print(f"\n[Victim] {message}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="VPN Server chat qua WireGuard")
    parser.add_argument("--host", default="10.200.0.1", help="Địa chỉ bind, mặc định là IP wg0 của VPN Server")
    parser.add_argument("--port", type=int, default=9000)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((args.host, args.port))
        listener.listen(1)
        print(f"[VPN Server] Đang lắng nghe tại {args.host}:{args.port}", flush=True)
        conn, peer = listener.accept()
        with conn:
            print(f"[VPN Server] Victim đã kết nối: {peer[0]}:{peer[1]}", flush=True)
            receiver = threading.Thread(target=receive_messages, args=(conn,), daemon=True)
            receiver.start()
            try:
                while True:
                    message = input("VPN Server> ")
                    if message == "/quit":
                        break
                    conn.sendall(message.encode("utf-8") + b"\n")
            except (EOFError, KeyboardInterrupt):
                pass
            finally:
                try:
                    conn.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        print("[VPN Server] Đã đóng phiên chat.", flush=True)


if __name__ == "__main__":
    main()
