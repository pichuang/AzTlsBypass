@echo off
REM ============================================================
REM  AzTlsBypass — 雙擊一鍵移除 (Double-click uninstaller)
REM
REM  作用:
REM    1. Disable-AzTlsBypass -Persist  (清 $PROFILE / function / env)
REM    2. Uninstall-AzTlsBypass.ps1     (刪 CurrentUser 模組資料夾)
REM    3. 詢問是否一併刪除 ~/.AzTlsBypass/config.json
REM ============================================================

chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%OneClick-Uninstall.ps1"

if not exist "%PS_SCRIPT%" (
    echo [錯誤] 找不到 %PS_SCRIPT%
    pause
    exit /b 1
)

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
)

endlocal
