#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

# Never rebuild or delete the user's existing V/A/G lab.
for ns in v a g; do
  if ! ip netns list | awk '{print $1}' | grep -qx "$ns"; then
    echo "[ERROR] Không tìm thấy namespace '$ns'."
    echo "Gói này chỉ bổ sung vào lab V-A-G đang tồn tại; nó không tự dựng lab gốc."
    exit 1
  fi
done

ip link show "$BRIDGE" >/dev/null 2>&1 || {
  echo "[ERROR] Không tìm thấy bridge '$BRIDGE'. Không có thay đổi nào được thực hiện."
  exit 1
}

check_ip() {
  local ns="$1" expected="$2"
  if ! ip -n "$ns" -4 -o addr show dev eth0 | grep -Fq "$expected/24"; then
    echo "[ERROR] IP của namespace '$ns' không đúng. Cần $expected/24 trên eth0."
    exit 1
  fi
}
check_ip v "$V_IP"
check_ip a "$A_IP"
check_ip g "$G_IP"

if ip netns list | awk '{print $1}' | grep -qx vpn; then
  echo "[ERROR] Namespace 'vpn' đã tồn tại. Installer không xóa hoặc ghi đè."
  echo "Kiểm tra bằng: sudo ./scripts/status.sh"
  echo "Nếu muốn gỡ riêng add-on trước: sudo ./uninstall-extension.sh"
  exit 1
fi

for cmd in wg ip iptables python3 arpspoof tcpdump curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[*] Cài công cụ còn thiếu..."
    apt-get update
    apt-get install -y wireguard-tools iproute2 iptables python3 dsniff tcpdump curl
    break
  fi
done

modprobe wireguard 2>/dev/null || true
if ! ip link add wg-addon-probe type wireguard 2>/dev/null; then
  echo "[ERROR] Kernel chưa hỗ trợ WireGuard. Không thay đổi mô hình hiện tại."
  exit 1
fi
ip link del wg-addon-probe

created_vpn=0
rollback() {
  if [[ "$created_vpn" -eq 1 ]]; then
    ip netns del vpn 2>/dev/null || true
    ip link del br-vpn 2>/dev/null || true
    ip -n g route del "$WG_NET" via "$VPN_IP" 2>/dev/null || true
    ip -n v link del wg0 2>/dev/null || true
    rm -rf "$KEY_DIR"
  fi
}
trap rollback ERR

echo "[*] Thêm VPN Server vào bridge hiện tại '$BRIDGE'..."
ip netns add vpn
created_vpn=1
ip -n vpn link set lo up

echo "[*] Tạo kết nối WAN riêng giữa Router và VPN Server..."

ip link add g-wan type veth peer name vpn-wan

ip link set g-wan netns g
ip link set vpn-wan netns vpn

ip -n g link set g-wan name eth1
ip -n vpn link set vpn-wan name eth0

ip -n g addr add "$ROUTER_WAN_IP/30" dev eth1
ip -n vpn addr add "$VPN_IP/30" dev eth0

ip -n g link set eth1 up
ip -n vpn link set eth0 up
ip -n vpn link set eth0 up

echo "[*] Tạo khóa WireGuard riêng trên máy này..."
install -d -m 700 "$KEY_DIR"
umask 077
wg genkey > "$KEY_DIR/server.key"
wg pubkey < "$KEY_DIR/server.key" > "$KEY_DIR/server.pub"
wg genkey > "$KEY_DIR/client.key"
wg pubkey < "$KEY_DIR/client.key" > "$KEY_DIR/client.pub"
chmod 600 "$KEY_DIR"/*.key
chmod 644 "$KEY_DIR"/*.pub

SERVER_PUB="$(cat "$KEY_DIR/server.pub")"
CLIENT_PUB="$(cat "$KEY_DIR/client.pub")"

echo "[*] Tạo WireGuard interface..."
ip -n vpn link add wg0 type wireguard
ip -n v link add wg0 type wireguard
ip -n vpn addr add "$WG_SERVER_IP/24" dev wg0
ip -n v addr add "$WG_CLIENT_IP/24" dev wg0

ip netns exec vpn wg set wg0 \
  private-key "$KEY_DIR/server.key" \
  listen-port "$WG_PORT" \
  peer "$CLIENT_PUB" \
  allowed-ips "$WG_CLIENT_IP/32"

ip netns exec v wg set wg0 \
  private-key "$KEY_DIR/client.key" \
  peer "$SERVER_PUB" \
  endpoint "$VPN_IP:$WG_PORT" \
  allowed-ips "$G_IP/32" \
  persistent-keepalive 25

ip -n vpn link set wg0 up
ip -n v link set wg0 up

echo "[*] Bật chức năng định tuyến..."

ip netns exec g sysctl -w net.ipv4.ip_forward=1 >/dev/null
ip netns exec vpn sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[*] Cấu hình đường đi giữa các mạng..."

ip -n g route replace "$WG_NET" \
    via "$VPN_IP" dev eth1

ip -n vpn route replace "$LAN_NET" \
    via "$ROUTER_WAN_IP" dev eth0

ip -n v route replace "$VPN_IP/32" \
    via "$G_IP" dev eth0

trap - ERR

echo
echo "[✓] Đã cài add-on WireGuard vào mô hình hiện tại."
echo "    Không xóa hoặc dựng lại V, A, G hay bridge $BRIDGE."
echo "    VPN Server: $VPN_IP"
echo "    WireGuard:  $WG_CLIENT_IP <-> $WG_SERVER_IP"
echo
echo "Bước tiếp theo:"
echo "    sudo ./scripts/enable-vpn.sh"
echo "    sudo ./scripts/status.sh"
echo "    sudo ./scripts/test-http.sh"
