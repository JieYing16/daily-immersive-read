#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Register the "Daily Immersive Read" scheduled task.

.DESCRIPTION
    Installs a Windows scheduled task that runs run_daily.ps1 on three triggers:

      * at logon
      * on resume from sleep (System log, Power-Troubleshooter, Event ID 1)
      * hourly, all day

    run_daily.ps1 is idempotent - it exits immediately if today's entries are
    already in daily_reads.md - so the overlapping triggers collapse to exactly
    one generation per day, at the first moment the laptop is actually awake.

    The task deliberately does NOT wake the machine. If the laptop stays shut
    all day, nothing runs, and the next wake picks it up.

.PARAMETER Uninstall
    Remove the task instead of installing it.

.EXAMPLE
    .\install_task.ps1
    .\install_task.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'Daily Immersive Read'
$TaskPath = '\'
$ScriptPath = Join-Path $PSScriptRoot 'run_daily.ps1'

# --------------------------------------------------------------------------
# Uninstall
# --------------------------------------------------------------------------
if ($Uninstall) {
    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Yellow
    }
    else {
        Write-Host "No scheduled task named '$TaskName' found." -ForegroundColor Yellow
    }
    return
}

if (-not (Test-Path $ScriptPath)) {
    throw "Cannot find run_daily.ps1 next to this script (looked in $PSScriptRoot)."
}

# --------------------------------------------------------------------------
# Action
# --------------------------------------------------------------------------
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath) `
    -WorkingDirectory (Split-Path $ScriptPath -Parent)

# --------------------------------------------------------------------------
# Triggers
# --------------------------------------------------------------------------

# 1. At logon (this user only).
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

# 2. Hourly, all day. Built as a daily trigger whose repetition is borrowed
#    from a throwaway one-shot trigger - the supported way to get a repeating
#    daily trigger out of New-ScheduledTaskTrigger.
$hourly = New-ScheduledTaskTrigger -Daily -At '00:05'
$repeatSource = New-ScheduledTaskTrigger -Once -At '00:05' `
    -RepetitionInterval (New-TimeSpan -Hours 1) `
    -RepetitionDuration (New-TimeSpan -Days 1)
$hourly.Repetition = $repeatSource.Repetition

# 3. On resume from sleep. Task Scheduler has no first-class "on wake" trigger,
#    so subscribe to the event Windows logs when the system resumes.
$eventClass = Get-CimClass `
    -ClassName MSFT_TaskEventTrigger `
    -Namespace Root/Microsoft/Windows/TaskScheduler
$onWake = New-CimInstance -CimClass $eventClass -ClientOnly
$onWake.Enabled = $true
$onWake.Subscription = @'
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>
'@
# Let the network and OneDrive settle before firing.
$onWake.Delay = 'PT2M'

$triggers = @($atLogon, $hourly, $onWake)

# --------------------------------------------------------------------------
# Principal and settings
# --------------------------------------------------------------------------
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 10)

$settings.WakeToRun = $false
$settings.RunOnlyIfNetworkAvailable = $true

# --------------------------------------------------------------------------
# Register (replacing any previous version)
# --------------------------------------------------------------------------
$existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Replacing existing task '$TaskName' ..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -TaskPath $TaskPath `
    -Action $action `
    -Trigger $triggers `
    -Principal $principal `
    -Settings $settings `
    -Description 'Generates the day''s Daily Immersive Read entries once per day, at logon, on wake, and hourly while awake.' | Out-Null

Write-Host ""
Write-Host "Installed '$TaskName'." -ForegroundColor Green
Write-Host "  Triggers : at logon, on resume from sleep (+2 min), hourly"
Write-Host "  Runs as  : $env:USERDOMAIN\$env:USERNAME (only while logged on)"
Write-Host "  Script   : $ScriptPath"
Write-Host "  Log      : $(Join-Path $env:LOCALAPPDATA 'daily-immersive-read\run_daily.log')"
Write-Host ""
Write-Host "Verify with:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'   # force one run now"
Write-Host ""
Write-Host "Remember to delete the old 17:39 task so it does not double-run." -ForegroundColor Yellow
