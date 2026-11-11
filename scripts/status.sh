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
        echo "=== $ns: chua ton tai ==="
    fi
done

if ip netns list | awk '{print $1}' | grep -qx g; then
    echo
    echo "=== WAN interface tren G ==="
    ip -n g -br addr show dev "$ROUTER_WAN_IF" 2>/dev/null || true

    echo
    echo "=== Route tren G ==="
    ip -n g route show
fi

if ip netns list | awk '{print $1}' | grep -qx vpn; then
    echo
    echo "=== WAN interface tren VPN Server ==="
    ip -n vpn -br addr show dev "$VPN_WAN_IF" 2>/dev/null || true

    echo
    echo "=== Server WireGuard ==="
    ip netns exec vpn wg show || true

    echo
    echo "=== Route tren VPN Server ==="
    ip -n vpn route show
fi

if ip netns list | awk '{print $1}' | grep -qx v; then
    echo
    echo "=== Client WireGuard ==="
    ip netns exec v wg show || true

    echo
    echo "=== Kill Switch ==="
    ip netns exec v python3 "$ROOT_DIR/scripts/vpn_guard.py" status || true

    echo
    echo "=== Route tren V ==="
    ip -n v route show
fi