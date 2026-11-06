# Distraction Log site blocker. Runs as SYSTEM (it edits the hosts file), so the
# installed copy lives in C:\ProgramData\DistractionLog where only admins can change it.
# It only READS the user's settings.json / focus.json as data and only ever writes the
# fixed domain list below. Re-run install-blocker.ps1 after editing this file.
# Keep this file ASCII-only.
#   -DataDir  the Distraction Log folder (install-blocker.ps1 passes it)
param([string]$DataDir = '')
if (-not $DataDir -or -not (Test-Path $DataDir)) { exit 1 }

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\DistractionLogBlocker', [ref]$created)
if (-not $created) { exit }

# Sites to block. WhatsApp is left out on purpose (often needed for work);
# add 'web.whatsapp.com' if you want it blocked too.
$Domains = @(
    'youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'
    'instagram.com', 'www.instagram.com'
    'facebook.com', 'www.facebook.com', 'm.facebook.com'
    'tiktok.com', 'www.tiktok.com'
    'twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'
    'netflix.com', 'www.netflix.com'
    'reddit.com', 'www.reddit.com', 'old.reddit.com'
    'twitch.tv', 'www.twitch.tv'
    'primevideo.com', 'www.primevideo.com'
    'globoplay.globo.com'
    'disneyplus.com', 'www.disneyplus.com'
    '9gag.com', 'www.9gag.com'
    'pinterest.com', 'www.pinterest.com', 'br.pinterest.com'
)

$hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$begin = '# BEGIN Distraction Log block'
$end   = '# END Distraction Log block'
$inv   = [Globalization.CultureInfo]::InvariantCulture

function Read-Json($file) {
    try { if (Test-Path $file) { return [IO.File]::ReadAllText($file) | ConvertFrom-Json } } catch {}
    return $null
}

function Get-Minutes($text, $fallback) {
    if ([string]$text -match '^(\d{1,2}):(\d{2})$') { return 60 * [int]$matches[1] + [int]$matches[2] }
    return $fallback
}

function Test-ShouldBlock {
    $now = Get-Date
    $s = Read-Json (Join-Path $DataDir 'settings.json')
    $f = Read-Json (Join-Path $DataDir 'focus.json')

    $duringFocus = $true
    if ($s -and $null -ne $s.BlockDuringFocus) { $duringFocus = [bool]$s.BlockDuringFocus }
    if ($duringFocus -and $f -and $f.State -eq 'focus') {
        try { if ($now -lt [datetime]::ParseExact([string]$f.End, 's', $inv)) { return $true } } catch {}
    }

    if ($s -and [bool]$s.BlockOn) {
        $weekdays = $true
        if ($null -ne $s.BlockWeekdaysOnly) { $weekdays = [bool]$s.BlockWeekdaysOnly }
        if ($weekdays -and ($now.DayOfWeek -eq 'Saturday' -or $now.DayOfWeek -eq 'Sunday')) { return $false }
        $from = Get-Minutes $s.BlockFrom 540; $to = Get-Minutes $s.BlockTo 720
        $m = 60 * $now.Hour + $now.Minute
        if ($from -le $to) { return ($m -ge $from -and $m -lt $to) }
        return ($m -ge $from -or $m -lt $to)   # e.g. 22:00 - 02:00
    }
    return $false
}

function Set-Block([bool]$on) {
    try { $text = [IO.File]::ReadAllText($hosts) } catch { return }
    if (-not $on -and -not $text.Contains($begin)) { return }   # nothing to remove: leave the file alone
    $pattern = '(?s)\r?\n?' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end) + '\r?\n?'
    $clean = [regex]::Replace($text, $pattern, "`r`n").TrimEnd()
    $new = $clean
    if ($on) {
        $lines = @('', $begin)
        foreach ($d in $Domains) { $lines += "0.0.0.0 $d"; $lines += ":: $d" }
        $lines += $end
        $new = $clean + ($lines -join "`r`n")
    }
    $new += "`r`n"
    if ($new -ne $text) {
        try {
            [IO.File]::WriteAllText($hosts, $new, [Text.Encoding]::ASCII)
            Clear-DnsClientCache -ErrorAction SilentlyContinue
        } catch {}
    }
}

$state = $null
while ($true) {
    $want = Test-ShouldBlock
    if ($want -ne $state) { Set-Block $want; $state = $want }
    Start-Sleep -Seconds 10
}
