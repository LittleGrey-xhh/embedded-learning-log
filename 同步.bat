@echo off
chcp 65001 >nul
title Sync learning log to GitHub
cd /d "%~dp0"

set PY=D:\python\python.exe
if not exist "%PY%" set PY=python

"%PY%" sync.py --push

echo.
echo ==========================================
echo  Done. Press any key to close.
echo ==========================================
pause >nul
