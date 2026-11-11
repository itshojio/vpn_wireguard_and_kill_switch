#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v
ip -n v route get "$WG_SERVER_IP" | grep -q 'dev wg0' || {
  echo "[ERROR] Route tới $WG_SERVER_IP chưa đi qua wg0. Chạy enable-vpn.sh trước." >&2
  exit 1
}
exec ip netns exec v python3 -u "$ROOT_DIR/scripts/vpn-chat-client.py"
