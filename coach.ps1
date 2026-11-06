# Focus coach: writes a summary of the last 14 days to coach-data.md and opens
# Claude Code on it for a personal weekly coaching session.
# Run from the app ("Ask Claude coach") or:  powershell -File coach.ps1
param([switch]$NoClaude)

. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location $PSScriptRoot

$days = 14
$rows = @(Get-FocusRows $days)
$sess = @(Get-FocusSessions $days)
$set  = Get-FocusSettings
$L = New-Object System.Collections.Generic.List[string]
function T($s) { Format-FocusTime $s }

$L.Add("# Distraction Log data, last $days days (until $((Get-Date).ToString('dddd yyyy-MM-dd HH:mm')))")
$L.Add('')
$L.Add('Categories: work = focused time, distract = distracting, neutral = counted as neither.')
$L.Add('')
$L.Add('## Settings')
$L.Add("- Daily focus goal: $(T (60 * $set.GoalMinutes))")
$L.Add("- Daily distraction limit: $(T (60 * $set.DailyLimitMinutes))")
$L.Add("- Continuous-distraction alert after: $($set.StreakAlertMinutes) min")
$L.Add("- Focus session: $($set.SessionMinutes) min, break $($set.BreakMinutes) min")
$L.Add("- Block sites during focus sessions: $($set.BlockDuringFocus). Scheduled blocking: $($set.BlockOn) ($($set.BlockFrom)-$($set.BlockTo), weekdays only: $($set.BlockWeekdaysOnly))")
$L.Add('')

$L.Add('## Per day')
$L.Add('| Day | Focused | Distracting | Neutral | Goal met | Focus sessions done |')
$L.Add('|---|---|---|---|---|---|')
for ($i = $days - 1; $i -ge 0; $i--) {
    $d = (Get-Date).AddDays(-$i); $k = $d.ToString('yyyy-MM-dd')
    $r = @($rows | Where-Object Date -eq $k)
    $f = ($r | Where-Object Cat -eq 'work' | Measure-Object Secs -Sum).Sum
    $x = ($r | Where-Object Cat -eq 'distract' | Measure-Object Secs -Sum).Sum
    $n = ($r | Where-Object Cat -eq 'neutral' | Measure-Object Secs -Sum).Sum
    $met = $(if ($set.GoalMinutes -gt 0) { if ($f -ge 60 * $set.GoalMinutes) { 'yes' } else { 'no' } } else { '-' })
    $sd = @($sess | Where-Object { $_.Date -eq $k -and $_.Done }).Count
    $L.Add("| $($d.ToString('ddd')) $k | $(T $f) | $(T $x) | $(T $n) | $met | $sd |")
}
$L.Add('')

$L.Add('## Top apps and sites (all 14 days)')
$L.Add('| App / site | Category | Time |')
$L.Add('|---|---|---|')
$rows | Group-Object Label | ForEach-Object { [pscustomobject]@{ L = $_.Name; C = $_.Group[0].Cat; S = ($_.Group | Measure-Object Secs -Sum).Sum } } |
    Sort-Object S -Descending | Select-Object -First 25 | ForEach-Object { $L.Add("| $($_.L) | $($_.C) | $(T $_.S) |") }
$L.Add('')

$L.Add('## By hour of day (all 14 days added up)')
$L.Add('| Hour | Focused | Distracting |')
$L.Add('|---|---|---|')
foreach ($h in 0..23) {
    $r = @($rows | Where-Object Hour -eq $h)
    if (-not $r) { continue }
    $f = ($r | Where-Object Cat -eq 'work' | Measure-Object Secs -Sum).Sum
    $x = ($r | Where-Object Cat -eq 'distract' | Measure-Object Secs -Sum).Sum
    $L.Add("| ${h}h | $(T $f) | $(T $x) |")
}
$L.Add('')

$L.Add('## Focus sessions (timer)')
if (-not $sess) { $L.Add('No focus sessions recorded yet.') }
else {
    $L.Add("Completed: $(@($sess | Where-Object Done).Count), stopped early: $(@($sess | Where-Object { -not $_.Done }).Count), distracting time during sessions: $(T (($sess | Measure-Object DistractSec -Sum).Sum))")
    $L.Add('')
    $L.Add('| Task | Sessions | Time |')
    $L.Add('|---|---|---|')
    $sess | Group-Object { if ($_.Task) { $_.Task } else { '(no task name)' } } | Sort-Object { ($_.Group | Measure-Object Secs -Sum).Sum } -Descending |
        ForEach-Object { $L.Add("| $($_.Name) | $($_.Count) | $(T (($_.Group | Measure-Object Secs -Sum).Sum)) |") }
}
$L.Add('')

$L.Add('## Daily top 3 (done = [x])')
$any = $false
for ($i = $days - 1; $i -ge -1; $i--) {
    $k = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
    $p = Get-FocusPlan $k
    if (-not (Test-FocusPlan $p)) { continue }
    $any = $true
    $items = for ($j = 0; $j -lt 3; $j++) { if ($p.Items[$j]) { '[' + $(if ($p.Done[$j]) { 'x' } else { ' ' }) + '] ' + $p.Items[$j] } }
    $L.Add("- $k$(if ($i -eq -1) { ' (tomorrow)' }): $($items -join '; ')")
}
if (-not $any) { $L.Add('No daily plans written yet.') }
$L.Add('')

$L.Add('## Weekly goals')
foreach ($w in @(@('This week', (Get-Date)), @('Last week', (Get-Date).AddDays(-7)))) {
    $p = Get-FocusPlan (Get-FocusWeekId $w[1])
    if (Test-FocusPlan $p) {
        $items = for ($j = 0; $j -lt 3; $j++) { if ($p.Items[$j]) { '[' + $(if ($p.Done[$j]) { 'x' } else { ' ' }) + '] ' + $p.Items[$j] } }
        $L.Add("- $($w[0]): $($items -join '; ')")
    } else { $L.Add("- $($w[0]): none set") }
}

[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'coach-data.md'), $L, (New-Object Text.UTF8Encoding $false))
if ($NoClaude) { return }

$prompt = 'You are my focus and productivity coach. Read coach-data.md in this folder: it is my Distraction Log data for the last 14 days ' +
          '(time per app and site, focus sessions, daily top 3 and weekly goals). Give me a short coaching report: ' +
          '1. what went well, with numbers. 2. the 3 biggest problems, with numbers. ' +
          '3. a concrete plan for this week, at most 5 actions, each tied to a specific day or hour. ' +
          '4. any change to my daily goal, distraction limit or blocking schedule you would suggest. ' +
          'Be direct and specific, no generic advice. If there is little data, say so and keep it short. Then wait for my questions.'
if ($set.Language -eq 'pt') { $prompt += ' Answer in Brazilian Portuguese.' }
Write-Host 'Focus coach: your last 14 days are in coach-data.md. Starting Claude...' -ForegroundColor Cyan
& claude $prompt
