#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

# Stop only the add-on's optional MITM helper processes in namespace A.
if [[ -f "$PID_DIR/mitm-v.pid" ]]; then
  kill "$(cat "$PID_DIR/mitm-v.pid")" 2>/dev/null || true
fi
if [[ -f "$PID_DIR/mitm-vpn.pid" ]]; then
  kill "$(cat "$PID_DIR/mitm-vpn.pid")" 2>/dev/null || true
fi
if ip netns list | awk '{print $1}' | grep -qx v; then
  ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" remove 2>/dev/null || true
  ip -n v route del "$G_IP/32" dev wg0 2>/dev/null || true
  ip -n v route del "$VPN_IP/32" dev eth0 2>/dev/null || true
  ip -n v link del wg0 2>/dev/null || true
fi

if ip netns list | awk '{print $1}' | grep -qx g; then
  ip -n g route del "$WG_NET" via "$VPN_IP" 2>/dev/null || true
fi

if ip netns list | awk '{print $1}' | grep -qx vpn; then
  ip netns del vpn
fi
ip link del br-vpn 2>/dev/null || true

rm -rf "$KEY_DIR" "$PID_DIR"

echo "[✓] Đã gỡ riêng add-on WireGuard."
echo "[✓] Namespace v, a, g và bridge br-lab vẫn được giữ nguyên."
echo "[✓] HTTP server trên G không bị dừng."
