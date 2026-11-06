# Extra dashboards for the Distraction Log app: Distractions, Sessions and Patterns.
# Dot-sourced by app.ps1 (uses its helpers, brushes and data functions).
# Keep this file ASCII-only: Windows PowerShell 5.1 misreads other characters.

$ARROW = [string][char]0x2192

# ---------- Colors ----------
# Sequential ramps (one hue, from "a little" to "a lot"). Empty cells use the track color.
if ($light) {
    $SeqEnds = @{ focus = @('#cde2fb', '#104281'); distract = @('#fbd9c9', '#8f3410') }
    $AquaBr = $conv.ConvertFromString('#1baf7a')
} else {
    $SeqEnds = @{ focus = @('#173a66', '#9ec5f4'); distract = @('#4a2010', '#f4a582') }
    $AquaBr = $conv.ConvertFromString('#199e70')
}
$AquaBr.Freeze()

function Get-SeqBrush([double]$t, [string]$hue) {
    $a = [Windows.Media.ColorConverter]::ConvertFromString($SeqEnds[$hue][0])
    $b = [Windows.Media.ColorConverter]::ConvertFromString($SeqEnds[$hue][1])
    $t = [math]::Max(0.0, [math]::Min(1.0, $t))
    $c = [Windows.Media.Color]::FromRgb([byte]($a.R + ($b.R - $a.R) * $t), [byte]($a.G + ($b.G - $a.G) * $t), [byte]($a.B + ($b.B - $a.B) * $t))
    $br = New-Object Windows.Media.SolidColorBrush $c; $br.Freeze()
    return $br
}

# ---------- Chart registry: charts redraw themselves when the window is resized ----------
$script:Charts = @{}

function Plot-Stack($canvas, $cats, [int]$every, [double]$goal, $spec) {
    $script:Charts[$canvas.Name] = @{ Kind = 'stack'; Cats = $cats; Every = $every; Goal = $goal; Spec = $spec }
    Draw-Stack $canvas $cats $every $goal $spec
}

function Plot-Heat($canvas, $rows, $cols, $vals, $tips, [string]$hue, $marks = $null) {
    $script:Charts[$canvas.Name] = @{ Kind = 'heat'; Rows = $rows; Cols = $cols; Vals = $vals; Tips = $tips; Hue = $hue; Marks = $marks }
    Draw-Heat $canvas $rows $cols $vals $tips $hue $marks
}

function Redraw-Canvas($canvas) {
    $e = $script:Charts[$canvas.Name]
    if (-not $e) { return }
    if ($e.Kind -eq 'stack') { Draw-Stack $canvas $e.Cats $e.Every $e.Goal $e.Spec }
    else { Draw-Heat $canvas $e.Rows $e.Cols $e.Vals $e.Tips $e.Hue $e.Marks }
}

