# =====================================================================
#  register_tasks.ps1 - (re)register the two Windows Scheduled Tasks
#                       that keep the n8n-job-tracker services alive.
#
#    1) "n8n Job Tracker Start"     at user logon -> start_hidden.vbs
#                                   -> start_n8n.bat -> service_control.ps1 -Action start
#    2) "n8n Job Tracker Watchdog"  every 5 minutes -> watchdog_hidden.vbs
#                                   -> watchdog.bat -> watchdog.ps1 (service_control.ps1 -Action watch)
#
#  Both tasks run as the current user with an interactive token (only
#  while logged on), which is what a user-scoped background service needs.
#  Registration is idempotent (/f overwrites) and uses schtasks.exe,
#  because Register-ScheduledTask fails with Access Denied (0x80070005)
#  for a non-elevated user on this machine.
#
#  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File register_tasks.ps1
# =====================================================================

[CmdletBinding()]
param(
    [string]$StartTaskName = 'n8n Job Tracker Start',
    [string]$WatchTaskName = 'n8n Job Tracker Watchdog',
    [int]$WatchdogMinutes  = 5
)

$ErrorActionPreference = 'Continue'
if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$root      = $PSScriptRoot
$startVbs  = Join-Path $root 'start_hidden.vbs'
$watchVbs  = Join-Path $root 'watchdog_hidden.vbs'

foreach ($f in @($startVbs, $watchVbs)) {
    if (-not (Test-Path $f)) { Write-Host "ERROR: missing launcher $f"; exit 2 }
}

function Invoke-Schtasks {
    param([string[]]$Arguments)
    Write-Host ("> schtasks.exe " + ($Arguments -join ' '))
    $out  = & schtasks.exe @Arguments 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($out)) { Write-Host "    $line" }
    return $code
}

function Test-TaskExists {
    param([string]$Name)
    & schtasks.exe /query /tn $Name 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
}

# --- idempotency: drop old definitions ---------------------------------
foreach ($name in @($StartTaskName, $WatchTaskName)) {
    if (Test-TaskExists -Name $name) {
        [void](Invoke-Schtasks @('/delete', '/tn', $name, '/f'))
    }
}

# --- 1) start services at logon ---------------------------------------
$rcStart = Invoke-Schtasks @(
    '/create',
    '/tn', $StartTaskName,
    '/tr', ("wscript.exe `"$startVbs`""),
    '/sc', 'onlogon',
    '/f'
)

# --- 2) watchdog every N minutes --------------------------------------
$rcWatch = Invoke-Schtasks @(
    '/create',
    '/tn', $WatchTaskName,
    '/tr', ("wscript.exe `"$watchVbs`""),
    '/sc', 'minute',
    '/mo', "$WatchdogMinutes",
    '/f'
)

Write-Host ''
Write-Host '=== verification (schtasks /query) ==='
foreach ($name in @($StartTaskName, $WatchTaskName)) {
    Write-Host ''
    Write-Host "--- $name ---"
    $out = & schtasks.exe /query /tn $name /v /fo LIST 2>&1
    foreach ($line in @($out)) {
        if ($line -match '^\s*$') { continue }
        if (($line -match 'TaskName|Status|Next Run Time|Schedule Type|Start Time|Repeat|Task To Run|Run As User|Logon Mode|Last Run Time|Last Result|Status|Schedule') ) {
            Write-Host $line
        }
    }
}

if ($rcStart -ne 0 -or $rcWatch -ne 0) {
    Write-Host ''
    Write-Host "RESULT: registration FAILED (start=$rcStart watch=$rcWatch)"
    exit 1
}
Write-Host ''
Write-Host 'RESULT: both tasks registered OK'
exit 0
