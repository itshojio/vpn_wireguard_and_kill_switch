#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v

if ! ip netns exec v iptables -C OUTPUT -j VPN_GUARD_OUT >/dev/null 2>&1; then
    echo "[ERROR] Kill Switch chua bat."
    echo "Chay: sudo ./scripts/enable-vpn.sh"
    exit 1
fi

echo "[*] Kiem tra HTTP qua VPN truoc khi thu nghiem..."

if ! ip netns exec v curl -fsS --max-time 5 \
    "http://$G_IP:8080/" >/dev/null; then
    echo "[ERROR] HTTP qua VPN chua hoat dong."
    echo "Hay kiem tra WireGuard va HTTP server truoc."
    exit 1
fi

restore_vpn() {
    ip -n v link set wg0 up 2>/dev/null || true
    ip -n v route replace "$G_IP/32" dev wg0 2>/dev/null || true
}

trap restore_vpn EXIT INT TERM

echo "[*] Tam ha wg0..."
ip -n v link set wg0 down

echo "[*] Chuyen thu route HTTP truc tiep qua eth0..."
ip -n v route replace "$G_IP/32" dev eth0

set +e
ip netns exec v curl -fsS --max-time 3 \
    "http://$G_IP:8080/" >/tmp/arp-wg-killswitch.out 2>&1
result=$?
set -e

if [[ "$result" -eq 0 ]]; then
    echo "[FAIL] Ket noi truc tiep van thanh cong."
    cat /tmp/arp-wg-killswitch.out || true
    exit 1
fi

echo "[PASS] Kill Switch da chan ket noi truc tiep khi VPN ngat."

restore_vpn
trap - EXIT INT TERM

echo "[*] Da khoi phuc wg0 va route qua VPN."