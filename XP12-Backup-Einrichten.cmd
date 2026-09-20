@echo off
chcp 65001 >nul
title XP12-Backup Einrichtung
echo.
echo   ============================================
echo     XP12-BACKUP  -  EINRICHTUNG
echo   ============================================
echo.
echo   Es wird eine Verknuepfung auf dem Desktop angelegt.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0XP12-Backup-Verknuepfung-erstellen.ps1"
echo.
echo   ============================================
echo.
pause
