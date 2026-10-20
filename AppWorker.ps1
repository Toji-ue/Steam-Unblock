#Requires -Version 5.1
param([ValidateSet('Status','Diagnose','Start','Stop','Restart')][string]$Action='Status')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
Import-Module (Join-Path $PSScriptRoot 'FuckFpt.psm1') -Force
$ok = $true; $message = ''; $status = $null; $report = $null
# Progress goes to stdout line by line as it happens so the app can show a live log; the JSON result is the last line.
function Say([string]$Text) { foreach ($line in ($Text -split "`r?`n")) { if ($line.Trim()) { [Console]::WriteLine($line) } } }
try {
    if ($Action -ne 'Status') {
        $lines = New-Object 'Collections.Generic.List[string]'
        Invoke-FuckFpt -Action $Action *>&1 | ForEach-Object { $text = "$_"; Say $text; $lines.Add($text) }
        $message = ($lines -join "`r`n").Trim()
    }
} catch { $ok = $false; $message = $_.Exception.Message; Say "Lỗi: $message" }
try { $status = Get-FuckFptStatus }
catch { $ok = $false; $message += "`r`nKhông đọc được trạng thái: $($_.Exception.Message)"; Say "Không đọc được trạng thái: $($_.Exception.Message)" }
$latest = Get-ChildItem (Join-Path $PSScriptRoot 'reports') -Filter '*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
if ($null -ne $latest) {
    try { $report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json }
    catch { $message += "`r`nKhông đọc được báo cáo gần nhất." }
}
$response = [ordered]@{ Ok=$ok; Message=$message; Status=$status; Report=$report }
[Console]::WriteLine(($response | ConvertTo-Json -Depth 8 -Compress))
if (-not $ok) { exit 1 }
exit 0