# Heatmap: rows x columns of rounded cells, 2px gaps, darker = more. $vals[r][c] = $null means "no cell".
function Draw-Heat($canvas, $rows, $cols, $vals, $tips, [string]$hue, $marks) {
    $canvas.Children.Clear()
    $W = [math]::Max(280, $canvas.ActualWidth); $H = $canvas.Height
    $ml = 44; $mb = 22; $legendH = 24
    $cw = ($W - $ml) / $cols.Count
    $ch = [math]::Min(30, ($H - $mb - $legendH) / $rows.Count)
    $max = 0.0
    foreach ($r in $vals) { foreach ($v in $r) { if ($null -ne $v -and $v -gt $max) { $max = [double]$v } } }

    for ($r = 0; $r -lt $rows.Count; $r++) {
        $y = $r * $ch
        Add-Text $canvas $rows[$r] 0 ($y + $ch / 2 - 8) ($ml - 10) 'Right'
        for ($c = 0; $c -lt $cols.Count; $c++) {
            $v = $vals[$r][$c]
            if ($null -eq $v) { continue }
            $rect = New-Object System.Windows.Shapes.Rectangle
            $rect.Width = [math]::Max(2, $cw - 2); $rect.Height = [math]::Max(2, $ch - 2); $rect.RadiusX = 3; $rect.RadiusY = 3
            $rect.Fill = $(if ($v -gt 0 -and $max -gt 0) { Get-SeqBrush (0.12 + 0.88 * $v / $max) $hue } else { $Br.track })
            $rect.StrokeThickness = 1.5
            [System.Windows.Controls.Canvas]::SetLeft($rect, $ml + $c * $cw); [System.Windows.Controls.Canvas]::SetTop($rect, $y)
            if ($tips) { $rect.ToolTip = $tips[$r][$c]; [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($rect, 0) }
            $rect.Add_MouseEnter({ $this.Stroke = $Br.ink })
            $rect.Add_MouseLeave({ $this.Stroke = $null })
            [void]$canvas.Children.Add($rect)
            if ($marks -and $marks[$r][$c]) {
                $dot = New-Object System.Windows.Shapes.Ellipse
                $dot.Width = 7; $dot.Height = 7; $dot.Fill = $Br.ink; $dot.Stroke = $Br.surface; $dot.StrokeThickness = 1.5; $dot.IsHitTestVisible = $false
                [System.Windows.Controls.Canvas]::SetLeft($dot, $ml + $c * $cw + ($cw - 2) / 2 - 3.5); [System.Windows.Controls.Canvas]::SetTop($dot, $y + ($ch - 2) / 2 - 3.5)
                [void]$canvas.Children.Add($dot)
            }
        }
    }
    # Column labels (skip some when cells are narrow)
    $every = [math]::Max(1, [math]::Ceiling(30 / [math]::Max(1, $cw)))
    for ($c = 0; $c -lt $cols.Count; $c++) {
        if ($cols[$c] -and ($c % $every -eq 0 -or $cols[$c] -notmatch '^\d+h$')) {
            Add-Text $canvas $cols[$c] ($ml + $c * $cw + $cw / 2 - 30) ($rows.Count * $ch + 2) 60 'Center'
        }
    }
    # Legend: Less [] [] [] [] [] More
    $ly = $rows.Count * $ch + $mb + 4
    $lx = $W - 5 * 16 - 80
    Add-Text $canvas 'Less' ($lx - 46) ($ly - 1) 40 'Right'
    for ($i = 0; $i -lt 5; $i++) {
        $s = New-Object System.Windows.Shapes.Rectangle; $s.Width = 14; $s.Height = 12; $s.RadiusX = 3; $s.RadiusY = 3
        $s.Fill = $(if ($i -eq 0) { $Br.track } else { Get-SeqBrush (0.12 + 0.88 * $i / 4) $hue })
        [System.Windows.Controls.Canvas]::SetLeft($s, $lx + $i * 16); [System.Windows.Controls.Canvas]::SetTop($s, $ly)
        [void]$canvas.Children.Add($s)
    }
    Add-Text $canvas 'More' ($lx + 5 * 16 + 4) ($ly - 1) 40 'Left'
    Translate-Tree $canvas
}

# ---------- Small building blocks ----------
function New-Tile($key, $value, $sub, $swatch = $null, $meter = $null) {
    $b = New-Object System.Windows.Controls.Border; $b.Style = $win.FindResource('Card'); $b.Margin = 6
    $sp = New-Object System.Windows.Controls.StackPanel
    $kp = New-Object System.Windows.Controls.StackPanel; $kp.Orientation = 'Horizontal'
    if ($swatch) {
        $r = New-Object System.Windows.Shapes.Rectangle; $r.Width = 10; $r.Height = 10; $r.RadiusX = 3; $r.RadiusY = 3; $r.Fill = $swatch
        $r.VerticalAlignment = 'Center'; $r.Margin = '0,0,6,0'; [void]$kp.Children.Add($r)
    }
    $k = New-Object System.Windows.Controls.TextBlock; $k.Style = $win.FindResource('Key'); $k.Text = $key; [void]$kp.Children.Add($k)
    [void]$sp.Children.Add($kp)
    $v = New-Object System.Windows.Controls.TextBlock; $v.Style = $win.FindResource('Big'); $v.Text = $value; $v.ToolTip = $value
    [void]$sp.Children.Add($v)
    if ($meter) {
        $g = New-Object System.Windows.Controls.Grid; $g.Height = 8; $g.Margin = '0,12,0,0'
        $t = New-Object System.Windows.Controls.Border; $t.CornerRadius = 4; $t.Background = $Br.track; [void]$g.Children.Add($t)
        $inner = New-Object System.Windows.Controls.Grid
        $f = [math]::Max(0.0, [math]::Min(1.0, [double]$meter[0]))
        $a = New-Object System.Windows.Controls.ColumnDefinition; $a.Width = New-Object System.Windows.GridLength $f, 'Star'
        $z = New-Object System.Windows.Controls.ColumnDefinition; $z.Width = New-Object System.Windows.GridLength (1 - $f), 'Star'
        $inner.ColumnDefinitions.Add($a); $inner.ColumnDefinitions.Add($z)
        $fill = New-Object System.Windows.Controls.Border; $fill.CornerRadius = 4; $fill.Background = $meter[1]
        [void]$inner.Children.Add($fill); [void]$g.Children.Add($inner)
        [void]$sp.Children.Add($g)
    }
    $s = New-Object System.Windows.Controls.TextBlock; $s.Style = $win.FindResource('Sub'); $s.Text = $sub; $s.Margin = '0,6,0,0'; $s.ToolTip = $sub
    [void]$sp.Children.Add($s)
    $b.Child = $sp
    return $b
}

function Add-Empty($panel, $text) {
    $e = New-Object System.Windows.Controls.TextBlock; $e.Text = $text; $e.Foreground = $Br.muted; $e.TextWrapping = 'Wrap'
    $e.FontSize = 13.5; $e.Margin = '0,6,0,6'
    [void]$panel.Children.Add($e)
}

function New-Text($text, $size = 13, $brush = $null, $weight = 'Normal') {
    $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $text; $t.FontSize = $size; $t.FontWeight = $weight
    $t.Foreground = $(if ($brush) { $brush } else { $Br.ink }); $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'
    return $t
}

# A row with a name, a bar and extra columns on the right
function New-ColRow($name, $secs, $max, $brush, $cols, [switch]$Header) {
    $g = New-Object System.Windows.Controls.Grid; $g.Margin = '0,0,0,9'; $g.Background = $Br.clear
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = '*'; $g.ColumnDefinitions.Add($c0)
    foreach ($x in $cols) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = 76; $g.ColumnDefinitions.Add($cd) }
    $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)); $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    if ($Header) {
        [void]$g.Children.Add((New-Text $name 12 $Br.muted))
        for ($i = 0; $i -lt $cols.Count; $i++) {
            $t = New-Text $cols[$i] 12 $Br.muted; $t.TextAlignment = 'Right'; $t.HorizontalAlignment = 'Right'
            [System.Windows.Controls.Grid]::SetColumn($t, $i + 1); [void]$g.Children.Add($t)
        }
        return $g
    }
    $d = New-Object System.Windows.Controls.DockPanel
    $tv = New-Text (Format-Time $secs) 13 $Br.ink2; $tv.Margin = '8,0,0,0'; [System.Windows.Controls.DockPanel]::SetDock($tv, 'Right')
    $tn = New-Text $name 13 $Br.ink 'Medium'
    [void]$d.Children.Add($tv); [void]$d.Children.Add($tn)
    [void]$g.Children.Add($d)
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $t = New-Text $cols[$i] 13 $Br.ink2; $t.HorizontalAlignment = 'Right'
        [System.Windows.Controls.Grid]::SetColumn($t, $i + 1); [void]$g.Children.Add($t)
    }
    $bar = New-Object System.Windows.Controls.Grid; $bar.Margin = '0,5,0,0'
    $a = New-Object System.Windows.Controls.ColumnDefinition; $a.Width = New-Object System.Windows.GridLength ([math]::Max(0.01, $secs)), 'Star'
    $b = New-Object System.Windows.Controls.ColumnDefinition; $b.Width = New-Object System.Windows.GridLength ([math]::Max(0, $max - $secs)), 'Star'
    $bar.ColumnDefinitions.Add($a); $bar.ColumnDefinitions.Add($b)
    $fill = New-Object System.Windows.Controls.Border; $fill.Height = 6; $fill.CornerRadius = '0,3,3,0'; $fill.Background = $brush; $fill.MinWidth = 2
    [void]$bar.Children.Add($fill)
    [System.Windows.Controls.Grid]::SetRow($bar, 1)
    [void]$g.Children.Add($bar)
    return $g
}

