# Distraction log report in the terminal.
#   .\report.ps1            -> today
#   .\report.ps1 -Days 7    -> last 7 days
# The distracting list lives in common.ps1.

param([int]$Days = 1, [int]$Top = 15)
. (Join-Path $PSScriptRoot 'common.ps1')

$rows = @(Get-FocusRows $Days)
if (-not $rows) { Write-Host 'No data yet. The tracker needs a few minutes of use first.'; return }

function Format-Time($s) { $m = [int]($s / 60); if ($m -ge 60) { '{0}h {1:00}m' -f [int][math]::Floor($m / 60), ($m % 60) } else { "${m}m" } }

$total = ($rows | Measure-Object Secs -Sum).Sum
$lost  = ($rows | Where-Object Distracting | Measure-Object Secs -Sum).Sum
if (-not $lost) { $lost = 0 }
$pct   = if ($total) { [int](100 * $lost / $total) } else { 0 }

$period = if ($Days -eq 1) { 'Today' } else { "Last $Days days" }
Write-Host ''
Write-Host "  DISTRACTION LOG - $period" -ForegroundColor Cyan
Write-Host ("  Active time: {0}   Distracting: {1} ({2}%)   Focused: {3}%" -f (Format-Time $total), (Format-Time $lost), $pct, (100 - $pct))
Write-Host ''

$grouped = $rows | Group-Object Label | ForEach-Object {
    [pscustomobject]@{ Label = $_.Name; Secs = ($_.Group | Measure-Object Secs -Sum).Sum; Distracting = $_.Group[0].Distracting }
} | Sort-Object Secs -Descending | Select-Object -First $Top

$max = ($grouped | Select-Object -First 1).Secs
foreach ($g in $grouped) {
    $bar   = '#' * [math]::Max(1, [int](30 * $g.Secs / $max))
    $color = if ($g.Distracting) { 'Red' } else { 'Green' }
    $name  = if ($g.Label.Length -gt 34) { $g.Label.Substring(0, 34) + '..' } else { $g.Label }
    Write-Host ('  {0,-36} {1,8}  ' -f $name, (Format-Time $g.Secs)) -NoNewline
    Write-Host $bar -ForegroundColor $color
}
Write-Host ''
Write-Host '  Red = on your distracting list (edit it in common.ps1)' -ForegroundColor DarkGray
Write-Host ''
