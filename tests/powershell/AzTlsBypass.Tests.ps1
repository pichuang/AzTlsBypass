#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester tests for the AzTlsBypass PowerShell module.

.NOTES
    Cross-platform: skips Windows-only paths when running on macOS/Linux,
    but still exercises config, env, profile, and idempotency logic.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    $script:ModulePath = Join-Path $RepoRoot 'powershell/AzTlsBypass/AzTlsBypass.psd1'

    # Use an isolated $HOME for config + profile tests so we never touch the
    # developer's real ~/.AzTlsBypass or $PROFILE.
    $script:TestHome = Join-Path ([IO.Path]::GetTempPath()) ("AzTlsBypass-test-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null

    $script:OriginalHome      = $env:HOME
    $script:OriginalUserProf  = $env:USERPROFILE
    $env:HOME        = $script:TestHome
    $env:USERPROFILE = $script:TestHome

    Import-Module $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module AzTlsBypass -Force -ErrorAction SilentlyContinue
    if ($script:TestHome -and (Test-Path $script:TestHome)) {
        Remove-Item $script:TestHome -Recurse -Force -ErrorAction SilentlyContinue
    }
    $env:HOME        = $script:OriginalHome
    $env:USERPROFILE = $script:OriginalUserProf
}

Describe 'AzTlsBypass module manifest' {
    It 'has the expected public functions' {
        $mod = Get-Module AzTlsBypass
        $expected = @(
            'Enable-AzTlsBypass'
            'Disable-AzTlsBypass'
            'Get-AzTlsBypassStatus'
            'Invoke-AzWithBypass'
            'Set-AzTlsBypassConfig'
            'Get-AzTlsBypassConfig'
            'Clear-AzTlsBypassConfig'
        )
        foreach ($name in $expected) {
            $mod.ExportedFunctions.Keys | Should -Contain $name
        }
    }

    It 'targets PowerShell 5.1 or newer' {
        $manifest = Import-PowerShellDataFile -Path $script:ModulePath
        $manifest.PowerShellVersion | Should -Be '5.1'
    }
}

