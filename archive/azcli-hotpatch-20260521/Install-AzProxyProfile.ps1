<#
.SYNOPSIS
Installs a transparent az wrapper into the current user's Windows PowerShell profile.

.DESCRIPTION
After installation, open a new Windows PowerShell 5.1 window and keep using
normal az commands. The profile function redirects az to Invoke-AzWithProxy.ps1.
#>

[CmdletBinding()]
param(
    [string]$HelperRoot,
    [string]$ProxyUrl = "http://proxy.example.com:8080",
    [string[]]$NoProxyHosts = @("169.254.169.254", "localhost", "127.0.0.1")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($HelperRoot)) {
    $HelperRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
}

$wrapperPath = Join-Path $HelperRoot "Invoke-AzWithProxy.ps1"
if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
    throw "Invoke-AzWithProxy.ps1 was not found: $wrapperPath"
}
$wrapperPath = (Resolve-Path -LiteralPath $wrapperPath).Path

$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Parent $profilePath
if (-not (Test-Path -Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$startMarker = "# >>> az proxy wrapper >>>"
$endMarker = "# <<< az proxy wrapper <<<"
$noProxyLiteral = ($NoProxyHosts | ForEach-Object { '"' + $_.Replace('"', '`"') + '"' }) -join ", "
$block = @"
$startMarker
function global:az {
    & "$wrapperPath" -ProxyUrl "$ProxyUrl" -NoProxyHosts @($noProxyLiteral) @args
}
$endMarker
"@

$existing = ""
if (Test-Path -Path $profilePath) {
    $existing = [System.IO.File]::ReadAllText($profilePath)
}

$pattern = [regex]::Escape($startMarker) + "(?s).*?" + [regex]::Escape($endMarker) + "(\r?\n)?"
$updated = [regex]::Replace($existing, $pattern, "")
if (-not [string]::IsNullOrWhiteSpace($updated)) {
    $updated = $updated.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine
}
$updated += $block + [Environment]::NewLine

[System.IO.File]::WriteAllText($profilePath, $updated, [System.Text.UTF8Encoding]::new($false))

Write-Host "[PASS] Installed transparent az proxy wrapper into:" -ForegroundColor Green
Write-Host $profilePath
Write-Host ""
Write-Host "Open a new Windows PowerShell 5.1 window, then use normal az commands:" -ForegroundColor Cyan
Write-Host "az login --tenant b449d301-e285-4551-8467-773bebf5ed31"
Write-Host "az login --identity"
Write-Host "az network application-gateway list"
