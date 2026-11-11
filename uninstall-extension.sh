#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

echo "[*] Dung cac tien trinh MITM cua add-on..."

for f in "$PID_DIR/mitm-v.pid" "$PID_DIR/mitm-vpn.pid"; do
    if [[ -f "$f" ]]; then
        kill "$(cat "$f")" 2>/dev/null || true
        rm -f "$f"
    fi
done

echo "[*] Go cau hinh tren V..."

if ip netns list | awk '{print $1}' | grep -qx v; then
    ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" remove \
        2>/dev/null || true

    # Route thu nghiem qua WireGuard
    ip -n v route del "$G_IP/32" dev wg0 2>/dev/null || true

    # Route WAN moi den VPN Server
    ip -n v route del "$VPN_IP/32" via "$G_IP" dev eth0 \
        2>/dev/null || true

    # Route endpoint cu theo cau hinh truoc day
    ip -n v route del "$VPN_IP/32" dev eth0 2>/dev/null || true
    ip -n v route del "192.168.77.2/32" dev eth0 \
        2>/dev/null || true

    # Xoa WireGuard interface tren V
    ip -n v link del wg0 2>/dev/null || true

    # Xoa cache ARP lien quan
    ip -n v neigh del "$G_IP" dev eth0 2>/dev/null || true
fi

echo "[*] Go route tren G..."

if ip netns list | awk '{print $1}' | grep -qx g; then
    # Route WAN moi
    ip -n g route del "$WG_NET" via "$VPN_IP" \
        dev "$ROUTER_WAN_IF" 2>/dev/null || true

    # Route cu qua VPN Server 192.168.77.2
    ip -n g route del "$WG_NET" via 192.168.77.2 \
        2>/dev/null || true

    # Xoa interface WAN do add-on tao, neu dung dia chi WAN cua add-on
    if ip -n g -4 -o addr show dev "$ROUTER_WAN_IF" \
        2>/dev/null | grep -Fq "$ROUTER_WAN_IP/30"; then
        ip -n g link del "$ROUTER_WAN_IF" 2>/dev/null || true
    fi

    ip -n g neigh del "$V_IP" dev eth0 2>/dev/null || true
fi

echo "[*] Xoa namespace VPN Server..."

if ip netns list | awk '{print $1}' | grep -qx vpn; then
    ip netns del vpn
fi

# Don cong br-vpn cu neu con ton tai
ip link del br-vpn 2>/dev/null || true

echo "[*] Xoa khoa va PID cua add-on..."
rm -rf "$KEY_DIR" "$PID_DIR"

echo
echo "[✓] Da go add-on WireGuard."
echo "[✓] Namespace v, a, g van duoc giu nguyen."
echo "[✓] Bridge br-lab van duoc giu nguyen."
echo "[✓] HTTP server tren G khong bi dung."