function Get-LabelCat($l) { if ($script:Bad.ContainsKey($l)) { 'distract' } elseif ($script:Neu.ContainsKey($l)) { 'neutral' } else { 'work' } }
function Get-Short($l) { $l -replace '^\w+: ', '' }
function Format-Sod([int]$sod) { '{0:00}:{1:00}' -f [math]::Floor($sod / 3600), [math]::Floor(($sod % 3600) / 60) }
function Get-DayName($date) { ([datetime]::ParseExact($date, 'yyyy-MM-dd', $null)).ToString('ddd d MMM') }

# Hours with activity (at least 8 wide), from a 24-value array
function Get-HourSpan($vals) {
    $used = @(0..23 | Where-Object { $vals[$_] -gt 0 })
    $h0 = $(if ($used) { $used[0] } else { 8 }); $h1 = $(if ($used) { $used[-1] } else { 18 })
    while ($h1 - $h0 -lt 7) { if ($h0 -gt 0) { $h0-- }; if ($h1 - $h0 -lt 7 -and $h1 -lt 23) { $h1++ } }
    return @($h0, $h1)
}

# ---------- Visits: logged pieces of the same app/site joined together (gaps up to 15 s) ----------
# From = what you were using right before (if within 2 minutes).
function Get-Visits($days) {
    foreach ($d in $days) {
        $last = $null
        foreach ($s in $d.Segs) {
            $st = [int]$s[0]; $len = [int]$s[1]; $lab = $s[2]
            if ($last -and $last.Label -eq $lab -and ($st - $last.End) -le 15) { $last.End = $st + $len; $last.Secs += $len; continue }
            $from = $null
            if ($last) { if (($st - $last.End) -le 120) { $from = $last.Label }; $last }
            $last = [pscustomobject]@{ Date = $d.Date; Start = $st; End = $st + $len; Secs = $len; Label = $lab; Cat = (Get-LabelCat $lab); From = $from }
        }
        if ($last) { $last }
    }
}

