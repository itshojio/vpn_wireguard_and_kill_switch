# Kiến trúc phần mở rộng

Mô hình V–A–G hiện có được giữ nguyên. Add-on chỉ gắn thêm VPN Server vào bridge hiện tại.

```text
             br-lab hiện có: 192.168.77.0/24
    +------------------------------------------------+
    |                                                |
    |  V .10          A .20          G .1:8080        |
    |   |              |                |            |
    |   +--------------+----------------+            |
    |                  |                             |
    |             VPN Server .2                     |
    |             wg0 10.200.0.1                     |
    +------------------------------------------------+
           V wg0 10.200.0.2
                  |
            WireGuard tunnel
                  |
             VPN Server
                  |
              G HTTP
```

Ở chế độ plain, V gửi HTTP trực tiếp đến G.

Ở chế độ VPN, V đưa đích `192.168.77.1/32` qua `wg0`. VPN Server giải mã rồi forward đến G. G trả lời qua route `10.200.0.0/24 via 192.168.77.2`.

A có thể tiếp tục MITM ở lớp LAN, nhưng chỉ quan sát được gói WireGuard mã hóa nếu tunnel đang hoạt động.
