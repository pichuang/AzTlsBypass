function Clear-AzTlsBypassConfig {
    <#
    .SYNOPSIS
        Delete the AzTlsBypass config file.

    .DESCRIPTION
        Removes ``$HOME/.AzTlsBypass/config.json`` if it exists.  Does not
        touch the parent directory.  Idempotent.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $path = Get-AzTlsBypassConfigPath
    if (Test-Path -LiteralPath $path) {
        if ($PSCmdlet.ShouldProcess($path, 'Remove AzTlsBypass config')) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}
