@echo off
rem CCAS Lab Runner V3 - double-click to start.
rem Uses PowerShell 7 if installed, otherwise Windows PowerShell 5.1.
setlocal
cd /d "%~dp0"
set "PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"

rem Files extracted from a downloaded zip are marked as "from the internet"; unblock them.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File" >nul 2>&1

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0LabRunner.ps1" %*
echo.
pause
endlocal
