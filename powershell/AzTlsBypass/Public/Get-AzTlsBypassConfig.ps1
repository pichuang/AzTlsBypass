function Get-AzTlsBypassConfig {
    <#
    .SYNOPSIS
        Load the AzTlsBypass JSON configuration.

    .DESCRIPTION
        Reads ``$HOME/.AzTlsBypass/config.json`` and returns a normalized
        configuration object.  When the file does not exist, returns a
        copy of the default (all-null) config.

    .OUTPUTS
        [pscustomobject] with ProxyUrl, NoProxy, CaCertPath.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $path = Get-AzTlsBypassConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            ProxyUrl   = $null
            NoProxy    = @()
            CaCertPath = $null
        }
    }

    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
            ProxyUrl   = $null
            NoProxy    = @()
            CaCertPath = $null
        }
    }

    $obj = $raw | ConvertFrom-Json
    return [pscustomobject]@{
        ProxyUrl   = $obj.ProxyUrl
        NoProxy    = @($obj.NoProxy)
        CaCertPath = $obj.CaCertPath
    }
}
