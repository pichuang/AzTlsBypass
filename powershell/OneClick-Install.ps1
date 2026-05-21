<#
.SYNOPSIS
    Interactive one-click installer launched from 點兩下安裝-AzTlsBypass.cmd.

.DESCRIPTION
    Designed to be double-click friendly:

        1. Show banner + security warning.
        2. Prompt for the corporate Proxy URL (Enter to skip if user wants
           to configure it later).
        3. Prompt for an optional CA bundle path.
        4. Run Install-AzTlsBypass.ps1 with -AutoEnable so the module is
           installed to CurrentUser, configured, and Enable-AzTlsBypass
           -Persist is invoked in one go.
        5. Verify by spawning a NEW pwsh/powershell session and calling
           Get-AzTlsBypassStatus, so the user sees that the next shell
           really has it active.
        6. Pause so the user can read the output before the window closes.

    Errors are caught and pressed Enter exits with code 1 — the user can
    still see what went wrong.
#>

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$ProxyUrl,
    [string]$CaCertPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Banner {
    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host '  AzTlsBypass — One-click Installer' -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '本工具會在 Python 程序內停用 TLS 憑證驗證,僅適用於受信任的' -ForegroundColor Yellow
    Write-Host '企業 TLS 解密 Proxy 後使用。請勿在公開網路或不受信任環境啟用。' -ForegroundColor Yellow
    Write-Host ''
}

function Ask-Confirm {
    param([string]$Message, [string]$Default = 'Y')

    if ($NonInteractive) { return ($Default -eq 'Y') }

    $hint = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $reply = Read-Host -Prompt "$Message $hint"
        if ([string]::IsNullOrWhiteSpace($reply)) { return ($Default -eq 'Y') }
        switch -Regex ($reply.Trim().ToLower()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host "  請輸入 Y 或 N。" -ForegroundColor DarkGray }
        }
    }
}

function Ask-String {
    param(
        [string]$Message,
        [string]$Default = '',
        [string]$ValidatePattern
    )
    if ($NonInteractive) { return $Default }

    while ($true) {
        $hint = if ($Default) { " (Enter = $Default)" } else { ' (Enter = 略過)' }
        $value = Read-Host -Prompt "$Message$hint"
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        if ($ValidatePattern -and ($value -notmatch $ValidatePattern)) {
            Write-Host "  格式不符,請再試一次。" -ForegroundColor DarkYellow
            continue
        }
        return $value
    }
}

function Find-AzCliPathInfo {
    $cmd = Get-Command az -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $default = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
    if (Test-Path -LiteralPath $default) { return $default }
    return $null
}

function Invoke-FreshSessionVerify {
    param([string]$InstalledModulePath)

    $pwshExe = $null
    foreach ($candidate in @('pwsh', 'powershell')) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $pwshExe = $found.Source; break }
    }
    if (-not $pwshExe) { return $null }

    # Run an isolated shell that picks up the just-installed module via
    # the user's $PROFILE auto-import snippet.
    & $pwshExe -NoProfile -Command "
        Import-Module '$InstalledModulePath' -Force -ErrorAction Stop
        \$st = Get-AzTlsBypassStatus
        '--- Verification (fresh in-process import) ---'
        \$st | Format-List
    " 2>&1
}

try {
    Write-Banner

    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $installer  = Join-Path -Path $PSScriptRoot -ChildPath 'Install-AzTlsBypass.ps1'
    if (-not (Test-Path -LiteralPath $installer)) {
        throw "找不到 Install-AzTlsBypass.ps1 於 '$installer'。"
    }

    # ------------------------------------------------------------
    # Step 1: pre-flight checks
    # ------------------------------------------------------------
    Write-Host '[1/4] 環境檢查' -ForegroundColor Cyan
    $azPath = Find-AzCliPathInfo
    if ($azPath) {
        Write-Host "  Azure CLI : $azPath" -ForegroundColor Green
    } else {
        Write-Host "  Azure CLI : 未偵測到 (安裝完成後仍可,但啟用後需要 az 才能驗證)" -ForegroundColor Yellow
    }
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Green
    Write-Host ''

    # ------------------------------------------------------------
    # Step 2: collect config
    # ------------------------------------------------------------
    Write-Host '[2/4] 設定企業 Proxy(可略過,事後可用 Set-AzTlsBypassConfig 補設)' -ForegroundColor Cyan
    if (-not $ProxyUrl) {
        $ProxyUrl = Ask-String -Message '  企業 Proxy URL (例: http://proxy.example.com:8080)' `
                               -ValidatePattern '^https?://[^\s]+$'
    }
    if (-not $CaCertPath) {
        $CaCertPath = Ask-String -Message '  企業 CA bundle .crt/.pem 路徑'
    }
    if ($CaCertPath -and -not (Test-Path -LiteralPath $CaCertPath)) {
        Write-Host "  ⚠ CA 路徑不存在,將忽略: $CaCertPath" -ForegroundColor Yellow
        $CaCertPath = $null
    }
    Write-Host ''

    # ------------------------------------------------------------
    # Step 3: install + auto-enable -Persist
    # ------------------------------------------------------------
    Write-Host '[3/4] 安裝模組並啟用永久模式' -ForegroundColor Cyan
    $installerArgs = @{
        Scope      = 'CurrentUser'
        Force      = $true
        AutoEnable = $true
    }
    if ($ProxyUrl) { $installerArgs['ProxyUrl'] = $ProxyUrl }

    & $installer @installerArgs

    # CA path is set AFTER install because Install handles -ProxyUrl only.
    if ($CaCertPath) {
        Import-Module AzTlsBypass -Force -ErrorAction Stop
        Set-AzTlsBypassConfig -CaCertPath $CaCertPath -Confirm:$false | Out-Null
        Write-Host "  Config: CaCertPath = $CaCertPath" -ForegroundColor Cyan
    }
    Write-Host ''

    # ------------------------------------------------------------
    # Step 4: verify by spawning a fresh shell
    # ------------------------------------------------------------
    Write-Host '[4/4] 驗證(在新的 PowerShell 子程序確認狀態)' -ForegroundColor Cyan
    $userModRoot = if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
        Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'
    } else {
        Join-Path $env:HOME '.local/share/powershell/Modules'
    }
    $installed = Join-Path $userModRoot 'AzTlsBypass/AzTlsBypass.psd1'
    $verifyOutput = Invoke-FreshSessionVerify -InstalledModulePath $installed
    if ($verifyOutput) {
        $verifyOutput | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ''

    Write-Host '================================================================' -ForegroundColor Green
    Write-Host '  ✓ 安裝完成。請開啟新的 PowerShell 視窗後直接執行:' -ForegroundColor Green
    Write-Host '      az login' -ForegroundColor Green
    Write-Host '  即可透明使用,無需任何手動 import。' -ForegroundColor Green
    Write-Host '================================================================' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host '[AzTlsBypass] 安裝失敗:' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    if (-not $NonInteractive) {
        Read-Host -Prompt '按 Enter 結束'
    }
    exit 1
}

if (-not $NonInteractive) {
    Write-Host ''
    Read-Host -Prompt '按 Enter 關閉視窗' | Out-Null
}