# Deep-work blocks: stretches without distractions or long breaks (gaps up to 2 minutes).
# Only work time counts toward a block's length.
function Get-DeepBlocks($visits) {
    $cur = $null
    foreach ($v in $visits) {
        $joins = $cur -and $v.Date -eq $cur.Date -and ($v.Start - $cur.End) -le 120 -and $v.Cat -ne 'distract'
        if ($joins) { $cur.End = $v.End; if ($v.Cat -eq 'work') { $cur.Secs += $v.Secs }; continue }
        if ($cur -and $cur.Secs -gt 0) { $cur }
        $cur = $null
        if ($v.Cat -ne 'distract') { $cur = [pscustomobject]@{ Date = $v.Date; Start = $v.Start; End = $v.End; Secs = $(if ($v.Cat -eq 'work') { $v.Secs } else { 0 }) } }
    }
    if ($cur -and $cur.Secs -gt 0) { $cur }
}

# ---------- Distractions dashboard ----------
function Render-Distractions {
    $n = $script:Days
    $days = @(Get-Days $n)
    $sum = Get-Summary $days
    $visits = @(Get-Visits $days)
    $bad = @($visits | Where-Object Cat -eq 'distract')
    $activeDays = [math]::Max(1, @($sum.PerDay | Where-Object { $_.F + $_.X -gt 0 }).Count)
    $period = $(if ($n -eq 1) { 'today' } else { "in the last $n days" })

    # Tiles
    $DTiles.Children.Clear()
    $pct = $(if ($sum.Total) { [int][math]::Round(100 * $sum.Lost / $sum.Total) } else { 0 })
    $sub1 = $(if ($n -eq 1) { "$pct% of your active time" } else { 'About ' + (Format-Time ($sum.Lost / $activeDays)) + " per day ($pct%)" })
    [void]$DTiles.Children.Add((New-Tile 'Distracting time' (Format-Time $sum.Lost) $sub1 $Br.distract))
    $sub2 = $(if ($bad) { 'Once every ' + (Format-Time ($sum.Total / $bad.Count)) + ' of active time' } else { 'None ' + $period + '. Nice.' })
    [void]$DTiles.Children.Add((New-Tile 'Times you opened one' ([string]$bad.Count) $sub2))
    $avg = $(if ($bad) { $sum.Lost / $bad.Count } else { 0 })
    $short = @($bad | Where-Object Secs -lt 120).Count
    $sub3 = $(if ($bad) { "$short of $($bad.Count) were under 2 minutes" } else { '-' })
    [void]$DTiles.Children.Add((New-Tile 'Average visit' $(if ($bad) { Format-Time $avg } else { '-' }) $sub3))
    $long = $bad | Sort-Object Secs -Descending | Select-Object -First 1
    if ($long) {
        $when = $(if ($n -eq 1) { 'at ' } else { (Get-DayName $long.Date) + ', ' }) + (Format-Sod $long.Start)
        [void]$DTiles.Children.Add((New-Tile 'Longest visit' (Format-Time $long.Secs) ((Get-Short $long.Label) + ' ' + $when)))
    } else { [void]$DTiles.Children.Add((New-Tile 'Longest visit' '-' 'No distractions')) }

    # Each distraction: time, visits, average visit
    $DList.Children.Clear()
    $groups = @($bad | Group-Object Label | ForEach-Object {
        $s = ($_.Group | Measure-Object Secs -Sum).Sum
        [pscustomobject]@{ Name = $_.Name; Secs = $s; Visits = $_.Count; Avg = $s / $_.Count } } | Sort-Object Secs -Descending)
    $DListSub.Text = $(if ($groups) { "$($groups.Count) distracting site$(if ($groups.Count -ne 1) { 's' }) or app$(if ($groups.Count -ne 1) { 's' }) $period" } else { "Nothing distracting $period" })
    if (-not $groups) { Add-Empty $DList 'No distractions in this period. Keep it up.' }
    else {
        [void]$DList.Children.Add((New-ColRow 'Site or app' 0 0 $null @('Visits', 'Avg visit') -Header))
        foreach ($g in ($groups | Select-Object -First 10)) {
            [void]$DList.Children.Add((New-ColRow $g.Name $g.Secs $groups[0].Secs $Br.distract @([string]$g.Visits, (Format-Time $g.Avg))))
        }
    }

    # What pulls you away: the non-distracting app used right before
    $DFrom.Children.Clear()
    $trig = @($bad | Where-Object { $_.From -and (Get-LabelCat $_.From) -ne 'distract' } | Group-Object From | Sort-Object Count -Descending | Select-Object -First 6)
    if (-not $trig) { Add-Empty $DFrom 'Not enough data yet. This shows which apps you most often leave for a distraction.' }
    else {
        foreach ($t in $trig) {
            $to = $t.Group | Group-Object Label | Sort-Object Count -Descending | Select-Object -First 1
            $txt = " $($t.Count) time$(if ($t.Count -ne 1) { 's' }), mostly $ARROW $(Get-Short $to.Name)"
            [void]$DFrom.Children.Add((New-Line $txt $t.Name))
        }
        Add-Empty $DFrom 'Tip: when you notice this pattern, close the distraction before you open the app, or start a focus session first.'
    }

    # When distractions start (count of visits by starting hour)
    $cnt = New-Object 'double[]' 24
    foreach ($v in $bad) { $cnt[[math]::Floor($v.Start / 3600)]++ }
    $span = Get-HourSpan $(if ($bad) { $cnt } else { $sum.HourF })
    $DHourSub.Text = "Times you opened a distraction, by hour ($period)"
    $cats = @(foreach ($h in $span[0]..$span[1]) { [pscustomobject]@{ Label = "${h}h"; Tip = ('{0:00}:00 - {1:00}:00' -f $h, (($h + 1) % 24)); F = $cnt[$h]; X = 0 } })
    Plot-Stack $DHourCanvas $cats $(if ($cats.Count -gt 12) { 2 } else { 1 }) 0 (New-Spec 'Times opened' $Br.distract $null -Count)

    # Trend: by hour today, by day otherwise; dashed line = daily limit
    $spec = New-Spec 'Distracting' $Br.distract $null
    $spec.GoalName = 'Limit'
    if ($n -eq 1) {
        $DTrendTitle.Text = 'Distracting time by hour'; $DTrendSub.Text = 'Minutes on distractions in each hour today'
        $span = Get-HourSpan $(if ($sum.Lost) { $sum.HourX } else { $sum.HourF })
        $cats = @(foreach ($h in $span[0]..$span[1]) { [pscustomobject]@{ Label = "${h}h"; Tip = ('{0:00}:00 - {1:00}:00' -f $h, (($h + 1) % 24)); F = $sum.HourX[$h]; X = 0 } })
        Plot-Stack $DTrendCanvas $cats $(if ($cats.Count -gt 12) { 2 } else { 1 }) 0 $spec
    } else {
        $limit = 60 * [double]$script:Settings.DailyLimitMinutes
        $DTrendTitle.Text = 'Distracting time per day'
        $DTrendSub.Text = $(if ($limit -gt 0) { 'The dashed line is your ' + (Format-Time $limit) + ' daily limit' } else { 'Minutes on distractions each day' })
        $cats = @(foreach ($c in (Get-DayCats $sum.PerDay ($n -gt 7))) {
            $over = $(if ($limit -gt 0) { if ($c.X -gt $limit) { 'Over the limit' } else { 'Within the limit' } } else { $null })
            [pscustomobject]@{ Label = $c.Label; Tip = $c.Tip; F = $c.X; X = 0; Extra = $over } })
        Plot-Stack $DTrendCanvas $cats $(if ($n -gt 7) { 3 } else { 1 }) $limit $spec
    }
}

