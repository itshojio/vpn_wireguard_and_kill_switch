#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

# This installer extends an existing lab. It must never rebuild V, A, G or br-lab.
for ns in v a g; do require_ns "$ns"; done
ip link show "$BRIDGE" >/dev/null 2>&1 || {
  echo "[ERROR] Không tìm thấy bridge '$BRIDGE'. Không có thay đổi nào được thực hiện."; exit 1;
}

check_ip() {
  local ns="$1" expected="$2"
  ip -n "$ns" -4 -o addr show dev eth0 | grep -Fq "$expected/24" || {
    echo "[ERROR] Namespace '$ns' cần có $expected/24 trên eth0."; exit 1;
  }
}
check_ip v "$V_IP"
check_ip a "$A_IP"
check_ip g "$G_IP"

if ns_exists vpn; then echo "[ERROR] Namespace 'vpn' đã tồn tại; không ghi đè."; exit 1; fi
if ip -n g link show eth1 >/dev/null 2>&1; then echo "[ERROR] g/eth1 đã tồn tại; installer không ghi đè interface này."; exit 1; fi
if ip -n v link show wg0 >/dev/null 2>&1; then echo "[ERROR] v/wg0 đã tồn tại; hãy kiểm tra hoặc gỡ add-on cũ trước."; exit 1; fi
if [[ -e "$KEY_DIR" || -e "$STATE_DIR" ]]; then
  echo "[ERROR] Đã tồn tại thư mục khóa/trạng thái của add-on. Không ghi đè."; exit 1
fi
for dev in g-wan vpn-wan wg-addon-probe; do
  if ip link show "$dev" >/dev/null 2>&1; then echo "[ERROR] Interface host '$dev' đã tồn tại."; exit 1; fi
done

missing=0
for cmd in wg ip iptables ip6tables python3 arpspoof tcpdump curl sysctl; do
  command -v "$cmd" >/dev/null 2>&1 || missing=1
done
if [[ "$missing" -eq 1 ]]; then
  echo "[*] Cài các công cụ cần thiết..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools iproute2 iptables python3 dsniff tcpdump curl
fi
for cmd in wg ip iptables ip6tables python3 arpspoof tcpdump curl sysctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[ERROR] Thiếu lệnh '$cmd' sau khi cài đặt."; exit 1; }
done

modprobe wireguard 2>/dev/null || true
if ! ip link add wg-addon-probe type wireguard 2>/dev/null; then
  echo "[ERROR] Kernel chưa hỗ trợ WireGuard."; exit 1
fi
ip link del wg-addon-probe

created_vpn=0
created_veth=0
created_v_wg=0
created_keys=0
created_state=0
saved_g_forward=0
rollback() {
  rc=$?
  trap - ERR
  echo "[ERROR] Cài đặt thất bại; đang hoàn tác phần add-on đã tạo..." >&2
  if [[ "$saved_g_forward" -eq 1 && -f "$STATE_DIR/g-ip-forward.before" ]] && ns_exists g; then
    old="$(cat "$STATE_DIR/g-ip-forward.before")"
    ip netns exec g sysctl -w "net.ipv4.ip_forward=$old" >/dev/null 2>&1 || true
  fi
  if ns_exists g; then
    ip -n g route del "$WG_NET" via "$VPN_IP" dev eth1 2>/dev/null || true
    ip -n g link del eth1 2>/dev/null || true
    ip -n g link del g-wan 2>/dev/null || true
  fi
  if [[ "$created_vpn" -eq 1 ]]; then ip netns del vpn 2>/dev/null || true; fi
  if [[ "$created_veth" -eq 1 ]]; then
    ip link del g-wan 2>/dev/null || true
    ip link del vpn-wan 2>/dev/null || true
  fi
  if [[ "$created_v_wg" -eq 1 ]] && ns_exists v; then ip -n v link del wg0 2>/dev/null || true; fi
  if [[ "$created_keys" -eq 1 ]]; then rm -rf "$KEY_DIR"; fi
  if [[ "$created_state" -eq 1 ]]; then rm -rf "$STATE_DIR"; fi
  exit "$rc"
}
trap rollback ERR

install -d -m 700 "$STATE_DIR"
created_state=1
ip netns exec g sysctl -n net.ipv4.ip_forward > "$STATE_DIR/g-ip-forward.before"
saved_g_forward=1

# Build an isolated point-to-point WAN; do not attach VPN Server to br-lab.
ip netns add vpn
created_vpn=1
ip -n vpn link set lo up
ip link add g-wan type veth peer name vpn-wan
created_veth=1
ip link set g-wan netns g
ip link set vpn-wan netns vpn
ip -n g link set g-wan name eth1
ip -n vpn link set vpn-wan name eth0
ip -n g addr add "$ROUTER_WAN_IP/30" dev eth1
ip -n vpn addr add "$VPN_IP/30" dev eth0
ip -n g link set eth1 up
ip -n vpn link set eth0 up

# Generate fresh keys; never overwrite an existing key directory.
install -d -m 700 "$KEY_DIR"
created_keys=1
umask 077
wg genkey > "$KEY_DIR/server.key"
wg pubkey < "$KEY_DIR/server.key" > "$KEY_DIR/server.pub"
wg genkey > "$KEY_DIR/client.key"
wg pubkey < "$KEY_DIR/client.key" > "$KEY_DIR/client.pub"
chmod 600 "$KEY_DIR"/*.key
chmod 644 "$KEY_DIR"/*.pub
SERVER_PUB="$(cat "$KEY_DIR/server.pub")"
CLIENT_PUB="$(cat "$KEY_DIR/client.pub")"

ip -n vpn link add wg0 type wireguard
ip -n v link add wg0 type wireguard
created_v_wg=1
ip -n vpn addr add "$WG_SERVER_IP/24" dev wg0
ip -n v addr add "$WG_CLIENT_IP/24" dev wg0

ip netns exec vpn wg set wg0 \
  private-key "$KEY_DIR/server.key" listen-port "$WG_PORT" \
  peer "$CLIENT_PUB" allowed-ips "$WG_CLIENT_IP/32"
ip netns exec v wg set wg0 \
  private-key "$KEY_DIR/client.key" \
  peer "$SERVER_PUB" endpoint "$VPN_IP:$WG_PORT" \
  allowed-ips "$G_IP/32" persistent-keepalive 25

ip -n vpn link set wg0 up
ip -n v link set wg0 up

# Required routing and forwarding for the two routed networks.
ip netns exec g sysctl -w net.ipv4.ip_forward=1 >/dev/null
ip netns exec vpn sysctl -w net.ipv4.ip_forward=1 >/dev/null
ip -n g route replace "$WG_NET" via "$VPN_IP" dev eth1
ip -n vpn route replace "$LAN_NET" via "$ROUTER_WAN_IP" dev eth0
# Endpoint traffic must leave V through its LAN gateway, not through wg0.
ip -n v route replace "$VPN_IP/32" via "$G_IP" dev eth0

trap - ERR

echo
echo "[✓] Đã cài add-on theo mô hình WAN riêng."
echo "    LAN V-A-G: $LAN_NET"
echo "    G eth1: $ROUTER_WAN_IP/30 <-> VPN eth0: $VPN_IP/30"
echo "    WireGuard: $WG_CLIENT_IP <-> $WG_SERVER_IP"
echo "    Namespace v, a, g và bridge $BRIDGE được giữ nguyên."
echo
echo "Bước tiếp theo:"
echo "    sudo ./scripts/enable-vpn.sh"
echo "    sudo ./scripts/status.sh"
echo "    sudo ./scripts/test-http.sh"
