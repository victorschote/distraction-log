# Shared settings and helpers for the distraction log (used by report.ps1 and dashboard.ps1).
# Keep this file ASCII-only: Windows PowerShell 5.1 misreads other characters.

$FocusDir = $PSScriptRoot
$FocusVersion = '1.0.0'   # keep in sync with CHANGELOG.md

# Distracting apps/sites: keyword (matched against app + window title, any case) = display name.
# Add or remove lines to match your habits.
$Distracting = [ordered]@{
    'youtube'     = 'YouTube'
    'instagram'   = 'Instagram'
    'facebook'    = 'Facebook'
    'tiktok'      = 'TikTok'
    'twitter'     = 'X (Twitter)'
    'x.com'       = 'X (Twitter)'
    'netflix'     = 'Netflix'
    'reddit'      = 'Reddit'
    'whatsapp'    = 'WhatsApp'
    'twitch'      = 'Twitch'
    'prime video' = 'Prime Video'
    'globoplay'   = 'Globoplay'
    'disney+'     = 'Disney+'
    '9gag'        = '9GAG'
    'pinterest'   = 'Pinterest'
}

$Friendly = @{
    'WINWORD'='Word'; 'EXCEL'='Excel'; 'POWERPNT'='PowerPoint'; 'ONENOTE'='OneNote'; 'OUTLOOK'='Outlook'
    'WindowsTerminal'='Windows Terminal'; 'claude'='Claude'; 'explorer'='File Explorer'; 'Code'='VS Code'
    'ms-teams'='Teams'; 'Teams'='Teams'; 'WhatsApp'='WhatsApp'; 'Spotify'='Spotify'; 'AcroRd32'='Acrobat'
    'Acrobat'='Acrobat'; 'notepad'='Notepad'; 'AnyDesk'='AnyDesk'; 'MobaXterm'='MobaXterm'
}
$Browsers = @{ 'firefox'='Firefox'; 'chrome'='Chrome'; 'msedge'='Edge'; 'opera'='Opera'; 'brave'='Brave' }
$Dashes   = '-' + [char]0x2014 + [char]0x2013   # hyphen, em dash, en dash

function Get-FocusLabel($app, $title) {
    if ($Browsers.ContainsKey($app)) {
        $t = $title -replace ('\s[' + $Dashes + ']\s(Mozilla Firefox|Google Chrome|Microsoft.*Edge|Opera|Brave)\s*$'), ''
        $low = $t.ToLower()
        foreach ($k in $Distracting.Keys) { if ($low.Contains($k)) { return "$($Browsers[$app]): $($Distracting[$k])" } }
        # Hyphen first in the class, so it is a literal "-" and not a range
        $site = (($t -split ('\s[' + $Dashes + '|]\s'))[-1]).Trim()
        if (-not $site) { $site = 'other' }
        if ($site.Length -gt 40) { $site = $site.Substring(0, 40) + '...' }
        return "$($Browsers[$app]): $site"
    }
    if ($Friendly.ContainsKey($app)) { return $Friendly[$app] }
    return $app
}

