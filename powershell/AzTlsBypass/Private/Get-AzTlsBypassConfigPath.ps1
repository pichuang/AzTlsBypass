function Get-AzTlsBypassConfigPath {
    <#
    .SYNOPSIS
        Returns the absolute path to the AzTlsBypass JSON config file.

    .DESCRIPTION
        Resolves to ``$HOME/.AzTlsBypass/config.json``.  When ``-Directory``
        is set, returns the parent directory instead.  Idempotent — does
        not create files.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$Directory
    )

    $home = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrEmpty($home)) {
        $home = $HOME
    }
    $dir = Join-Path -Path $home -ChildPath $script:ConfigDirName
    if ($Directory) { return $dir }
    return Join-Path -Path $dir -ChildPath $script:ConfigFileName
}
