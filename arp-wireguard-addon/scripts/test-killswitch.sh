#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v

if ! ip netns exec v iptables -C OUTPUT -j VPN_GUARD_OUT >/dev/null 2>&1; then
  echo "[ERROR] Kill Switch chưa bật. Chạy sudo ./scripts/enable-vpn.sh trước."; exit 1
fi

# Confirm the service works through the tunnel first; otherwise a failed curl is inconclusive.
if ! ip netns exec v curl -fsS --max-time 5 "http://$G_IP:8080/" >/dev/null; then
  echo "[ERROR] HTTP qua VPN chưa hoạt động. Không thể kết luận Kill Switch chặn đúng."; exit 1
fi

restore() {
  ip -n v link set wg0 up 2>/dev/null || true
  ip -n v route replace "$G_IP/32" dev wg0 2>/dev/null || true
}
trap restore EXIT INT TERM

echo "[*] Tạm hạ wg0 và ép HTTP đi trực tiếp qua eth0..."
ip -n v route replace "$G_IP/32" dev eth0
ip -n v link set wg0 down

set +e
ip netns exec v curl -fsS --max-time 3 "http://$G_IP:8080/" >/tmp/arp-wg-killswitch.out 2>&1
result=$?
set -e

restore
trap - EXIT INT TERM
if [[ "$result" -eq 0 ]]; then
  echo "[FAIL] Kết nối trực tiếp vẫn thành công; cần kiểm tra firewall."; exit 1
fi

echo "[PASS] Kill Switch đã chặn kết nối trực tiếp khi wg0 ngắt."
echo "[*] wg0 và route qua tunnel đã được khôi phục."
