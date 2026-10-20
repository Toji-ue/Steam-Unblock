# Kết quả kiểm chứng — 20/10/2026 (UTC+07)

## Kết nối Steam thực tế

Sau khi người dùng tắt Cloudflare, không phát hiện tuyến tunnel hoạt động. Adapter Tailscale còn Up nhưng chỉ có tuyến Local.

**Lượt cuối 21:59 UTC+07:** native đạt hai lượt liên tiếp, được giữ chạy để người dùng kiểm tra ứng dụng. [Kết quả](reports/20261020-215903-native-cf0204.json), [xác nhận](reports/20261020-215906-native-confirm-ad28a3.json): Store 200, Community 200, Help 302, API 200, Microsoft 200; tất cả CurlExit=0.

**Vòng đời đạt:** [bật](reports/lifecycle-start.log) → [dừng](reports/lifecycle-stop.log) → [kiểm tra hoàn tác](reports/lifecycle-stop-check.json) cho OwnedRules=0, WinDivertDrivers=0, StateExists=false → [bật lại](reports/active-final.log). Status cuối: Phase=running, Profile=native, ProcessRunning=True. PathVerified=False khi chạy Status không có quyền quản trị là giới hạn quyền đọc đường dẫn, không phải tiến trình chết.

Bảng dưới ghi lại lần thành công đầu tiên lúc 15:12:

| Hạng mục | Trước bật | Reverse, hai lượt liên tiếp |
|---|---|---|
| DNS Store, Community, Help, API | 127.0.0.1 | IP công cộng |
| Store | Không kết nối được | HTTP 200 |
| Community | Không kết nối được | HTTP 200 |
| Help | Không kết nối được | HTTP 302 |
| API GetServerInfo | Không kết nối được | HTTP 200 |
| Microsoft đối chứng | Truy cập được | HTTP 200 |

Nguồn: [trước bật](reports/20261020-151122-before-040f6b.json), [reverse](reports/20261020-151207-reverse-af535d.json), [xác nhận reverse](reports/20261020-151229-reverse-confirm-dc64cb.json).

Native trong lần đầu timeout ở Store và Help; Community/API đạt. Reverse đạt ở lần đó, native đạt ở lượt cuối. Khả năng tương thích thay đổi giữa các lượt; script thử và xác nhận lại thay vì giả định profile luôn thành công. Help HTTP 302 chứng minh TLS và phản hồi HTTP thành công; phép thử không theo redirect.

Trang chủ Microsoft có timeout thất thường ngay cả khi ba URL đối chứng nhỏ truy cập được. Phép thử hiện dùng https://www.microsoft.com/robots.txt, giữ cùng hostname và chứng chỉ TLS, giảm phụ thuộc vào trang chủ.

## Mã nguồn và vòng đời

- **22/22 kiểm thử Pester đạt** trên Windows PowerShell 5.1.
- Gói chính thức, hash EXE/DLL/driver và chữ ký driver: đã xác minh.
- Khởi tạo thư mục quản trị, tạo NRPT thật, khởi chạy driver và chọn profile: đã chạy thực tế.
- Gọi Start khi đang chạy: không tạo phiên thứ hai.
- Đã dừng tiến trình, gỡ DNS và driver thực tế. Một lần gỡ driver báo sai vì dịch vụ tự biến mất trước lệnh xóa cuối; đã sửa để chấp nhận mã service does not exist và kiểm tra lại sự vắng mặt của driver.
- Đã sửa lỗi PowerShell 5.1 serialize metadata của chuỗi đọc từ tệp; thêm regression test.
- Đã sửa Status không có quyền đọc đường dẫn tiến trình nâng quyền và giữ chính xác phần giây lẻ khi PowerShell 7 giải mã ngày JSON.
- Đã thêm kiểm thử driver tự xóa và bảo vệ driver của ứng dụng khác. Lệnh thành công trả exit code 0 rõ ràng.

Các kiểm thử giả lập không thay thế nghiệm thu ứng dụng Steam. Mã Go cũ được giữ nguyên.

## Chưa nghiệm thu

| Hạng mục | Trạng thái |
|---|---|
| Đăng nhập Steam và Friends/chat | Chưa kiểm tra |
| Tải/cập nhật game và Workshop | Chưa kiểm tra |
| Market trong ứng dụng/trình duyệt | Chưa kiểm tra |
| Một game online thực tế | Chưa kiểm tra |
| IPv6 Steam, QUIC, DNS riêng của trình duyệt | Chưa kiểm tra độc lập |
| Phục hồi sau reboot/mất điện thật | Chưa kiểm tra |

Không sửa DNS adapter hoặc hosts. Không tự bật/tắt WARP/Tailscale. Không bảo đảm mọi dịch vụ/game hay mọi kiểu chặn của nhà mạng.
