# =====================================================================
#  service_control.ps1 - start / watch / status for the local services
#
#  Services managed:
#    1) scraper bridge   : node  scraper_server.js        (port 3456, GET /health)
#    2) self-hosted n8n  : node  <npm-global>\n8n\bin\n8n start --port=5678
#                                                        (GET /healthz)
#
#  Actions:
#    -Action start   one-shot: start whatever is down, wait until BOTH
#                    health endpoints answer HTTP 200, exit 0 (1 otherwise).
#                    Used by the logon scheduled task (via start_n8n.bat).
#    -Action watch   periodic: check both endpoints, restart whatever is
#                    down, append a timestamped summary to logs\watchdog.log.
#                    Used by watchdog.ps1 / the 5-minute scheduled task.
#    -Action status  read-only health report.
#
#  Safety notes:
#    * NEVER uses `taskkill /f /im node.exe`. Processes are matched on their
#      COMMAND LINE, so unrelated node.exe processes (Adobe CC, other bots,
#      Hermes itself) are never touched.
#    * A service is only killed when its own health endpoint is NOT answering.
#    * Before starting anything we check whether the port is already taken,
#      so no duplicate instance can be spawned.
#    * Services are launched DETACHED (own hidden process, stdout/stderr
#      redirected to logs\*.log) and this script exits deliberately.
# =====================================================================

