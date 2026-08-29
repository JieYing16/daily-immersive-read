#Requires -Version 5.1
<#
.SYNOPSIS
    Generate the day's Daily Immersive Read entries - once per day, whenever
    the laptop happens to be awake.

.DESCRIPTION
    Task Scheduler fires this at logon, on resume from sleep, and hourly. The
    script is idempotent: it looks for a "## yyyy-MM-dd" header for today in
    daily_reads.md and exits at once if one is already there. That makes the
    number of triggers irrelevant - twenty fires in a day still produce one set
    of entries - and it self-heals after a day the laptop stayed shut.

    State is read from daily_reads.md itself rather than a marker file, so the
    guard cannot drift out of sync with the thing it is guarding.

.PARAMETER Force
    Generate even if today's entries already exist.

.PARAMETER DryRun
    Report what would happen, then exit without generating or committing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scheduler\run_daily.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------
$Repo = 'D:\GitHub\daily-immersive-read'

# The generation command. EDIT THIS if your Claude CLI is installed elsewhere
# or you invoke it differently. The prompt mirrors the scheduled-task SKILL.md.
$ClaudeExe = 'claude'
$ClaudeArgs = @(
    '-p'
    @'
Read README.md in this repo for the entry format. Then:
1. Read daily_reads.md. If a "## <today>" header already exists, only generate
   the topics missing under it; if all four are present, stop.
2. For each missing topic - AI Technology, Geopolitics, Environment, Economics,
   in that order - search the web for one real, recent development.
3. Write each as: "### Topic: <name>", a bold 5-8 word title, 3-5 bullets
   (~150-200 words), a "**Why it matters:**" line, and an italic source + date.
   Prepend today's "## <today>" header directly under the log heading, and put
   a "---" after the last topic, before the previous date.
4. Run: python build_reader.py
'@
)

$LogDir = Join-Path $env:LOCALAPPDATA 'daily-immersive-read'
$LogFile = Join-Path $LogDir 'run_daily.log'

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $line = '{0}  {1,-5}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Native {
    <#  Run a child process, log every line it writes, and return its exit code.

        $ErrorActionPreference is dropped to 'Continue' for the duration of the
        call. Under 'Stop', PowerShell 5.1 promotes *any* stderr line from a
        native command to a terminating NativeCommandError - even on exit code
        0 - so a claude banner or a python deprecation warning was enough to
        abort the whole run and log that line as the failure. The assignment is
        function-scoped, so it reverts on return; callers check the exit code.  #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$Tag
    )
    $ErrorActionPreference = 'Continue'

    & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Log "  ${Tag}: $_" }
    return $LASTEXITCODE
}

function Resolve-Python {
    <#  Prefer the repo virtualenv so the scheduled run uses the same
        interpreter (and the same 'markdown' install) as a manual run.  #>
    $venv = Join-Path $Repo '.venv\Scripts\python.exe'
    if (Test-Path $venv) { return $venv }
    $sys = Get-Command python -ErrorAction SilentlyContinue
    if ($sys) { return $sys.Source }
    throw "No Python found. Expected $venv or 'python' on PATH."
}

function Test-TodayPresent {
    param([Parameter(Mandatory)][string]$MarkdownPath)
    $today = Get-Date -Format 'yyyy-MM-dd'
    return [bool](Select-String -Path $MarkdownPath -Pattern "^##\s+$today\s*$" -Quiet)
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
try {
    if (-not (Test-Path $Repo)) { throw "Repo not found: $Repo" }
    Set-Location $Repo

    $markdown = Join-Path $Repo 'daily_reads.md'
    if (-not (Test-Path $markdown)) { throw "Missing $markdown" }

    $today = Get-Date -Format 'yyyy-MM-dd'

    # Present in the file is not the same as published. A day written by hand,
    # or a run that died after generating, leaves daily_reads.md modified and
    # uncommitted - and the phone reads reads.json from main, so it never sees
    # that day. So this skips generation only; build and commit still run, and
    # both are no-ops when there is genuinely nothing new.
    $skipGeneration = (Test-TodayPresent $markdown) -and -not $Force

    if ($DryRun) {
        if ($skipGeneration) {
            Write-Log "DRY RUN: entries for $today already present - would rebuild and commit only."
        }
        else {
            Write-Log "DRY RUN: would generate entries for $today, rebuild, and commit."
        }
        exit 0
    }

    # Generation ------------------------------------------------------------
    if ($skipGeneration) {
        Write-Log "Entries for $today already present - skipping generation."
    }
    else {
        $claude = Get-Command $ClaudeExe -ErrorAction SilentlyContinue
        if (-not $claude) {
            Write-Log "'$ClaudeExe' not on PATH. Edit `$ClaudeExe in this script." 'ERROR'
            exit 2
        }

        Write-Log "Generating entries for $today ..."
        $code = Invoke-Native -FilePath $claude.Source -Arguments $ClaudeArgs -Tag 'claude'
        if ($code -ne 0) {
            Write-Log "Generation exited with code $code." 'WARN'
        }

        # Verify the generation actually wrote something before we build/commit.
        if (-not (Test-TodayPresent $markdown)) {
            Write-Log "No '## $today' header after generation - stopping without commit." 'ERROR'
            exit 3
        }
    }

    # Build -----------------------------------------------------------------
    $python = Resolve-Python
    Write-Log "Rebuilding reads.json with $python ..."
    $code = Invoke-Native -FilePath $python -Arguments @((Join-Path $Repo 'build_reader.py')) -Tag 'build'
    if ($code -ne 0) { throw "build_reader.py failed with code $code." }

    # Commit ----------------------------------------------------------------
    # Also routed through Invoke-Native: the commit script shells out to git,
    # which writes CRLF warnings and push progress to stderr on success.
    $commit = Join-Path $Repo 'commit_daily_reads.ps1'
    if (Test-Path $commit) {
        Write-Log 'Committing ...'
        $code = Invoke-Native -FilePath $commit -Tag 'commit'
        if ($code -ne 0) { throw "commit_daily_reads.ps1 failed with code $code." }
    }
    else {
        Write-Log "No commit_daily_reads.ps1 - skipping commit." 'WARN'
    }

    Write-Log "Done for $today."
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
