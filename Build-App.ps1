#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$output = Join-Path $PSScriptRoot 'FuckFpt.exe'
if (-not (Test-Path $compiler)) { throw 'Cần .NET Framework 4.x x64 có sẵn trên Windows.' }
$arguments = @('/nologo','/target:winexe','/platform:x64','/optimize+',('/out:' + $output),('/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')),('/win32icon:' + (Join-Path $PSScriptRoot 'app.ico')),('/resource:' + (Join-Path $PSScriptRoot 'app.ico') + ',App.ico'),
    '/reference:System.dll','/reference:System.Core.dll','/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll','/reference:System.Xaml.dll')
$wpf = Join-Path (Split-Path $compiler) 'WPF'
foreach ($name in @('PresentationFramework.dll','PresentationCore.dll','WindowsBase.dll')) { $arguments += '/reference:' + (Join-Path $wpf $name) }
foreach ($name in @('FuckFpt.psm1','AppWorker.ps1','steam-domains.txt','manifest.json')) {
    $arguments += '/resource:' + (Join-Path $PSScriptRoot $name) + ',Payload.' + $name
}
$arguments += Join-Path $PSScriptRoot 'FuckFpt.App.cs'
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'Biên dịch ứng dụng thất bại.' }
Get-FileHash -LiteralPath $output -Algorithm SHA256
