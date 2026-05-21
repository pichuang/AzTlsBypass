function Invoke-AzWithBypass {
    <#
    .SYNOPSIS
        Run ``az`` with TLS verification bypassed and the configured proxy.

    .DESCRIPTION
        Resolves the bundled Azure CLI Python, injects the AzTlsBypass
        ``sitecustomize.py`` shim via ``PYTHONPATH``, sets the required
        environment variables (TLS bypass + proxy + NO_PROXY merged with
        IMDS hosts), then invokes ``az.cmd`` with the supplied arguments.

        Environment mutations are confined to the current process (no
        ``-Persist`` semantics here — for that use ``Enable-AzTlsBypass
        -Persist``).

    .PARAMETER AzArgs
        Arguments passed verbatim to ``az`` (e.g. ``login --identity``).
        Use ``-AzArgs`` explicitly when arguments start with ``-`` to
        avoid PowerShell parameter binding ambiguity.

    .EXAMPLE
        Invoke-AzWithBypass login --identity

    .EXAMPLE
        Invoke-AzWithBypass -AzArgs @('account', 'show')
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$AzArgs
    )

    if (-not $AzArgs) { $AzArgs = @() }

    $config = Get-AzTlsBypassConfig
    $azInfo = Get-AzCliPath

    # Snapshot env so we can restore the proxy/CA bundle keys after the call.
    $snapshotKeys = @(
        $script:ActiveEnvVar
        $script:LegacyActiveEnvVar
        $script:CompanionEnvVars
        $script:CaBundleEnvVars
        'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY', 'PYTHONPATH'
    ) | ForEach-Object { $_ }

    $snapshot = @{}
    foreach ($k in $snapshotKeys) {
        $snapshot[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
    }

    try {
        Set-AzTlsBypassEnvironment -Config $config -Scope Process

        # Inject the PythonShim directory at the FRONT of PYTHONPATH so our
        # sitecustomize.py is the one that wins during interpreter startup.
        $shimDir = Join-Path -Path $PSScriptRoot -ChildPath '..\PythonShim'
        $shimDir = (Resolve-Path -LiteralPath $shimDir).Path
        $existing = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
        $sep = if ($azInfo.IsWindowsLayout) { ';' } else { ':' }
        if ($existing) {
            [Environment]::SetEnvironmentVariable('PYTHONPATH', "$shimDir$sep$existing", 'Process')
        } else {
            [Environment]::SetEnvironmentVariable('PYTHONPATH', $shimDir, 'Process')
        }

        # Tell child process not to write .pyc — matches az.cmd's own behaviour
        # (`python -B`).  Belt-and-braces; the sitecustomize itself does no I/O.
        [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', '1', 'Process')

        & $azInfo.AzPath @AzArgs
        $exit = $LASTEXITCODE
    } finally {
        foreach ($k in $snapshot.Keys) {
            [Environment]::SetEnvironmentVariable($k, $snapshot[$k], 'Process')
        }
    }

    if ($null -ne $exit) {
        $global:LASTEXITCODE = $exit
    }
}
