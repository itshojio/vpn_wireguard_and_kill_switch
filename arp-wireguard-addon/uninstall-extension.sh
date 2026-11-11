#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

# Stop only the MITM helper processes and restore A's saved settings.
"$ROOT_DIR/scripts/stop-mitm-vpn.sh" 2>/dev/null || true

if ns_exists v; then
  ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" remove 2>/dev/null || true
  ip -n v route del "$WG_SERVER_IP/32" dev wg0 2>/dev/null || true
  ip -n v route del "$G_IP/32" dev wg0 2>/dev/null || true
  ip -n v route del "$VPN_IP/32" via "$G_IP" dev eth0 2>/dev/null || true
  ip -n v link del wg0 2>/dev/null || true
fi

if ns_exists g; then
  ip -n g route del "$WG_NET" via "$VPN_IP" dev eth1 2>/dev/null || true
  if [[ -f "$STATE_DIR/g-ip-forward.before" ]]; then
    old="$(cat "$STATE_DIR/g-ip-forward.before")"
    ip netns exec g sysctl -w "net.ipv4.ip_forward=$old" >/dev/null 2>&1 || true
    # eth1 is add-on-owned: installer required it to be absent before installation.
    ip -n g link del eth1 2>/dev/null || true
    ip -n g link del g-wan 2>/dev/null || true
  elif ns_exists vpn; then
    ip -n g link del eth1 2>/dev/null || true
    ip -n g link del g-wan 2>/dev/null || true
  fi
fi

if ns_exists vpn; then ip netns del vpn; fi
# Clean up only a leftover host-side endpoint from an interrupted installation.
ip link del g-wan 2>/dev/null || true
ip link del vpn-wan 2>/dev/null || true

rm -rf "$KEY_DIR" "$STATE_DIR" "$PID_DIR"
echo "[✓] Đã gỡ add-on WireGuard."
echo "[✓] Namespace v, a, g và bridge br-lab được giữ nguyên."
echo "[✓] Không có dịch vụ ứng dụng nào trên G được tạo hoặc quản lý bởi add-on."
