function Disable-AzTlsBypass {
    <#
    .SYNOPSIS
        Deactivate AzTlsBypass in the current session (and optionally from profile).

    .DESCRIPTION
        Removes the global ``az`` function override (restoring access to
        the real ``az.cmd`` on PATH), clears the AzTlsBypass + companion
        environment variables, and — when ``-Persist`` is supplied —
        removes the activation block from
        ``$PROFILE.CurrentUserAllHosts``.

    .PARAMETER Persist
        Also remove the AzTlsBypass block from the user profile.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Persist
    )

    # PowerShell's function provider treats 'function:global:az' as an
    # item NAME (not a scope qualifier) for Remove-Item / Test-Path, which
    # makes those commands silently no-op for a global-scope function.
    # The only reliable removal idiom is to dispatch through a child
    # scope so the scope chain finds and removes the global entry.
    & { Remove-Item function:az -Force -ErrorAction SilentlyContinue }
    Clear-AzTlsBypassEnvironment -Scope Process

    if ($Persist) {
        $profilePath = $PROFILE.CurrentUserAllHosts
        if ($profilePath -and (Test-Path -LiteralPath $profilePath)) {
            $existing = Get-Content -LiteralPath $profilePath -Raw
            $pattern = "(?ms)" + [regex]::Escape($script:ProfileMarkerBegin) + ".*?" + [regex]::Escape($script:ProfileMarkerEnd) + "\s*"
            $cleaned = [regex]::Replace($existing, $pattern, '')
            if ($PSCmdlet.ShouldProcess($profilePath, 'Remove AzTlsBypass activation snippet')) {
                Set-Content -LiteralPath $profilePath -Value $cleaned -Encoding UTF8
            }
        }
    }

    Write-Host "[AzTlsBypass] disabled." -ForegroundColor Green
}
