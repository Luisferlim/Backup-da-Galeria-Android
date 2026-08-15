@echo off
cd /d "%~dp0"
start "" powershell.exe -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0BackupGaleriaAndroid.ps1"
exit /b
