@echo off
REM =====================================================================
REM  watchdog.bat - run the self-healing health check once, by hand.
REM  (The 5-minute schedule uses watchdog_hidden.vbs -> watchdog.ps1.)
REM
REM  Usage:  watchdog.bat            (pauses at the end)
REM          watchdog.bat /nopause   (no prompt, for scripts/tests)
REM =====================================================================

setlocal
cd /d "%~dp0"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0watchdog.ps1"
set "RC=%ERRORLEVEL%"

echo.
if /i "%~1"=="/nopause" goto :end
pause

:end
exit /b %RC%
