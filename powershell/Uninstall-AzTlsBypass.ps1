<#
.SYNOPSIS
    Uninstall the AzTlsBypass PowerShell module.

.DESCRIPTION
    Calls ``Disable-AzTlsBypass -Persist`` (best-effort) to remove the
    profile snippet and the function override, then removes the installed
    module folder.

.PARAMETER Scope
    ``CurrentUser`` (default) | ``AllUsers``.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

$root = if ($Scope -eq 'CurrentUser') { _GetUserModulePath } else { _GetAllUsersModulePath }
$dest = Join-Path -Path $root -ChildPath 'AzTlsBypass'

if (Get-Module AzTlsBypass) {
    try { Disable-AzTlsBypass -Persist -ErrorAction SilentlyContinue } catch { }
    Remove-Module AzTlsBypass -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $dest) {
    if ($PSCmdlet.ShouldProcess($dest, 'Remove installed module')) {
        Remove-Item -LiteralPath $dest -Recurse -Force
        Write-Host "[AzTlsBypass] uninstalled from '$dest'." -ForegroundColor Green
    }
} else {
    Write-Host "[AzTlsBypass] no installation found at '$dest'." -ForegroundColor Yellow
}
