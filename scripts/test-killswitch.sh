#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v

if ! ip netns exec v iptables -C OUTPUT -j VPN_GUARD_OUT >/dev/null 2>&1; then
  echo "[ERROR] Kill Switch chưa bật. Chạy sudo ./scripts/enable-vpn.sh trước."
  exit 1
fi

echo "[*] Tạm hạ wg0, ép route HTTP đi eth0 để kiểm tra Kill Switch..."
ip -n v link set wg0 down
ip -n v route replace "$G_IP/32" dev eth0

set +e
ip netns exec v curl -fsS --max-time 3 "http://$G_IP:8080/" >/tmp/arp-wg-killswitch.out 2>&1
result=$?
set -e

ip -n v route replace "$G_IP/32" dev wg0
ip -n v link set wg0 up

if [[ "$result" -eq 0 ]]; then
  echo "[FAIL] Kết nối trực tiếp vẫn thành công. Cần kiểm tra firewall."
  cat /tmp/arp-wg-killswitch.out || true
  exit 1
fi

echo "[PASS] Kill Switch đã chặn kết nối trực tiếp khi VPN ngắt."
echo "[*] wg0 và route qua tunnel đã được khôi phục."
