# AzTlsBypass.psm1 — module loader
# Dot-sources every script under Private/ then Public/.
# Public scripts must be filename = function name + .ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-private constants exposed to the dot-sourced scripts.
$script:ModuleName        = 'AzTlsBypass'
$script:ConfigDirName     = '.AzTlsBypass'
$script:ConfigFileName    = 'config.json'
$script:ProfileMarkerBegin = '# >>> AzTlsBypass >>>'
$script:ProfileMarkerEnd   = '# <<< AzTlsBypass <<<'

# IMDS / WireServer / Hyper-V hosts that must never go through the corporate
# proxy. Used as the floor of NO_PROXY when invoking az.
$script:RequiredNoProxyHosts = @(
    '169.254.169.254'
    '169.254.169.253'
    '168.63.129.16'
    'localhost'
    '127.0.0.1'
)

$script:ActiveEnvVar       = 'AZ_TLS_BYPASS_ACTIVE'
$script:LegacyActiveEnvVar = 'AZ_LOGIN_INSECURE_PATCH'
$script:CompanionEnvVars   = @(
    'AZURE_CLI_DISABLE_CONNECTION_VERIFICATION'
    'ADAL_PYTHON_SSL_NO_VERIFY'
    'PYTHONHTTPSVERIFY'
)
$script:CaBundleEnvVars    = @('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE')

# Default config used when no config.json exists yet.
$script:DefaultConfig = [pscustomobject]@{
    ProxyUrl   = $null
    NoProxy    = @()
    CaCertPath = $null
}

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    } catch {
        Write-Error -Message "Failed to import '$($file.FullName)': $_" -ErrorAction Stop
    }
}

Export-ModuleMember -Function $public.BaseName
