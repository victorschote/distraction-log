# Sets up Distraction Log for the current Windows user. No admin rights needed.
#
#   powershell -ExecutionPolicy Bypass -File setup.ps1             install
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Desktop    also add desktop shortcuts
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Uninstall  remove (your data is kept)
#
# What it does: a scheduled task that starts the tracker when you log in, Start menu
# shortcuts (app + on/off), and the distractionlog: link used by notification clicks.
# The optional site blocker is separate: run install-blocker.ps1 as admin, or use
# Settings > Set up site blocking in the app.
# Keep this file ASCII-only.
param([switch]$Desktop, [switch]$Uninstall)

$dir      = $PSScriptRoot
$task     = 'Distraction Log'
$appId    = 'DistractionLog.App'
$startDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Distraction Log'
$deskDir  = [Environment]::GetFolderPath('Desktop')
$proto    = 'HKCU:\Software\Classes\distractionlog'

function Stop-FocusProcesses {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*\tracker.ps1*' -or $_.CommandLine -like '*\app.ps1*' } |
        Where-Object { $_.CommandLine -like "*$dir*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

if ($Uninstall) {
    Stop-FocusProcesses
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $startDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $deskDir 'Distraction Log.lnk'), (Join-Path $deskDir 'Distraction Log - On-Off.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item $proto -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Distraction Log was removed. Your data in this folder was kept.'
    Write-Host 'If you set up the site blocker, remove it as admin: install-blocker.ps1 -Uninstall'
    return
}

# Shortcut identity, so the taskbar, Start menu and notifications show the app's own name and icon
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
[ComImport, Guid("00021401-0000-0000-C000-000000000046")] class FlShellLink { }
[StructLayout(LayoutKind.Sequential, Pack = 4)] public struct FlPropKey { public Guid fmtid; public uint pid; }
[StructLayout(LayoutKind.Explicit, Size = 24)] public struct FlPropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr ptr; }
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IFlPropertyStore {
    [PreserveSig] int GetCount(out uint c);
    [PreserveSig] int GetAt(uint i, out FlPropKey k);
    [PreserveSig] int GetValue(ref FlPropKey k, out FlPropVariant v);
    [PreserveSig] int SetValue(ref FlPropKey k, ref FlPropVariant v);
    [PreserveSig] int Commit();
}
public static class FlLinkAumid {
    public static void Set(string lnk, string id) {
        var link = (IPersistFile)new FlShellLink();
        link.Load(lnk, 2);
        var store = (IFlPropertyStore)link;
        var key = new FlPropKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
        var v = new FlPropVariant { vt = 31, ptr = Marshal.StringToCoTaskMemUni(id) };
        try {
            Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref v));
            Marshal.ThrowExceptionForHR(store.Commit());
            link.Save(lnk, true);
        } finally { Marshal.FreeCoTaskMem(v.ptr); }
    }
}
"@

function New-Shortcut([string]$path, [string]$target, [string]$arguments, [string]$desc, [switch]$AppId) {
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($path)
    $l.TargetPath = $target; $l.Arguments = $arguments; $l.WorkingDirectory = $dir
    $l.IconLocation = (Join-Path $dir 'app.ico') + ',0'; $l.Description = $desc
    $l.Save()
    if ($AppId) { [FlLinkAumid]::Set($path, $appId) }
}

# 1. Icon
if (-not (Test-Path (Join-Path $dir 'app.ico'))) { & (Join-Path $dir 'make-icon.ps1') }

# 2. Tracker: starts at every login, hidden
$action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + (Join-Path $dir 'run-hidden.vbs') + '"')
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Force `
    -Description 'Distraction Log: records which app or site is in front, for your focus statistics. Data stays on this computer.' | Out-Null

# 3. Shortcuts
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$ps      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$openArg = '"' + (Join-Path $dir 'open-app.vbs') + '"'
$toggleArg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $dir 'toggle.ps1') + '"'
New-Item -ItemType Directory -Force $startDir | Out-Null
New-Shortcut (Join-Path $startDir 'Distraction Log.lnk') $wscript $openArg 'Distraction Log: your focus dashboard' -AppId
New-Shortcut (Join-Path $startDir 'Distraction Log On-Off.lnk') $ps $toggleArg 'Turn Distraction Log tracking on or off'
if ($Desktop) {
    New-Shortcut (Join-Path $deskDir 'Distraction Log.lnk') $wscript $openArg 'Distraction Log: your focus dashboard' -AppId
    New-Shortcut (Join-Path $deskDir 'Distraction Log - On-Off.lnk') $ps $toggleArg 'Turn Distraction Log tracking on or off'
}

# 4. distractionlog: links (clicking a notification opens the right screen)
New-Item -Path "$proto\shell\open\command" -Force | Out-Null
New-Item -Path "$proto\DefaultIcon" -Force | Out-Null
Set-ItemProperty $proto '(default)' 'URL:Distraction Log'
Set-ItemProperty $proto 'URL Protocol' ''
Set-ItemProperty "$proto\DefaultIcon" '(default)' (Join-Path $dir 'app.ico')
Set-ItemProperty "$proto\shell\open\command" '(default)' ('"' + $wscript + '" "' + (Join-Path $dir 'open-app.vbs') + '" "%1"')

# 5. Start tracking now
Stop-FocusProcesses
Enable-ScheduledTask -TaskName $task | Out-Null
Start-ScheduledTask -TaskName $task

Write-Host 'Distraction Log is set up.'
Write-Host '  - Tracking is on and starts automatically when you log in.'
Write-Host '  - Open it from the Start menu: Distraction Log (right-click > Pin to Start).'
Write-Host '  - Optional site blocking: in the app, Settings > Set up site blocking.'