# ---------- Sessions dashboard ----------
function Render-SessionsDash {
    $n = $script:Days
    $ss = @(Get-FocusSessions $n)
    $done = @($ss | Where-Object Done); $stopped = @($ss | Where-Object { -not $_.Done })
    $secs = ($ss | Measure-Object Secs -Sum).Sum
    $sum = Get-Summary @(Get-Days $n)
    $period = $(if ($n -eq 1) { 'today' } else { "in the last $n days" })

    $STiles.Children.Clear()
    [void]$STiles.Children.Add((New-Tile 'Sessions completed' ([string]$done.Count) "$($stopped.Count) stopped early" $Br.focus))
    $rate = $(if ($ss) { $done.Count / $ss.Count } else { 0 })
    [void]$STiles.Children.Add((New-Tile 'Completion rate' $(if ($ss) { "$([int][math]::Round(100 * $rate))%" } else { '-' }) $(if ($ss) { "of $($ss.Count) started" } else { "No sessions $period" }) $null @($rate, $Br.focus)))
    $share = $(if ($sum.Focus) { [int][math]::Round(100 * [math]::Min($secs, $sum.Focus) / $sum.Focus) } else { 0 })
    [void]$STiles.Children.Add((New-Tile 'Time in sessions' (Format-Time $secs) $(if ($sum.Focus) { "$share% of your focused time" } else { '-' })))
    $dsum = ($ss | Measure-Object DistractSec -Sum).Sum
    $clean = @($ss | Where-Object { $_.DistractSec -eq 0 }).Count
    [void]$STiles.Children.Add((New-Tile 'Distraction in sessions' $(if ($ss) { Format-Time ($dsum / $ss.Count) } else { '-' }) $(if ($ss) { "per session - $clean of $($ss.Count) had none" } else { '-' }) $Br.distract))

    # Chart: by starting hour today, per day otherwise
    $spec = New-Spec 'Completed' $Br.focus 'Stopped early' $Br.other -Count
    if ($n -eq 1) {
        $SChartTitle.Text = 'Sessions by starting hour'; $SChartSub.Text = 'When you started focus sessions today'
        $a = New-Object 'double[]' 24; $b = New-Object 'double[]' 24
        foreach ($s in $ss) { $h = [int]$s.Start.Substring(11, 2); if ($s.Done) { $a[$h]++ } else { $b[$h]++ } }
        $all = New-Object 'double[]' 24; for ($h = 0; $h -lt 24; $h++) { $all[$h] = $a[$h] + $b[$h] }
        $span = Get-HourSpan $(if ($ss) { $all } else { $sum.HourF })
        $cats = @(foreach ($h in $span[0]..$span[1]) { [pscustomobject]@{ Label = "${h}h"; Tip = ('{0:00}:00 - {1:00}:00' -f $h, (($h + 1) % 24)); F = $a[$h]; X = $b[$h] } })
        Plot-Stack $SChart $cats $(if ($cats.Count -gt 14) { 2 } else { 1 }) 0 $spec
    } else {
        $SChartTitle.Text = 'Sessions per day'; $SChartSub.Text = "Focus sessions you started each day, $period"
        $cats = @(for ($i = 0; $i -lt $sum.PerDay.Count; $i++) {
            $p = $sum.PerDay[$i]; $c = (Get-DayCats @($p) ($n -gt 7))
            $day = @($ss | Where-Object Date -eq $p.Date)
            [pscustomobject]@{ Label = $c.Label; Tip = $c.Tip; F = @($day | Where-Object Done).Count; X = @($day | Where-Object { -not $_.Done }).Count } })
        Plot-Stack $SChart $cats $(if ($n -gt 7) { 3 } else { 1 }) 0 $spec
    }

    # By task
    $STasks.Children.Clear()
    $groups = @($ss | Group-Object { if ($_.Task) { $_.Task } else { '(no task name)' } } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Secs = ($_.Group | Measure-Object Secs -Sum).Sum; Count = $_.Count; Done = @($_.Group | Where-Object Done).Count } } |
        Sort-Object Secs -Descending)
    $STaskSub.Text = "Time per task $period"
    if (-not $groups) { Add-Empty $STasks "No focus sessions $period. Start one at the top: type a task and press Start." }
    else {
        [void]$STasks.Children.Add((New-ColRow 'Task' 0 0 $null @('Sessions', 'Completed') -Header))
        foreach ($g in ($groups | Select-Object -First 8)) {
            [void]$STasks.Children.Add((New-ColRow $g.Name $g.Secs $groups[0].Secs $Br.focus @([string]$g.Count, "$([int][math]::Round(100 * $g.Done / $g.Count))%")))
        }
    }

    # Recent sessions
    $SRecent.Children.Clear()
    $recent = @($ss | Sort-Object Start -Descending | Select-Object -First 8)
    if (-not $recent) { Add-Empty $SRecent "No sessions $period." }
    foreach ($s in $recent) {
        $d = New-Object System.Windows.Controls.DockPanel; $d.Margin = '0,0,0,10'
        $sw = New-Object System.Windows.Shapes.Rectangle; $sw.Width = 10; $sw.Height = 10; $sw.RadiusX = 3; $sw.RadiusY = 3
        $sw.Fill = $(if ($s.Done) { $Br.focus } else { $Br.other }); $sw.Margin = '0,0,10,0'; $sw.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($sw, 'Left')
        $state = $(if ($s.Done) { 'Completed' } else { 'Stopped early' })
        $right = New-Text ((Format-Time $s.Secs) + '  ' + $state) 12.5 $Br.ink2; $right.Margin = '10,0,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($right, 'Right')
        $when = ([datetime]::ParseExact($s.Start, 's', $null)).ToString('ddd HH:mm')
        $mid = New-Object System.Windows.Controls.TextBlock; $mid.TextTrimming = 'CharacterEllipsis'; $mid.VerticalAlignment = 'Center'; $mid.FontSize = 13
        $r1 = New-Object System.Windows.Documents.Run ($when + '   '); $r1.Foreground = $Br.muted; [void]$mid.Inlines.Add($r1)
        $r2 = New-Object System.Windows.Documents.Run $(if ($s.Task) { $s.Task } else { '(no task name)' }); $r2.Foreground = $Br.ink; $r2.Tag = 'raw'; [void]$mid.Inlines.Add($r2)
        if ($s.DistractSec -gt 0) { $r3 = New-Object System.Windows.Documents.Run ('   ' + (Format-Time $s.DistractSec) + ' distracted'); $r3.Foreground = $Br.muted; [void]$mid.Inlines.Add($r3) }
        [void]$d.Children.Add($sw); [void]$d.Children.Add($right); [void]$d.Children.Add($mid)
        [void]$SRecent.Children.Add($d)
    }
}

