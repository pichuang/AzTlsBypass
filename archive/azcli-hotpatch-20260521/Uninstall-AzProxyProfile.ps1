<#
.SYNOPSIS
Removes the transparent az wrapper from the current user's Windows PowerShell profile.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$profilePath = $PROFILE.CurrentUserAllHosts
$startMarker = "# >>> az proxy wrapper >>>"
$endMarker = "# <<< az proxy wrapper <<<"

if (-not (Test-Path -Path $profilePath)) {
    Write-Host "[PASS] Profile does not exist; nothing to remove." -ForegroundColor Green
    return
}

$existing = [System.IO.File]::ReadAllText($profilePath)
$pattern = [regex]::Escape($startMarker) + "(?s).*?" + [regex]::Escape($endMarker) + "(\r?\n)?"
$updated = [regex]::Replace($existing, $pattern, "")
[System.IO.File]::WriteAllText($profilePath, $updated.TrimEnd() + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

Write-Host "[PASS] Removed transparent az proxy wrapper from:" -ForegroundColor Green
Write-Host $profilePath