[CmdletBinding()]
param(
    [ValidateSet('start', 'watch', 'status')]
    [string]$Action = 'start',

    # how long to wait for a service to become ready after (re)starting it
    [int]$ScraperWaitSeconds = 120,
    [int]$N8nWaitSeconds = 300,

    # single health-probe timeout
    [int]$HealthTimeoutSeconds = 5
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # keeps Invoke-WebRequest fast

if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$script:Root   = $PSScriptRoot
$script:LogDir = Join-Path $script:Root 'logs'
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

# ---------------------------------------------------------------------
# configuration (env overridable, sane defaults kept in sync with .env.example)
# ---------------------------------------------------------------------
$script:ScraperPort = if ($env:SCRAPER_PORT) { [int]$env:SCRAPER_PORT } else { 3456 }
$script:N8nPort     = if ($env:N8N_PORT)     { [int]$env:N8N_PORT }     else { 5678 }

$script:ScraperHealthUrl = "http://localhost:$($script:ScraperPort)/health"
$script:N8nHealthUrl     = "http://localhost:$($script:N8nPort)/healthz"

$script:ScraperOut = Join-Path $script:LogDir 'scraper.log'
$script:ScraperErr = Join-Path $script:LogDir 'scraper.err.log'
$script:N8nOut     = Join-Path $script:LogDir 'n8n.log'
$script:N8nErr     = Join-Path $script:LogDir 'n8n.err.log'

$script:CvDir = Join-Path $script:Root 'cv'

# log file for this run
$script:LogFile = Join-Path $script:LogDir $(switch ($Action) {
    'start'  { 'startup.log' }
    'watch'  { 'watchdog.log' }
    default  { 'status.log' }
})

function Find-NodeExe {
    # 1) explicit override, 2) PATH, 3) well-known install dirs, 4) bundled runtime
    if ($env:SCRAPER_NODE -and (Test-Path $env:SCRAPER_NODE)) { return $env:SCRAPER_NODE }
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cands = @(
        (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'),
        (Join-Path $env:LOCALAPPDATA 'hermes\node\node.exe')
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return 'node.exe'
}

function Test-Jobspy {
    param([string]$Exe)
    if (-not $Exe) { return $false }
    try {
        $null = & $Exe -c 'import jobspy' 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Find-Python {
    # prefer an interpreter that can actually import the scraper dependency
    if ($env:SCRAPER_PYTHON -and (Test-Path $env:SCRAPER_PYTHON)) { return $env:SCRAPER_PYTHON }
    $cands = @()
    foreach ($name in @('python.exe', 'python3.exe')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { $cands += $c.Source }
    }
    $cands += (Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\python.exe')
    foreach ($c in $cands) { if ($c -and (Test-Path $c) -and (Test-Jobspy $c)) { return $c } }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return 'python'
}

function Find-N8nBin {
    # never assume an install prefix: ask npm, ask PATH, then try the usual places
    if ($env:N8N_BIN -and (Test-Path $env:N8N_BIN)) { return $env:N8N_BIN }
    $prefixes = @()
    try {
        $npmPrefix = (& npm config get prefix 2>$null | Select-Object -First 1)
        if ($npmPrefix) { $prefixes += $npmPrefix.Trim() }
    } catch { }
    $shim = Get-Command n8n -ErrorAction SilentlyContinue
    if ($shim) { $prefixes += (Split-Path -Parent $shim.Source) }
    $prefixes += (Join-Path $env:APPDATA 'npm')
    $prefixes += (Join-Path $env:USERPROFILE 'npm-global')
    foreach ($p in $prefixes) {
        if (-not $p) { continue }
        $bin = Join-Path $p 'node_modules\n8n\bin\n8n'
        if (Test-Path $bin) { return $bin }
    }
    throw "n8n CLI not found. Install it ('npm i -g n8n') or set N8N_BIN to the n8n\bin\n8n path."
}

$script:NodeExe = Find-NodeExe
$script:Python  = Find-Python
$script:N8nBin  = Find-N8nBin

# environment inherited by every service process we spawn
$env:SCRAPER_PYTHON               = $script:Python
$env:SCRAPER_PORT                 = "$($script:ScraperPort)"
$env:N8N_RESTRICT_FILE_ACCESS_TO  = $script:CvDir
$env:N8N_PORT                     = "$($script:N8nPort)"

# ---------------------------------------------------------------------
# environment hygiene
#   When this script is launched from git-bash, MSYS exports TMP as a
#   POSIX path (and a lowercase "tmp" variable). .NET then refuses to
#   create a redirected process ("The environment variable TMP is
#   missing"). Normalise TMP/TEMP to a real Windows directory first so
#   Start-Process with -RedirectStandardOutput works from any caller
#   (double-click, git-bash, Task Scheduler).
# ---------------------------------------------------------------------
try { [Environment]::SetEnvironmentVariable('tmp', $null) } catch { }
$tempDir = $env:LOCALAPPDATA
if (-not $tempDir) { $tempDir = Join-Path $env:USERPROFILE 'AppData\Local' }
if ($tempDir) {
    $tempDir = Join-Path $tempDir 'Temp'
    if (-not (Test-Path $tempDir)) {
        try { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null } catch { }
    }
    if (Test-Path $tempDir) { $env:TMP = $tempDir; $env:TEMP = $tempDir }
}

# ---------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Path = $script:LogFile)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try {
        $enc = New-Object System.Text.UTF8Encoding($false)   # no BOM, keeps appends clean
        [System.IO.File]::AppendAllText($Path, $line + "`r`n", $enc)
    } catch { }
    Write-Host $line
}

function Rotate-Log {
    param([string]$Path, [int]$MaxBytes = 1048576, [int]$KeepLines = 500)
    if (-not (Test-Path $Path)) { return }
    try {
        $fi = Get-Item $Path
        if ($fi.Length -le $MaxBytes) { return }
        $tail = @(Get-Content -Path $Path -Tail $KeepLines)
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($Path, [string[]]$tail, $enc)
    } catch { }
}

# ---------------------------------------------------------------------
# health / port helpers
# ---------------------------------------------------------------------
function Test-Health {
    param([string]$Url, [int]$TimeoutSec = 5)
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        try {
            $code = & $curl -s -o NUL -m $TimeoutSec -w '%{http_code}' $Url 2>$null
            if ($code) { return ((([string]$code).Trim()) -eq '200') }
        } catch { }
    }
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Test-PortListening {
    param([int]$Port)
    try {
        $c = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
        if ($c.Count -gt 0) { return $true }
    } catch { }
    return $false
}

function Wait-Health {
    param([string]$Url, [int]$TimeoutSec, [int]$IntervalSec = 3, [int]$ProbeTimeoutSec = 5)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Health -Url $Url -TimeoutSec $ProbeTimeoutSec) { return $true }
        Start-Sleep -Seconds $IntervalSec
    }
    return $false
}

# ---------------------------------------------------------------------
# process discovery (command-line matched, never blind-kill)
# ---------------------------------------------------------------------
$script:NodeProcFilter = "Name='node.exe'"

function Get-NodeProcs {
    try { return @(Get-CimInstance Win32_Process -Filter $script:NodeProcFilter -ErrorAction Stop) }
    catch { return @() }
}

# strict patterns: "is this process the service itself?"
$script:ScraperMatch = 'scraper_server\.js'
$script:N8nMatch     = 'n8n[\\/]bin[\\/]n8n'
# broad patterns: everything belonging to that service (incl. n8n child helpers)
$script:ScraperCleanup = 'scraper_server\.js'
$script:N8nCleanup     = 'node_modules[\\/]n8n[\\/]'

function Get-MatchingProcs {
    param([string]$Pattern)
    return @(Get-NodeProcs | Where-Object { $_.CommandLine -and ($_.CommandLine -match $Pattern) })
}

# ---------------------------------------------------------------------
# service start actions (detached, hidden, logs redirected)
# ---------------------------------------------------------------------
function Start-ScraperProcess {
    if (-not (Test-Path (Join-Path $script:Root 'scraper_server.js'))) {
        throw "scraper_server.js not found in $($script:Root)"
    }
    return Start-Process -FilePath $script:NodeExe `
        -ArgumentList 'scraper_server.js' `
        -WorkingDirectory $script:Root `
        -WindowStyle Hidden `
        -RedirectStandardOutput $script:ScraperOut `
        -RedirectStandardError  $script:ScraperErr `
        -PassThru
}

function Start-N8nProcess {
    if (-not (Test-Path $script:N8nBin)) {
        throw "n8n not found at $($script:N8nBin)"
    }
    # quoted because $script:N8nBin / $script:NodeExe may contain spaces
    return Start-Process -FilePath $script:NodeExe `
        -ArgumentList "`"$($script:N8nBin)`" start --port=$($script:N8nPort)" `
        -WorkingDirectory $script:Root `
        -WindowStyle Hidden `
        -RedirectStandardOutput $script:N8nOut `
        -RedirectStandardError  $script:N8nErr `
        -PassThru
}

# ---------------------------------------------------------------------
# ensure one service is up; restart it if it is not
# ---------------------------------------------------------------------
function Ensure-Service {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$HealthUrl,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$WaitSeconds,
        [Parameter(Mandatory)][string]$MatchPattern,
        [Parameter(Mandatory)][string]$CleanupPattern,
        [Parameter(Mandatory)][scriptblock]$StartBlock
    )

    $result = [ordered]@{
        Name      = $Name
        WasUp     = $false
        Restarted = $false
        Up        = $false
        Seconds   = 0
        Pids      = @()
    }

    if (Test-Health -Url $HealthUrl -TimeoutSec $HealthTimeoutSeconds) {
        $result.WasUp = $true
        $result.Up    = $true
        $procs = Get-MatchingProcs -Pattern $MatchPattern
        $result.Pids = @($procs | ForEach-Object { $_.ProcessId })
        if ($procs.Count -gt 1) {
            Write-Log "WARN $Name healthy but $($procs.Count) matching processes (PIDs $($result.Pids -join ', ')) - possible duplicates, leaving them alone"
        } else {
            Write-Log "$Name already UP (pid $($result.Pids -join ','))"
        }
        return $result
    }

    Write-Log "$Name DOWN - $HealthUrl did not answer 200"

    # clean up the corpse / half-dead instance (command-line matched only)
    $stale = Get-MatchingProcs -Pattern $CleanupPattern
    foreach ($p in $stale) {
        Write-Log "$Name : killing stale node process pid $($p.ProcessId)"
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop }
        catch { Write-Log "$Name : could not kill pid $($p.ProcessId) - $($_.Exception.Message)" }
    }
    if ($stale.Count -gt 0) { Start-Sleep -Seconds 2 }

    if (Test-PortListening -Port $Port) {
        Write-Log "WARN port $Port still listening after cleanup - NOT starting a duplicate $Name"
        return $result
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $proc = & $StartBlock
        Write-Log "$Name : started pid $($proc.Id) -> $HealthUrl"
    } catch {
        Write-Log "ERROR $Name : could not start - $($_.Exception.Message)"
        return $result
    }

    $ok = Wait-Health -Url $HealthUrl -TimeoutSec $WaitSeconds
    $sw.Stop()
    $result.Restarted = $true
    $result.Up        = $ok
    $result.Seconds   = [int]$sw.Elapsed.TotalSeconds
    if ($ok) {
        Write-Log "$Name RECOVERED - $HealthUrl OK after $($result.Seconds)s"
    } else {
        Write-Log "ERROR $Name did not come up within ${WaitSeconds}s (see logs\$Name.log / .err.log)"
    }
    return $result
}

