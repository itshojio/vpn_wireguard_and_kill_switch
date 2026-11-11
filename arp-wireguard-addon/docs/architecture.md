# Kiến trúc phần mở rộng WireGuard

## 1. Mục tiêu

Giữ nguyên mô hình LAN V–A–G hiện có và bổ sung một VPN Server ở mạng WAN mô phỏng riêng. Không đưa VPN Server vào bridge LAN `br-lab`.

## 2. Sơ đồ mạng

```text
                  LAN hiện có: 192.168.77.0/24
       +--------------------------------------------------+
       |                                                  |
       |  Victim V             Attacker A       Gateway G  |
       |  .10/24               .20/24           .1/24      |
       |  eth0                 eth0             eth0       |
       |    |                    |                |        |
       +----+--------------------+----------------+--------+
                                                    |
                                                 eth1
                                           203.0.113.1/30
                                                    |
                                          WAN point-to-point
                                          203.0.113.0/30
                                                    |
                                           203.0.113.2/30
                                              eth0  VPN
                                              wg0 10.200.0.1
                                                    ^
                                                    |
                                        WireGuard UDP/51820
                                                    |
                                      V wg0: 10.200.0.2
```

`203.0.113.0/30` là dải địa chỉ TEST-NET dùng cho tài liệu/mô phỏng, ở đây được dùng làm WAN nội bộ giữa hai namespace. Đây không phải Internet hay VPS thật.

## 3. Địa chỉ và định tuyến

| Thiết bị | Interface | Địa chỉ |
|---|---|---|
| V | eth0 | 192.168.77.10/24 |
| A | eth0 | 192.168.77.20/24 |
| G | eth0 | 192.168.77.1/24 |
| G | eth1 | 203.0.113.1/30 |
| VPN | eth0 | 203.0.113.2/30 |
| V | wg0 | 10.200.0.2/24 |
| VPN | wg0 | 10.200.0.1/24 |

- V đi đến VPN endpoint `203.0.113.2` qua Gateway `192.168.77.1` trên eth0.
- V có route `192.168.77.1/32` qua wg0 để kiểm thử HTTP tới dịch vụ trên G.
- G có route `10.200.0.0/24` qua `203.0.113.2` trên eth1.
- VPN có route `192.168.77.0/24` qua `203.0.113.1` trên eth0.
- G và VPN bật IPv4 forwarding để chuyển tiếp gói giữa các mạng.

## 4. Luồng dữ liệu

**Khi không bật VPN:** V gửi HTTP trực tiếp tới G trong LAN.

**Khi bật VPN:** V đóng gói lưu lượng gửi tới `192.168.77.1` vào WireGuard. G chuyển gói UDP/51820 đến VPN Server qua WAN riêng. VPN Server giải mã, chuyển gói tới G; phản hồi quay lại VPN Server và được mã hóa gửi về V.

## 5. Vai trò của MITM

A nằm trên LAN, vì vậy MITM được thực hiện bằng cách giả mạo ánh xạ ARP giữa V và Gateway G. A không ARP spoof VPN Server `203.0.113.2`, vì VPN Server không nằm cùng subnet LAN. Khi tunnel hoạt động, A có thể quan sát gói UDP WireGuard và metadata mạng, nhưng không đọc được HTTP request/body bên trong tunnel. A vẫn có thể làm gián đoạn hoặc thả gói.

## 6. Kill Switch

Kill Switch chạy trong namespace V:
- Cho phép lưu lượng ứng dụng đi qua wg0.
- Chỉ cho phép UDP tới VPN endpoint `203.0.113.2:51820` đi trực tiếp qua eth0 để duy trì tunnel.
- Chặn các lưu lượng IPv4 khác đi ra ngoài.
- Chặn IPv6 trong namespace V để tránh ứng dụng bỏ qua tunnel IPv4.

Đây là mô hình thử nghiệm IPv4; không nên coi nó là cấu hình VPN hoàn chỉnh cho môi trường sản xuất.
