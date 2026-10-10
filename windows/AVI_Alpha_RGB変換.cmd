@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0MOV_Alpha_RGB変換\Split-Mov.ps1" -InputKind Avi
