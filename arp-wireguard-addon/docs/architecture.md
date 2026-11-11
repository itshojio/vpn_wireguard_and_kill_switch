# Kiến trúc phần mở rộng WireGuard: truyền dữ liệu hai chiều V ↔ VPN Server

## 1. Mục tiêu

Giữ nguyên LAN V–A–G đang có và bổ sung VPN Server trong namespace `vpn`, nối với Gateway G bằng một đường WAN point-to-point riêng. Mục tiêu là chứng minh dữ liệu ứng dụng được mã hóa từ V đến VPN Server và được giải mã tại VPN Server; chiều phản hồi được mã hóa lại trước khi quay về V.

**G không phải máy chủ ứng dụng.** **A và G không chạy chương trình nhận nội dung chat.**

## 2. Sơ đồ vật lý

```text
                 LAN hiện có: 192.168.77.0/24
  +---------------------------------------------------------+
  |                                                         |
  | Victim V                 Attacker A          Gateway G  |
  | eth0 .10/24              eth0 .20/24          eth0 .1/24 |
  | wg0 10.200.0.2              |                    |       |
  +------|---------------------|--------------------|-------+
         |              A MITM trên đoạn V-G         |
         +---------------------+--------------------+
                                                   eth1
                                             203.0.113.1/30
                                                   |
                                      WAN point-to-point riêng
                                                   |
                                             203.0.113.2/30
                                                eth0 VPN
                                                wg0 10.200.0.1
                                                TCP chat :9000
```

`203.0.113.0/30` là dải TEST-NET dành cho tài liệu và mô phỏng. Trong lab này nó chỉ là mạng WAN nội bộ giữa hai namespace, không phải Internet/VPS thật.

## 3. Địa chỉ

| Thành phần | Interface | Địa chỉ |
|---|---|---|
| V | `eth0` | `192.168.77.10/24` |
| A | `eth0` | `192.168.77.20/24` |
| G | `eth0` | `192.168.77.1/24` |
| G | `eth1` | `203.0.113.1/30` |
| VPN Server | `eth0` | `203.0.113.2/30` |
| V | `wg0` | `10.200.0.2/24` |
| VPN Server | `wg0` | `10.200.0.1/24` |
| Ứng dụng chat | TCP | `10.200.0.1:9000` |
| WireGuard | UDP | `203.0.113.2:51820` |

## 4. Hai lớp địa chỉ cần phân biệt

- **Gói bên trong tunnel (inner packet):** TCP từ `10.200.0.2` đến `10.200.0.1:9000`. Đây là dữ liệu chat gốc sau khi được giải mã tại VPN Server.
- **Gói bên ngoài (outer packet):** UDP WireGuard từ địa chỉ LAN của V (`192.168.77.10`) đến endpoint VPN (`203.0.113.2:51820`). Payload của gói dữ liệu WireGuard được mã hóa.

Vì vậy, A và G nhìn thấy địa chỉ IP/UDP bên ngoài, kích thước gói và thời điểm truyền; chúng không nhìn thấy nội dung chat bên trong tunnel.

## 5. Luồng gửi: V → A → G → VPN Server

1. Người dùng nhập một dòng văn bản ở ứng dụng `vpn-chat-client.py` trên V.
2. Ứng dụng tạo TCP đến `10.200.0.1:9000`. Route của V đưa đích này qua `wg0`.
3. WireGuard trên V mã hóa gói bên trong và đóng gói thành UDP đến `203.0.113.2:51820`.
4. Gói ngoài đi ra `V/eth0`, qua đoạn LAN có A MITM, đến G; G chỉ định tuyến gói UDP qua `eth1` đến VPN Server.
5. WireGuard trên VPN Server xác thực và giải mã. TCP gốc được đưa lên `vpn/wg0`, sau đó ứng dụng chat tại `10.200.0.1:9000` nhận và hiển thị nội dung.

## 6. Luồng phản hồi: VPN Server → G → A → V

1. Người vận hành nhập nội dung tại terminal chạy `vpn-chat-server.py` trên VPN Server.
2. Ứng dụng gửi dữ liệu TCP từ `10.200.0.1:9000` về `10.200.0.2` qua `wg0`.
3. WireGuard trên VPN Server mã hóa và đóng gói thành UDP/51820 hướng về địa chỉ LAN của V.
4. G định tuyến gói UDP về LAN; do MITM ARP, frame trên đoạn G–V đi qua A. A chỉ chuyển tiếp gói ngoài.
5. WireGuard trên V giải mã và chuyển TCP gốc đến ứng dụng client; nội dung phản hồi hiện trên terminal V.

## 7. Vai trò từng thành phần

- **V:** chạy WireGuard client và ứng dụng chat client.
- **A:** thực hiện MITM ARP trên LAN V–G, chuyển tiếp và bắt gói UDP/51820. Không có khóa WireGuard nên không giải mã được nội dung tunnel.
- **G:** gateway định tuyến gói WireGuard giữa LAN và WAN mô phỏng. Không chạy HTTP/chat server và không nhận nội dung chat ở dạng plaintext.
- **VPN Server:** kết thúc tunnel WireGuard; ứng dụng chat chỉ lắng nghe trên `10.200.0.1:9000` (địa chỉ `wg0`). Đây là điểm giải mã và hiển thị dữ liệu.

## 8. Định tuyến quan trọng

- V đi đến endpoint `203.0.113.2/32` qua Gateway `192.168.77.1` trên `eth0`. Đây là đường vận chuyển gói WireGuard bên ngoài.
- V đi đến `10.200.0.1/32` qua `wg0`. Đây là đường của ứng dụng chat bên trong tunnel.
- VPN Server có route đến LAN `192.168.77.0/24` qua G (`203.0.113.1`) để gửi gói UDP WireGuard trở lại địa chỉ LAN của V.
- G bật IPv4 forwarding để chuyển tiếp gói UDP bên ngoài giữa LAN và WAN. Không cần đưa VPN Server vào bridge `br-lab`.

## 9. Kiểm chứng bằng bắt gói

- Trên A: `tcpdump -X -s 0 -ni eth0 'udp port 51820'` — thấy gói WireGuard bên ngoài, không thấy dòng chat plaintext.
- Trên G/`eth1`: `tcpdump -ni eth1 'udp port 51820'` — chỉ thấy gói UDP được định tuyến.
- Trên VPN Server/`eth0`: `tcpdump -ni eth0 'udp port 51820'` — vẫn là gói ngoài đã mã hóa.
- Trên VPN Server/`wg0`: `tcpdump -A -s 0 -ni wg0 'tcp port 9000'` — thấy TCP sau giải mã; ứng dụng server cũng hiển thị nội dung.

WireGuard bảo vệ nội dung và tính toàn vẹn của gói trong tunnel; nó không ngăn A làm rớt hoặc trì hoãn gói. Metadata bên ngoài như địa chỉ endpoint, kích thước và thời điểm truyền vẫn có thể quan sát được.

## 10. Giới hạn

Đây là mô hình IPv4 trong môi trường lab cô lập. Chương trình chat dùng TCP và phân tách thông điệp theo ký tự xuống dòng, do đó mỗi lần nhấn Enter là một thông điệp. Không dùng bộ chat mẫu này cho môi trường sản xuất; nó không có xác thực người dùng hay giao diện bảo mật bổ sung. Khóa riêng phải được giữ trong thư mục quyền hạn chế `/etc/arp-wireguard-extension/keys/`.
