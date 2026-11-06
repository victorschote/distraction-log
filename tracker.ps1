# Distraction log tracker: every few seconds, records which app/window is in
# front. Time away from the keyboard (2+ minutes) is not counted.
# Data stays local in .\logs\YYYY-MM-DD.tsv (start, seconds, app, window title).
# Also sends the notifications: continuous distraction, daily limit, goal reached,
# focus-session nudges and timer ends, morning top 3, end-of-day summary and the
# Monday weekly review. Settings live in settings.json.

$dir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $dir 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

# Only one tracker at a time
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\DistractionLogTracker', [ref]$created)
if (-not $created) { exit }

. (Join-Path $dir 'common.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class FocusWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO i);
    public static uint IdleSeconds() {
        var i = new LASTINPUTINFO();
        i.cbSize = (uint)Marshal.SizeOf(i);
        GetLastInputInfo(ref i);
        return ((uint)Environment.TickCount - i.dwTime) / 1000;
    }
}
"@

$intervalSec = 5
$idleLimit   = 120   # seconds without mouse/keyboard = away
$maxSegment  = 300   # write to disk at least every 5 minutes

$curApp = $null; $curTitle = $null; $start = $null

function Save-Segment([datetime]$end) {
    if (-not $script:curApp -or $script:curApp -eq 'Idle') { return }
    $secs = [int]($end - $script:start).TotalSeconds
    if ($secs -le 0) { return }
    $file = Join-Path $logDir ($script:start.ToString('yyyy-MM-dd') + '.tsv')
    $line = "{0}`t{1}`t{2}`t{3}`r`n" -f $script:start.ToString('s'), $secs, $script:curApp, $script:curTitle
    Add-FocusLine $file $line
}

# ---------- Alert state ----------
$alertFile = Join-Path $dir 'alerts.json'
$labelCache = @{}

function Reset-Day {
    $script:day = (Get-Date).ToString('yyyy-MM-dd')
    $script:focusSec = 0; $script:distSec = 0; $script:distByLabel = @{}
    foreach ($r in @(Get-FocusRows 1)) {
        if ($r.Cat -eq 'distract') { $script:distSec += $r.Secs; $script:distByLabel[$r.Label] = [double]$script:distByLabel[$r.Label] + $r.Secs }
        elseif ($r.Cat -eq 'work') { $script:focusSec += $r.Secs }
    }
    $script:alerts = [pscustomobject]@{ Date = $script:day; LimitAlerted = $false; GoalAlerted = $false; SummaryShown = $false; MorningShown = $false; ReviewWeek = '' }
    if (Test-Path $alertFile) {
        try {
            $a = Get-Content $alertFile -Raw | ConvertFrom-Json
            $script:alerts.ReviewWeek = [string]$a.ReviewWeek
            if ($a.Date -eq $script:day) {
                foreach ($k in 'LimitAlerted', 'GoalAlerted', 'SummaryShown', 'MorningShown') { $script:alerts.$k = [bool]$a.$k }
            }
        } catch {}
    }
    $script:streak = 0; $script:focusRun = 0; $script:nextStreakAlert = 0; $script:nextFocusNudge = 15
}

function Save-Alerts { try { $script:alerts | ConvertTo-Json | Set-Content $alertFile -Encoding UTF8 } catch {} }

function Get-CatStamp { if (Test-Path $CategoryFile) { (Get-Item $CategoryFile).LastWriteTimeUtc.Ticks } else { 0 } }

$settings = Get-FocusSettings
$settingsCheck = Get-Date
$catStamp = Get-CatStamp
Reset-Day
$lastLoop = Get-Date

