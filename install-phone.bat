@echo off
REM Double-click launcher: runs install-phone.ps1 (extra arguments are passed through).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-phone.ps1" %*
echo.
pause
