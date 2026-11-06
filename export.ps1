# Export: saves Distraction Log data as CSV files (open in Excel or Google Sheets).
# Dot-sourced by app.ps1 ("Export" button). Keep this file ASCII-only.
# Each export goes into its own folder; export-history.tsv keeps a list of past exports.

$ExportHistory = Join-Path $FocusDir 'export-history.tsv'

function Get-ExportFolder {
    $f = [string](Get-FocusSettings).ExportFolder
    if (-not $f) { $f = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Distraction Log exports' }
    return $f
}

# Excel reads CSV with the Windows list separator and decimal mark (in Brazil: ; and ,)
function Get-CsvFormat {
    $sep = ';'; $dec = ','
    try {
        $i = Get-ItemProperty 'HKCU:\Control Panel\International'
        if ($i.sList) { $sep = [string]$i.sList }
        if ($i.sDecimal) { $dec = [string]$i.sDecimal }
    } catch {}
    if ($sep -eq $dec) { $sep = ';' }
    return @($sep, $dec)
}

function ConvertTo-CsvLine($fields, [string]$sep) {
    $special = [char[]]($sep + '"' + "`r`n")
    $out = foreach ($f in $fields) {
        $v = [string]$f
        if ($v -match '^[=+@\-]' -and $v -notmatch '^-?[\d.,]+$') { $v = "'" + $v }   # keep Excel from running text as a formula
        if ($v.IndexOfAny($special) -ge 0) { '"' + $v.Replace('"', '""') + '"' } else { $v }
    }
    return ($out -join $sep)
}

function Format-Min([double]$secs, [string]$dec) { ([math]::Round($secs / 60, 1)).ToString('0.0', $Inv).Replace('.', $dec) }

function Write-Csv([string]$path, $header, $rows, [string]$sep) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((ConvertTo-CsvLine @($header | ForEach-Object { Tr $_ }) $sep))
    foreach ($r in $rows) { $lines.Add((ConvertTo-CsvLine $r $sep)) }
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding $true))   # with BOM, so Excel reads accents right
    return ($lines.Count - 1)
}

