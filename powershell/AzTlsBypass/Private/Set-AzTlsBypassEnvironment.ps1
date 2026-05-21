function Set-AzTlsBypassEnvironment {
    <#
    .SYNOPSIS
        Configure environment variables for an az invocation with TLS bypass.

    .DESCRIPTION
        Sets ``AZ_TLS_BYPASS_ACTIVE``, the legacy ``AZ_LOGIN_INSECURE_PATCH``,
        the companion azure-cli verify-disable vars, proxy vars from the
        supplied config, and merges ``NO_PROXY`` with the required IMDS /
        WireServer hosts.  Existing ``REQUESTS_CA_BUNDLE`` /
        ``CURL_CA_BUNDLE`` env vars are cleared unless a ``CaCertPath`` is
        supplied (in which case ``REQUESTS_CA_BUNDLE`` is set to it).

        Pure side-effect function: writes only into the *current process*
        environment.  Caller is responsible for restoring or scoping.

    .PARAMETER Config
        Configuration object from ``Get-AzTlsBypassConfig``.

    .PARAMETER Scope
        ``Process`` (default) | ``User``.  ``User`` is only valid on
        Windows and persists across sessions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [ValidateSet('Process', 'User')]
        [string]$Scope = 'Process'
    )

    function _Set([string]$Name, [string]$Value) {
        if ($Scope -eq 'User') {
            [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        }
        # Always also apply to current process so it takes effect immediately.
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }

    function _Unset([string]$Name) {
        if ($Scope -eq 'User') {
            [Environment]::SetEnvironmentVariable($Name, $null, 'User')
        }
        [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
    }

    _Set $script:ActiveEnvVar       '1'
    _Set $script:LegacyActiveEnvVar '1'
    _Set 'AZURE_CLI_DISABLE_CONNECTION_VERIFICATION' '1'
    _Set 'ADAL_PYTHON_SSL_NO_VERIFY' '1'
    _Set 'PYTHONHTTPSVERIFY' '0'

    if ($Config.ProxyUrl) {
        _Set 'HTTPS_PROXY' $Config.ProxyUrl
        _Set 'HTTP_PROXY'  $Config.ProxyUrl
    }

    # Merge user-supplied NO_PROXY with mandatory IMDS/loopback entries.
    $userNoProxy = @()
    if ($Config.NoProxy) { $userNoProxy = @($Config.NoProxy) }
    $merged = @($script:RequiredNoProxyHosts + $userNoProxy) |
              Where-Object { $_ -and $_.Trim().Length -gt 0 } |
              ForEach-Object { $_.Trim() } |
              Select-Object -Unique
    _Set 'NO_PROXY' ($merged -join ',')

    if ($Config.CaCertPath -and (Test-Path -LiteralPath $Config.CaCertPath)) {
        _Set 'REQUESTS_CA_BUNDLE' (Resolve-Path -LiteralPath $Config.CaCertPath).Path
    } else {
        foreach ($v in $script:CaBundleEnvVars) { _Unset $v }
    }
}
