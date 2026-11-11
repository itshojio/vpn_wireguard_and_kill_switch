#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Existing V-A-G LAN (must already exist)
BRIDGE="br-lab"
LAN_NET="192.168.77.0/24"
V_IP="192.168.77.10"
A_IP="192.168.77.20"
G_IP="192.168.77.1"

# Separate point-to-point WAN between Gateway and VPN Server
WAN_NET="203.0.113.0/30"
ROUTER_WAN_IP="203.0.113.1"
VPN_IP="203.0.113.2"

# WireGuard tunnel
WG_NET="10.200.0.0/24"
WG_SERVER_IP="10.200.0.1"
WG_CLIENT_IP="10.200.0.2"
WG_PORT="51820"
CHAT_PORT="9000"

KEY_DIR="/etc/arp-wireguard-extension/keys"
STATE_DIR="/var/lib/arp-wireguard-extension"
PID_DIR="/run/arp-wireguard-extension"

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[ERROR] Hãy chạy bằng sudo."
    exit 1
  fi
}

require_ns() {
  ip netns list | awk '{print $1}' | grep -qx "$1" || {
    echo "[ERROR] Không tìm thấy namespace '$1'."
    exit 1
  }
}

ns_exists() {
  ip netns list | awk '{print $1}' | grep -qx "$1"
}
