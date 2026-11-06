# One-time setup for the site blocker (needs admin). Run again after editing blocker.ps1.
#   -Uninstall  removes the task, the installed copy and any block in the hosts file
param([switch]$Uninstall)

$src  = $PSScriptRoot
$dest = Join-Path $env:ProgramData 'DistractionLog'
$task = 'Distraction Log Blocker'
$log  = Join-Path $src 'install-blocker.log'

function Say($m) { Add-Content $log ("{0}  {1}" -f (Get-Date -Format s), $m) }

try {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
        Say 'ERROR: needs to run as administrator'; exit 1
    }
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*DistractionLog\blocker.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

    # Always clear our block from the hosts file (the new copy re-adds it if needed)
    $hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $text = [IO.File]::ReadAllText($hosts)
    if ($text.Contains('# BEGIN Distraction Log block')) {
        $text = [regex]::Replace($text, '(?s)\r?\n?# BEGIN Distraction Log block.*?# END Distraction Log block\r?\n?', "`r`n").TrimEnd() + "`r`n"
        [IO.File]::WriteAllText($hosts, $text, [Text.Encoding]::ASCII)
        Clear-DnsClientCache
    }

    if ($Uninstall) {
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Say 'Uninstalled'; exit 0
    }

    # Folder only SYSTEM and Administrators can change (the task runs as SYSTEM)
    New-Item -ItemType Directory -Force $dest | Out-Null
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $admins = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $acl.SetOwner($admins)
    foreach ($r in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $sid = New-Object Security.Principal.SecurityIdentifier $r[0]
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule $sid, $r[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl $dest $acl
    Copy-Item (Join-Path $src 'blocker.ps1') (Join-Path $dest 'blocker.ps1') -Force

    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -DataDir "{1}"' -f (Join-Path $dest 'blocker.ps1'), $src
    $action = New-ScheduledTaskAction -Execute $ps -Argument $arg
    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5))   # restarts it if it ever stops
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $task -Action $action -Trigger $triggers -Principal $principal -Settings $settings `
        -Description 'Distraction Log: blocks distracting sites during focus sessions / scheduled hours (edits the hosts file).' | Out-Null
    Start-ScheduledTask -TaskName $task
    Say 'Installed and started'
} catch {
    Say "ERROR: $_"
    exit 1
}
