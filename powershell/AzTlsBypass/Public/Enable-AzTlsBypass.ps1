function Enable-AzTlsBypass {
    <#
    .SYNOPSIS
        Activate AzTlsBypass for the current session (and optionally persist).

    .DESCRIPTION
        Performs two distinct actions:

        1. Sets the AzTlsBypass + companion environment variables in the
           current process so any direct ``az`` call (without the function
           override) still picks up the bypass — useful when a child
           process invokes ``az`` for you.

        2. Defines a global function ``az`` that transparently forwards to
           ``Invoke-AzWithBypass``.  This is what makes the bypass
           invisible to the user — they keep typing ``az login`` exactly
           as before.

        When ``-Persist`` is supplied, the activation snippet is also
        injected into ``$PROFILE.CurrentUserAllHosts`` between marker
        comments so future PowerShell sessions auto-activate.  The
        snippet is idempotent — re-running ``Enable-AzTlsBypass -Persist``
        will replace any existing block in-place.

    .PARAMETER Persist
        Write the activation snippet into the user profile so it loads on
        every new session.

    .PARAMETER NoBanner
        Suppress the one-line activation banner.

    .EXAMPLE
        Enable-AzTlsBypass

    .EXAMPLE
        Enable-AzTlsBypass -Persist
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Persist,
        [switch]$NoBanner
    )

    $config = Get-AzTlsBypassConfig
    Set-AzTlsBypassEnvironment -Config $config -Scope Process

    # Define / replace the global az function override.
    $body = {
        param([Parameter(ValueFromRemainingArguments)] [string[]]$AzArgs)
        Invoke-AzWithBypass -AzArgs $AzArgs
    }
    Set-Item -Path 'function:global:az' -Value $body

    if ($Persist) {
        $profilePath = $PROFILE.CurrentUserAllHosts
        if (-not $profilePath) {
            throw '$PROFILE.CurrentUserAllHosts is not defined; cannot persist.'
        }
        $profileDir = Split-Path -Path $profilePath -Parent
        if (-not (Test-Path -LiteralPath $profileDir)) {
            if ($PSCmdlet.ShouldProcess($profileDir, 'Create profile directory')) {
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            }
        }
        $existing = ''
        if (Test-Path -LiteralPath $profilePath) {
            $existing = Get-Content -LiteralPath $profilePath -Raw
        }

        # Strip any prior AzTlsBypass block.
        $pattern = "(?ms)" + [regex]::Escape($script:ProfileMarkerBegin) + ".*?" + [regex]::Escape($script:ProfileMarkerEnd) + "\s*"
        $cleaned = [regex]::Replace($existing, $pattern, '')

        $snippet = @"
$($script:ProfileMarkerBegin)
# Managed by AzTlsBypass. Re-run 'Enable-AzTlsBypass -Persist' to refresh.
Import-Module AzTlsBypass -ErrorAction SilentlyContinue
if (Get-Module AzTlsBypass) {
    Enable-AzTlsBypass -NoBanner | Out-Null
}
$($script:ProfileMarkerEnd)
"@
        $final = ($cleaned.TrimEnd() + "`r`n`r`n" + $snippet + "`r`n").TrimStart()
        if ($PSCmdlet.ShouldProcess($profilePath, 'Inject AzTlsBypass activation snippet')) {
            Set-Content -LiteralPath $profilePath -Value $final -Encoding UTF8
        }
    }

    if (-not $NoBanner) {
        $proxyDisplay = if ($config.ProxyUrl) { $config.ProxyUrl } else { '<none configured>' }
        Write-Host "[AzTlsBypass] active. Proxy=$proxyDisplay. TLS verification disabled." -ForegroundColor Yellow
    }
}
