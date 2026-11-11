#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v

if ! ip netns exec v iptables -C OUTPUT -j VPN_GUARD_OUT >/dev/null 2>&1; then
  echo "[ERROR] Kill Switch chưa bật. Chạy sudo ./scripts/enable-vpn.sh trước."; exit 1
fi

restore() {
  ip -n v link set wg0 up 2>/dev/null || true
  ip -n v route replace "$WG_SERVER_IP/32" dev wg0 2>/dev/null || true
}
trap restore EXIT INT TERM

echo "[*] Kiểm tra bằng một gói UDP thử nghiệm hướng tới G (không phải dữ liệu chat)."
echo "[*] Gói thử bị firewall chặn tại V; G không nhận nội dung ứng dụng."
ip netns exec v iptables -Z VPN_GUARD_OUT
ip -n v route replace "$G_IP/32" dev eth0
ip -n v link set wg0 down

ip netns exec v python3 - "$G_IP" <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.sendto(b'KILLSWITCH-PROBE', (sys.argv[1], 9))
s.close()
PY

DROP_COUNT="$(ip netns exec v iptables -nvxL VPN_GUARD_OUT | awk '$3 == "DROP" {print $1; exit}')"
restore
trap - EXIT INT TERM

if [[ "${DROP_COUNT:-0}" =~ ^[0-9]+$ ]] && (( DROP_COUNT > 0 )); then
  echo "[PASS] Kill Switch chặn gói đi trực tiếp qua eth0 (DROP counter=$DROP_COUNT)."
  echo "[✓] wg0 và route tới $WG_SERVER_IP đã được khôi phục."
else
  echo "[FAIL] Không thấy bộ đếm DROP tăng. Kiểm tra lại firewall."; exit 1
fi
