#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

for ns in v a g vpn; do
  if ip netns list | awk '{print $1}' | grep -qx "$ns"; then
    echo
    echo "=== $ns ==="
    ip -n "$ns" -br addr
  else
    echo
    echo "=== $ns: chưa tồn tại ==="
  fi
done

if ip netns list | awk '{print $1}' | grep -qx v; then
  echo
  echo "=== Client WireGuard ==="
  ip netns exec v wg show || true
  echo
  echo "=== Kill Switch ==="
  ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" status || true
  echo
  echo "=== Route trên V ==="
  ip -n v route show
fi

if ip netns list | awk '{print $1}' | grep -qx vpn; then
  echo
  echo "=== Server WireGuard ==="
  ip netns exec vpn wg show || true
  echo
  echo "=== Route trên G ==="
  ip -n g route show
fi
