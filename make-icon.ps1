# Draws the Distraction Log icon (blue tile with a small bar chart) and saves app.ico.
Add-Type -AssemblyName System.Drawing

function New-IconPng([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    function RoundRect($x, $y, $w, $h, $r) {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = [float]($r * 2)
        if ($d -le 0) { $p.AddRectangle((New-Object System.Drawing.RectangleF $x, $y, $w, $h)); return $p }
        $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
        $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
        $p.CloseFigure(); return $p
    }

    $blue   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 42, 120, 214))
    $white  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $orange = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 104, 52))

    $g.FillPath($blue, (RoundRect 0 0 ($s - 1) ($s - 1) ($s * 0.22)))

    # Three bars; the middle one has an orange "distracted" cap
    $bw = $s * 0.16; $gap = $s * 0.075; $base = $s * 0.78
    $x0 = ($s - (3 * $bw + 2 * $gap)) / 2
    $heights = @(0.30, 0.54, 0.40)
    $r = [math]::Max(0.5, $s * 0.035)
    for ($i = 0; $i -lt 3; $i++) {
        $x = $x0 + $i * ($bw + $gap); $h = $s * $heights[$i]
        if ($i -eq 1) {
            $cap = $s * 0.15; $sep = [math]::Max(1, $s * 0.03)
            $g.FillPath($orange, (RoundRect $x ($base - $h) $bw $cap $r))
            $g.FillRectangle($white, $x, ($base - $h + $cap + $sep), $bw, ($h - $cap - $sep))
        } else {
            $g.FillPath($white, (RoundRect $x ($base - $h) $bw $h $r))
        }
    }
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    return , $ms.ToArray()
}

# ICO file with PNG images inside (supported since Windows Vista)
$sizes = 16, 24, 32, 48, 64, 256
$pngs  = foreach ($s in $sizes) { , (New-IconPng $s) }
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter $out
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Flush()
[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'app.ico'), $out.ToArray())
# Also save a large PNG preview
[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'app-icon.png'), $pngs[-1])
