#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v

ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" remove
ip -n v route del "$WG_SERVER_IP/32" dev wg0 2>/dev/null || true
ip -n v route del "$G_IP/32" dev wg0 2>/dev/null || true

echo "[✓] Đã tắt chế độ bảo vệ VPN trên V."
echo "    Route tới ứng dụng VPN Server được gỡ; namespace và WireGuard vẫn được giữ."
