# Turns the distraction log on or off. "Off" also keeps it off after restarts.
#   -Quiet  no message box (used by the dashboard button)
param([switch]$Quiet)

$task = 'Distraction Log'

function Get-Tracker {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*FocusLog\tracker.ps1*' }
}

$running = @(Get-Tracker).Count -gt 0

if ($running) {
    Disable-ScheduledTask -TaskName $task | Out-Null
    Get-Tracker | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    $new = 'off'
    $msg = 'Distraction log is now OFF.' + "`n" + 'It will stay off until you turn it back on.'
} else {
    Enable-ScheduledTask -TaskName $task | Out-Null
    Start-ScheduledTask -TaskName $task
    $new = 'on'
    $msg = 'Distraction log is now ON.' + "`n" + 'It will also start automatically when you log in.'
}

if (-not $Quiet) {
    # Small message box that closes itself after 4 seconds
    (New-Object -ComObject WScript.Shell).Popup($msg, 4, 'Distraction Log', 64) | Out-Null
}
