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

# Xoa cache ARP bi anh huong tai V
if ip netns list | awk '{print $1}' | grep -qx v; then
    ip -n v neigh del "$G_IP" dev eth0 2>/dev/null || true
fi

# Xoa cache ARP bi anh huong tai G
if ip netns list | awk '{print $1}' | grep -qx g; then
    ip -n g neigh del "$V_IP" dev eth0 2>/dev/null || true
fi

echo "[✓] Da dung MITM helper."
echo "[✓] Da xoa cache ARP lien quan tren V va G."