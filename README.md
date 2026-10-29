<div align="center">

<img src="app.ico" alt="Fuck FPT" width="96">

# FUCK FPT

Bật một nút là vào được Steam trên mạng FPT. Không VPN, không proxy.

**[Tải FuckFpt.exe](https://github.com/Toji-ue/Steam-Unblock/releases/latest)** · [Tất cả bản phát hành](https://github.com/Toji-ue/Steam-Unblock/releases) · [Build từ mã nguồn](#build-và-kiểm-thử)

</div>

FPT chặn Steam bằng DPI. App này chạy [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) bản chính thức (đã kiểm tra hash) và đặt DNS riêng 1.1.1.1 / 8.8.8.8 cho đúng các miền Steam. DNS của card mạng và file `hosts` giữ nguyên. App không tự chạy cùng Windows, và khi thoát thì mọi thay đổi được hoàn tác.

## Bắt đầu

Cần Windows 10/11 x64. .NET Framework 4.x và Windows PowerShell 5.1 có sẵn trong Windows nên không phải cài gì thêm.

1. Tải `FuckFpt.exe` từ [bản mới nhất](https://github.com/Toji-ue/Steam-Unblock/releases/latest).
2. Tắt WARP, Tailscale, VPN hay công cụ chặn gói tin nào đang bật. App phát hiện được xung đột thì sẽ báo.
3. Mở exe và đồng ý quyền quản trị. App cần quyền này để cài driver và quy tắc DNS.
4. Bấm **nút nguồn**. Vòng xoay quay trong lúc app thử cấu hình và đo kết nối, khung **Log** ghi lại từng bước.

> [!NOTE]
> Exe chưa ký số nên SmartScreen có thể hiện "Windows protected your PC". Bấm **More info → Run anyway**, hoặc tự build nếu không muốn tin file build sẵn.

| Thao tác | Kết quả |
|---|---|
| Nút nguồn | Bật, hoặc tắt và hoàn tác |
| Kiểm tra kết nối | Đo lại DNS / TCP / TLS tới các dịch vụ Steam |
| Khởi động lại | Tắt rồi bật lại |
| Thu nhỏ (–) | Ẩn xuống khay hệ thống, kết nối vẫn giữ |
| Đóng (X) / Thoát ở khay | Hỏi xác nhận, tắt, hoàn tác DNS rồi thoát |

App chỉ đo được phía web. Bật xong, bạn nên tự thử trong Steam: đăng nhập, Friends/chat, tải hoặc cập nhật game, Workshop, Market, rồi vào một game online. App không bao giờ hỏi mật khẩu hay mã Steam Guard.

Máy sập nguồn lúc đang bật thì cứ mở lại app. Trạng thái "Cần phục hồi" sẽ hiện ra, bấm nút nguồn là phiên cũ được dọn sạch.

## Anti-cheat và phần mềm diệt virus

GoodbyeDPI dựa vào **WinDivert**, một driver kernel bắt và sửa gói tin mạng. App không đọc hay ghi bộ nhớ game, chỉ sửa gói tin tới các miền Steam. Dù vậy, anti-cheat chạy ở kernel vẫn có thể phản ứng khi gặp một driver mạng lạ.

> [!WARNING]
> Tắt app (bấm nút nguồn hoặc thoát) trước khi mở game có anti-cheat kernel. Lúc tắt, app gỡ hẳn driver WinDivert nó đã cài và không để gì chạy nền. Steam vẫn giữ đăng nhập.

| Anti-cheat | Game ví dụ | Ghi chú |
|---|---|---|
| **Riot Vanguard** | Valorant, League of Legends | Vanguard chặn driver nó coi là không an toàn, có khi không cho game chạy. Đã có người gặp lỗi Vanguard khi WinDivert còn trên máy. Tắt app trước, nếu Vanguard vẫn báo lỗi thì khởi động lại máy. |
| **FACEIT AC** | CS2 trên FACEIT | Kernel, chạy cùng game. Tắt app trước khi mở FACEIT. |
| **Easy Anti-Cheat** | Apex Legends, Rust, Elden Ring… | Có báo cáo lỗi khởi động EAC dính tới `WinDivert64.sys`. Tắt app trước khi vào game. |
| **BattlEye** | PUBG, Rainbow Six Siege, DayZ… | Kernel. Tắt app trước khi vào game. |
| **VAC** (Valve) | CS2, Dota 2 | Chạy ở user mode, quét tiến trình game. App không đụng vào game và chưa ai báo xung đột. |

Tới giờ chưa nhà phát hành nào nói sẽ **cấm tài khoản** vì GoodbyeDPI hay WinDivert. Những sự cố từng gặp chỉ là game không khởi động hoặc xung đột driver. Chính sách anti-cheat đổi lúc nào cũng được, nên chạy app cùng game là **bạn tự chịu rủi ro**.

ESET, Kaspersky, Norton và vài phần mềm diệt virus khác có thể chặn nhầm GoodbyeDPI hay WinDivert, vì cả hai can thiệp vào gói tin. App báo GoodbyeDPI thoát sớm thì kiểm tra phần mềm diệt virus trước. Chỉ thêm ngoại lệ khi bạn tin nguồn tải, hash có trong [`manifest.json`](manifest.json).

## Dùng bằng dòng lệnh

Script chạy thẳng được trong thư mục repo. `Diagnose` và `Status` không cần quyền quản trị:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FuckFpt.ps1 Diagnose
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FuckFpt.ps1 Status
```

Các lệnh đổi mạng phải chạy trong **PowerShell → Run as administrator**:

| Lệnh | Việc làm |
|---|---|
| `Start` | Kiểm tra xung đột, xác minh gói, tạo DNS riêng, thử native rồi reverse |
| `Stop` | Tắt, hoàn tác DNS và driver do phiên này tạo |
| `Restart` | `Stop` rồi `Start` |
| `Restore` | Dọn phiên dở dang (mất điện, tắt ngang, hoặc `Status` báo lỗi). Cùng cơ chế với `Stop` |

`ExecutionPolicy Bypass` chỉ áp dụng cho tiến trình đó, execution policy của Windows không đổi. Khởi động lại Windows xong mà quy tắc NRPT còn nằm đó dù driver không chạy thì dùng `Restore`.

## Cách hoạt động

Khi bật, app làm lần lượt:

1. Tìm xung đột: công cụ lọc gói tin khác, driver WinDivert lạ, adapter tunnel đang có tuyến, quy tắc DNS sẵn có trùng với Steam.
2. Xác minh gói GoodbyeDPI (hash ghim, chữ ký driver), rồi ghi trạng thái phiên vào `%ProgramData%\FuckFpt` **trước** khi đụng tới mạng.
3. Tạo quy tắc NRPT cho riêng các miền trong [`steam-domains.txt`](steam-domains.txt).
4. Chạy GoodbyeDPI với `-f 2 -e 2 --native-frag --blacklist <file>`, không đạt thì đổi sang `--reverse-frag`. Cấu hình nào cũng phải qua **hai lượt** kiểm tra HTTPS tới bốn dịch vụ Steam, cộng `www.microsoft.com` làm đối chứng. Mỗi request tối đa 12 giây và được thử lại một lần.
5. Không cấu hình nào đạt thì hoàn tác toàn bộ.

Khi tắt, app dừng GoodbyeDPI, gỡ driver WinDivert và quy tắc NRPT mà phiên này tạo, rồi xóa DNS cache. Quy tắc NRPT nào bị sửa từ bên ngoài sẽ được giữ lại để bạn kiểm tra. Quy tắc hay driver không do app tạo thì app không đụng tới.

App không dùng preset `-9`, `-p`, `-q`, tùy chọn chuyển DNS hay `--allow-no-sni`.

### Miền Steam

| Miền | Phạm vi |
|---|---|
| steampowered.com | Store, Help, API và các miền con |
| steamcommunity.com | Community, Market, Workshop |
| steamstatic.com | Tài nguyên web |
| steamcontent.com | Nội dung/CDN |
| steamserver.net | Máy chủ Steam |

Danh sách đối chiếu với trang [Required Ports của Steam Support](https://help.steampowered.com/en/faqs/view/2EA8-4D75-DA21-31EB) và chưa chắc phủ hết mọi CDN hay game. Chỉ thêm miền khi có lỗi thật làm bằng chứng. CDN dùng chung như Akamai thì không thêm.

### Dữ liệu trên máy

- `%ProgramData%\FuckFpt`: bản GoodbyeDPI đã xác minh, log của engine, khóa và `state.json`. Chỉ Administrators/SYSTEM được ghi.
- `%ProgramData%\FuckFptDesktop`: script app giải nén từ exe ra để chạy.
- `reports/`: báo cáo DNS/HTTPS kèm thời điểm và IP máy chủ. Không lưu cookie, mật khẩu hay lưu lượng ứng dụng. Thư mục này nằm trong `.gitignore`.

## Nguồn và xác minh

App ghim [GoodbyeDPI 0.2.3rc3](https://github.com/ValdikSS/GoodbyeDPI/releases/tag/0.2.3rc3), gói `goodbyedpi-0.2.3rc3-2.zip` để trong `vendor/`. Đây là bản **release candidate**. Chọn bản này vì tham số giới hạn hostname đã được đối chiếu với mã nguồn cùng phiên bản.

[`manifest.json`](manifest.json) chứa SHA-256 của gói và ba file x64 bên trong, lấy từ release chính thức qua HTTPS ngày 20/10/2026. GitHub không công bố digest cho bản này nên đây là hash ghim tại chỗ, **không phải** checksum có chữ ký của tác giả. Driver còn được kiểm tra Authenticode.

Thiếu gói trong `vendor/` thì script tải về từ đúng URL đã ghim. Hash sai, tải lỗi hay chữ ký không hợp lệ đều làm script dừng trước khi đổi DNS. Phiên bản không tự cập nhật.

GoodbyeDPI (Apache-2.0) và WinDivert (LGPL-3.0 / GPL-2.0) thuộc về tác giả của chúng. Giấy phép đi kèm trong gói ở `vendor/`.

## Build và kiểm thử

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-App.ps1
```

Script dùng `csc.exe` có sẵn trong .NET Framework 4.x. Script PowerShell, danh sách miền và gói GoodbyeDPI đều được nhúng vào `FuckFpt.exe`.

Test chạy bằng Pester 3.4 đi kèm Windows PowerShell, mọi thứ đều giả lập nên không bật driver hay đổi DNS thật. Gọi bằng `powershell.exe`, đừng dùng PowerShell 7:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script .\FuckFpt.Tests.ps1"
```

| File | Vai trò |
|---|---|
| `FuckFpt.App.cs` | Giao diện WPF, khay hệ thống, gọi worker |
| `AppWorker.ps1` | Cầu nối: chạy một lệnh, in log từng dòng, trả kết quả JSON |
| `FuckFpt.psm1` | Toàn bộ logic: xung đột, cài GoodbyeDPI, NRPT, kiểm tra, hoàn tác |
| `FuckFpt.ps1` | Bản dòng lệnh |
| `FuckFpt.Tests.ps1` | Test Pester |
| `Build-App.ps1`, `app.manifest` | Build exe (exe đòi quyền quản trị khi chạy) |
| `app.ico` | Icon của exe, cửa sổ và khay hệ thống |
| `manifest.json`, `vendor/` | Phiên bản, hash ghim và gói GoodbyeDPI gốc |
| `steam-domains.txt` | Danh sách miền Steam |

## Giới hạn

- Không xử lý chặn theo IP, giao thức game UDP, QUIC hay TLS không có SNI.
- Driver có thể bắt cả TCP ngoài Steam, nhưng chỉ sửa gói có Host/SNI nằm trong danh sách Steam.
- Trình duyệt dùng DoH, DNS riêng hoặc HTTP/3 có thể cho kết quả khác với phép đo của app.
- Phát hiện tunnel là kiểm tra thận trọng và không nhận ra mọi phần mềm lọc mạng. App cũng không tự tắt phần mềm khác.
