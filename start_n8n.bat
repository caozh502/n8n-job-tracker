@echo off
REM =====================================================================
REM  start_n8n.bat - one-click / Task-Scheduler entry point for the
REM  local n8n-job-tracker services (scraper bridge + self-hosted n8n).
REM
REM  What it does: delegates to service_control.ps1 -Action start, which
REM    1. starts the JobSpy scraper bridge (node scraper_server.js, port 3456)
REM    2. starts n8n (node <npm-global>\node_modules\n8n\bin\n8n start --port=5678)
REM       with N8N_RESTRICT_FILE_ACCESS_TO=<project>\cv
REM    3. waits until BOTH http://localhost:3456/health and
REM       http://localhost:5678/healthz answer HTTP 200
REM    4. writes everything to logs\startup.log
REM  Both services are launched DETACHED (own hidden process, output
REM  redirected to logs\scraper.log / logs\n8n.log), so this script
REM  finishes and exits deliberately with 0 (success) or 1 (failure).
REM
REM  Safe by design: no `taskkill /f /im node.exe` anymore - stale
REM  processes are killed by COMMAND LINE match only, and only when their
REM  health endpoint is already down. Unrelated node.exe processes
REM  (Adobe CC, other bots, Hermes) are never touched.
REM
REM  Usage:  start_n8n.bat            (double-click: pauses at the end)
REM          start_n8n.bat /nopause   (Task Scheduler: no prompts)
REM =====================================================================

setlocal
cd /d "%~dp0"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0service_control.ps1" -Action start
set "RC=%ERRORLEVEL%"

echo.
if /i "%~1"=="/nopause" goto :end
pause

:end
exit /b %RC%
