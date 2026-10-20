#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Diagnose', 'Start', 'Status', 'Stop', 'Restore', 'Restart')]
    [string]$Action = 'Status'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FuckFpt.psm1') -Force
try { Invoke-FuckFpt -Action $Action; exit 0 }
catch { Write-Host ("Lỗi: " + $_.Exception.Message) -ForegroundColor Red; exit 1 }
