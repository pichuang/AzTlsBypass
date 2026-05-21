@echo off
setlocal
title Install Azure CLI Proxy Wrapper
cd /d "%~dp0"

echo Installing Azure CLI proxy wrapper for Windows PowerShell 5.1...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-AzProxyProfile.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Install completed.
  echo Close and reopen Windows PowerShell 5.1, then run normal az commands.
) else (
  echo Install failed with exit code %EXITCODE%.
)
echo.
pause
exit /b %EXITCODE%
