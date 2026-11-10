#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v
require_ns vpn

ip -n v link show wg0 >/dev/null
ip -n v route replace "$VPN_IP/32" dev eth0
ip -n v route replace "$G_IP/32" dev wg0

ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" install \
  --server-ip "$VPN_IP" --port "$WG_PORT"

echo "[✓] VPN route và Kill Switch đã bật trên V."
echo "[*] Tạo lưu lượng để kích hoạt handshake:"
echo "    sudo ./scripts/test-http.sh"
