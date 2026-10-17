@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0runtime\start-codex-wallpaper.ps1"
if errorlevel 1 pause
