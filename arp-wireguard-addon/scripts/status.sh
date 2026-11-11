#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

for ns in v a g vpn; do
  echo
  echo "=== $ns ==="
  if ns_exists "$ns"; then ip -n "$ns" -br addr; else echo "chưa tồn tại"; fi
done

if ns_exists v; then
  echo; echo "=== WireGuard Client trên V ==="
  ip netns exec v wg show || true
  echo; echo "=== Kill Switch trên V ==="
  ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" status || true
  echo; echo "=== Route trên V ==="
  ip -n v route show
fi
if ns_exists a; then
  echo; echo "=== Route đến VPN endpoint trên A ==="
  ip -n a route get "$VPN_IP" 2>/dev/null || true
fi
if ns_exists g; then
  echo; echo "=== Route và forwarding trên G ==="
  ip -n g route show
  ip netns exec g sysctl net.ipv4.ip_forward
fi
if ns_exists vpn; then
  echo; echo "=== WireGuard Server trên VPN ==="
  ip netns exec vpn wg show || true
  echo; echo "=== Route và forwarding trên VPN ==="
  ip -n vpn route show
  ip netns exec vpn sysctl net.ipv4.ip_forward
fi
