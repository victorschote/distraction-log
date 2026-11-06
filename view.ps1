# Opens the report: today first, then press W for the last 7 days.

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$on  = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
         Where-Object { $_.CommandLine -like '*FocusLog\tracker.ps1*' }).Count -gt 0

$Host.UI.RawUI.WindowTitle = 'Distraction Log'
$days = 1
while ($true) {
    Clear-Host
    if ($on) { Write-Host '  Status: ON' -ForegroundColor Green } else { Write-Host '  Status: OFF (use the On-Off shortcut to start it)' -ForegroundColor Yellow }
    & (Join-Path $dir 'report.ps1') -Days $days
    if ($days -eq 1) { Write-Host '  [W] last 7 days    [any other key] close' } else { Write-Host '  [T] today    [any other key] close' }
    $k = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
    if ($k -eq 'W') { $days = 7 } elseif ($k -eq 'T') { $days = 1 } else { break }
}