# ---------- Categories: work / neutral / distracting ----------
# Your own choices (made in the app under "Sites & apps") are kept in categories.json
# and win over the keyword list above.
$CategoryFile   = Join-Path $FocusDir 'categories.json'
$DefaultNeutral = @('Spotify', 'LockApp', 'SearchHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'Unknown')

function Import-FocusCategories {
    $m = @{}
    if (Test-Path $CategoryFile) {
        try {
            $j = Get-Content $CategoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { if (@('work', 'neutral', 'distract') -contains $p.Value) { $m[$p.Name] = [string]$p.Value } }
        } catch {}
    }
    return $m
}
$FocusCatMap = Import-FocusCategories

function Save-FocusCategories($map) {
    $o = [ordered]@{}
    foreach ($k in ($map.Keys | Sort-Object)) { $o[$k] = $map[$k] }
    [pscustomobject]$o | ConvertTo-Json | Set-Content $CategoryFile -Encoding UTF8
}

# 'work', 'neutral' or 'distract'. -Default ignores your own choices.
function Get-FocusCategory($label, $title, [switch]$Default) {
    if (-not $Default -and $FocusCatMap.ContainsKey($label)) { return $FocusCatMap[$label] }
    $hay = "$label $title".ToLower()
    foreach ($k in $Distracting.Keys) { if ($hay.Contains($k)) { return 'distract' } }
    if ($DefaultNeutral -contains $label) { return 'neutral' }
    return 'work'
}

function Test-FocusDistracting($label, $title) { (Get-FocusCategory $label $title) -eq 'distract' }

# Read a file's lines while another process may be writing to it
function Read-FocusLines([string]$file) {
    if (-not (Test-Path $file)) { return @() }
    try {
        $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd(); $sr.Close()
        return ($text -split "`r?`n")
    } catch { return @() }
}

# Append a line, retrying briefly if a reader has the file open
function Add-FocusLine([string]$file, [string]$line) {
    for ($i = 0; $i -lt 5; $i++) {
        try { [IO.File]::AppendAllText($file, $line, [Text.Encoding]::UTF8); return } catch { Start-Sleep -Milliseconds 150 }
    }
}

# Rows for the last N days (today included): Date, Hour, Label, Secs, Cat, Distracting
function Get-FocusRows([int]$Days) {
    $logDir = Join-Path $FocusDir 'logs'
    $cache  = @{}
    for ($i = $Days - 1; $i -ge 0; $i--) {
        $file = Join-Path $logDir ((Get-Date).AddDays(-$i).ToString('yyyy-MM-dd') + '.tsv')
        foreach ($line in (Read-FocusLines $file)) {
            $c = $line -split "`t"
            if ($c.Count -lt 4 -or $c[0].Length -lt 13) { continue }
            $key = $c[2] + "`t" + $c[3]
            if (-not $cache.ContainsKey($key)) {
                $label = Get-FocusLabel $c[2] $c[3]
                $cache[$key] = @($label, (Get-FocusCategory $label $c[3]))
            }
            [pscustomobject]@{
                Date        = $c[0].Substring(0, 10)
                Hour        = [int]$c[0].Substring(11, 2)
                Label       = $cache[$key][0]
                Secs        = [int]$c[1]
                Cat         = $cache[$key][1]
                Distracting = ($cache[$key][1] -eq 'distract')
            }
        }
    }
}

function Get-FocusWeekId([datetime]$d) {
    $cal = [Globalization.CultureInfo]::InvariantCulture.Calendar
    '{0}-W{1:00}' -f $d.Year, $cal.GetWeekOfYear($d, 'FirstFourDayWeek', 'Monday')
}

# ---------- Goals and alerts settings (settings.json) ----------
$SettingsFile = Join-Path $FocusDir 'settings.json'

function Get-FocusSettings {
    $s = [ordered]@{ GoalMinutes = 240; DailyLimitMinutes = 30; StreakAlertMinutes = 10; AlertsOn = $true
                     SessionMinutes = 25; BreakMinutes = 5; SummaryTime = '18:00'
                     BlockDuringFocus = $true; BlockOn = $false; BlockFrom = '09:00'; BlockTo = '12:00'; BlockWeekdaysOnly = $true
                     Language = 'en'; ExportFolder = '' }
    if (Test-Path $SettingsFile) {
        try {
            $f = Get-Content $SettingsFile -Raw | ConvertFrom-Json
            foreach ($k in @($s.Keys)) { if ($null -ne $f.$k) { $s[$k] = $f.$k } }
        } catch {}
    }
    return [pscustomobject]$s
}

function Save-FocusSettings($s) {
    $s | ConvertTo-Json | Set-Content $SettingsFile -Encoding UTF8
}

# Windows notification, shown under the app's own name and icon
# $launch (e.g. 'distractionlog:plan') opens the app at that place when the notification is clicked.
function Show-FocusToast([string]$title, [string]$body, [string]$launch = '') {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $t = [Security.SecurityElement]::Escape((Tr $title)); $b = [Security.SecurityElement]::Escape((Tr $body))
        $open = $(if ($launch) { " activationType='protocol' launch='" + [Security.SecurityElement]::Escape($launch) + "'" } else { '' })
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast$open><visual><binding template='ToastGeneric'><text>$t</text><text>$b</text></binding></visual></toast>")
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        try { [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('DistractionLog.App').Show($toast) }
        catch {
            $ps = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($ps).Show($toast)
        }
    } catch {}
}

function Format-FocusTime($s) {
    $m = [int][math]::Round($s / 60)
    if ($s -gt 0 -and $m -lt 1) { return '<1m' }
    if ($m -lt 60) { return "${m}m" }
    return ('{0}h {1:00}m' -f [math]::Floor($m / 60), ($m % 60))
}

function Test-TrackerOn {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*FocusLog\tracker.ps1*' }).Count -gt 0
}

# ---------- Focus sessions (timer) ----------
# Current session: focus.json. Finished sessions: sessions.tsv
# (start, end, planned minutes, seconds, completed 1/0, distracting seconds, task).
$SessionFile = Join-Path $FocusDir 'focus.json'
$SessionLog  = Join-Path $FocusDir 'sessions.tsv'
$Inv = [Globalization.CultureInfo]::InvariantCulture

function ConvertTo-FocusDate($x) {
    if ($x -is [datetime]) { return $x }
    return [datetime]::ParseExact([string]$x, 's', $Inv)
}

# Run a block while holding the session lock (app and tracker both update the session)
function Invoke-FocusLocked([scriptblock]$block) {
    if (-not $script:SessionMutex) { $script:SessionMutex = New-Object System.Threading.Mutex($false, 'Local\DistractionLogSession') }
    $got = $false
    try { $got = $script:SessionMutex.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    try { & $block } finally { if ($got) { $script:SessionMutex.ReleaseMutex() } }
}

function Get-FocusSession {
    $s = [pscustomobject]@{ State = 'idle'; Task = ''; Start = ''; End = ''; BreakEnd = ''; Minutes = 0; DistractSec = 0 }
    if (Test-Path $SessionFile) {
        try {
            $j = [IO.File]::ReadAllText($SessionFile) | ConvertFrom-Json
            foreach ($p in @($s.PSObject.Properties.Name)) { if ($null -ne $j.$p) { $s.$p = $j.$p } }
        } catch {}
    }
    return $s
}

function Save-FocusSession($s) {
    # Write to a temp file first, so readers never see half a file
    $tmp = $SessionFile + '.tmp'
    [IO.File]::WriteAllText($tmp, ($s | ConvertTo-Json), [Text.Encoding]::UTF8)
    if (Test-Path $SessionFile) { [IO.File]::Replace($tmp, $SessionFile, [NullString]::Value) } else { [IO.File]::Move($tmp, $SessionFile) }
}

function Write-FocusSessionLog($s, [datetime]$end, [bool]$done) {
    $start = ConvertTo-FocusDate $s.Start
    $secs = [int]($end - $start).TotalSeconds
    if ($secs -lt 60) { return }
    $task = ([string]$s.Task) -replace "[`t`r`n]", ' '
    $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`r`n" -f $start.ToString('s'), $end.ToString('s'), [int]$s.Minutes, $secs, [int]$done, [int]$s.DistractSec, $task
    Add-FocusLine $SessionLog $line
}

function Start-FocusSession([string]$task, [int]$minutes) {
    Invoke-FocusLocked {
        $old = Get-FocusSession
        $now = Get-Date
        if ($old.State -eq 'focus') { Write-FocusSessionLog $old $now $false }
        Save-FocusSession ([pscustomobject]@{ State = 'focus'; Task = $task.Trim(); Start = $now.ToString('s'); End = $now.AddMinutes($minutes).ToString('s')
                                              BreakEnd = ''; Minutes = $minutes; DistractSec = 0 })
    }
}

function Stop-FocusSession {
    Invoke-FocusLocked {
        $s = Get-FocusSession
        if ($s.State -eq 'focus') {
            $now = Get-Date; $end = ConvertTo-FocusDate $s.End
            if ($now -ge $end) { Write-FocusSessionLog $s $end $true } else { Write-FocusSessionLog $s $now $false }
        }
        Save-FocusSession ([pscustomobject]@{ State = 'idle'; Task = $s.Task; Start = ''; End = ''; BreakEnd = ''; Minutes = 0; DistractSec = 0 })
    }
}

# Moves the session along (focus -> break -> idle), logs finished sessions and
# sends the notifications. Safe to call often; returns the current session.
function Update-FocusSession {
    Invoke-FocusLocked {
        $s = Get-FocusSession
        $now = Get-Date
        if ($s.State -eq 'focus') {
            $end = ConvertTo-FocusDate $s.End
            if ($now -ge $end) {
                Write-FocusSessionLog $s $end $true
                $late = ($now - $end).TotalMinutes -gt 10      # nobody was around to see it end
                $brk = [int](Get-FocusSettings).BreakMinutes
                if ($brk -gt 0 -and -not $late) { $s.State = 'break'; $s.BreakEnd = $end.AddMinutes($brk).ToString('s') }
                else { $s.State = 'idle' }
                Save-FocusSession $s
                if (-not $late) {
                    $what = $(if ($s.Task) { "$($s.Minutes) minutes on '$($s.Task)' done." } else { "$($s.Minutes) minutes of focus done." })
                    $next = $(if ($brk -gt 0) { " Take a $brk-minute break: stand up, look away from the screen." } else { '' })
                    Show-FocusToast 'Focus session complete' ((Tr $what) + ' ' + (Tr $next.Trim())).Trim() 'distractionlog:today' | Out-Null
                }
            }
        } elseif ($s.State -eq 'break') {
            $be = ConvertTo-FocusDate $s.BreakEnd
            if ($now -ge $be) {
                $s.State = 'idle'; Save-FocusSession $s
                if (($now - $be).TotalMinutes -le 10) { Show-FocusToast "Break's over" 'Ready for another focus session? Click to start one.' 'distractionlog:focus' | Out-Null }
            }
        }
        $s
    }
}

function Add-FocusSessionDistract([double]$secs) {
    Invoke-FocusLocked {
        $s = Get-FocusSession
        if ($s.State -eq 'focus') { $s.DistractSec = [int]$s.DistractSec + [int][math]::Round($secs); Save-FocusSession $s }
    }
}

# Finished sessions in the last N days: Date, Start, Planned, Secs, Done, DistractSec, Task
function Get-FocusSessions([int]$Days) {
    $from = (Get-Date).Date.AddDays(1 - $Days).ToString('yyyy-MM-dd')
    foreach ($line in (Read-FocusLines $SessionLog)) {
        $c = $line -split "`t"
        if ($c.Count -lt 7 -or $c[0].Length -lt 19) { continue }
        $d = $c[0].Substring(0, 10)
        if ([string]::CompareOrdinal($d, $from) -lt 0) { continue }
        [pscustomobject]@{ Date = $d; Start = $c[0]; Planned = [int]$c[2]; Secs = [int]$c[3]; Done = ($c[4] -eq '1')
                           DistractSec = [int]$c[5]; Task = $c[6].Trim() }
    }
}

# ---------- Plans: daily top 3 and weekly goals (plans.json) ----------
# Keys: 'yyyy-MM-dd' for a day, 'yyyy-Www' for a week.
$PlanFile = Join-Path $FocusDir 'plans.json'

function Get-FocusPlan([string]$key) {
    $p = [pscustomobject]@{ Items = @('', '', ''); Done = @($false, $false, $false) }
    if (Test-Path $PlanFile) {
        try {
            $e = (Get-Content $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json).$key
            if ($e) { for ($i = 0; $i -lt 3; $i++) { $p.Items[$i] = [string]@($e.Items)[$i]; $p.Done[$i] = [bool]@($e.Done)[$i] } }
        } catch {}
    }
    return $p
}

function Test-FocusPlan($p) { @($p.Items | Where-Object { $_ -and $_.Trim() }).Count -gt 0 }

function Set-FocusPlan([string]$key, $items, $done) {
    $all = [ordered]@{}
    if (Test-Path $PlanFile) {
        try { foreach ($pp in (Get-Content $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { $all[$pp.Name] = $pp.Value } } catch {}
    }
    $all[$key] = [pscustomobject]@{ Items = @($items | ForEach-Object { ([string]$_).Trim() }); Done = @($done | ForEach-Object { [bool]$_ }) }
    [pscustomobject]$all | ConvertTo-Json -Depth 5 | Set-Content $PlanFile -Encoding UTF8
}

# ---------- Language: English (built in) or Portuguese (pt.json) ----------
# pt.json maps English text to Portuguese. Keys may contain placeholders:
# {0} = any text, {0#} = a number or time (digits . , : %). The captured parts are
# translated too when they are known phrases (like "today").
$LangFile = Join-Path $FocusDir 'pt.json'

function Set-FocusLanguage([string]$code) {
    $script:LangCode = $(if ($code -eq 'pt') { 'pt' } else { 'en' })
    $script:LangExact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $script:LangPatterns = New-Object System.Collections.Generic.List[object]
    $script:LangCache = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    if ($script:LangCode -ne 'pt' -or -not (Test-Path $LangFile)) { return }
    # .NET's JSON reader keeps keys case-sensitive ("Today" and "today" are different texts)
    try {
        Add-Type -AssemblyName System.Web.Extensions
        $j = (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject([IO.File]::ReadAllText($LangFile, [Text.Encoding]::UTF8))
    } catch { return }
    $pats = @()
    foreach ($k in $j.Keys) {
        if ($k.StartsWith('_')) { continue }
        if ($k -match '\{\d#?\}') {
            $rx = [regex]::Escape($k)
            $rx = $rx -replace '\\\{(\d)\\#\}', '(?<g$1>[\d.,:%]+)' -replace '\\\{(\d)\}', '(?<g$1>.+?)'
            $pats += , @($k.Length, (New-Object regex ('^' + $rx + '$'), 'Singleline'), [string]$j[$k])
        } else { $script:LangExact[$k] = [string]$j[$k] }
    }
    # Longer (more specific) templates first
    foreach ($p in ($pats | Sort-Object { $_[0] } -Descending)) { $script:LangPatterns.Add(@($p[1], $p[2])) }
}

# Translate a text into the current language (returns it unchanged in English or when unknown)
function Tr([string]$s, [int]$depth = 0) {
    if ($script:LangCode -ne 'pt' -or -not $s) { return $s }
    $hit = $null
    if ($depth -eq 0 -and $script:LangCache.TryGetValue($s, [ref]$hit)) { return $hit }
    $core = $s.Trim()
    $out = $null
    if ($core) {
        if ($script:LangExact.ContainsKey($core)) { $out = $script:LangExact[$core] }
        elseif ($depth -lt 2) {
            foreach ($p in $script:LangPatterns) {
                $m = $p[0].Match($core)
                if (-not $m.Success) { continue }
                $out = $p[1]
                for ($i = 0; $i -le 5; $i++) {
                    $g = $m.Groups["g$i"]
                    if ($g.Success) { $out = $out.Replace('{' + $i + '}', (Tr $g.Value ($depth + 1))) }
                }
                break
            }
        }
    }
    $res = $s
    if ($null -ne $out) {
        $lead = $s.Substring(0, $s.Length - $s.TrimStart().Length)
        $trail = $s.Substring($s.TrimEnd().Length)
        $res = $lead + $out + $trail
    }
    if ($depth -eq 0) { if ($script:LangCache.Count -gt 5000) { $script:LangCache.Clear() }; $script:LangCache[$s] = $res }
    return $res
}

Set-FocusLanguage (Get-FocusSettings).Language
