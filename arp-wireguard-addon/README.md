# WireGuard Extension Add-on for Existing ARP Lab

Đây là gói mở rộng cho mô hình V–A–G đã được dựng sẵn trên Kali. Add-on **không dựng lại và không xóa** namespace `v`, `a`, `g` hoặc bridge `br-lab`.

## 1. Mô hình gốc cần có

| Thành phần | Namespace | Interface | Địa chỉ |
|---|---|---|---|
| Victim | `v` | `eth0` | `192.168.77.10/24` |
| Attacker | `a` | `eth0` | `192.168.77.20/24` |
| Gateway / HTTP server | `g` | `eth0` | `192.168.77.1/24` |
| LAN bridge | host | `br-lab` | Kết nối V, A, G |

Dịch vụ HTTP dùng để kiểm thử phải đang lắng nghe tại `192.168.77.1:8080` **bên trong namespace G**. Add-on không tự tạo hoặc dừng dịch vụ HTTP này.

## 2. Add-on bổ sung gì?

VPN Server được tạo trong namespace `vpn`, nối với G bằng một cặp veth riêng. VPN Server **không** được nối vào `br-lab`.

| Thành phần | Interface | Địa chỉ |
|---|---|---|
| G – WAN | `eth1` | `203.0.113.1/30` |
| VPN – WAN | `eth0` | `203.0.113.2/30` |
| V – WireGuard | `wg0` | `10.200.0.2/24` |
| VPN – WireGuard | `wg0` | `10.200.0.1/24` |
| WireGuard UDP | – | `51820` |

`203.0.113.0/30` là dải TEST-NET dùng trong mô hình lab, không phải địa chỉ Internet/VPS thật.

Luồng dữ liệu khi VPN bật:

```text
V (10.200.0.2)
    -> WireGuard mã hóa
    -> V eth0 / G eth0
    -> G eth1 (203.0.113.1)
    -> VPN eth0 (203.0.113.2)
    -> VPN giải mã
    -> G (192.168.77.1:8080)
```

## 3. Cài đặt

Giải nén thư mục `arp-wireguard-addon`, mở Terminal tại thư mục đó và chạy:

```bash
chmod +x install-extension.sh uninstall-extension.sh scripts/*.sh
sudo ./install-extension.sh
```

Installer sẽ kiểm tra V/A/G, bridge và địa chỉ LAN; kiểm tra interface `g/eth1`, `v/wg0`, namespace `vpn` và thư mục khóa chưa tồn tại; sau đó tạo WAN veth, namespace VPN, khóa và WireGuard. Nếu lỗi giữa chừng, installer cố gắng hoàn tác các tài nguyên add-on đã tạo.

**Không chạy installer khi `vpn`, `g/eth1`, `v/wg0`, hoặc thư mục khóa/trạng thái của add-on đang tồn tại.** Nếu add-on đã được cài trước đó, hãy kiểm tra và gỡ đúng phiên bản trước khi cài lại.

## 4. Bật VPN và Kill Switch

```bash
sudo ./scripts/enable-vpn.sh
sudo ./scripts/status.sh
```

Trên V, route tới VPN endpoint `203.0.113.2/32` đi qua Gateway `192.168.77.1` trên eth0. Route thử nghiệm tới G `192.168.77.1/32` đi qua wg0.

Kill Switch cho phép ứng dụng đi qua wg0 và cho phép UDP tới VPN endpoint qua eth0; chặn lưu lượng IPv4 trực tiếp khác và chặn IPv6 trong namespace V.

## 5. Kiểm tra HTTP

```bash
sudo ./scripts/test-http.sh
```

Nếu lệnh thất bại, trước tiên xác nhận HTTP server đang chạy trong namespace G:

```bash
sudo ip netns exec g ss -lntp | grep ':8080'
```

Nếu chưa có dịch vụ HTTP, cần khởi chạy dịch vụ thử nghiệm trong namespace G trước. Ví dụ:

```bash
sudo mkdir -p /tmp/arp-http
printf 'DU LIEU THU NGHIEM - ARP LAB\n' | sudo tee /tmp/arp-http/index.html
sudo ip netns exec g python3 -m http.server 8080 --bind 192.168.77.1 --directory /tmp/arp-http
```

Lệnh cuối chạy ở foreground; mở Terminal khác để chạy `test-http.sh`.

## 6. Mô phỏng MITM và bắt gói

Bật MITM trên đoạn LAN V–G:

```bash
sudo ./scripts/start-mitm-vpn.sh
```

A giả mạo ARP để V gửi frame dành cho G tới A, đồng thời G gửi frame dành cho V tới A. VPN Server nằm ở subnet WAN riêng nên **không** bị ARP spoof trực tiếp.

Ở Terminal khác, bắt gói WireGuard tại A:

```bash
sudo ./scripts/capture-vpn.sh
```

Tạo lưu lượng HTTP từ V:

```bash
sudo ./scripts/test-http.sh
```

Khi tunnel hoạt động, A có thể quan sát gói UDP/51820 và thông tin mạng bên ngoài, nhưng không đọc được nội dung HTTP nằm bên trong WireGuard.

Dừng MITM helper:

```bash
sudo ./scripts/stop-mitm-vpn.sh
```

Lệnh này dừng đúng các tiến trình do add-on tạo, khôi phục route và trạng thái forwarding đã lưu của A, đồng thời xóa cache ARP ở V và G.

## 7. Kiểm tra Kill Switch

Khi HTTP qua VPN đang hoạt động:

```bash
sudo ./scripts/test-killswitch.sh
```

Script xác nhận HTTP hoạt động trước, sau đó tạm hạ wg0 và thử ép HTTP đi trực tiếp qua eth0. Nếu firewall chặn kết nối, kết quả là `[PASS]`. Cuối cùng script khôi phục wg0 và route qua tunnel.

## 8. Tắt VPN nhưng giữ add-on

```bash
sudo ./scripts/disable-vpn.sh
```

Lệnh này gỡ Kill Switch và route thử nghiệm qua wg0; không xóa namespace VPN hoặc WireGuard interface.

## 9. Gỡ add-on

```bash
sudo ./uninstall-extension.sh
```

Lệnh gỡ Kill Switch, route do add-on tạo, WireGuard interface trên V, WAN interface `g/eth1`, namespace `vpn`, khóa và trạng thái add-on. Nó khôi phục giá trị `ip_forward` ban đầu của G nếu đã được lưu.

Lệnh **không xóa** namespace `v`, `a`, `g`, bridge `br-lab`, địa chỉ LAN hoặc HTTP server của G.

## 10. Giới hạn và diễn giải kết quả

- Đây là mô hình lab cô lập trên một máy Kali, không phải VPN qua Internet thật.
- WireGuard không ngăn ARP spoofing; nó mã hóa dữ liệu bên trong tunnel.
- A vẫn có thể quan sát metadata gói UDP và gây gián đoạn kết nối.
- HTTP chỉ được dùng để minh họa plaintext khi đi trực tiếp và ciphertext khi nằm trong tunnel. Khi triển khai thực tế vẫn cần HTTPS.
- Kill Switch trong add-on chặn IPv6 trong namespace V; phạm vi mô hình định tuyến là IPv4.
- Cần bảo vệ khóa riêng tại `/etc/arp-wireguard-extension/keys/`; không đưa khóa riêng lên GitHub.