# ---------------------------------------------------------------------
# main
# ---------------------------------------------------------------------
$exitCode = 0

Write-Log "--- $Action (node=$($script:NodeExe)) (python=$($script:Python)) (restrict=$env:N8N_RESTRICT_FILE_ACCESS_TO) ---"

switch ($Action) {

    'start' {
        Rotate-Log -Path $script:LogFile

        $scraper = Ensure-Service -Name 'scraper' -HealthUrl $script:ScraperHealthUrl `
            -Port $script:ScraperPort -WaitSeconds $ScraperWaitSeconds `
            -MatchPattern $script:ScraperMatch -CleanupPattern $script:ScraperCleanup `
            -StartBlock { Start-ScraperProcess }

        $n8n = Ensure-Service -Name 'n8n' -HealthUrl $script:N8nHealthUrl `
            -Port $script:N8nPort -WaitSeconds $N8nWaitSeconds `
            -MatchPattern $script:N8nMatch -CleanupPattern $script:N8nCleanup `
            -StartBlock { Start-N8nProcess }

        Write-Log ("start summary: scraper={0} n8n={1} (n8n UI http://localhost:{2}, bridge http://localhost:{3})" -f `
            $(if ($scraper.Up) { 'UP' } else { 'DOWN' }), `
            $(if ($n8n.Up) { 'UP' } else { 'DOWN' }), `
            $script:N8nPort, $script:ScraperPort)

        if (-not ($scraper.Up -and $n8n.Up)) { $exitCode = 1 }
    }

    'watch' {
        Rotate-Log -Path $script:LogFile

        $scraper = Ensure-Service -Name 'scraper' -HealthUrl $script:ScraperHealthUrl `
            -Port $script:ScraperPort -WaitSeconds $ScraperWaitSeconds `
            -MatchPattern $script:ScraperMatch -CleanupPattern $script:ScraperCleanup `
            -StartBlock { Start-ScraperProcess }

        $n8n = Ensure-Service -Name 'n8n' -HealthUrl $script:N8nHealthUrl `
            -Port $script:N8nPort -WaitSeconds $N8nWaitSeconds `
            -MatchPattern $script:N8nMatch -CleanupPattern $script:N8nCleanup `
            -StartBlock { Start-N8nProcess }

        $restarted = @()
        if ($scraper.Restarted) { $restarted += 'scraper' }
        if ($n8n.Restarted)     { $restarted += 'n8n' }

        $summary = "WATCH scraper={0}(pid {1}) n8n={2}(pid {3}) restarted={4}" -f `
            $(if ($scraper.Up) { 'UP' } else { 'DOWN' }), $($scraper.Pids -join ','), `
            $(if ($n8n.Up) { 'UP' } else { 'DOWN' }), $($n8n.Pids -join ','), `
            $(if ($restarted.Count -gt 0) { $restarted -join '+' } else { 'none' })
        Write-Log $summary

        if (-not ($scraper.Up -and $n8n.Up)) { $exitCode = 1 }
    }

    'status' {
        $sUp = Test-Health -Url $script:ScraperHealthUrl -TimeoutSec $HealthTimeoutSeconds
        $nUp = Test-Health -Url $script:N8nHealthUrl -TimeoutSec $HealthTimeoutSeconds
        $sp  = @(Get-MatchingProcs -Pattern $script:ScraperMatch | ForEach-Object { $_.ProcessId })
        $np  = @(Get-MatchingProcs -Pattern $script:N8nMatch     | ForEach-Object { $_.ProcessId })
        Write-Log ("status: scraper={0} {1} (pids {2}) | n8n={3} {4} (pids {5})" -f `
            $(if ($sUp) { 'UP' } else { 'DOWN' }), $script:ScraperHealthUrl, ($sp -join ','), `
            $(if ($nUp) { 'UP' } else { 'DOWN' }), $script:N8nHealthUrl, ($np -join ','))
        if (-not ($sUp -and $nUp)) { $exitCode = 1 }
    }
}

exit $exitCode
