function Get-AzTlsBypassStatus {
    <#
    .SYNOPSIS
        Report the current AzTlsBypass activation state.

    .DESCRIPTION
        Inspects environment variables and the ``az`` function override to
        determine whether AzTlsBypass is active in the current session.
        Also returns the loaded configuration and resolved az/Python paths
        for diagnostic purposes.

    .OUTPUTS
        [pscustomobject] with Active, EnvActive, FunctionOverride,
        Persisted, Config, AzPath, PythonPath.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $envActive = ([Environment]::GetEnvironmentVariable($script:ActiveEnvVar, 'Process')) -eq '1'
    $functionOverride = $false
    # NOTE: avoid -LiteralPath; the function provider needs scope expansion.
    $fn = Get-Item function:az -ErrorAction SilentlyContinue
    if ($fn -and $fn.ScriptBlock.ToString() -match 'Invoke-AzWithBypass') {
        $functionOverride = $true
    }

    $persisted = $false
    $profilePath = $PROFILE.CurrentUserAllHosts
    if ($profilePath -and (Test-Path -LiteralPath $profilePath)) {
        $content = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match [regex]::Escape($script:ProfileMarkerBegin)) {
            $persisted = $true
        }
    }

    $azInfo = $null
    try { $azInfo = Get-AzCliPath } catch { $azInfo = $null }

    return [pscustomobject]@{
        Active           = ($envActive -or $functionOverride)
        EnvActive        = $envActive
        FunctionOverride = $functionOverride
        Persisted        = $persisted
        Config           = (Get-AzTlsBypassConfig)
        AzPath           = if ($azInfo) { $azInfo.AzPath } else { $null }
        PythonPath       = if ($azInfo) { $azInfo.PythonPath } else { $null }
    }
}
