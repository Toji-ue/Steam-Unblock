# FUCK FPT

Ứng dụng Windows một cửa sổ giúp vào **Steam** trên mạng FPT, nơi Steam bị chặn bằng DPI. Bấm nút nguồn để bật, bấm lần nữa để tắt; thoát app là mọi thay đổi được hoàn tác.

- Không VPN, không proxy, không tự chạy cùng Windows.
- Chỉ tác động tới các miền Steam: không đổi DNS của card mạng, không sửa file `hosts`.
- Dùng [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) bản chính thức, đã kiểm tra hash, kèm DNS riêng (1.1.1.1 / 8.8.8.8) chỉ cho các miền Steam.

## Tải về

**[⬇ Tải FuckFpt.exe (bản mới nhất)](https://github.com/Toji-ue/Steam-Unblock/releases/latest)** · [Tất cả bản phát hành](https://github.com/Toji-ue/Steam-Unblock/releases)

Exe chưa được ký số, nên Windows SmartScreen có thể hiện "Windows protected your PC": bấm **More info → Run anyway**. Nếu không muốn tin file build sẵn, hãy tự build từ mã nguồn (xem [Build và kiểm thử](#build-và-kiểm-thử)).

## Cài và chạy

Yêu cầu: Windows 10/11 x64. .NET Framework 4.x và Windows PowerShell 5.1 đã có sẵn trên Windows.

1. [Tải `FuckFpt.exe`](https://github.com/Toji-ue/Steam-Unblock/releases/latest), hoặc tự build.
2. Tắt WARP, Tailscale, VPN hoặc công cụ chặn gói tin khác nếu đang bật. App sẽ báo nếu phát hiện xung đột.
3. Mở `FuckFpt.exe` và đồng ý quyền quản trị (cần để cài driver và quy tắc DNS).
4. Bấm **nút nguồn**. Vòng xoay chạy trong lúc app thử cấu hình và kiểm tra kết nối; khung **Log** hiện từng bước đang làm.

| Thao tác | Kết quả |
|---|---|
| Nút nguồn | Bật, hoặc tắt và hoàn tác |
| Kiểm tra kết nối | Đo lại DNS / TCP / TLS tới các dịch vụ Steam |
| Khởi động lại | Tắt rồi bật lại |
| Thu nhỏ (–) | Ẩn xuống khay hệ thống, kết nối vẫn giữ |
| Đóng (X) / Thoát ở khay | Hỏi xác nhận, tắt và hoàn tác DNS rồi thoát |

Nếu máy tắt đột ngột khi đang bật, mở lại app: trạng thái "Cần phục hồi" sẽ hiện ra, bấm nút nguồn để dọn phiên cũ.

Sau khi bật, hãy tự kiểm tra trong ứng dụng Steam: đăng nhập, Friends/chat, tải/cập nhật, Workshop, Market và một game online. App chỉ kiểm tra web; không bao giờ cần mật khẩu hay mã Steam Guard của bạn.

## Anti-cheat và phần mềm diệt virus

GoodbyeDPI dùng driver kernel **WinDivert** để chặn và sửa gói tin mạng. App không đọc hay sửa bộ nhớ game, chỉ sửa gói tin tới các miền Steam. Tuy vậy, anti-cheat chạy ở kernel vẫn có thể phản ứng khi thấy một driver mạng lạ.

**Khuyến nghị: tắt app (nút nguồn hoặc thoát) trước khi mở game có anti-cheat kernel.** Khi tắt, app gỡ hẳn driver WinDivert do nó cài, không để lại gì chạy nền. Steam vẫn giữ đăng nhập sau khi tắt.

| Anti-cheat | Game ví dụ | Ghi chú |
|---|---|---|
| **Riot Vanguard** | Valorant, League of Legends | Vanguard chặn các driver nó coi là không an toàn và có thể không cho game chạy. Đã có người báo lỗi Vanguard khi WinDivert còn trên máy. **Tắt app, rồi khởi động lại máy nếu Vanguard vẫn báo lỗi**, trước khi chơi. |
| **FACEIT AC** | CS2 trên FACEIT | Anti-cheat kernel, chạy cùng lúc với game. Tắt app trước khi mở FACEIT. |
| **Easy Anti-Cheat** | Apex Legends, Rust, Elden Ring… | Có người gặp lỗi khởi động EAC liên quan tới `WinDivert64.sys`. Tắt app trước khi vào game. |
| **BattlEye** | PUBG, Rainbow Six Siege, DayZ… | Driver kernel; cùng khuyến nghị: tắt app trước khi vào game. |
| **VAC** (Valve) | CS2, Dota 2 | Chạy ở user mode và quét tiến trình game; app không đụng vào game. Chưa ghi nhận xung đột. |

Chưa thấy nhà phát hành nào công bố **cấm tài khoản** vì GoodbyeDPI hay WinDivert; các sự cố được ghi nhận là game không khởi động được hoặc xung đột driver. Chính sách anti-cheat có thể thay đổi bất cứ lúc nào, nên **bạn tự chịu rủi ro** khi chạy app cùng lúc với game.

**Phần mềm diệt virus:** một số phần mềm (ESET, Kaspersky, Norton…) có thể chặn hoặc cảnh báo nhầm GoodbyeDPI hay WinDivert vì chúng can thiệp vào gói tin mạng. Nếu app báo GoodbyeDPI thoát sớm, hãy xem phần mềm diệt virus có chặn nó không. Chỉ thêm ngoại lệ khi bạn đã tin tưởng nguồn tải (hash có trong [`manifest.json`](manifest.json)).

## Dùng bằng dòng lệnh

Không cần giao diện, có thể chạy thẳng script trong thư mục repo. `Diagnose` và `Status` không cần quyền quản trị:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FuckFpt.ps1 Diagnose
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FuckFpt.ps1 Status
```

Các lệnh thay đổi mạng cần **PowerShell → Run as administrator**:

| Lệnh | Việc làm |
|---|---|
| `Start` | Bật: kiểm tra xung đột, xác minh gói, tạo DNS riêng, thử native rồi reverse |
| `Stop` | Tắt và hoàn tác DNS, driver do phiên này tạo |
| `Restart` | `Stop` rồi `Start` |
| `Restore` | Dọn phiên dở (mất điện, tắt ngang, hoặc `Status` báo lỗi). Cùng cơ chế với `Stop` |

`ExecutionPolicy Bypass` chỉ áp dụng cho tiến trình đó, không đổi execution policy của Windows. Sau khi khởi động lại Windows, quy tắc NRPT có thể còn dù driver không chạy: dùng `Restore`.

## Cách hoạt động

Khi bật:

1. Kiểm tra xung đột: công cụ lọc gói tin khác, driver WinDivert lạ, adapter tunnel có tuyến hoạt động, quy tắc DNS có sẵn trùng với Steam.
2. Xác minh gói GoodbyeDPI (hash ghim, chữ ký driver), rồi ghi trạng thái phiên vào `%ProgramData%\FuckFpt` **trước** mọi thay đổi mạng.
3. Tạo quy tắc NRPT chỉ cho các miền trong [`steam-domains.txt`](steam-domains.txt).
4. Chạy GoodbyeDPI với `-f 2 -e 2 --native-frag --blacklist <file>`, nếu không đạt thì thay bằng `--reverse-frag`. Mỗi cấu hình phải vượt qua **hai lượt** kiểm tra HTTPS tới bốn dịch vụ Steam và `www.microsoft.com` đối chứng (mỗi request tối đa 12 giây, thử lại một lần).
5. Nếu không cấu hình nào đạt, tự hoàn tác toàn bộ.

Khi tắt: dừng GoodbyeDPI, gỡ driver WinDivert và quy tắc NRPT mà phiên này tạo ra, xóa DNS cache. Quy tắc NRPT đã bị sửa từ bên ngoài được giữ lại để bạn kiểm tra; quy tắc hay driver không do app tạo thì không bị đụng tới.

Không dùng preset `-9`, `-p`, `-q`, tùy chọn chuyển DNS hay `--allow-no-sni`.

### Miền Steam

| Miền | Phạm vi |
|---|---|
| steampowered.com | Store, Help, API và các miền con |
| steamcommunity.com | Community, Market, Workshop |
| steamstatic.com | Tài nguyên web |
| steamcontent.com | Nội dung/CDN |
| steamserver.net | Máy chủ Steam |

Danh sách đối chiếu với [Steam Support — Required Ports](https://help.steampowered.com/en/faqs/view/2EA8-4D75-DA21-31EB), không coi là đầy đủ cho mọi CDN/game. Chỉ thêm miền khi có lỗi thực tế làm bằng chứng; không thêm miền CDN dùng chung như Akamai.

### Dữ liệu trên máy

- `%ProgramData%\FuckFpt`: bản GoodbyeDPI đã xác minh, log của engine, khóa và `state.json`. Chỉ Administrators/SYSTEM được ghi.
- `%ProgramData%\FuckFptDesktop`: script mà app giải nén từ exe để chạy.
- `reports/`: báo cáo DNS/HTTPS có thời điểm và IP máy chủ. Không lưu cookie, mật khẩu hay lưu lượng ứng dụng; được `.gitignore` bỏ qua.

## Nguồn và xác minh

Ghim [GoodbyeDPI 0.2.3rc3](https://github.com/ValdikSS/GoodbyeDPI/releases/tag/0.2.3rc3), gói `goodbyedpi-0.2.3rc3-2.zip` trong `vendor/`. Đây là bản **release candidate**, chọn vì tham số giới hạn hostname đã được đối chiếu với mã nguồn cùng phiên bản.

[`manifest.json`](manifest.json) lưu SHA-256 của gói và ba file x64 bên trong, lấy từ release chính thức qua HTTPS ngày 20/10/2026. GitHub không công bố digest cho bản này, nên đây là hash ghim tại chỗ, **không phải** checksum có chữ ký của tác giả. Driver được kiểm tra Authenticode. Nếu thiếu gói trong `vendor/`, script tải đúng URL ghim; hash sai, tải lỗi hay chữ ký không hợp lệ đều dừng trước khi đổi DNS. Không tự cập nhật phiên bản.

## Build và kiểm thử

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-App.ps1
```

Dùng `csc.exe` có sẵn trong .NET Framework 4.x, không cần cài thêm gì. Script, danh sách miền và gói GoodbyeDPI được nhúng vào `FuckFpt.exe`.

Kiểm thử giả lập bằng Pester 3.4 đi kèm Windows PowerShell (không bật driver hay đổi DNS). Dùng `powershell.exe`, không dùng PowerShell 7:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script .\FuckFpt.Tests.ps1"
```

## Cấu trúc

| File | Vai trò |
|---|---|
| `FuckFpt.App.cs` | Giao diện WPF, khay hệ thống, gọi worker |
| `AppWorker.ps1` | Cầu nối: chạy một lệnh, in log từng dòng, trả kết quả JSON |
| `FuckFpt.psm1` | Toàn bộ logic: xung đột, cài GoodbyeDPI, NRPT, kiểm tra, hoàn tác |
| `FuckFpt.ps1` | Dùng bằng dòng lệnh |
| `FuckFpt.Tests.ps1` | Kiểm thử Pester |
| `Build-App.ps1`, `app.manifest` | Build exe (yêu cầu quyền quản trị khi chạy) |
| `app.ico` | Icon của exe, cửa sổ và khay hệ thống |
| `manifest.json`, `vendor/` | Phiên bản, hash ghim và gói GoodbyeDPI gốc |
| `steam-domains.txt` | Danh sách miền Steam |

## Giới hạn

- Không xử lý chặn theo IP, giao thức game UDP, QUIC hay TLS không có SNI.
- Driver có thể bắt TCP ngoài Steam, nhưng chỉ sửa gói có Host/SNI thuộc danh sách Steam.
- Trình duyệt dùng DoH, DNS riêng hoặc HTTP/3 có thể cho kết quả khác kiểm tra của app.
- Phát hiện tunnel là kiểm tra bảo thủ, không nhận ra mọi phần mềm lọc mạng; app không tự tắt phần mềm khác.

## Bản quyền bên thứ ba

GoodbyeDPI (Apache-2.0) và WinDivert (LGPL-3.0 / GPL-2.0) thuộc về tác giả của chúng; giấy phép đi kèm trong gói ở `vendor/`.
