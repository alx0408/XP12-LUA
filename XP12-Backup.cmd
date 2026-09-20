@echo off
chcp 65001 >nul
title XP12-Backup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0XP12-Backup-Start.ps1"
if errorlevel 1 pause
