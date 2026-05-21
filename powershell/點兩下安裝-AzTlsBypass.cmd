@echo off
REM ============================================================
REM  AzTlsBypass — 雙擊一鍵安裝 (Double-click installer)
REM
REM  作用:
REM    1. 以 -ExecutionPolicy Bypass 啟動 PowerShell
REM    2. 執行 OneClick-Install.ps1(互動式詢問 Proxy URL / CA)
REM    3. 透過 Install-AzTlsBypass.ps1 -AutoEnable 自動完成:
REM         - 複製模組到 CurrentUser
REM         - Set-AzTlsBypassConfig
REM         - Enable-AzTlsBypass -Persist  (寫入 $PROFILE)
REM    4. 開啟新的 PowerShell 視窗驗證後 pause
REM
REM  使用者體驗:點兩下 -> 回答幾個問題 -> 完成
REM ============================================================

chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%OneClick-Install.ps1"

if not exist "%PS_SCRIPT%" (
    echo [錯誤] 找不到 %PS_SCRIPT%
    pause
    exit /b 1
)

REM 優先 pwsh.exe (7+),回退 powershell.exe (5.1)
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
)

endlocal