Describe 'Config round-trip' {
    BeforeEach {
        Clear-AzTlsBypassConfig -Confirm:$false -ErrorAction SilentlyContinue
    }

    It 'returns empty default when no file exists' {
        $cfg = Get-AzTlsBypassConfig
        $cfg.ProxyUrl   | Should -BeNullOrEmpty
        $cfg.NoProxy    | Should -BeNullOrEmpty
        $cfg.CaCertPath | Should -BeNullOrEmpty
    }

    It 'persists ProxyUrl and reads it back' {
        Set-AzTlsBypassConfig -ProxyUrl 'http://10.0.0.1:8080' -Confirm:$false | Out-Null
        $cfg = Get-AzTlsBypassConfig
        $cfg.ProxyUrl | Should -Be 'http://10.0.0.1:8080'
    }

    It 'persists NoProxy as an array' {
        Set-AzTlsBypassConfig -ProxyUrl 'http://p:8080' -NoProxy @('a.com', 'b.com') -Confirm:$false | Out-Null
        $cfg = Get-AzTlsBypassConfig
        $cfg.NoProxy | Should -Contain 'a.com'
        $cfg.NoProxy | Should -Contain 'b.com'
    }

    It 'preserves unspecified fields on partial update' {
        Set-AzTlsBypassConfig -ProxyUrl 'http://p:8080' -CaCertPath '/tmp/ca.pem' -Confirm:$false | Out-Null
        Set-AzTlsBypassConfig -NoProxy @('z.com') -Confirm:$false | Out-Null
        $cfg = Get-AzTlsBypassConfig
        $cfg.ProxyUrl   | Should -Be 'http://p:8080'
        $cfg.CaCertPath | Should -Be '/tmp/ca.pem'
        $cfg.NoProxy    | Should -Contain 'z.com'
    }

    It 'Clear-AzTlsBypassConfig removes the file' {
        Set-AzTlsBypassConfig -ProxyUrl 'http://p:8080' -Confirm:$false | Out-Null
        Clear-AzTlsBypassConfig -Confirm:$false
        $path = Join-Path $script:TestHome '.AzTlsBypass/config.json'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'Enable / Disable environment behavior' {
    BeforeEach {
        Clear-AzTlsBypassConfig -Confirm:$false -ErrorAction SilentlyContinue
        # 'function:global:az' is parsed as an item-name (not scope) by the
        # function provider for Remove-Item; dispatching through a child
        # scope is the only reliable removal idiom.
        & { Remove-Item function:az -Force -ErrorAction SilentlyContinue }
        foreach ($v in @(
            'AZ_TLS_BYPASS_ACTIVE', 'AZ_LOGIN_INSECURE_PATCH',
            'AZURE_CLI_DISABLE_CONNECTION_VERIFICATION',
            'ADAL_PYTHON_SSL_NO_VERIFY', 'PYTHONHTTPSVERIFY',
            'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY',
            'REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE'
        )) {
            [Environment]::SetEnvironmentVariable($v, $null, 'Process')
        }
    }

    It 'sets the primary and legacy active env vars' {
        Enable-AzTlsBypass -NoBanner
        [Environment]::GetEnvironmentVariable('AZ_TLS_BYPASS_ACTIVE', 'Process') | Should -Be '1'
        [Environment]::GetEnvironmentVariable('AZ_LOGIN_INSECURE_PATCH', 'Process') | Should -Be '1'
    }

    It 'sets companion azure-cli env vars' {
        Enable-AzTlsBypass -NoBanner
        [Environment]::GetEnvironmentVariable('AZURE_CLI_DISABLE_CONNECTION_VERIFICATION', 'Process') | Should -Be '1'
        [Environment]::GetEnvironmentVariable('ADAL_PYTHON_SSL_NO_VERIFY', 'Process') | Should -Be '1'
        [Environment]::GetEnvironmentVariable('PYTHONHTTPSVERIFY', 'Process') | Should -Be '0'
    }

    It 'merges NO_PROXY with required IMDS hosts' {
        Set-AzTlsBypassConfig -ProxyUrl 'http://p:8080' -NoProxy @('foo.com') -Confirm:$false | Out-Null
        Enable-AzTlsBypass -NoBanner
        $np = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Process')
        $np | Should -Match '169\.254\.169\.254'
        $np | Should -Match 'foo\.com'
        $np | Should -Match 'localhost'
    }

    It 'sets HTTPS_PROXY from config' {
        Set-AzTlsBypassConfig -ProxyUrl 'http://proxy.example:8000' -Confirm:$false | Out-Null
        Enable-AzTlsBypass -NoBanner
        [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') | Should -Be 'http://proxy.example:8000'
    }

    It 'removes CA bundle env vars when no CaCertPath configured' {
        [Environment]::SetEnvironmentVariable('REQUESTS_CA_BUNDLE', '/tmp/stale.pem', 'Process')
        [Environment]::SetEnvironmentVariable('CURL_CA_BUNDLE',     '/tmp/stale.pem', 'Process')
        Enable-AzTlsBypass -NoBanner
        [Environment]::GetEnvironmentVariable('REQUESTS_CA_BUNDLE', 'Process') | Should -BeNullOrEmpty
        [Environment]::GetEnvironmentVariable('CURL_CA_BUNDLE',     'Process') | Should -BeNullOrEmpty
    }

    It 'defines a global az function override' {
        Enable-AzTlsBypass -NoBanner
        # Use 'function:az' (no 'global:' prefix) so the function provider
        # walks the scope chain up to global, matching Set-Item semantics.
        Test-Path function:az | Should -BeTrue
        (Get-Item function:az).ScriptBlock.ToString() | Should -Match 'Invoke-AzWithBypass'
    }

    It 'Disable-AzTlsBypass removes the function and clears env' {
        Enable-AzTlsBypass -NoBanner
        Disable-AzTlsBypass
        Test-Path function:az | Should -BeFalse
        [Environment]::GetEnvironmentVariable('AZ_TLS_BYPASS_ACTIVE', 'Process') | Should -BeNullOrEmpty
        [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') | Should -BeNullOrEmpty
    }
}

Describe 'Get-AzTlsBypassStatus' {
    BeforeEach {
        & { Remove-Item function:az -Force -ErrorAction SilentlyContinue }
        [Environment]::SetEnvironmentVariable('AZ_TLS_BYPASS_ACTIVE', $null, 'Process')
    }

    It 'reports Active=false when nothing is set' {
        $st = Get-AzTlsBypassStatus
        $st.Active           | Should -BeFalse
        $st.EnvActive        | Should -BeFalse
        $st.FunctionOverride | Should -BeFalse
    }

    It 'reports Active=true after Enable-AzTlsBypass' {
        Enable-AzTlsBypass -NoBanner
        $st = Get-AzTlsBypassStatus
        $st.Active           | Should -BeTrue
        $st.EnvActive        | Should -BeTrue
        $st.FunctionOverride | Should -BeTrue
    }
}

Describe 'Profile persistence (idempotent)' {
    BeforeAll {
        $script:FakeProfileDir = Join-Path $script:TestHome 'fake-profile'
        $script:FakeProfilePath = Join-Path $script:FakeProfileDir 'profile.ps1'
        New-Item -ItemType Directory -Path $script:FakeProfileDir -Force | Out-Null
    }

    BeforeEach {
        Set-Content -LiteralPath $script:FakeProfilePath -Value "# pre-existing user content`r`nWrite-Host 'hello'`r`n" -Encoding UTF8

        # Stub $PROFILE.CurrentUserAllHosts to point at our fake file by
        # rebuilding the $PROFILE PSObject for this scope.
        $script:OriginalProfile = $PROFILE
        $newProfile = [pscustomobject]@{
            CurrentUserAllHosts   = $script:FakeProfilePath
            CurrentUserCurrentHost = $script:FakeProfilePath
            AllUsersAllHosts      = $script:FakeProfilePath
            AllUsersCurrentHost   = $script:FakeProfilePath
        }
        Set-Variable -Name PROFILE -Value $newProfile -Scope Global -Force
    }

    AfterEach {
        Set-Variable -Name PROFILE -Value $script:OriginalProfile -Scope Global -Force
    }

    It 'injects an AzTlsBypass block on -Persist' {
        Enable-AzTlsBypass -Persist -NoBanner -Confirm:$false
        $content = Get-Content -LiteralPath $script:FakeProfilePath -Raw
        $content | Should -Match '# >>> AzTlsBypass >>>'
        $content | Should -Match '# <<< AzTlsBypass <<<'
        $content | Should -Match 'Enable-AzTlsBypass'
    }

    It 'is idempotent (no duplicate blocks on re-Persist)' {
        Enable-AzTlsBypass -Persist -NoBanner -Confirm:$false
        Enable-AzTlsBypass -Persist -NoBanner -Confirm:$false
        $content = Get-Content -LiteralPath $script:FakeProfilePath -Raw
        $matches = [regex]::Matches($content, '# >>> AzTlsBypass >>>')
        $matches.Count | Should -Be 1
    }

    It 'preserves pre-existing user content' {
        Enable-AzTlsBypass -Persist -NoBanner -Confirm:$false
        $content = Get-Content -LiteralPath $script:FakeProfilePath -Raw
        $content | Should -Match "Write-Host 'hello'"
    }

    It 'Disable -Persist removes the block but keeps user content' {
        Enable-AzTlsBypass  -Persist -NoBanner -Confirm:$false
        Disable-AzTlsBypass -Persist          -Confirm:$false
        $content = Get-Content -LiteralPath $script:FakeProfilePath -Raw
        $content | Should -Not -Match '# >>> AzTlsBypass >>>'
        $content | Should -Match     "Write-Host 'hello'"
    }
}

Describe 'PSScriptAnalyzer baseline' -Tag 'Lint' {
    It 'has no Error-severity findings' -Skip:(-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Import-Module PSScriptAnalyzer -ErrorAction Stop
        $modDir = Join-Path $script:RepoRoot 'powershell/AzTlsBypass'
        $results = Invoke-ScriptAnalyzer -Path $modDir -Recurse -Severity Error
        if ($results) {
            $results | Format-Table -AutoSize | Out-String | Write-Host
        }
        $results.Count | Should -Be 0
    }
}
