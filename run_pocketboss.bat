@echo off
TITLE PocketBoss - Personal Finance Manager (Oracle PL/SQL)
cd /d "%~dp0"

REM Launch the interactive PocketBoss application via PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo PowerShell failed or was cancelled. Falling back to SQL*Plus...
    sqlplus bankuser/bankuser@//localhost:1521/XEPDB1
)
pause
