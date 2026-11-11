#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

for f in "$PID_DIR/mitm-v.pid" "$PID_DIR/mitm-g.pid"; do
  if [[ -f "$f" ]]; then
    pid="$(cat "$f" 2>/dev/null || true)"
    [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
    rm -f "$f"
  fi
done

if ns_exists a && [[ -f "$PID_DIR/a-vpn-route.before" ]]; then
  if [[ -s "$PID_DIR/a-vpn-route.before" ]]; then
    read -r -a oldroute < "$PID_DIR/a-vpn-route.before"
    ip -n a route replace "${oldroute[@]}" 2>/dev/null || true
  else
    ip -n a route del "$VPN_IP/32" via "$G_IP" dev eth0 2>/dev/null || true
  fi
fi
if ns_exists a && [[ -f "$PID_DIR/a-ip-forward.before" ]]; then
  old="$(cat "$PID_DIR/a-ip-forward.before")"
  ip netns exec a sysctl -w "net.ipv4.ip_forward=$old" >/dev/null 2>&1 || true
fi
if ns_exists a && [[ -f "$PID_DIR/a-redirects-all.before" ]]; then
  old="$(cat "$PID_DIR/a-redirects-all.before")"
  ip netns exec a sysctl -w "net.ipv4.conf.all.send_redirects=$old" >/dev/null 2>&1 || true
fi
if ns_exists a && [[ -f "$PID_DIR/a-redirects-eth0.before" ]]; then
  old="$(cat "$PID_DIR/a-redirects-eth0.before")"
  ip netns exec a sysctl -w "net.ipv4.conf.eth0.send_redirects=$old" >/dev/null 2>&1 || true
fi
rm -f "$PID_DIR/a-vpn-route.before" "$PID_DIR/a-ip-forward.before" \
  "$PID_DIR/a-redirects-all.before" "$PID_DIR/a-redirects-eth0.before"

for ns in v g; do
  if ns_exists "$ns"; then ip netns exec "$ns" ip neigh flush dev eth0 >/dev/null 2>&1 || true; fi
done

echo "[✓] Đã dừng MITM helper và khôi phục trạng thái route/forwarding của A."
