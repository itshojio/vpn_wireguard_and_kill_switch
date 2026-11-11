#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns a

echo "[*] Bắt gói WireGuard UDP/$WG_PORT trên A. Nhấn Ctrl+C để dừng."
echo "    A nằm trên LAN V-G; VPN Server ở WAN riêng."
ip netns exec a tcpdump -X -s 0 -ni eth0 "udp port $WG_PORT"
