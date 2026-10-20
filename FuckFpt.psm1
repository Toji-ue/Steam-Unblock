#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Source = $PSScriptRoot
$script:Root = Join-Path $env:ProgramData 'FuckFpt'
$script:StatePath = Join-Path $script:Root 'state.json'
$script:Exe = Join-Path $script:Root 'bin\goodbyedpi.exe'
# Method results are plain strings. PS 5.1 serializes Get-Content's attached
# provider metadata (including PSDrive) if the original decorated strings survive.
$script:Domains = @(Get-Content (Join-Path $PSScriptRoot 'steam-domains.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($domain in $script:Domains) {
    if ($domain -notmatch '^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z]{2,}$') { throw 'Danh sách miền không hợp lệ.' }
}
$script:Namespaces = @($script:Domains | ForEach-Object { $_; ".$_" })
$script:Resolvers = @('1.1.1.1', '8.8.8.8')

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-Admin {
    if (-not (Test-Admin)) { throw 'Mở PowerShell bằng Run as administrator rồi chạy lại lệnh. Diagnose và Status không cần quyền này.' }
}
function Initialize-Root {
    if (Test-Path $script:Root) {
        $item = Get-Item $script:Root -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Thư mục trạng thái là liên kết; từ chối sử dụng.' }
        $acl = Get-Acl $script:Root
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'Chủ sở hữu thư mục trạng thái không phải Administrators/SYSTEM; cần kiểm tra thủ công.' }
        foreach ($entry in $acl.Access) {
            $sid = $entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($entry.AccessControlType -eq 'Allow' -and $sid -notin @('S-1-5-18', 'S-1-5-32-544') -and
                ($entry.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write)) {
                throw 'Thư mục trạng thái cho phép người dùng thường ghi; từ chối nâng quyền dữ liệu.'
            }
        }
    } else {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $acl.SetOwner($admins)
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-545')) {
            $rights = if ($sid -eq 'S-1-5-32-545') { 'ReadAndExecute' } else { 'FullControl' }
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                (New-Object Security.Principal.SecurityIdentifier($sid)), $rights,
                'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        # Create with the restrictive ACL in one operation (also on PowerShell 7).
        $directory = New-Object IO.DirectoryInfo($script:Root)
        if ($PSVersionTable.PSEdition -eq 'Core') {
            [IO.FileSystemAclExtensions]::Create($directory, $acl)
        } else { $directory.Create($acl) }
    }
}
function Save-State($State) {
    $temp = "$script:StatePath.tmp"
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    if (Test-Path $script:StatePath) { [IO.File]::Replace($temp, $script:StatePath, [NullString]::Value) }
    else { [IO.File]::Move($temp, $script:StatePath) }
}
function Read-State {
    if (-not (Test-Path $script:StatePath)) { return $null }
    $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($state.Schema -ne 1 -or $state.Token -notmatch '^FuckFpt:[0-9a-f-]{36}$') {
        throw 'Trạng thái không hợp lệ; không tự động xóa hay dừng tiến trình.'
    }
    return $state
}
function Test-NamespaceOverlap([string]$Left, [string]$Right) {
    $a = $Left.TrimStart('.').ToLowerInvariant()
    $b = $Right.TrimStart('.').ToLowerInvariant()
    return (-not $a -or -not $b -or $a -eq $b -or $a.EndsWith(".$b") -or $b.EndsWith(".$a"))
}
function Get-Conflicts {
    $messages = New-Object 'Collections.Generic.List[string]'
    foreach ($process in @(Get-Process -Name goodbyedpi,winws,winws2,zapret -ErrorAction SilentlyContinue)) {
        $messages.Add("Công cụ lọc gói tin đang chạy: $($process.ProcessName) (PID $($process.Id)).")
    }
    foreach ($driver in @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'WinDivert' })) {
        $messages.Add("Driver WinDivert đã được đăng ký: $($driver.Name). Cần kiểm tra công cụ sở hữu trước khi tiếp tục.")
    }
    $routes = @(Get-NetRoute -PolicyStore ActiveStore)
    foreach ($adapter in @(Get-NetAdapter -IncludeHidden | Where-Object { $_.Status -eq 'Up' })) {
        if (($adapter.Name + ' ' + $adapter.InterfaceDescription) -match 'Tailscale|WireGuard|WARP|OpenVPN|TAP-Windows|Tunnel|VPN') {
            $active = @($routes | Where-Object {
                $_.InterfaceIndex -eq $adapter.ifIndex -and $_.Protocol -ne 'Local' -and
                $_.DestinationPrefix -notmatch '^(fe80:|ff00:|224\.|255\.|127\.)'
            })
            if ($active.Count) { $messages.Add("Adapter tunnel có tuyến hoạt động: $($adapter.Name). Hãy tự ngắt kết nối rồi thử lại.") }
        }
    }
    foreach ($policy in @(Get-DnsClientNrptPolicy -Effective)) {
        foreach ($ns in @($policy.Namespace)) {
            foreach ($domain in $script:Domains) {
                if (Test-NamespaceOverlap $ns $domain) { $messages.Add("Quy tắc DNS có sẵn giao với $domain."); break }
            }
        }
    }
    foreach ($rule in @(Get-DnsClientNrptRule)) {
        foreach ($ns in @($rule.Namespace)) {
            foreach ($domain in $script:Domains) {
                if (Test-NamespaceOverlap $ns $domain) { $messages.Add("Quy tắc NRPT có sẵn giao với $domain."); break }
            }
        }
    }
    return $messages.ToArray()
}
function Assert-Hash([string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "SHA-256 không khớp: $Path. Không chạy công cụ."
    }
}
function Install-Engine {
    $manifest = Get-Content (Join-Path $script:Source 'manifest.json') -Raw | ConvertFrom-Json
    $bin = Join-Path $script:Root 'bin'
    if (-not (Test-Path $bin)) {
        $archive = Join-Path $script:Root $manifest.archive
        $bundled = Join-Path $script:Source "vendor\$($manifest.archive)"
        if (Test-Path $bundled) { Copy-Item -LiteralPath $bundled -Destination $archive }
        else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $manifest.url -OutFile $archive -UseBasicParsing -TimeoutSec 60
        }
        Assert-Hash $archive $manifest.sha256
        $stage = Join-Path $script:Root ("unpack-" + [guid]::NewGuid().ToString())
        Expand-Archive -LiteralPath $archive -DestinationPath $stage
        $sourceBin = Join-Path $stage "$($manifest.directory)\x86_64"
        foreach ($file in $manifest.files.PSObject.Properties) { Assert-Hash (Join-Path $sourceBin $file.Name) $file.Value }
        Move-Item -LiteralPath $sourceBin -Destination $bin
        Copy-Item -LiteralPath (Join-Path $stage "$($manifest.directory)\licenses") -Destination (Join-Path $script:Root 'licenses') -Recurse -Force
    }
    foreach ($file in $manifest.files.PSObject.Properties) { Assert-Hash (Join-Path $bin $file.Name) $file.Value }
    if ((Get-AuthenticodeSignature (Join-Path $bin 'WinDivert64.sys')).Status -ne 'Valid') {
        throw 'Chữ ký driver không hợp lệ hoặc chưa xác minh được.'
    }
    Copy-Item -LiteralPath (Join-Path $script:Source 'steam-domains.txt') -Destination (Join-Path $script:Root 'steam-domains.txt') -Force
}
function Get-EngineArguments([string]$Profile, [string]$ListPath = (Join-Path $script:Root 'steam-domains.txt')) {
    if ($Profile -notin @('native', 'reverse')) { throw 'Profile không hợp lệ.' }
    $fragment = if ($Profile -eq 'native') { '--native-frag' } else { '--reverse-frag' }
    return @('-f', '2', '-e', '2', $fragment, '--blacklist', ('"' + $ListPath + '"'))
}
function Test-PublicAddress([string]$Address) {
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    if ([Net.IPAddress]::IsLoopback($ip)) { return $false }
    if ($ip.AddressFamily -eq 'InterNetwork') {
        $b = $ip.GetAddressBytes()
        return -not ($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
            ($b[0] -eq 169 -and $b[1] -eq 254) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or
            ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
            ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127))
    }
    return ($ip.GetAddressBytes()[0] -band 0xe0) -eq 0x20
}
function Invoke-Probe {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    $targets = @(
        @{ Host = 'store.steampowered.com'; Path = '/' },
        @{ Host = 'steamcommunity.com'; Path = '/' },
        @{ Host = 'help.steampowered.com'; Path = '/' },
        @{ Host = 'api.steampowered.com'; Path = '/ISteamWebAPIUtil/GetServerInfo/v1/' },
        @{ Host = 'www.microsoft.com'; Path = '/robots.txt' }
    )
    foreach ($target in $targets) {
        $addresses = @(); $dnsError = $null
        try {
            $addresses = @(Resolve-DnsName $target.Host -Type A -DnsOnly -QuickTimeout -ErrorAction Stop |
                Where-Object Type -eq A | Select-Object -ExpandProperty IPAddress)
        } catch { $dnsError = $_.Exception.Message }
        # --disable ignores user curl configuration; no proxy, cookies, credentials, or insecure TLS.
        $errorFile = [IO.Path]::GetTempFileName()
        try {
            # PS 5.1 otherwise promotes curl stderr into terminating PowerShell errors.
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $output = @(& $curl --disable --noproxy '*' --silent --show-error --output NUL --connect-timeout 5 --max-time 12 --retry 1 --retry-delay 1 --retry-max-time 25 `
                --write-out '%{http_code}|%{remote_ip}|%{time_connect}|%{time_appconnect}|%{time_total}' `
                "https://$($target.Host)$($target.Path)" 2> $errorFile)
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $oldPreference
            $output += @(Get-Content -LiteralPath $errorFile)
        } finally {
            $ErrorActionPreference = $oldPreference
            Remove-Item -LiteralPath $errorFile -ErrorAction SilentlyContinue
        }
        $metrics = @($output | ForEach-Object { "$_" } | Where-Object { $_ -match '^\d{3}\|' } | Select-Object -Last 1)
        $parts = if ($metrics.Count) { $metrics[0].Split('|') } else { @('000','','0','0','0') }
        $dnsOk = $addresses.Count -gt 0 -and @($addresses | Where-Object { -not (Test-PublicAddress $_) }).Count -eq 0
        [pscustomobject]@{
            Host = $target.Host; DNS = $addresses -join ', '; DnsOK = $dnsOk; DnsError = $dnsError
            CurlExit = $exitCode; HTTP = [int]$parts[0]; RemoteIP = $parts[1]
            TcpSeconds = $parts[2]; TlsSeconds = $parts[3]; TotalSeconds = $parts[4]
            Pass = ($dnsOk -and $exitCode -eq 0 -and [int]$parts[0] -ge 200 -and [int]$parts[0] -lt 400)
            Error = (@($output | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^\d{3}\|' }) -join ' ')
        }
    }
}
function Save-Report($Results, [string]$Label) {
    $reports = Join-Path $script:Source 'reports'
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    $path = Join-Path $reports ("{0}-{1}-{2}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Label, [guid]::NewGuid().ToString('N').Substring(0,6))
    [ordered]@{ At = [DateTimeOffset]::Now.ToString('o'); Label = $Label; Results = @($Results) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    # Write-Host, not Out-Host: the app worker captures it with *>&1; Out-Host would corrupt its JSON stdout.
    $Results | Format-Table Host,DNS,HTTP,CurlExit,Pass -AutoSize | Out-String | Write-Host
    Write-Host "Báo cáo: $path"
}
function Get-OwnedProcess {
    param($State, [switch]$AllowLimitedVisibility)
    # Match path + creation time, never trust PID alone (Windows can reuse it).
    if ($null -ne $State.EnginePid) {
        $process = Get-Process -Id $State.EnginePid -ErrorAction SilentlyContinue
        $pathMatches = $null -ne $process -and ($process.Path -eq $script:Exe -or
            ($AllowLimitedVisibility -and -not $process.Path -and $process.ProcessName -eq 'goodbyedpi'))
        if ($pathMatches -and
            $process.StartTime.ToUniversalTime().Ticks -eq ([datetime]$State.EngineStartedUtc).ToUniversalTime().Ticks) {
            return $process
        }
        return $null
    }
    if (-not $State.LaunchPending) { return $null }
    # Recovery for a crash between CreateProcess and recording its PID:
    # the unique blacklist argument identifies this session, not merely an EXE name.
    $list = Join-Path $script:Root ("steam-" + $State.Token.Substring($State.Token.IndexOf(':') + 1) + '.txt')
    $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'goodbyedpi.exe'" | Where-Object {
        $_.ExecutablePath -eq $script:Exe -and $_.CommandLine -and $_.CommandLine.Contains('"' + $list + '"')
    } | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
    if ($matches.Count -gt 1) { throw 'Có nhiều tiến trình cùng đường dẫn; cần kiểm tra thủ công.' }
    if ($matches.Count) { return $matches[0] }
    return $null
}
function Stop-OwnedEngine($State) {
    $process = Get-OwnedProcess $State
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        $process.WaitForExit(5000) | Out-Null
        if (-not $process.HasExited) { throw 'Chưa dừng được GoodbyeDPI.' }
    }
}
function Invoke-ServiceControl([string]$Action, [string]$Name) {
    & "$env:SystemRoot\System32\sc.exe" $Action $Name | Out-Null
    return $LASTEXITCODE
}
function Remove-OwnedDriver($State) {
    foreach ($driver in @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match '^WinDivert' })) {
        $driverPath = $driver.PathName.Trim('"') -replace '^\\\?\?\\', ''
        if ($driver.Name -notin @($State.BaselineDrivers) -and
            $driverPath -eq (Join-Path $script:Root 'bin\WinDivert64.sys')) {
            if ($driver.State -eq 'Running') {
                $code = Invoke-ServiceControl 'stop' $driver.Name
                if ($code -notin @(0,1060,1062)) { throw "Chưa dừng được driver $($driver.Name); giữ trạng thái để Restore." }
            }
            $code = Invoke-ServiceControl 'delete' $driver.Name
            # WinDivert can remove its service as the final handle closes.
            if ($code -notin @(0,1060,1072)) { throw "Chưa gỡ được đăng ký driver $($driver.Name)." }
            $remaining = @(Get-CimInstance Win32_SystemDriver -Filter "Name = '$($driver.Name)'")
            if ($remaining.Count) { throw "Đăng ký driver $($driver.Name) chưa biến mất; chạy Restore để kiểm tra lại." }
        }
    }
}
function Restore-Session($State) {
    Stop-OwnedEngine $State
    foreach ($rule in @(Get-DnsClientNrptRule)) {
        if ($rule.Comment -eq $State.Token) {
            $allowed = @($State.Namespaces)
            $servers = @($rule.NameServers | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
            if ((@($rule.Namespace | Sort-Object) -join "`n") -ne (@($allowed | Sort-Object) -join "`n") -or
                (@($servers | Sort-Object) -join "`n") -ne (@($script:Resolvers | Sort-Object) -join "`n")) {
                throw 'Quy tắc do script tạo đã bị chỉnh sửa; giữ lại để bạn kiểm tra.'
            }
            Remove-DnsClientNrptRule -Name $rule.Name -Force
        }
    }
    Clear-DnsClientCache
    Remove-OwnedDriver $State
    $list = Join-Path $script:Root ("steam-" + $State.Token.Substring($State.Token.IndexOf(':') + 1) + '.txt')
    if (Test-Path -LiteralPath $list) { Remove-Item -LiteralPath $list }
    Remove-Item -LiteralPath $script:StatePath
    Write-Host 'Đã dừng và hoàn tác quy tắc DNS/driver do phiên này tạo.'
}
function Start-Session {
    $existing = Read-State
    if ($null -ne $existing) {
        if ($existing.Phase -eq 'running' -and $null -ne (Get-OwnedProcess $existing)) {
            Write-Host "Đang chạy profile $($existing.Profile). Không tạo phiên thứ hai."
            return
        }
        throw 'Có phiên chưa hoàn tất. Chạy Restore trước khi bật lại.'
    }
    $conflicts = @(Get-Conflicts)
    if ($conflicts.Count) { throw ($conflicts -join "`n") }
    Install-Engine
    $baseline = @(Invoke-Probe)
    Save-Report $baseline 'before'
    if (@($baseline | Where-Object { $_.Host -eq 'www.microsoft.com' -and -not $_.Pass }).Count) {
        throw 'Website đối chứng chưa đạt; kiểm tra kết nối Internet trước khi bật xử lý Steam.'
    }
    if (@($baseline | Where-Object { -not $_.Pass }).Count -eq 0) {
        Write-Host 'Các kiểm tra web đã đạt; không thay đổi mạng. Các chức năng ứng dụng vẫn cần kiểm tra riêng.'
        return
    }
    Write-Host 'Đang ghi nhận driver và lưu trạng thái phục hồi...'
    $baselineDrivers = @(Get-CimInstance Win32_SystemDriver -Filter "Name LIKE '%WinDivert%'" | Select-Object -ExpandProperty Name)
    $state = [pscustomobject]@{
        Schema = 1; Token = "FuckFpt:$([guid]::NewGuid())"; Phase = 'starting'; Profile = $null
        EnginePid = $null; EngineStartedUtc = $null; LaunchPending = $false
        StartedUtc = [datetime]::UtcNow.ToString('o'); Namespaces = $script:Namespaces
        BaselineDrivers = $baselineDrivers
    }
    Write-Host 'Đang ghi journal...'
    Save-State $state  # Journal exists before any network mutation, including NRPT creation.
    try {
        Write-Host 'Đang tạo quy tắc DNS riêng cho Steam...'
        $list = Join-Path $script:Root ("steam-" + $state.Token.Substring($state.Token.IndexOf(':') + 1) + '.txt')
        $script:Domains | Set-Content -LiteralPath $list -Encoding ASCII
        Add-DnsClientNrptRule -Namespace $script:Namespaces -NameServers $script:Resolvers -Comment $state.Token | Out-Null
        Clear-DnsClientCache
        foreach ($profile in @('native', 'reverse')) {
            Write-Host "Đang thử cấu hình $profile..."
            $state.Profile = $profile
            $state.EnginePid = $null; $state.EngineStartedUtc = $null; $state.LaunchPending = $true
            Save-State $state
            $process = Start-Process -FilePath $script:Exe -ArgumentList (Get-EngineArguments $profile $list) `
                -WorkingDirectory (Join-Path $script:Root 'bin') -WindowStyle Hidden -PassThru `
                -RedirectStandardOutput (Join-Path $script:Root "$profile.stdout.log") `
                -RedirectStandardError (Join-Path $script:Root "$profile.stderr.log")
            $state.EnginePid = $process.Id; $state.EngineStartedUtc = $process.StartTime.ToUniversalTime().ToString('o')
            $state.LaunchPending = $false
            Save-State $state
            Start-Sleep -Milliseconds 700
            if ($process.HasExited) { throw "GoodbyeDPI thoát sớm; xem $script:Root\$profile.stderr.log." }
            $results = @(Invoke-Probe)
            Save-Report $results $profile
            if (@($results | Where-Object { -not $_.Pass }).Count -eq 0) {
                # Require a second pass rather than accepting a one-off success.
                $confirmation = @(Invoke-Probe)
                Save-Report $confirmation "$profile-confirm"
                if (@($confirmation | Where-Object { -not $_.Pass }).Count -eq 0 -and -not $process.HasExited) {
                    $state.Phase = 'running'; Save-State $state
                    Write-Host "Đã bật profile $profile; kiểm tra web đạt. Đăng nhập/Friends/tải game/Workshop/Market/chơi online chưa nghiệm thu."
                    return
                }
            }
            Stop-OwnedEngine $state
        }
        throw 'Cả native và reverse đều chưa đạt kiểm tra. Không có cấu hình được xác nhận.'
    } catch {
        $original = $_.Exception.Message
        try { Restore-Session $state }
        catch { throw "$original`nHoàn tác chưa hoàn tất: $($_.Exception.Message). Chạy Restore." }
        throw $original
    }
}
function Get-FuckFptStatus {
    $state = Read-State
    if ($null -eq $state) {
        return [pscustomobject]@{ Phase='stopped'; Profile=''; ProcessRunning=$false; PathVerified=$false; StartedUtc=''; EnginePid=0; RecoveryRequired=$false }
    }
    $process = Get-OwnedProcess $state -AllowLimitedVisibility
    $running = $null -ne $process
    return [pscustomobject]@{
        Phase=$state.Phase; Profile=$state.Profile; ProcessRunning=$running
        PathVerified=($running -and $process.Path -eq $script:Exe)
        StartedUtc=([datetime]$state.StartedUtc).ToUniversalTime().ToString('o')
        EnginePid=$state.EnginePid; RecoveryRequired=(-not $running -or $state.Phase -ne 'running')
    }
}
function Invoke-FuckFpt {
    [CmdletBinding()]
    param([ValidateSet('Diagnose','Start','Status','Stop','Restore','Restart')][string]$Action)
    if ($Action -eq 'Diagnose') {
        Save-Report @(Invoke-Probe) 'diagnose'
        Write-Host 'Đây là kiểm tra DNS Windows và HTTPS trực tiếp; DNS riêng/DoH trong trình duyệt có thể khác. Không tự đổi cấu hình trình duyệt.'
        return
    }
    if ($Action -eq 'Status') {
        $status = Get-FuckFptStatus
        $status | Format-List | Out-String | Write-Host
        if ($status.ProcessRunning -and -not $status.PathVerified) { Write-Host 'PID và thời điểm khởi động khớp; cần quyền quản trị để đọc đường dẫn tiến trình.' }
        if ($status.RecoveryRequired) { Write-Host 'Phiên chưa hoàn tất hoặc tiến trình đã dừng: chạy Restore.' }
        return
    }
    Assert-Admin
    if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Bản này yêu cầu PowerShell x64 trên Windows x64.' }
    Initialize-Root
    $lock = $null
    try {
        try { $lock = [IO.File]::Open((Join-Path $script:Root 'session.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw 'Một lệnh Fuck FPT khác đang thao tác. Hãy chờ lệnh đó kết thúc.' }
        if ($Action -eq 'Restart') {
            $state = Read-State
            if ($null -ne $state) { Restore-Session $state }
            Start-Session
        }
        elseif ($Action -eq 'Start') { Start-Session }
        else {
            $state = Read-State
            if ($null -eq $state) { Write-Host 'Không có phiên cần hoàn tác.' }
            else { Restore-Session $state }
        }
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}
Export-ModuleMember -Function Invoke-FuckFpt,Get-FuckFptStatus
