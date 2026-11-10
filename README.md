# WireGuard Extension Add-on for Existing ARP Lab

Đây là **gói bổ sung** cho mô hình ARP lab V–A–G đã được dựng sẵn trên Kali.
Nó KHÔNG dựng lại mô hình gốc và KHÔNG xóa namespace/bridge hiện tại.

## 1. Mô hình hiện có được yêu cầu

Gói này mặc định tìm thấy:

| Thành phần | Namespace | Địa chỉ |
|---|---|---|
| Victim | `v` | `192.168.77.10/24` |
| Attacker | `a` | `192.168.77.20/24` |
| Gateway/HTTP server | `g` | `192.168.77.1/24` |
| Bridge hiện tại | `br-lab` | Linux bridge |

Máy chủ HTTP đang chạy trên G tại `192.168.77.1:8080` được giữ nguyên.

## 2. Gói bổ sung sẽ làm gì?

Chỉ thêm một thành phần mới:

| Thành phần mới | Giá trị |
|---|---|
| VPN Server namespace | `vpn` |
| VPN Server LAN IP | `192.168.77.2/24` |
| WireGuard Server | `10.200.0.1/24` |
| WireGuard Client trên V | `10.200.0.2/24` |
| UDP port | `51820` |

VPN Server được nối vào **bridge `br-lab` đang tồn tại**. Gói không tạo bridge mới.

Luồng VPN:
`V (wg0) -> WireGuard tunnel -> VPN Server -> G (HTTP server)`

G được thêm một route trả về `10.200.0.0/24` thông qua VPN Server. Route mặc định hiện tại của V không bị thay thế.

## 3. Cài đặt add-on

Giải nén thư mục này trên Kali, mở Terminal tại thư mục `arp-wireguard-addon`, sau đó chạy:

```bash
chmod +x install-extension.sh uninstall-extension.sh scripts/*.sh
sudo ./install-extension.sh
```

Installer sẽ:
1. Kiểm tra namespace `v`, `a`, `g` và bridge `br-lab` có sẵn.
2. Kiểm tra đúng IP của V, A, G.
3. Chỉ tạo namespace `vpn` và một cổng mới `br-vpn` trên bridge cũ.
4. Tạo khóa WireGuard tại `/etc/arp-wireguard-extension/keys/`.
5. Tạo WireGuard interface ở V và VPN Server.
6. Thêm route trả về trên G.

**Installer không xóa, không đổi IP, không tạo lại, không khởi động lại namespace `v`, `a`, `g`; không xóa bridge `br-lab`; không dừng HTTP server của G.**

Nếu namespace `vpn` đã tồn tại, installer sẽ dừng và yêu cầu kiểm tra thay vì xóa hoặc ghi đè.

## 4. Bật phần mở rộng

Sau khi cài xong, bật VPN và Kill Switch:

```bash
sudo ./scripts/enable-vpn.sh
```

Lệnh này chỉ thay route đích thử nghiệm `192.168.77.1/32` trên V để đi qua `wg0`, đồng thời cài firewall Kill Switch. Route đến VPN Server `192.168.77.2` vẫn đi qua LAN `eth0` để duy trì WireGuard transport.

Kiểm tra:

```bash
sudo ./scripts/status.sh
```

Tạo lưu lượng HTTP từ V:

```bash
sudo ./scripts/test-http.sh
```

Kết quả mong đợi:

```text
DU LIEU THU NGHIEM - ARP LAB
```

Lưu ý: nếu VPN chưa handshake, hãy chạy `test-http.sh` để tạo lưu lượng trước, sau đó kiểm tra `wg show`.

## 5. Kiểm tra lưu lượng tại A

Để A tiếp tục MITM nhưng nhắm vào VPN Server thay vì HTTP server G, có thể chạy:

```bash
sudo ./scripts/start-mitm-vpn.sh
```

Lệnh này chỉ sử dụng namespace A hiện có, bật forwarding và giả mạo ARP giữa V (`192.168.77.10`) với VPN Server (`192.168.77.2`). Nó không dựng lại A hay thay đổi địa chỉ của A. Tiến trình do add-on khởi chạy được ghi PID riêng để lệnh dừng/gỡ không chủ động dừng các tiến trình ARP khác của bạn.

Mở một cửa sổ khác và bắt gói tại A:

```bash
sudo ./scripts/capture-vpn.sh
```

Từ V tạo HTTP:

```bash
sudo ./scripts/test-http.sh
```

Khi VPN hoạt động, A có thể thấy lưu lượng UDP WireGuard port 51820 nhưng không đọc được HTTP GET hoặc body bên trong tunnel.

Dừng MITM bổ sung:

```bash
sudo ./scripts/stop-mitm-vpn.sh
```

## 6. Kiểm tra Kill Switch

Khi VPN đã bật:

```bash
sudo ./scripts/test-killswitch.sh
```

Script tạm hạ `wg0`, thử chuyển HTTP sang đường trực tiếp qua eth0, xác nhận firewall chặn kết nối, rồi khôi phục interface và route.

Kết quả mong đợi:

```text
PASS: Kill Switch da chan ket noi truc tiep khi VPN ngat.
```

## 7. Python VPN Guard

Chương trình `scripts/vpn_guard.py` thực hiện cài đặt, gỡ và giám sát firewall:

```bash
sudo ip netns exec v python3 "$PWD/scripts/vpn_guard.py" status
sudo ip netns exec v python3 "$PWD/scripts/vpn_guard.py" watch
```

Kill Switch được thực thi bởi iptables trong namespace V; nó không phụ thuộc vào việc tiến trình Python `watch` còn chạy hay không.

## 8. Tắt VPN nhưng giữ add-on

```bash
sudo ./scripts/disable-vpn.sh
```

Lệnh này gỡ Kill Switch và route thử nghiệm qua wg0. Nó không gỡ WireGuard interface, namespace VPN hay mô hình V–A–G.

## 9. Gỡ riêng add-on

```bash
sudo ./uninstall-extension.sh
```

Lệnh này chỉ:
- Dừng tiến trình MITM VPN do add-on khởi chạy.
- Gỡ Kill Switch và WireGuard interface `wg0` khỏi V.
- Gỡ route do add-on thêm trên V và G.
- Xóa namespace `vpn` và cổng `br-vpn`.
- Xóa khóa WireGuard tại `/etc/arp-wireguard-extension/`.

Lệnh **không xóa** namespace `v`, `a`, `g`, bridge `br-lab`, IP hiện tại của chúng hoặc HTTP server của G.

## 10. Bảo vệ khóa

Khóa riêng được sinh trên máy Kali tại:

`/etc/arp-wireguard-extension/keys/`

Không đưa khóa riêng lên GitHub. `.gitignore` cũng loại trừ các file khóa và log nếu vô tình được tạo trong repository.

## 11. Giới hạn

- Đây là mô hình lab cô lập trên một máy Kali.
- WireGuard không ngăn ARP spoofing xảy ra; nó mã hóa lưu lượng bên trong tunnel.
- A vẫn có thể làm gián đoạn hoặc thả gói.
- Bài thử dùng HTTP để minh họa khác biệt plaintext/ciphertext; triển khai thực tế vẫn nên sử dụng HTTPS.
- Chỉ dùng trong lab do bạn kiểm soát.
