@echo off
REM Double-click launcher: runs install-watch.ps1 (extra arguments are passed through).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-watch.ps1" %*
echo.
pause
