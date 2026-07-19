@echo off
setlocal
title PalWhip Uninstaller

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-PalWhip.ps1" %*
set "PalWhipExitCode=%ERRORLEVEL%"

echo(
if "%PalWhipExitCode%"=="0" (
    echo The PalWhip uninstaller finished successfully.
) else if "%PalWhipExitCode%"=="2" (
    echo Uninstall cancelled. Nothing was changed.
) else (
    echo The uninstaller stopped with error code %PalWhipExitCode%.
)

if not defined PALWHIP_UNINSTALL_NO_PAUSE pause
exit /b %PalWhipExitCode%