while ($true) {
    $now  = Get-Date
    $idle = [FocusWin]::IdleSeconds()

    if ($idle -ge $idleLimit) {
        $app = 'Idle'; $title = ''
    } else {
        $h  = [FocusWin]::GetForegroundWindow()
        $sb = New-Object System.Text.StringBuilder 512
        [void][FocusWin]::GetWindowText($h, $sb, 512)
        $title = $sb.ToString() -replace "[`t`r`n]", ' '
        [uint32]$procId = 0
        [void][FocusWin]::GetWindowThreadProcessId($h, [ref]$procId)
        $app = try { (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { 'Unknown' }
    }

    $changed = ($app -ne $curApp) -or ($title -ne $curTitle) -or
               ($start -and (($now - $start).TotalSeconds -ge $maxSegment)) -or
               ($start -and $now.Date -ne $start.Date)

    if ($changed) {
        # When going idle, stop the previous app's clock when input actually stopped
        $end = if ($app -eq 'Idle') { $now.AddSeconds(-$idle) } else { $now }
        if ($start -and $end -lt $start) { $end = $start }
        Save-Segment $end
        $curApp = $app; $curTitle = $title; $start = $now
    }

    # ---------- Alerts ----------
    try {
        if ($now.ToString('yyyy-MM-dd') -ne $day) { Reset-Day }
        if (($now - $settingsCheck).TotalSeconds -ge 60) {
            $settings = Get-FocusSettings; $settingsCheck = $now
            if ([string]$settings.Language -ne $LangCode) { Set-FocusLanguage ([string]$settings.Language) }
            $st = Get-CatStamp
            if ($st -ne $catStamp) {   # you changed a category in the app: recount today
                $catStamp = $st; $FocusCatMap = Import-FocusCategories; $labelCache.Clear(); Reset-Day
            }
        }

        $sess = $null
        try { $sess = Update-FocusSession } catch {}
        $inFocus = $sess -and $sess.State -eq 'focus'

        $step = [math]::Min(10, ($now - $lastLoop).TotalSeconds)
        if ($app -ne 'Idle') {
            $key = $app + "`t" + $title
            if (-not $labelCache.ContainsKey($key)) {
                if ($labelCache.Count -gt 5000) { $labelCache.Clear() }
                $l = Get-FocusLabel $app $title
                $labelCache[$key] = @($l, (Get-FocusCategory $l $title))
            }
            $label = $labelCache[$key][0]; $cat = $labelCache[$key][1]
            $short = $label -replace '^\w+: ', ''

            if ($cat -eq 'distract') {
                $distSec += $step; $streak += $step; $focusRun = 0; $streakLabel = $label
                $distByLabel[$label] = [double]$distByLabel[$label] + $step
                if ($inFocus) {
                    Add-FocusSessionDistract $step
                    # During a focus session, nudge right away (after 15 s), then every 2 minutes
                    if ($streak -ge $nextFocusNudge) {
                        $back = $(if ($sess.Task) { "'" + $sess.Task + "'" } else { 'your work' })
                        Show-FocusToast 'You are in a focus session' ("You opened $short. Back to $back?") 'distractionlog:today'
                        $nextFocusNudge = $streak + 120
                    }
                }
            } elseif ($cat -eq 'work') {
                $focusSec += $step; $focusRun += $step
                if ($focusRun -ge 60) { $streak = 0; $nextStreakAlert = 0; $nextFocusNudge = 15 }   # a real minute of work ends the streak
            }

            if ($settings.AlertsOn) {
                $streakLimit = 60 * [double]$settings.StreakAlertMinutes
                if ($nextStreakAlert -eq 0) { $nextStreakAlert = $streakLimit }
                if ($streakLimit -gt 0 -and $streak -ge $nextStreakAlert -and -not $inFocus) {
                    Show-FocusToast 'Time for a break from distractions?' ("You've been on {0} for {1} minutes. Back to work?" -f ($streakLabel -replace '^\w+: ', ''), [int]($streak / 60))
                    $nextStreakAlert += $streakLimit
                }
                $limit = 60 * [double]$settings.DailyLimitMinutes
                if ($limit -gt 0 -and $distSec -ge $limit -and -not $alerts.LimitAlerted) {
                    Show-FocusToast 'Daily distraction limit reached' ("You've spent {0} on distracting sites and apps today." -f (Format-FocusTime $distSec))
                    $alerts.LimitAlerted = $true; Save-Alerts
                }
                $goal = 60 * [double]$settings.GoalMinutes
                if ($goal -gt 0 -and $focusSec -ge $goal -and -not $alerts.GoalAlerted) {
                    Show-FocusToast 'Daily goal reached!' ("{0} of focused work today. Great job." -f (Format-FocusTime $focusSec))
                    $alerts.GoalAlerted = $true; Save-Alerts
                }

                # Morning: today's top 3 (first activity before noon)
                if (-not $alerts.MorningShown) {
                    if ($now.Hour -ge 5 -and $now.Hour -lt 12) {
                        $plan = Get-FocusPlan $day
                        if (Test-FocusPlan $plan) {
                            $lines = for ($i = 0; $i -lt 3; $i++) { if ($plan.Items[$i]) { "$($i + 1). $($plan.Items[$i])" } }
                            Show-FocusToast 'Your top 3 for today' ($lines -join "`n") 'distractionlog:today'
                        } else {
                            Show-FocusToast 'Good morning! What are your top 3 today?' 'Click to write down the three things that would make today a good day.' 'distractionlog:plantoday'
                        }
                    }
                    $alerts.MorningShown = $true; Save-Alerts
                }

                # End of day summary
                if (-not $alerts.SummaryShown -and [string]$settings.SummaryTime -match '^(\d{1,2}):(\d{2})$') {
                    $at = $now.Date.AddHours([int]$matches[1]).AddMinutes([int]$matches[2])
                    if ($now -ge $at -and ($focusSec + $distSec) -ge 600) {
                        $parts = @()
                        if ($goal -gt 0) { $parts += $(if ($focusSec -ge $goal) { 'Goal met.' } else { 'Goal: ' + (Format-FocusTime ($goal - $focusSec)) + ' short.' }) }
                        $topBad = $distByLabel.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
                        if ($topBad) { $parts += ('Top distraction: {0} ({1}).' -f ($topBad.Key -replace '^\w+: ', ''), (Format-FocusTime $topBad.Value)) }
                        $done = @(Get-FocusSessions 1 | Where-Object Done).Count
                        if ($done) { $parts += "$done focus session$(if ($done -ne 1) { 's' })." }
                        $parts += "Click to plan tomorrow's top 3."
                        Show-FocusToast ('Your day: {0} focused' -f (Format-FocusTime $focusSec)) (($parts | ForEach-Object { Tr $_ }) -join ' ') 'distractionlog:plan'
                        $alerts.SummaryShown = $true; Save-Alerts
                    }
                }

                # Monday: weekly review
                $week = Get-FocusWeekId $now
                if ($now.DayOfWeek -eq 'Monday' -and $alerts.ReviewWeek -ne $week) {
                    Show-FocusToast 'Your weekly review is ready' 'See how last week went and set 3 goals for this week.' 'distractionlog:review'
                    $alerts.ReviewWeek = $week; Save-Alerts
                }
            }
        }
    } catch {}
    $lastLoop = $now

    Start-Sleep -Seconds $intervalSec
}
