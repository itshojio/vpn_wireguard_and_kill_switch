#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v
require_ns g
require_ns vpn

for spec in "v:wg0" "g:eth1" "vpn:wg0"; do
  ns="${spec%%:*}"; dev="${spec##*:}"
  ip -n "$ns" link show "$dev" >/dev/null
done
[[ -s "$KEY_DIR/server.pub" ]] || { echo "[ERROR] Không tìm thấy server.pub trong $KEY_DIR" >&2; exit 1; }
SERVER_PUB="$(cat "$KEY_DIR/server.pub")"

# The client peer must select the VPN Server's tunnel IP, not Gateway G.
ip netns exec v wg set wg0 peer "$SERVER_PUB" allowed-ips "$WG_SERVER_IP/32"
ip -n v route replace "$VPN_IP/32" via "$G_IP" dev eth0
ip -n v route del "$G_IP/32" dev wg0 2>/dev/null || true
ip -n v route replace "$WG_SERVER_IP/32" dev wg0
# Remove the legacy route from the earlier HTTP-to-G test design, if present.
ip -n g route del "$WG_NET" via "$VPN_IP" dev eth1 2>/dev/null || true
ip -n vpn route replace "$LAN_NET" via "$ROUTER_WAN_IP" dev eth0

ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" install \
  --server-ip "$VPN_IP" --port "$WG_PORT"

echo "[✓] Route ứng dụng V -> $WG_SERVER_IP:$CHAT_PORT qua wg0 đã được thiết lập."
echo "[✓] Kill Switch đã bật trên V."
echo "[*] Chạy server trên VPN Server trước, sau đó chạy client trên V:"
echo "    sudo ./scripts/run-vpn-chat-server.sh"
echo "    sudo ./scripts/run-victim-chat.sh"
