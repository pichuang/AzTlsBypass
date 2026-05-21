@echo off
setlocal
title Uninstall Azure CLI Proxy Wrapper
cd /d "%~dp0"

echo Removing Azure CLI proxy wrapper from Windows PowerShell 5.1 profile...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-AzProxyProfile.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Uninstall completed.
  echo Close and reopen Windows PowerShell 5.1.
) else (
  echo Uninstall failed with exit code %EXITCODE%.
)
echo.
pause
exit /b %EXITCODE%
