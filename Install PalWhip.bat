@echo off
setlocal
title PalWhip + PalBoombox Installer
cd /d "%~dp0"

echo Installing PalWhip and PalBoombox...
echo A Windows administrator prompt may appear.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
if "%INSTALL_EXIT%"=="0" (
    echo Installation complete. You can now launch Palworld.
) else (
    echo Installation failed. Review the message above for the reason.
)
echo.
pause
exit /b %INSTALL_EXIT%
