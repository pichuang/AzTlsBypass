function Set-AzTlsBypassConfig {
    <#
    .SYNOPSIS
        Persist AzTlsBypass configuration to the JSON file.

    .DESCRIPTION
        Writes ``$HOME/.AzTlsBypass/config.json`` with the supplied
        ProxyUrl, NoProxy hosts, and optional CaCertPath.  Existing values
        are preserved when their corresponding parameter is not supplied
        (use ``Clear-AzTlsBypassConfig`` to start fresh).

    .PARAMETER ProxyUrl
        Corporate proxy URL (e.g. ``http://proxy.example.com:8080``).

    .PARAMETER NoProxy
        Extra hostnames/CIDRs that bypass the proxy.  Mandatory IMDS hosts
        (``169.254.169.254`` etc.) are appended automatically at runtime
        and need not be listed here.

    .PARAMETER CaCertPath
        Path to a PEM CA bundle used as ``REQUESTS_CA_BUNDLE``.  When
        omitted, TLS verification is disabled entirely.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ProxyUrl,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]]$NoProxy,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$CaCertPath
    )

    $current = Get-AzTlsBypassConfig

    if ($PSBoundParameters.ContainsKey('ProxyUrl')) {
        $current.ProxyUrl = $ProxyUrl
    }
    if ($PSBoundParameters.ContainsKey('NoProxy')) {
        $current.NoProxy = @($NoProxy)
    }
    if ($PSBoundParameters.ContainsKey('CaCertPath')) {
        $current.CaCertPath = $CaCertPath
    }

    $dir = Get-AzTlsBypassConfigPath -Directory
    if (-not (Test-Path -LiteralPath $dir)) {
        if ($PSCmdlet.ShouldProcess($dir, 'Create AzTlsBypass config directory')) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $path = Get-AzTlsBypassConfigPath
    if ($PSCmdlet.ShouldProcess($path, 'Write AzTlsBypass config')) {
        ($current | ConvertTo-Json -Depth 4) |
            Set-Content -LiteralPath $path -Encoding UTF8
    }

    return $current
}
