# Phần mở rộng WireGuard cho mô hình ARP MITM

Gói này bổ sung một VPN Server vào mô hình LAN V–A–G đã được dựng sẵn. Nó **không dựng lại hoặc xóa** namespace `v`, `a`, `g` hay bridge `br-lab`.

Mục tiêu demo là truyền văn bản hai chiều giữa Victim V và VPN Server. Nội dung chat chỉ được hiển thị ở hai đầu tunnel. Attacker A và Gateway G chỉ quan sát/chuyển tiếp gói WireGuard bên ngoài; G không phải đích ứng dụng.

## 1. Mô hình gốc cần có

| Thành phần | Namespace | Interface | Địa chỉ |
|---|---|---|---|
| Victim V | `v` | `eth0` | `192.168.77.10/24` |
| Attacker A | `a` | `eth0` | `192.168.77.20/24` |
| Gateway G | `g` | `eth0` | `192.168.77.1/24` |
| LAN bridge | host | `br-lab` | Kết nối V, A, G |

VPN Server được tạo trong namespace `vpn`, nối riêng với G qua WAN point-to-point. Không gắn VPN Server vào `br-lab`.

## 2. Địa chỉ của phần mở rộng

| Thành phần | Interface | Địa chỉ |
|---|---|---|
| G – WAN | `eth1` | `203.0.113.1/30` |
| VPN Server – WAN | `eth0` | `203.0.113.2/30` |
| V – WireGuard | `wg0` | `10.200.0.2/24` |
| VPN Server – WireGuard | `wg0` | `10.200.0.1/24` |
| Ứng dụng chat trên VPN Server | TCP | `10.200.0.1:9000` |
| WireGuard endpoint | UDP | `203.0.113.2:51820` |

`203.0.113.0/30` là dải TEST-NET dùng trong mô phỏng, không phải Internet hay VPS thật.

## 3. Luồng dữ liệu chính xác

**Chiều V gửi lên VPN Server:**

```text
V: ứng dụng chat
  -> TCP đích 10.200.0.1:9000 qua wg0
  -> WireGuard mã hóa tại V
  -> gói UDP/51820 đi qua LAN: V -> A (MITM) -> G
  -> G định tuyến qua WAN đến VPN Server
  -> WireGuard giải mã tại VPN Server
  -> ứng dụng chat trên VPN Server hiển thị nội dung
```

**Chiều VPN Server phản hồi về V:**

```text
VPN Server: ứng dụng chat
  -> TCP gửi về 10.200.0.2 qua wg0
  -> WireGuard mã hóa tại VPN Server
  -> gói UDP/51820 đi qua G và đoạn LAN có A MITM
  -> V nhận gói WireGuard
  -> WireGuard giải mã tại V
  -> ứng dụng chat trên V hiển thị nội dung
```

A và G không chạy ứng dụng chat/HTTP, không nhận plaintext. Chúng có thể thấy địa chỉ và cổng bên ngoài, kích thước, thời điểm gói; A vẫn có thể chặn hoặc làm gián đoạn kết nối. WireGuard không che giấu metadata của gói ngoài.

## 4. Cài đặt

Giải nén ZIP, vào thư mục `arp-wireguard-addon`, rồi chạy:

```bash
chmod +x install-extension.sh uninstall-extension.sh scripts/*.sh
sudo ./install-extension.sh
```

Installer kiểm tra các namespace và địa chỉ LAN hiện có, sau đó tạo namespace `vpn`, cặp WAN veth, khóa và hai interface WireGuard. Nếu có thành phần add-on trùng tên, installer dừng thay vì ghi đè.

**Không chạy installer lần nữa nếu add-on đã được cài và namespace `vpn` đang tồn tại.** Với bản cài đang có, dùng `enable-vpn.sh` của gói đã cập nhật để cập nhật AllowedIPs và route tunnel mà không phải dựng lại topology.

## 5. Bật VPN và Kill Switch

```bash
sudo ./scripts/enable-vpn.sh
sudo ./scripts/status.sh
```

Lệnh bật VPN cập nhật peer của V để chỉ định `10.200.0.1/32` qua WireGuard, giữ route tới endpoint `203.0.113.2/32` bên ngoài tunnel qua G, và cài Kill Switch ở V.

Kill Switch cho phép ứng dụng đi qua `wg0`, đồng thời chỉ cho phép UDP đến endpoint WireGuard `203.0.113.2:51820` đi trực tiếp qua `eth0`. Các lưu lượng IPv4 trực tiếp khác và IPv6 trong namespace V bị chặn.

