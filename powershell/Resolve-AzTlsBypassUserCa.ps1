<#
.SYNOPSIS
    Detect user-provided CA certificate(s) in the repo's certs/ folder.

.DESCRIPTION
    Scans the supplied directory (default: <repoRoot>/certs) for *.crt and
    *.pem files. If one or more are found, concatenates them into a single
    bundle file under $HOME/.AzTlsBypass/certs/bundle.pem and returns the
    bundle path. Returns $null when the folder is missing or empty.

    PEM concatenation works because PEM files are plain text containing
    one or more -----BEGIN CERTIFICATE----- blocks; appending them gives
    a valid bundle that OpenSSL / requests / curl all accept.

.PARAMETER CertsDir
    Source directory to scan. Defaults to <repoRoot>/certs based on the
    caller's $PSScriptRoot. Pass explicitly when calling from elsewhere.

.PARAMETER OutputDir
    Where to write the merged bundle. Defaults to ~/.AzTlsBypass/certs.

.OUTPUTS
    [string] absolute path to the merged bundle, or $null if no certs.

.EXAMPLE
    $bundle = Resolve-AzTlsBypassUserCa -CertsDir 'D:\repo\certs'
    if ($bundle) { Set-AzTlsBypassConfig -CaCertPath $bundle }
#>
function Resolve-AzTlsBypassUserCa {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CertsDir,

        [string]$OutputDir
    )

    if (-not $OutputDir) {
        $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
        $OutputDir = Join-Path $userHome '.AzTlsBypass/certs'
    }

    if (-not (Test-Path -LiteralPath $CertsDir)) {
        Write-Verbose "[Resolve-AzTlsBypassUserCa] certs dir not found: $CertsDir"
        return $null
    }

    $files = @(Get-ChildItem -LiteralPath $CertsDir -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -match '^\.(crt|pem)$' } |
               Sort-Object Name)

    if ($files.Count -eq 0) {
        Write-Verbose "[Resolve-AzTlsBypassUserCa] no .crt/.pem in $CertsDir"
        return $null
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $bundlePath = Join-Path $OutputDir 'bundle.pem'

    # Verify each file actually starts with a PEM marker before merging,
    # to give clearer errors for DER/.cer files mis-renamed to .crt.
    $sb       = New-Object System.Text.StringBuilder
    $accepted = New-Object System.Collections.ArrayList
    foreach ($f in $files) {
        $head = (Get-Content -LiteralPath $f.FullName -TotalCount 1 -ErrorAction SilentlyContinue) -join ''
        if ($head -notmatch '-----BEGIN CERTIFICATE-----') {
            Write-Warning "[AzTlsBypass] '$($f.Name)' 看起來不是 PEM 格式(沒有 -----BEGIN CERTIFICATE----- 開頭),已略過。請用 certs/README.md 的方法轉換。"
            continue
        }
        [void]$sb.AppendLine("# Source: $($f.Name)")
        [void]$sb.AppendLine((Get-Content -LiteralPath $f.FullName -Raw))
        [void]$accepted.Add($f.Name)
    }

    if ($sb.Length -eq 0) {
        Write-Verbose "[Resolve-AzTlsBypassUserCa] all candidate files rejected as non-PEM"
        return $null
    }

    Set-Content -LiteralPath $bundlePath -Value $sb.ToString() -Encoding ascii
    Write-Verbose "[Resolve-AzTlsBypassUserCa] wrote bundle: $bundlePath ($($accepted.Count) source file(s))"
    return [pscustomobject]@{
        BundlePath = $bundlePath
        Sources    = $accepted.ToArray()
    }
}