function Get-ExportDates([int]$days) {
    if ($days -gt 0) { return @(for ($i = $days - 1; $i -ge 0; $i--) { (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd') }) }
    $d = @(Get-ChildItem (Join-Path $FocusDir 'logs') -Filter '*.tsv' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName } |
           Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' })
    $d += @(Get-FocusSessions 36500 | ForEach-Object { $_.Date })
    return @($d | Sort-Object -Unique)
}

function Get-CatName($cat) { switch ($cat) { 'distract' { Tr 'Distracting' } 'neutral' { Tr 'Neutral' } default { Tr 'Work' } } }

# Exports the chosen data. $what: hashtable with Activity, Daily, Sessions, Plans = $true/$false.
# Returns: folder path, number of files, number of rows.
function Export-FocusData([int]$days, [string]$folder, $what, [bool]$titles) {
    $sep, $dec = Get-CsvFormat
    $dates = Get-ExportDates $days
    $pt = $LangCode -eq 'pt'
    $base = Join-Path $folder ('Distraction Log ' + (Get-Date).ToString('yyyy-MM-dd HHmm'))
    $dir = $base; $k = 2
    while (Test-Path $dir) { $dir = "$base ($k)"; $k++ }
    New-Item -ItemType Directory -Force $dir | Out-Null
    $set = Get-FocusSettings
    $goal = 60 * [double]$set.GoalMinutes
    $allSess = @(Get-FocusSessions 36500)
    $files = 0; $rowsOut = 0
    $yes = Tr 'Yes'; $no = Tr 'No'

    # 1. Activity log: every logged piece of time
    $act = New-Object System.Collections.Generic.List[object]
    $perDay = @{}
    foreach ($date in $dates) {
        $f = 0.0; $x = 0.0; $n = 0.0; $bad = @{}
        foreach ($line in (Read-FocusLines (Join-Path $FocusDir "logs\$date.tsv"))) {
            $c = $line -split "`t"
            if ($c.Count -lt 4 -or $c[0].Length -lt 19) { continue }
            $label = Get-FocusLabel $c[2] $c[3]
            $cat = Get-FocusCategory $label $c[3]
            $secs = [int]$c[1]
            switch ($cat) { 'distract' { $x += $secs; $bad[$label] = [double]$bad[$label] + $secs } 'neutral' { $n += $secs } default { $f += $secs } }
            if ($what.Activity) {
                $st = [datetime]::ParseExact($c[0], 's', $Inv)
                $row = @($date, $st.ToString('HH:mm:ss'), $st.AddSeconds($secs).ToString('HH:mm:ss'), (Format-Min $secs $dec), $c[2])
                if ($titles) { $row += $c[3] }
                $row += @($label, (Get-CatName $cat))
                $act.Add($row)
            }
        }
        $perDay[$date] = @($f, $x, $n, $bad)
    }
    if ($what.Activity) {
        $h = @('Date', 'Start', 'End', 'Minutes', 'App'); if ($titles) { $h += 'Window title' }; $h += @('App or site', 'Category')
        $rowsOut += Write-Csv (Join-Path $dir $(if ($pt) { 'atividade.csv' } else { 'activity.csv' })) $h $act $sep; $files++
    }

    # 2. Daily summary: one row per day
    if ($what.Daily) {
        $rows = @(foreach ($date in $dates) {
            $f, $x, $n, $bad = $perDay[$date]
            $active = $f + $x
            $top = $bad.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
            $done = @($allSess | Where-Object { $_.Date -eq $date -and $_.Done }).Count
            $d = [datetime]::ParseExact($date, 'yyyy-MM-dd', $Inv)
            , @($date, $d.ToString('dddd'), (Format-Min $f $dec), (Format-Min $x $dec), (Format-Min $n $dec), (Format-Min $active $dec),
                $(if ($active) { [string][int][math]::Round(100 * $f / $active) } else { '' }),
                [string][int]$set.GoalMinutes, $(if ($goal -gt 0) { if ($f -ge $goal) { $yes } else { $no } } else { '' }),
                [string]$done, $(if ($top) { $top.Key } else { '' }), $(if ($top) { Format-Min $top.Value $dec } else { '' }))
        })
        $rowsOut += Write-Csv (Join-Path $dir $(if ($pt) { 'resumo-diario.csv' } else { 'daily-summary.csv' })) @('Date', 'Weekday', 'Focused (min)', 'Distracting (min)', 'Neutral (min)',
            'Active (min)', 'Focus %', 'Goal (min)', 'Goal met', 'Sessions completed', 'Top distraction', 'Top distraction (min)') $rows $sep
        $files++
    }

    # 3. Focus sessions
    if ($what.Sessions) {
        $inRange = @{}; foreach ($d in $dates) { $inRange[$d] = $true }
        $rows = @(foreach ($s in ($allSess | Where-Object { $inRange.ContainsKey($_.Date) })) {
            $st = [datetime]::ParseExact($s.Start, 's', $Inv)
            , @($s.Date, $st.ToString('HH:mm'), $st.AddSeconds($s.Secs).ToString('HH:mm'), [string]$s.Planned, (Format-Min $s.Secs $dec),
                $(if ($s.Done) { $yes } else { $no }), (Format-Min $s.DistractSec $dec), $s.Task)
        })
        $rowsOut += Write-Csv (Join-Path $dir $(if ($pt) { 'sessoes.csv' } else { 'sessions.csv' })) @('Date', 'Start', 'End', 'Planned (min)', 'Actual (min)',
            'Completed', 'Distracted (min)', 'Task') $rows $sep
        $files++
    }

    # 4. Plans: daily top 3 and weekly goals
    if ($what.Plans) {
        $keys = @{}
        foreach ($d in $dates) { $keys[$d] = 'Day'; $keys[(Get-FocusWeekId ([datetime]::ParseExact($d, 'yyyy-MM-dd', $Inv)))] = 'Week' }
        if ($days -le 0 -and (Test-Path $PlanFile)) {
            try { foreach ($p in (Get-Content $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { if (-not $keys.ContainsKey($p.Name)) { $keys[$p.Name] = $(if ($p.Name -like '*-W*') { 'Week' } else { 'Day' }) } } } catch {}
        }
        $rows = @(foreach ($k in ($keys.Keys | Sort-Object)) {
            $p = Get-FocusPlan $k
            for ($i = 0; $i -lt 3; $i++) {
                if ($p.Items[$i]) { , @((Tr $keys[$k]), $k, [string]($i + 1), $p.Items[$i], $(if ($p.Done[$i]) { $yes } else { $no })) }
            }
        })
        $rowsOut += Write-Csv (Join-Path $dir $(if ($pt) { 'planos.csv' } else { 'plans.csv' })) @('Type', 'Period', '#', 'Item', 'Done') $rows $sep
        $files++
    }

    Add-FocusLine $ExportHistory ("{0}`t{1}`t{2}`t{3}`t{4}`r`n" -f (Get-Date).ToString('s'), $days, $files, $rowsOut, $dir)
    return @($dir, $files, $rowsOut)
}

function Get-PeriodName([int]$days) {
    switch ($days) { 1 { Tr 'Today' } 7 { Tr 'Last 7 days' } 30 { Tr 'Last 30 days' } default { Tr 'All data' } }
}

# ---------- Export dialog ----------
function New-ExportDialog {
    $ex = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Export data" Width="560" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="##page##" Foreground="##ink##" FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
##styles##
  </Window.Resources>
  <StackPanel Margin="22,18,22,20">
    <TextBlock Text="Export data" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock Text="Saves your data as CSV files that open in Excel or Google Sheets." Style="{StaticResource Sub}" TextWrapping="Wrap" TextTrimming="None" Margin="0,4,0,16"/>

    <TextBlock Text="Period" FontWeight="SemiBold" Margin="0,0,0,6"/>
    <Border Background="##wash##" CornerRadius="8" Padding="3" HorizontalAlignment="Left" Margin="0,0,0,16">
      <StackPanel Orientation="Horizontal">
        <RadioButton x:Name="X1" Style="{StaticResource Seg}" GroupName="xp" Content="Today"/>
        <RadioButton x:Name="X7" Style="{StaticResource Seg}" GroupName="xp" Content="7 days"/>
        <RadioButton x:Name="X30" Style="{StaticResource Seg}" GroupName="xp" Content="30 days" IsChecked="True"/>
        <RadioButton x:Name="X0" Style="{StaticResource Seg}" GroupName="xp" Content="All data"/>
      </StackPanel>
    </Border>

    <TextBlock Text="What to include" FontWeight="SemiBold" Margin="0,0,0,6"/>
    <CheckBox x:Name="XAct" Content="Activity log - every app and site, with time and category" Foreground="##ink##" IsChecked="True" Margin="0,2,0,6"/>
    <CheckBox x:Name="XTitles" Content="Include window titles (may contain private information)" Foreground="##ink2##" IsChecked="True" Margin="22,0,0,8"/>
    <CheckBox x:Name="XDay" Content="Daily summary - one row per day" Foreground="##ink##" IsChecked="True" Margin="0,0,0,6"/>
    <CheckBox x:Name="XSes" Content="Focus sessions" Foreground="##ink##" IsChecked="True" Margin="0,0,0,6"/>
    <CheckBox x:Name="XPlan" Content="Daily top 3 and weekly goals" Foreground="##ink##" IsChecked="True" Margin="0,0,0,16"/>

    <TextBlock Text="Save to" FontWeight="SemiBold" Margin="0,0,0,6"/>
    <DockPanel Margin="0,0,0,8">
      <Button x:Name="XBrowse" DockPanel.Dock="Right" Style="{StaticResource Btn}" Content="Change..." Margin="8,0,0,0"/>
      <Border BorderBrush="##axis##" BorderThickness="1" Padding="8,5">
        <TextBlock x:Name="XFolder" Tag="raw" TextTrimming="CharacterEllipsis" Foreground="##ink2##" FontSize="13"/>
      </Border>
    </DockPanel>
    <TextBlock x:Name="XMsg" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,4,0,0"/>

    <TextBlock Text="Recent exports" FontWeight="SemiBold" Margin="0,14,0,6"/>
    <StackPanel x:Name="XHist"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="XClose" Style="{StaticResource Btn}" Content="Close" MinWidth="90" IsCancel="True"/>
      <Button x:Name="XGo" Style="{StaticResource Btn}" Content="Export" MinWidth="110" Margin="8,0,0,0" IsDefault="True"
              Background="##focus##" Foreground="White" BorderBrush="##focus##"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Expand-Xaml $ex))
    if ($win.Icon) { $dlg.Icon = $win.Icon }
    $dlg.Add_SourceInitialized({ Set-DarkTitle ([System.Windows.Window]$this) })
    $dlg.FindName('XFolder').Text = Get-ExportFolder
    $dlg.FindName('XAct').Add_Click({ $d = [System.Windows.Window]::GetWindow($this); $d.FindName('XTitles').IsEnabled = [bool]$this.IsChecked })
    Update-ExportHistory $dlg

    $dlg.FindName('XBrowse').Add_Click({
        $d = [System.Windows.Window]::GetWindow($this)
        Add-Type -AssemblyName System.Windows.Forms
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.SelectedPath = $d.FindName('XFolder').Text
        if ($fb.ShowDialog() -eq 'OK') {
            $d.FindName('XFolder').Text = $fb.SelectedPath
            $s = Get-FocusSettings; $s.ExportFolder = $fb.SelectedPath; Save-FocusSettings $s
        }
    })

    $dlg.FindName('XGo').Add_Click({
        $d = [System.Windows.Window]::GetWindow($this)
        $msg = $d.FindName('XMsg')
        $what = @{ Activity = [bool]$d.FindName('XAct').IsChecked; Daily = [bool]$d.FindName('XDay').IsChecked
                   Sessions = [bool]$d.FindName('XSes').IsChecked; Plans = [bool]$d.FindName('XPlan').IsChecked }
        if (-not ($what.Values -contains $true)) { $msg.Text = Tr 'Choose at least one thing to export.'; return }
        $days = 30
        foreach ($p in @(@('X1', 1), @('X7', 7), @('X30', 30), @('X0', 0))) { if ($d.FindName($p[0]).IsChecked) { $days = $p[1] } }
        $this.IsEnabled = $false
        try {
            $r = Export-FocusData $days $d.FindName('XFolder').Text $what ([bool]$d.FindName('XTitles').IsChecked)
            $t = $(if ($r[1] -eq 1) { 'Saved {0} file to {1}' } else { 'Saved {0} files to {1}' }) -f $r[1], $r[0]
            $msg.Text = Tr $t
            if ($r[2] -eq 0) { $msg.Text += ' ' + (Tr 'Nothing was recorded in this period, so the files only have headers.') }
            Start-Process explorer.exe -ArgumentList ('"' + $r[0] + '"')
        } catch { $msg.Text = Tr ('Could not export: {0}' -f $_) }
        $this.IsEnabled = $true
        Update-ExportHistory $d
    })
    return $dlg
}

function Update-ExportHistory($d) {
    $panel = $d.FindName('XHist')
    $panel.Children.Clear()
    $rows = @(Read-FocusLines $ExportHistory | Where-Object { $_ } | Select-Object -Last 5)
    if (-not $rows) { Add-Empty $panel 'No exports yet.' }
    [array]::Reverse($rows)
    foreach ($line in $rows) {
        $c = $line -split "`t"
        if ($c.Count -lt 5) { continue }
        $when = ([datetime]::ParseExact($c[0], 's', $Inv)).ToString('g')
        $files = [int]$c[2]
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $(if ($files -eq 1) { '{0} - {1} - {2} file' } else { '{0} - {1} - {2} files' }) -f $when, (Get-PeriodName ([int]$c[1])), $files
        $tb.FontSize = 13; $tb.Foreground = $Br.ink2; $tb.Margin = '0,0,0,6'; $tb.Cursor = 'Hand'
        $tb.ToolTip = $c[4]; $tb.Tag = $c[4]
        $tb.Add_MouseEnter({ $this.TextDecorations = [System.Windows.TextDecorations]::Underline })
        $tb.Add_MouseLeave({ $this.TextDecorations = $null })
        $tb.Add_MouseLeftButtonUp({ if (Test-Path $this.Tag) { Start-Process explorer.exe -ArgumentList ('"' + $this.Tag + '"') } })
        [void]$panel.Children.Add($tb)
    }
    Translate-Tree $panel
}
