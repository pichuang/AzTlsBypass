<#
.SYNOPSIS
One-click repair and login launcher for Azure CLI behind an HTTP proxy.

.DESCRIPTION
Designed for Windows PowerShell 5.1 users. This script does not require git
or git apply. It repairs the Python TLS fallback shim used by
Start-AzLoginWithProxy.ps1, validates the helper, and optionally starts login.
#>

[CmdletBinding()]
param(
    [string]$ProxyUrl = "http://proxy.example.com:8080",
    [string]$Tenant = "b449d301-e285-4551-8467-773bebf5ed31",
    [switch]$RunLogin,
    [switch]$DebugAzCli
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Message) Write-Host ""; Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Pass { param([string]$Message) Write-Host "[PASS] $Message" -ForegroundColor Green }

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$helper = Join-Path $root "Start-AzLoginWithProxy.ps1"
$shimDir = Join-Path $root ".azure-cli-insecure-sitecustomize"
$shim = Join-Path $shimDir "sitecustomize.py"

Write-Step "Checking required files"
if (-not (Test-Path $helper)) {
    throw "Missing Start-AzLoginWithProxy.ps1. Put this repair script in the same folder as Start-AzLoginWithProxy.ps1."
}
if (-not (Test-Path $shimDir)) {
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
}

@'
import os

if os.environ.get("AZ_LOGIN_INSECURE_PATCH") == "1":
    import requests
    import urllib3

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    _original_request = requests.sessions.Session.request
    _original_merge_environment_settings = requests.sessions.Session.merge_environment_settings

    def _request_without_tls_verification(self, method, url, **kwargs):
        kwargs["verify"] = False
        return _original_request(self, method, url, **kwargs)

    def _merge_environment_settings_without_tls_verification(self, url, proxies, stream, verify, cert):
        settings = _original_merge_environment_settings(self, url, proxies, stream, verify, cert)
        settings["verify"] = False
        return settings

    requests.sessions.Session.request = _request_without_tls_verification
    requests.sessions.Session.merge_environment_settings = _merge_environment_settings_without_tls_verification
'@ | Set-Content -Path $shim -Encoding UTF8
Write-Pass "Repaired Python shim"

Write-Step "Validating helper"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($helper, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
    throw "Start-AzLoginWithProxy.ps1 has syntax errors."
}
Write-Pass "PowerShell syntax OK"

$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
    throw "Azure CLI was not found in PATH."
}
Write-Pass "Azure CLI found: $($az.Source)"

Write-Host ""
Write-Host "Repair completed." -ForegroundColor Green
Write-Host "Next command:" -ForegroundColor Cyan
Write-Host ".\Start-AzLoginWithProxy.ps1 -ProxyUrl `"$ProxyUrl`" -UnsafeDisableTlsVerification -Tenant `"$Tenant`""

if ($RunLogin) {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper, "-ProxyUrl", $ProxyUrl, "-UnsafeDisableTlsVerification", "-Tenant", $Tenant)
    if ($DebugAzCli) { $args += "-DebugAzCli" }
    & powershell.exe @args
    if ($LASTEXITCODE -ne 0) { throw "Login helper failed with exit code $LASTEXITCODE." }
}
