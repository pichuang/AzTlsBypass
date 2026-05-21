function Get-AzCliPath {
    <#
    .SYNOPSIS
        Locate the ``az.cmd`` / ``az`` launcher and the bundled Python.

    .DESCRIPTION
        On Windows: prefers ``Get-Command az.cmd``, falls back to the
        default ``C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd``
        path.  The bundled ``python.exe`` is located one directory above
        the launcher (``..\python.exe``).

        On macOS/Linux (test environments): uses ``Get-Command az`` and
        ``Get-Command python3`` so the module can be imported and
        partially exercised in cross-platform CI.

    .OUTPUTS
        [pscustomobject] with properties ``AzPath``, ``PythonPath``,
        ``InstallRoot``, ``IsWindowsLayout``.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $isWin = $false
    if (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) {
        $isWin = [bool]$IsWindows
    } else {
        # Windows PowerShell 5.1 lacks $IsWindows.
        $isWin = $true
    }

    $azCmd      = $null
    $python     = $null
    $installDir = $null

    if ($isWin) {
        $found = Get-Command -Name 'az.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $azCmd = $found.Source
        } else {
            $default = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
            if (Test-Path -LiteralPath $default) {
                $azCmd = $default
            }
        }
        if (-not $azCmd) {
            throw "Cannot locate az.cmd. Install Azure CLI or add it to PATH."
        }

        $wbin = Split-Path -Path $azCmd -Parent
        $installDir = Split-Path -Path $wbin -Parent
        $python = Join-Path -Path $installDir -ChildPath 'python.exe'
        if (-not (Test-Path -LiteralPath $python)) {
            throw "Bundled python.exe not found at '$python'."
        }
    } else {
        $found = Get-Command -Name 'az' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) {
            throw "Cannot locate az on PATH."
        }
        $azCmd = $found.Source

        $py = Get-Command -Name 'python3' -ErrorAction SilentlyContinue |
              Select-Object -First 1
        if (-not $py) {
            $py = Get-Command -Name 'python' -ErrorAction SilentlyContinue |
                  Select-Object -First 1
        }
        if (-not $py) {
            throw "Cannot locate python interpreter on PATH."
        }
        $python = $py.Source
        $installDir = Split-Path -Path $azCmd -Parent
    }

    return [pscustomobject]@{
        AzPath          = $azCmd
        PythonPath      = $python
        InstallRoot     = $installDir
        IsWindowsLayout = $isWin
    }
}
