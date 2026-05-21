<#
.SYNOPSIS
Starts az login through an HTTP proxy.

.DESCRIPTION
Use the default secure mode when you have a proxy CA certificate that Azure CLI
can validate. Use -UnsafeDisableTlsVerification only for short-lived
connectivity tests when the current proxy CA is known to be incompatible with
Azure CLI validation, such as a CA missing Authority Key Identifier.

This script changes environment variables only in the current PowerShell
process. Azure CLI config changes are reverted after az login unless
-KeepUnsafeAzConfig is specified.

.EXAMPLE
.\Start-AzLoginWithProxy.ps1

.EXAMPLE
.\Start-AzLoginWithProxy.ps1 -UnsafeDisableTlsVerification

.EXAMPLE
.\Start-AzLoginWithProxy.ps1 -UnsafeDisableTlsVerification -Tenant "00000000-0000-0000-0000-000000000000"

.EXAMPLE
.\Start-AzLoginWithProxy.ps1 -ManagedIdentity

.EXAMPLE
.\Start-AzLoginWithProxy.ps1 -ManagedIdentity -IdentityClientId "00000000-0000-0000-0000-000000000000"
#>

[CmdletBinding()]
param(
    [string]$ProxyUrl = "http://proxy.example.com:8080",

    [string]$CertificatePath = ".\corp-ca.crt",

    [string]$Tenant,

    [switch]$ManagedIdentity,

    [string]$IdentityClientId,

    [switch]$UnsafeDisableTlsVerification,

    [switch]$KeepUnsafeAzConfig,

    [switch]$DebugAzCli,

    [string[]]$NoProxyHosts = @("169.254.169.254", "localhost", "127.0.0.1")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$previousPythonPath = $env:PYTHONPATH
$previousNoProxy = $env:NO_PROXY
$previousNoProxyLower = $env:no_proxy
$script:AzCommandPath = $null
$script:AzPythonPath = $null
$script:UseAzPythonDirectly = $false

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Pass {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Merge-NoProxyHosts {
    param(
        [string]$Existing,
        [string[]]$Required
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($Existing)) {
        foreach ($item in ($Existing -split ',')) {
            $candidate = $item.Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                [void]$set.Add($candidate)
            }
        }
    }

    foreach ($requiredHost in $Required) {
        if (-not [string]::IsNullOrWhiteSpace($requiredHost)) {
            [void]$set.Add($requiredHost.Trim())
        }
    }

    return [string]::Join(',', $set)
}

function Invoke-Az {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if ($script:UseAzPythonDirectly) {
        $output = & $script:AzPythonPath -Bm azure.cli @Arguments 2>&1
    }
    else {
        $output = & $script:AzCommandPath @Arguments 2>&1
    }
    $exitCode = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -ne 0) {
        throw "az $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

try {
    Write-Step "Checking Azure CLI"
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        throw "Azure CLI was not found in PATH."
    }
    $script:AzCommandPath = $azCommand.Source
    Write-Pass "Azure CLI found: $($azCommand.Source)"

    Write-Step "Configuring proxy for this PowerShell process"
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:ALL_PROXY = $ProxyUrl
    $mergedNoProxy = Merge-NoProxyHosts -Existing $env:NO_PROXY -Required $NoProxyHosts
    $env:NO_PROXY = $mergedNoProxy
    $env:no_proxy = $mergedNoProxy
    Write-Pass "HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, and NO_PROXY are configured."

    if ($UnsafeDisableTlsVerification) {
        Write-Step "Preparing unsafe Azure CLI login fallback"
        Remove-Item Env:\REQUESTS_CA_BUNDLE -ErrorAction SilentlyContinue
        Remove-Item Env:\CURL_CA_BUNDLE -ErrorAction SilentlyContinue
        $siteCustomizePath = Join-Path $PSScriptRoot ".azure-cli-insecure-sitecustomize"
        $azWbinPath = Split-Path -Parent $azCommand.Source
        $script:AzPythonPath = Join-Path (Split-Path -Parent $azWbinPath) "python.exe"
        if (-not (Test-Path -Path $script:AzPythonPath)) {
            throw "Azure CLI Python executable was not found: $script:AzPythonPath"
        }
        $script:UseAzPythonDirectly = $true
        $env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION = "1"
        $env:ADAL_PYTHON_SSL_NO_VERIFY = "1"
        $env:PYTHONHTTPSVERIFY = "0"
        $env:AZ_LOGIN_INSECURE_PATCH = "1"
        if ($env:PYTHONPATH) {
            $env:PYTHONPATH = "$siteCustomizePath$([IO.Path]::PathSeparator)$env:PYTHONPATH"
        }
        else {
            $env:PYTHONPATH = $siteCustomizePath
        }
        Invoke-Az -Arguments @("config", "set", "core.disable_connection_verification=true")
        Write-Warn "TLS certificate verification is disabled for Azure CLI and MSAL requests. Use only for temporary connectivity testing."
    }
    else {
        Write-Step "Configuring custom CA bundle"
        $resolvedCertificate = (Resolve-Path -Path $CertificatePath).Path
        $env:REQUESTS_CA_BUNDLE = $resolvedCertificate
        $env:CURL_CA_BUNDLE = $resolvedCertificate
        Remove-Item Env:\AZURE_CLI_DISABLE_CONNECTION_VERIFICATION -ErrorAction SilentlyContinue
        Remove-Item Env:\ADAL_PYTHON_SSL_NO_VERIFY -ErrorAction SilentlyContinue
        Remove-Item Env:\PYTHONHTTPSVERIFY -ErrorAction SilentlyContinue
        Remove-Item Env:\AZ_LOGIN_INSECURE_PATCH -ErrorAction SilentlyContinue
        Invoke-Az -Arguments @("config", "unset", "core.disable_connection_verification")
        Write-Pass "REQUESTS_CA_BUNDLE and CURL_CA_BUNDLE are set to $resolvedCertificate"
    }

    if ($ManagedIdentity) {
        Write-Step "Starting az login with managed identity"
        $loginArgs = @("login", "--identity")
        if (-not [string]::IsNullOrWhiteSpace($IdentityClientId)) {
            $loginArgs += @("--client-id", $IdentityClientId)
        }
    }
    else {
        Write-Step "Starting az login with browser authentication"
        $loginArgs = @("login")
        if (-not [string]::IsNullOrWhiteSpace($Tenant)) {
            $loginArgs += @("--tenant", $Tenant)
        }
    }
    if ($DebugAzCli) {
        $loginArgs += "--debug"
    }
    Invoke-Az -Arguments $loginArgs

    Write-Step "Checking active Azure account"
    Invoke-Az -Arguments @("account", "show", "--output", "table")
    Write-Pass "Azure CLI login completed."
}
finally {
    if ($null -eq $previousNoProxy) {
        Remove-Item Env:\NO_PROXY -ErrorAction SilentlyContinue
    }
    else {
        $env:NO_PROXY = $previousNoProxy
    }
    if ($null -eq $previousNoProxyLower) {
        Remove-Item Env:\no_proxy -ErrorAction SilentlyContinue
    }
    else {
        $env:no_proxy = $previousNoProxyLower
    }

    if ($UnsafeDisableTlsVerification -and -not $KeepUnsafeAzConfig) {
        Write-Step "Cleaning up unsafe Azure CLI config"
        Remove-Item Env:\AZURE_CLI_DISABLE_CONNECTION_VERIFICATION -ErrorAction SilentlyContinue
        Remove-Item Env:\ADAL_PYTHON_SSL_NO_VERIFY -ErrorAction SilentlyContinue
        Remove-Item Env:\PYTHONHTTPSVERIFY -ErrorAction SilentlyContinue
        Remove-Item Env:\AZ_LOGIN_INSECURE_PATCH -ErrorAction SilentlyContinue
        if ($null -eq $previousPythonPath) {
            Remove-Item Env:\PYTHONPATH -ErrorAction SilentlyContinue
        }
        else {
            $env:PYTHONPATH = $previousPythonPath
        }
        & az config unset core.disable_connection_verification 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "Disabled core.disable_connection_verification."
        }
        else {
            Write-Warn "Could not unset core.disable_connection_verification automatically. Run: az config unset core.disable_connection_verification"
        }
    }
}
