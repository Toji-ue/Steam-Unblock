Import-Module "$PSScriptRoot\FuckFpt.psm1" -Force

InModuleScope FuckFpt {
    Describe 'FuckFpt safety and lifecycle' {
        Context 'domain file serialization' {
        It 'keeps file-loaded namespaces as plain JSON strings without provider metadata' {
            $json = ConvertTo-Json -InputObject $script:Namespaces -Depth 2
            ($json -match 'PSDrive|PSPath|Provider|ReadCount') | Should Be $false
            $decoded = ConvertFrom-Json -InputObject $json
            $decoded.Count | Should Be ($script:Domains.Count * 2)
            foreach ($item in $decoded) { ($item -is [string]) | Should Be $true }
        }
        }
        Context 'rejects non-public DNS destinations' {
        It 'rejects non-public DNS destinations' {
            foreach ($ip in @('127.0.0.1','0.0.0.0','10.1.2.3','192.168.1.1','172.16.1.1','100.64.1.1','::1','fe80::1','garbage')) {
                (Test-PublicAddress $ip) | Should Be $false
            }
            (Test-PublicAddress '23.0.222.94') | Should Be $true
            (Test-PublicAddress '2606:4700:4700::1111') | Should Be $true
        }
        }
        Context 'detects parent, child and catch-all NRPT conflicts but not suffix lookalikes' {
        It 'detects parent, child and catch-all NRPT conflicts but not suffix lookalikes' {
            (Test-NamespaceOverlap '.' 'steampowered.com') | Should Be $true
            (Test-NamespaceOverlap '.com' 'steampowered.com') | Should Be $true
            (Test-NamespaceOverlap 'store.steampowered.com' 'steampowered.com') | Should Be $true
            (Test-NamespaceOverlap 'notsteampowered.com' 'steampowered.com') | Should Be $false
        }
        }
        Context 'never enables unscoped DPI or DNS options' {
        It 'never enables unscoped DPI or DNS options' {
            foreach ($profile in @('native','reverse')) {
                $args = Get-EngineArguments $profile
                ($args -contains '--blacklist') | Should Be $true
                ($args -contains "-9") | Should Be $false
                foreach ($forbidden in @('-q','-p','--allow-no-sni','--dns-addr','--dnsv6-addr')) {
                    ($args -contains $forbidden) | Should Be $false
                }
            }
            { Get-EngineArguments 'unknown' } | Should Throw
        }
        }
        Context 'fails closed for missing or tampered packages' {
        It 'fails closed for missing or tampered packages' {
            { Assert-Hash "$TestDrive\missing.zip" ('0' * 64) } | Should Throw
            Set-Content "$TestDrive\bad.zip" 'tampered'
            { Assert-Hash "$TestDrive\bad.zip" ('0' * 64) } | Should Throw
        }
        }
        Context 'requires admin before mutating operations' {
        It 'requires admin before mutating operations' {
            Mock Test-Admin { $false }
            Mock Initialize-Root { throw 'must not be reached' }
            { Invoke-FuckFpt Start } | Should Throw
            Assert-MockCalled Initialize-Root -Times 0 -Exactly
        }
        }
        Context 'does not create another running session' {
        It 'does not create another running session' {
            Mock Read-State { [pscustomobject]@{ Phase='running'; Profile='native' } }
            Mock Get-OwnedProcess { [pscustomobject]@{ Id=999 } }
            Mock Get-Conflicts { throw 'must not be reached' }
            Start-Session
            Assert-MockCalled Get-Conflicts -Times 0 -Exactly
        }
        }
        Context 'requires recovery after an interrupted session or dead process' {
        It 'requires recovery after an interrupted session or dead process' {
            Mock Read-State { [pscustomobject]@{ Phase='running'; Profile='native' } }
            Mock Get-OwnedProcess { $null }
            Mock Install-Engine {}
            { Start-Session } | Should Throw
            Assert-MockCalled Install-Engine -Times 0 -Exactly
        }
        }
        Context 'stops before downloading or changing DNS on conflict' {
        It 'stops before downloading or changing DNS on conflict' {
            Mock Read-State { $null }
            Mock Get-Conflicts { 'active tunnel' }
            Mock Install-Engine {}
            Mock Add-DnsClientNrptRule {}
            { Start-Session } | Should Throw
            Assert-MockCalled Install-Engine -Times 0 -Exactly
            Assert-MockCalled Add-DnsClientNrptRule -Times 0 -Exactly
        }
        }
        Context 'does not change DNS if installation fails' {
        It 'does not change DNS if installation fails' {
            Mock Read-State { $null }
            Mock Get-Conflicts {}
            Mock Install-Engine { throw 'download failed' }
            Mock Add-DnsClientNrptRule {}
            { Start-Session } | Should Throw
            Assert-MockCalled Add-DnsClientNrptRule -Times 0 -Exactly
        }
        }
        Context 'rolls back if rule creation fails after journaling' {
        It 'rolls back if rule creation fails after journaling' {
            Mock Read-State { $null }
            Mock Get-Conflicts {}
            Mock Install-Engine {}
            Mock Invoke-Probe { [pscustomobject]@{ Host='store.steampowered.com'; Pass=$false } }
            Mock Save-Report {}
            Mock Get-CimInstance {}
            Mock Save-State {}
            Mock Set-Content {}
            Mock Add-DnsClientNrptRule { throw 'partial NRPT failure' }
            Mock Restore-Session {}
            { Start-Session } | Should Throw
            Assert-MockCalled Save-State -Times 1 -Exactly
            Assert-MockCalled Restore-Session -Times 1 -Exactly
        }
        }
        Context 'only removes rules bearing the session ownership marker' {
        It 'only removes rules bearing the session ownership marker' {
            $state = [pscustomobject]@{ Token='FuckFpt:test'; Namespaces=@('steampowered.com','.steampowered.com') }
            Mock Stop-OwnedEngine {}
            Mock Get-DnsClientNrptRule {
                [pscustomobject]@{ Name='ours'; Comment='FuckFpt:test'; Namespace=@('steampowered.com','.steampowered.com'); NameServers='1.1.1.1;8.8.8.8' }
                [pscustomobject]@{ Name='other'; Comment='other'; Namespace=@('.example.com'); NameServers=@('9.9.9.9') }
            }
            Mock Remove-DnsClientNrptRule {}
            Mock Clear-DnsClientCache {}
            Mock Remove-OwnedDriver {}
            Mock Remove-Item {}
            Restore-Session $state
            Assert-MockCalled Remove-DnsClientNrptRule -Times 1 -Exactly -ParameterFilter { $Name -eq 'ours' }
            Assert-MockCalled Remove-DnsClientNrptRule -Times 0 -Exactly -ParameterFilter { $Name -eq 'other' }
        }
        }
        Context 'preserves modified owned rules and recovery state' {
        It 'preserves modified owned rules and recovery state' {
            Mock Stop-OwnedEngine {}
            Mock Get-DnsClientNrptRule {
                [pscustomobject]@{ Name='ours'; Comment='FuckFpt:test'; Namespace=@('.example.com'); NameServers=@('1.1.1.1') }
            }
            Mock Remove-DnsClientNrptRule {}
            Mock Remove-Item {}
            { Restore-Session ([pscustomobject]@{ Token='FuckFpt:test'; Namespaces=@('.steampowered.com') }) } | Should Throw
            Assert-MockCalled Remove-DnsClientNrptRule -Times 0 -Exactly
            Assert-MockCalled Remove-Item -Times 0 -Exactly
        }
        }
        Context 'profile fallback' {
        It 'tries native first and accepts reverse only after two successful passes' {
            $script:ProbeIndex = 0
            $script:SavedPhases = @()
            Mock Read-State { $null }
            Mock Get-Conflicts {}
            Mock Install-Engine {}
            Mock Invoke-Probe {
                $script:ProbeIndex++
                [pscustomobject]@{ Host='store.steampowered.com'; Pass=($script:ProbeIndex -gt 2) }
            }
            Mock Save-Report {}
            Mock Get-CimInstance {}
            Mock Save-State { $script:SavedPhases += $State.Phase }
            Mock Set-Content {}
            Mock Add-DnsClientNrptRule {}
            Mock Clear-DnsClientCache {}
            Mock Start-Sleep {}
            Mock Start-Process { [pscustomobject]@{ Id=12345; StartTime=(Get-Date); HasExited=$false } }
            Mock Stop-OwnedEngine {}
            Mock Restore-Session {}
            Start-Session
            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '--native-frag' }
            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '--reverse-frag' }
            Assert-MockCalled Invoke-Probe -Times 4 -Exactly
            Assert-MockCalled Restore-Session -Times 0 -Exactly
            @($script:SavedPhases | Where-Object { $_ -eq 'running' }).Count | Should Be 1
        }
        }
        Context 'no passing profile' {
        It 'restores all owned changes when both profiles fail' {
            Mock Read-State { $null }
            Mock Get-Conflicts {}
            Mock Install-Engine {}
            Mock Invoke-Probe { [pscustomobject]@{ Host='store.steampowered.com'; Pass=$false } }
            Mock Save-Report {}
            Mock Get-CimInstance {}
            Mock Save-State {}
            Mock Set-Content {}
            Mock Add-DnsClientNrptRule {}
            Mock Clear-DnsClientCache {}
            Mock Start-Sleep {}
            Mock Start-Process { [pscustomobject]@{ Id=12345; StartTime=(Get-Date); HasExited=$false } }
            Mock Stop-OwnedEngine {}
            Mock Restore-Session {}
            { Start-Session } | Should Throw
            Assert-MockCalled Start-Process -Times 2 -Exactly
            Assert-MockCalled Restore-Session -Times 1 -Exactly
        }
        }
        Context 'PID reuse' {
        It 'never claims a reused PID with a different creation time' {
            Mock Get-Process { [pscustomobject]@{ Path=$script:Exe; StartTime=[datetime]'2026-10-20T01:00:01Z' } }
            $state = [pscustomobject]@{ EnginePid=12345; EngineStartedUtc='2026-10-20T01:00:00Z'; LaunchPending=$false }
            ($null -eq (Get-OwnedProcess $state)) | Should Be $true
        }
        }
        Context 'process identity compatibility' {
        It 'preserves fractional seconds when JSON dates are already DateTime objects' {
            Mock Get-Process { [pscustomobject]@{ Id=12345; Path=$script:Exe; ProcessName='goodbyedpi'; StartTime=[datetime]'2026-10-20T01:00:00.1234567Z' } }
            $state = [pscustomobject]@{ EnginePid=12345; EngineStartedUtc=[datetime]'2026-10-20T01:00:00.1234567Z'; LaunchPending=$false }
            (Get-OwnedProcess $state).Id | Should Be 12345
        }
        }
        Context 'unprivileged status' {
        It 'can observe the recorded process but never authorizes stopping it without its path' {
            Mock Get-Process { [pscustomobject]@{ Id=12345; Path=$null; ProcessName='goodbyedpi'; StartTime=[datetime]'2026-10-20T01:00:00Z' } }
            $state = [pscustomobject]@{ EnginePid=12345; EngineStartedUtc='2026-10-20T01:00:00Z'; LaunchPending=$false }
            ($null -eq (Get-OwnedProcess $state)) | Should Be $true
            (Get-OwnedProcess $state -AllowLimitedVisibility).Id | Should Be 12345
        }
        }
        Context 'state journal' {
        It 'writes and atomically replaces a valid recovery state' {
            $previous = $script:StatePath
            try {
                $script:StatePath = Join-Path $TestDrive 'state.json'
                $state = [pscustomobject]@{ Schema=1; Token="FuckFpt:$([guid]::NewGuid())"; Phase='starting' }
                Save-State $state
                (Read-State).Phase | Should Be 'starting'
                $state.Phase = 'running'
                Save-State $state
                (Read-State).Phase | Should Be 'running'
                (Test-Path "$script:StatePath.tmp") | Should Be $false
            } finally { $script:StatePath = $previous }
        }
        }
        Context 'concurrent commands' {
        It 'holds an exclusive file lock and releases it after disposal' {
            $path = Join-Path $TestDrive 'session.lock'
            $first = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
            try {
                { $second = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None'); $second.Dispose() } | Should Throw
            } finally { $first.Dispose() }
            $second = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
            $second.Dispose()
        }
        }
        Context 'driver self-removal' {
        It 'accepts service already gone after stopping and verifies its absence' {
            $script:DriverQueries = 0
            Mock Get-CimInstance {
                $script:DriverQueries++
                if ($script:DriverQueries -eq 1) {
                    [pscustomobject]@{ Name='WinDivert'; State='Running'; PathName=('\??\' + (Join-Path $script:Root 'bin\WinDivert64.sys')) }
                }
            }
            Mock Invoke-ServiceControl { if ($Action -eq 'stop') { 0 } else { 1060 } }
            Remove-OwnedDriver ([pscustomobject]@{ BaselineDrivers=@() })
            Assert-MockCalled Invoke-ServiceControl -Times 1 -Exactly -ParameterFilter { $Action -eq 'delete' }
            $script:DriverQueries | Should Be 2
        }
        }
        Context 'foreign driver ownership' {
        It 'never stops or deletes a driver registered from another location' {
            Mock Get-CimInstance { [pscustomobject]@{ Name='WinDivert'; State='Running'; PathName='C:\OtherApp\WinDivert64.sys' } }
            Mock Invoke-ServiceControl {}
            Remove-OwnedDriver ([pscustomobject]@{ BaselineDrivers=@() })
            Assert-MockCalled Invoke-ServiceControl -Times 0 -Exactly
        }
        }
    }
}