## 6. Chạy demo chat hai chiều

Mở hai terminal. Chạy VPN Server trước:

**Terminal của VPN Server (namespace `vpn`, ví dụ TMN 8):**

```bash
sudo ./scripts/run-vpn-chat-server.sh
```

Server lắng nghe tại `10.200.0.1:9000`. Sau khi client kết nối, nội dung từ V sẽ xuất hiện với nhãn `[Victim]`. Nhập phản hồi tại dấu nhắc `VPN Server>` rồi nhấn Enter.

**Terminal của Victim (namespace `v`, ví dụ TMN 2):**

```bash
sudo ./scripts/run-victim-chat.sh
```

Nhập nội dung tại `Victim>` rồi nhấn Enter. Nội dung sẽ hiện ở terminal VPN Server. Khi VPN Server nhập phản hồi, nội dung đó sẽ hiện ở terminal Victim. Nhập `/quit` để kết thúc phiên.

Mỗi lần nhấn Enter gửi một thông điệp dạng một dòng. Ứng dụng client kết nối đến `10.200.0.1`, không kết nối đến G.

## 7. Bắt gói để chứng minh A và G không đọc được nội dung

Nếu A đã được cấu hình MITM và các tiến trình ARP spoof đang chạy, **không chạy lại** lệnh khởi động MITM. Nếu chưa bật MITM, từ thư mục dự án chạy:

```bash
sudo ./scripts/start-mitm-vpn.sh
```

Trên terminal A:

```bash
sudo ./scripts/capture-vpn.sh
```

Khi gửi tin nhắn, A sẽ thấy UDP/51820 và dữ liệu gói ngoài nhưng không thấy nội dung văn bản đã gửi. Có thể đối chiếu thêm:

Trên VPN Server, bắt gói tại WAN (vẫn là gói mã hóa):

```bash
sudo ip netns exec vpn tcpdump -ni eth0 'udp port 51820'
```

Trên VPN Server, bắt gói tại `wg0` (đã giải mã, thấy TCP chat):

```bash
sudo ip netns exec vpn tcpdump -A -s 0 -ni wg0 'tcp port 9000'
```

Trên G, chỉ quan sát gói UDP được định tuyến:

```bash
sudo ip netns exec g tcpdump -ni eth1 'udp port 51820'
```

Dừng MITM helper do add-on khởi chạy (chỉ khi bạn muốn dừng các tiến trình do script này quản lý):

```bash
sudo ./scripts/stop-mitm-vpn.sh
```

## 8. Kiểm tra Kill Switch

Sau khi bật Kill Switch:

```bash
sudo ./scripts/test-killswitch.sh
```

Bài kiểm tra gửi một gói UDP probe thử nghiệm hướng tới G sau khi tạm hạ `wg0`, rồi xác nhận bộ đếm rule DROP của firewall tăng. Đây **không phải dữ liệu chat** và G không chạy dịch vụ nhận nội dung. Script tự khôi phục `wg0` và route chat qua tunnel.

## 9. Trạng thái, tắt và gỡ

Xem trạng thái:

```bash
sudo ./scripts/status.sh
```

Tắt Kill Switch và route chat qua tunnel nhưng giữ namespace/interface WireGuard:

```bash
sudo ./scripts/disable-vpn.sh
```

Gỡ add-on:

```bash
sudo ./uninstall-extension.sh
```

Lệnh gỡ xóa tài nguyên do add-on tạo, nhưng giữ namespace `v`, `a`, `g` và bridge `br-lab`. Không dùng lệnh gỡ nếu bạn muốn tiếp tục giữ VPN Server đang chạy.

## 10. Diễn giải kết quả

- Nội dung hiển thị ở ứng dụng VPN Server là dữ liệu sau khi WireGuard giải mã.
- Bắt gói tại A hoặc tại WAN interface của VPN Server chỉ thấy lớp UDP WireGuard bên ngoài, không thấy nội dung chat plaintext.
- Bắt gói tại `vpn/wg0` thấy TCP chat sau giải mã.
- Chiều phản hồi chứng minh VPN Server cũng mã hóa dữ liệu trước khi gửi về V.
- WireGuard bảo vệ nội dung và tính toàn vẹn trong tunnel; không ngăn MITM làm rớt/chậm gói và không che giấu metadata bên ngoài.

Đây là demo lab IPv4, không phải ứng dụng chat dùng trong môi trường sản xuất. Khóa riêng phải được bảo vệ trong `/etc/arp-wireguard-extension/keys/` và không đưa lên GitHub.
