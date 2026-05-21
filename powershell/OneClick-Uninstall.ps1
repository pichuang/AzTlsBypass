<#
.SYNOPSIS
    Interactive one-click uninstaller launched from 點兩下移除-AzTlsBypass.cmd.

.DESCRIPTION
    1. Confirm intent with the user.
    2. Run Disable-AzTlsBypass -Persist (clears profile snippet, function
       override, and env vars in this process).
    3. Run Uninstall-AzTlsBypass.ps1 to delete the module from
       $env:PSModulePath.
    4. Optionally also delete ~/.AzTlsBypass/config.json.
    5. Pause so the user can see the result.
#>

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$KeepConfig
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

try {
    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host '  AzTlsBypass — One-click Uninstaller' -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Ask-Confirm '確定要解除 AzTlsBypass(會停止透明 az 攔截)?' -Default 'Y')) {
        Write-Host '已取消。' -ForegroundColor Yellow
        if (-not $NonInteractive) { Read-Host -Prompt '按 Enter 關閉視窗' | Out-Null }
        return
    }

    Write-Host ''
    Write-Host '[1/3] 從 $PROFILE 移除自動啟用區塊 + 清除環境變數' -ForegroundColor Cyan
    if (Get-Module -ListAvailable AzTlsBypass) {
        Import-Module AzTlsBypass -Force -ErrorAction Stop
        try {
            Disable-AzTlsBypass -Persist -Confirm:$false
        } catch {
            Write-Host "  (Disable 步驟略過: $($_.Exception.Message))" -ForegroundColor Yellow
        }
    } else {
        Write-Host '  AzTlsBypass 模組未安裝,跳過 Disable 步驟。' -ForegroundColor Yellow
    }
    Write-Host ''

    Write-Host '[2/3] 刪除模組檔案' -ForegroundColor Cyan
    $uninstaller = Join-Path -Path $PSScriptRoot -ChildPath 'Uninstall-AzTlsBypass.ps1'
    if (Test-Path -LiteralPath $uninstaller) {
        & $uninstaller -Scope CurrentUser -Confirm:$false
    } else {
        Write-Host "  找不到 Uninstall-AzTlsBypass.ps1 ($uninstaller),已跳過。" -ForegroundColor Yellow
    }
    Write-Host ''

    Write-Host '[3/3] 設定檔處置' -ForegroundColor Cyan
    $configPath = Join-Path -Path $HOME -ChildPath '.AzTlsBypass/config.json'
    if (Test-Path -LiteralPath $configPath) {
        if ($KeepConfig) {
            Write-Host "  保留設定檔: $configPath" -ForegroundColor Cyan
        } elseif (Ask-Confirm "  也要刪除設定檔 '$configPath' ?" -Default 'N') {
            Remove-Item -LiteralPath $configPath -Force
            $configDir = Split-Path -Parent $configPath
            if ((Get-ChildItem -LiteralPath $configDir -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                Remove-Item -LiteralPath $configDir -Force
            }
            Write-Host "  設定檔已刪除。" -ForegroundColor Green
        } else {
            Write-Host "  保留設定檔(下次再安裝可沿用)。" -ForegroundColor Cyan
        }
    } else {
        Write-Host '  無設定檔需處理。' -ForegroundColor Cyan
    }

    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Green
    Write-Host '  ✓ 解除完成。新的 PowerShell 視窗將恢復原生 az 行為。' -ForegroundColor Green
    Write-Host '================================================================' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host '[AzTlsBypass] 解除失敗:' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    if (-not $NonInteractive) { Read-Host -Prompt '按 Enter 結束' | Out-Null }
    exit 1
}

if (-not $NonInteractive) {
    Write-Host ''
    Read-Host -Prompt '按 Enter 關閉視窗' | Out-Null
}
