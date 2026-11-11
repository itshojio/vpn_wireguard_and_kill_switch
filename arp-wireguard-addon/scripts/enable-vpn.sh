#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v
require_ns g
require_ns vpn

ip -n v link show wg0 >/dev/null
ip -n g link show eth1 >/dev/null
ip -n vpn link show wg0 >/dev/null
ip -n v route replace "$VPN_IP/32" via "$G_IP" dev eth0
ip -n v route replace "$G_IP/32" dev wg0
ip -n g route replace "$WG_NET" via "$VPN_IP" dev eth1
ip -n vpn route replace "$LAN_NET" via "$ROUTER_WAN_IP" dev eth0

ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" install \
  --server-ip "$VPN_IP" --port "$WG_PORT"

echo "[✓] Đã bật route VPN và Kill Switch trên V."
echo "[*] Tạo lưu lượng để kích hoạt WireGuard handshake:"
echo "    sudo ./scripts/test-http.sh"
