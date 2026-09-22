# =====================================================================
#  watchdog.ps1 - 5-minute self-healing check for the n8n-job-tracker
#                 services (scraper bridge on 3456 + n8n on 5678).
#
#  Registered as the scheduled task "n8n Job Tracker Watchdog"
#  (schtasks /sc minute /mo 5) and launched silently through
#  watchdog_hidden.vbs.
#
#  All logic lives in service_control.ps1 -Action watch so that the
#  manual start path and the watchdog can never drift apart.
#  Exit code: 0 = both services healthy at the end, 1 = at least one down.
#  Logs: logs\watchdog.log (one timestamped line per run, plus details
#  for every restart).
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$control = Join-Path $PSScriptRoot 'service_control.ps1'
if (-not (Test-Path $control)) {
    Write-Host "ERROR: service_control.ps1 not found next to watchdog.ps1 ($PSScriptRoot)"
    exit 2
}

# 'exit $code' inside service_control.ps1 terminates this script too and
# carries the exit code out to Task Scheduler / the calling bat file.
& $control -Action watch
