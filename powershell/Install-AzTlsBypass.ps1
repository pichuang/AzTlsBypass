<#
.SYNOPSIS
    Install the AzTlsBypass PowerShell module into the user module path.

.DESCRIPTION
    Copies the module folder under ``./AzTlsBypass`` into
    ``$env:PSModulePath`` (first user-writable entry).  Re-installing
    replaces an existing copy.

    After install you can ``Import-Module AzTlsBypass`` from any new
    session.  Use ``Enable-AzTlsBypass -Persist`` to have it auto-import
    on every shell.

    When called with ``-AutoEnable`` this script also writes the proxy
    config (if ``-ProxyUrl`` is supplied) and activates AzTlsBypass with
    ``-Persist`` so all new PowerShell sessions auto-enable.  This is the
    one-click path used by ``點兩下安裝-AzTlsBypass.cmd``.

.PARAMETER Scope
    ``CurrentUser`` (default) | ``AllUsers``.

.PARAMETER Force
    Overwrite an existing installed module of the same name.

.PARAMETER AutoEnable
    After install, immediately run ``Enable-AzTlsBypass -Persist``.

.PARAMETER ProxyUrl
    Optional corporate proxy URL written to the config before activation.
    Only honoured when ``-AutoEnable`` is also supplied.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force,

    [switch]$AutoEnable,

    [string]$ProxyUrl
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = Join-Path -Path $PSScriptRoot -ChildPath 'AzTlsBypass'
if (-not (Test-Path -LiteralPath $source)) {
    throw "Module source not found at '$source'."
}

# Sync the latest core into PythonShim so the installed module has it.
$coreSource = Join-Path -Path $PSScriptRoot -ChildPath '..\core\tls_bypass_core.py'
if (Test-Path -LiteralPath $coreSource) {
    Copy-Item -LiteralPath $coreSource `
              -Destination (Join-Path -Path $source -ChildPath 'PythonShim\tls_bypass_core.py') `
              -Force
}

function _GetUserModulePath {
    if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
        return Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'
    }
    return Join-Path $env:HOME '.local/share/powershell/Modules'
}

function _GetAllUsersModulePath {
    if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
        return 'C:\Program Files\WindowsPowerShell\Modules'
    }
    return '/usr/local/share/powershell/Modules'
}

$target = if ($Scope -eq 'CurrentUser') { _GetUserModulePath } else { _GetAllUsersModulePath }
$dest   = Join-Path -Path $target -ChildPath 'AzTlsBypass'

if (Test-Path -LiteralPath $dest) {
    if (-not $Force) {
        throw "Module already installed at '$dest'. Re-run with -Force to overwrite."
    }
    if ($PSCmdlet.ShouldProcess($dest, 'Remove existing install')) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
}

if (-not (Test-Path -LiteralPath $target)) {
    if ($PSCmdlet.ShouldProcess($target, 'Create module root')) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }
}

if ($PSCmdlet.ShouldProcess($dest, 'Copy module')) {
    Copy-Item -LiteralPath $source -Destination $dest -Recurse
    Write-Host "[AzTlsBypass] installed to '$dest'." -ForegroundColor Green
}

if ($AutoEnable) {
    Write-Host ''
    Write-Host "[AzTlsBypass] Activating with -Persist ..." -ForegroundColor Cyan

    # Force-reload the freshly installed module copy.
    Import-Module $dest -Force -ErrorAction Stop

    if ($ProxyUrl) {
        Set-AzTlsBypassConfig -ProxyUrl $ProxyUrl -Confirm:$false | Out-Null
        Write-Host "  Config: ProxyUrl = $ProxyUrl" -ForegroundColor Cyan
    }

    Enable-AzTlsBypass -Persist -NoBanner -Confirm:$false

    Write-Host ''
    Write-Host "[AzTlsBypass] OK. All new PowerShell sessions will auto-activate." -ForegroundColor Green
    Write-Host "  Run 'Get-AzTlsBypassStatus' in a NEW shell to verify." -ForegroundColor Cyan
} else {
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    Import-Module AzTlsBypass"
    Write-Host "    Set-AzTlsBypassConfig -ProxyUrl 'http://YOUR.PROXY:PORT'"
    Write-Host "    Enable-AzTlsBypass -Persist"
}
