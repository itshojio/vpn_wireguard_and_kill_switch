#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

for f in "$PID_DIR/mitm-v.pid" "$PID_DIR/mitm-vpn.pid"; do
  if [[ -f "$f" ]]; then
    kill "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
  fi
done

for ns in v vpn; do
  if ip netns list | awk '{print $1}' | grep -qx "$ns"; then
    ip netns exec "$ns" ip neigh flush dev eth0 2>/dev/null || true
  fi
done

echo "[✓] Đã dừng MITM helper của add-on."