# ---------- Patterns dashboard ----------
function Render-Patterns($goal) {
    $dayNames = [Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.AbbreviatedDayNames
    $rowNames = @(1, 2, 3, 4, 5, 6, 0 | ForEach-Object { $dayNames[$_] })   # Monday first

    # Weekday x hour, last 4 weeks
    $d28 = @(Get-Days 28)
    $F = @(foreach ($r in 0..6) { , (New-Object 'double[]' 24) }); $X = @(foreach ($r in 0..6) { , (New-Object 'double[]' 24) })
    $dayCount = New-Object 'int[]' 7; $dayFocus = New-Object 'double[]' 7
    $any = New-Object 'double[]' 24
    foreach ($d in $d28) {
        $r = ([int]([datetime]::ParseExact($d.Date, 'yyyy-MM-dd', $null)).DayOfWeek + 6) % 7
        $df = 0
        foreach ($k in $d.Agg.Keys) {
            $parts = $k.Split('|', 2); $h = [int]$parts[0]; $l = $parts[1]; $sec = $d.Agg[$k]
            if ($script:Bad.ContainsKey($l)) { $X[$r][$h] += $sec; $any[$h] += $sec }
            elseif (-not $script:Neu.ContainsKey($l)) { $F[$r][$h] += $sec; $any[$h] += $sec; $df += $sec }
        }
        if ($d.Agg.Count) { $dayCount[$r]++; $dayFocus[$r] += $df }
    }
    $span = Get-HourSpan $any
    $hours = @($span[0]..$span[1])
    $colNames = @($hours | ForEach-Object { "${_}h" })
    foreach ($pair in @(@($PHeatF, $F, 'focus', 'focused'), @($PHeatX, $X, 'distract', 'distracting'))) {
        $vals = @(foreach ($r in 0..6) { , @(foreach ($h in $hours) { $pair[1][$r][$h] }) })
        $tips = @(foreach ($r in 0..6) { , @(foreach ($h in $hours) { '{0} {1:00}:00 - {2:00}:00: {3} {4} (4 weeks added up)' -f $rowNames[$r], $h, (($h + 1) % 24), (Format-Time $pair[1][$r][$h]), $pair[3] }) })
        Plot-Heat $pair[0] $rowNames $colNames $vals $tips $pair[2]
    }

    # Calendar: last 12 weeks, one column per week
    $today = (Get-Date).Date
    $start = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7)).AddDays(-77)   # Monday, 11 weeks before this week
    $per = @{}
    foreach ($p in (Get-Summary @(Get-Days 84)).PerDay) { $per[$p.Date] = $p }
    $cvals = @(foreach ($r in 0..6) { , (New-Object 'object[]' 12) })
    $ctips = @(foreach ($r in 0..6) { , (New-Object 'object[]' 12) })
    $cmarks = @(foreach ($r in 0..6) { , (New-Object 'object[]' 12) })
    $ccols = New-Object 'string[]' 12
    for ($i = 0; $i -lt 84; $i++) {
        $day = $start.AddDays($i)
        if ($day -gt $today) { break }
        $c = [math]::Floor($i / 7); $r = $i % 7
        $key = $day.ToString('yyyy-MM-dd')
        $f = $(if ($per.ContainsKey($key)) { $per[$key].F } else { 0 })
        $cvals[$r][$c] = $f
        $met = $goal -gt 0 -and $f -ge $goal
        $cmarks[$r][$c] = $met
        $ctips[$r][$c] = $day.ToString('dddd, d MMM') + ': ' + (Format-Time $f) + ' focused' + $(if ($met) { ' - goal met' } else { '' })
        if ($r -eq 0 -and ($c -eq 0 -or $day.Day -le 7)) { $ccols[$c] = $day.ToString('MMM') }
    }
    $PCalSub.Text = $(if ($goal -gt 0) { 'Focused time per day. A dot marks a day you met your ' + (Format-Hours $script:Settings.GoalMinutes) + ' goal.' } else { 'Focused time per day.' })
    Plot-Heat $PCal $rowNames $ccols $cvals $ctips 'focus' $cmarks

    # App switching and deep work, last 14 days
    $d14 = @(Get-Days 14)
    $visits = @(Get-Visits $d14)
    $sw = New-Object 'double[]' 24; $act = New-Object 'double[]' 24
    foreach ($v in $visits) {
        $h = [int][math]::Floor($v.Start / 3600)
        if ($v.From) { $sw[$h]++ }
    }
    foreach ($d in $d14) { foreach ($k in $d.Agg.Keys) { $act[[int]$k.Split('|', 2)[0]] += $d.Agg[$k] } }
    $span = Get-HourSpan $act
    $cats = @(foreach ($h in $span[0]..$span[1]) {
        $rateH = $(if ($act[$h] -ge 600) { $sw[$h] / ($act[$h] / 3600) } else { 0 })
        [pscustomobject]@{ Label = "${h}h"; Tip = ('{0:00}:00 - {1:00}:00' -f $h, (($h + 1) % 24)); F = [math]::Round($rateH, 1); X = 0
                           Extra = $(if ($act[$h] -lt 600) { 'Too little activity to tell' } else { "$([int]$sw[$h]) switches in $(Format-Time $act[$h])" }) } })
    Plot-Stack $PSwitch $cats $(if ($cats.Count -gt 12) { 2 } else { 1 }) 0 (New-Spec 'Switches per hour' $AquaBr $null -Count)

    $blocks = @(Get-DeepBlocks $visits)
    $best = $blocks | Sort-Object Secs -Descending | Select-Object -First 1
    $deep = @($blocks | Where-Object Secs -ge 1500)
    $activeDays = [math]::Max(1, @($d14 | Where-Object { $_.Agg.Count }).Count)
    $totalAct = ($act | Measure-Object -Sum).Sum
    $swTotal = ($sw | Measure-Object -Sum).Sum

    $PTiles.Children.Clear()
    if ($best) {
        $when = (Get-DayName $best.Date) + ', from ' + (Format-Sod $best.Start)
        [void]$PTiles.Children.Add((New-Tile 'Longest deep-work block' (Format-Time $best.Secs) $when $Br.focus))
    } else { [void]$PTiles.Children.Add((New-Tile 'Longest deep-work block' '-' 'Last 14 days' $Br.focus)) }
    [void]$PTiles.Children.Add((New-Tile 'Deep-work blocks (25m+)' ([string]$deep.Count) ('About {0:0.#} per active day (14 days)' -f ($deep.Count / $activeDays))))
    [void]$PTiles.Children.Add((New-Tile 'App switches' $(if ($totalAct -ge 600) { [string][int][math]::Round($swTotal / ($totalAct / 3600)) } else { '-' }) 'per hour of active time (14 days)' $AquaBr))
    $bestDay = -1; $bestAvg = 0
    for ($r = 0; $r -lt 7; $r++) { if ($dayCount[$r] -gt 0 -and $dayFocus[$r] / $dayCount[$r] -gt $bestAvg) { $bestAvg = $dayFocus[$r] / $dayCount[$r]; $bestDay = $r } }
    if ($bestDay -ge 0) {
        $full = [Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.DayNames[(1, 2, 3, 4, 5, 6, 0)[$bestDay]]
        [void]$PTiles.Children.Add((New-Tile 'Best weekday' $full ('Average ' + (Format-Time $bestAvg) + ' focused (4 weeks)')))
    } else { [void]$PTiles.Children.Add((New-Tile 'Best weekday' '-' 'Not enough data yet')) }
}
