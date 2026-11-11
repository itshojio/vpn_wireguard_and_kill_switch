#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns vpn
ip -n vpn addr show dev wg0 | grep -Fq "$WG_SERVER_IP/24" || {
  echo "[ERROR] vpn/wg0 chưa có địa chỉ $WG_SERVER_IP/24. Kiểm tra cài đặt WireGuard." >&2
  exit 1
}
exec ip netns exec vpn python3 -u "$ROOT_DIR/scripts/vpn-chat-server.py"
