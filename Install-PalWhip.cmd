@echo off
setlocal
title PalWhip Installer

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "PalWhipExitCode=%ERRORLEVEL%"

echo(
if "%PalWhipExitCode%"=="0" (
    echo PalWhip installation finished successfully.
) else (
    echo The installer stopped with error code %PalWhipExitCode%.
)

if not defined PALWHIP_INSTALL_NO_PAUSE pause
exit /b %PalWhipExitCode%
