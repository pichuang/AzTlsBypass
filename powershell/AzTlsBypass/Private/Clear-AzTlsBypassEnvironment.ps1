function Clear-AzTlsBypassEnvironment {
    <#
    .SYNOPSIS
        Undo the env var mutations made by ``Set-AzTlsBypassEnvironment``.

    .PARAMETER Scope
        ``Process`` | ``User``.  ``User`` only applies on Windows.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Process', 'User')]
        [string]$Scope = 'Process'
    )

    function _Unset([string]$Name) {
        if ($Scope -eq 'User') {
            [Environment]::SetEnvironmentVariable($Name, $null, 'User')
        }
        [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
    }

    $vars = @(
        $script:ActiveEnvVar
        $script:LegacyActiveEnvVar
        $script:CompanionEnvVars
        $script:CaBundleEnvVars
        'HTTPS_PROXY'
        'HTTP_PROXY'
        'NO_PROXY'
    ) | ForEach-Object { $_ }

    foreach ($v in $vars) { _Unset $v }
}
