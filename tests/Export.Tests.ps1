# Tests for export.ps1: CSV formatting and the exported files.
# Keep this file ASCII-only.

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $work = Join-Path $TestDrive 'app'
    New-Item -ItemType Directory -Force (Join-Path $work 'logs') | Out-Null
    Copy-Item (Join-Path $root 'common.ps1'), (Join-Path $root 'pt.json'), (Join-Path $root 'export.ps1') $work
    . (Join-Path $work 'common.ps1')
    . (Join-Path $work 'export.ps1')

    # Sample day: 30 min Word, 10 min YouTube, 5 min Spotify
    $day = (Get-Date).Date
    $t = $day.AddHours(10)
    $lines = @(
        ("{0}`t1800`tWINWORD`tPlan.docx - Word" -f $t.ToString('s'))
        ("{0}`t600`tfirefox`tYouTube - Mozilla Firefox" -f $t.AddMinutes(30).ToString('s'))
        ("{0}`t300`tSpotify`tSpotify" -f $t.AddMinutes(40).ToString('s'))
    )
    [IO.File]::WriteAllLines((Join-Path $work ("logs\{0}.tsv" -f $day.ToString('yyyy-MM-dd'))), $lines)
    Add-FocusLine $SessionLog ("{0}`t{1}`t25`t1500`t1`t0`tPlan`r`n" -f $t.ToString('s'), $t.AddMinutes(25).ToString('s'))
    Set-FocusPlan $day.ToString('yyyy-MM-dd') @('One', 'Two', '') @($true, $false, $false)

    $all = @{ Activity = $true; Daily = $true; Sessions = $true; Plans = $true }
    $sep = (Get-CsvFormat)[0]
}

Describe 'CSV lines' {
    It 'joins plain values with the separator' {
        ConvertTo-CsvLine @('a', 'b', '3') ';' | Should -Be 'a;b;3'
    }
    It 'quotes values with the separator, quotes or line breaks' {
        ConvertTo-CsvLine @('a;b', 'say "hi"', "two`nlines") ';' | Should -Be ('"a;b";"say ""hi""";"two' + "`n" + 'lines"')
    }
    It 'stops Excel from running text as a formula' {
        ConvertTo-CsvLine @('=SUM(A1)', '+1 call', '@home') ';' | Should -Be "'=SUM(A1);'+1 call;'@home"
    }
    It 'leaves negative numbers alone' {
        ConvertTo-CsvLine @('-5', '-2,5') ';' | Should -Be '-5;-2,5'
    }
    It 'formats minutes with the given decimal mark' {
        Format-Min 90 ',' | Should -Be '1,5'
        Format-Min 30 '.' | Should -Be '0.5'
    }
}

Describe 'Export' {
    It 'writes the four files with the right rows' {
        $r = Export-FocusData 1 (Join-Path $TestDrive 'out') $all $true
        $r[1] | Should -Be 4
        $files = @(Get-ChildItem $r[0] -Filter *.csv | ForEach-Object Name | Sort-Object)
        $files | Should -Be @('activity.csv', 'daily-summary.csv', 'plans.csv', 'sessions.csv')

        $act = Get-Content (Join-Path $r[0] 'activity.csv') -Encoding UTF8
        $act.Count | Should -Be 4
        $act[0] | Should -BeLike '*Window title*'

        $sum = (Get-Content (Join-Path $r[0] 'daily-summary.csv') -Encoding UTF8)[1] -split [regex]::Escape($sep)
        $sum[2] | Should -Match '^30[.,]0$'   # focused minutes
        $sum[3] | Should -Match '^10[.,]0$'   # distracting
        $sum[4] | Should -Match '^5[.,]0$'    # neutral
        $sum[10] | Should -Be 'Firefox: YouTube'

        (Get-Content (Join-Path $r[0] 'sessions.csv') -Encoding UTF8).Count | Should -Be 2
        (Get-Content (Join-Path $r[0] 'plans.csv') -Encoding UTF8).Count | Should -Be 3
    }
    It 'can leave window titles out' {
        $r = Export-FocusData 1 (Join-Path $TestDrive 'out2') @{ Activity = $true } $false
        $r[1] | Should -Be 1
        $act = Get-Content (Join-Path $r[0] 'activity.csv') -Encoding UTF8
        $act[0] | Should -Not -BeLike '*Window title*'
        ($act -join "`n") | Should -Not -BeLike '*Plan.docx*'
    }
    It 'writes a UTF-8 BOM so Excel reads accents' {
        $r = Export-FocusData 1 (Join-Path $TestDrive 'out3') @{ Plans = $true } $true
        $b = [IO.File]::ReadAllBytes((Join-Path $r[0] 'plans.csv'))
        $b[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }
    It 'never overwrites an earlier export' {
        $a = Export-FocusData 1 (Join-Path $TestDrive 'same') @{ Plans = $true } $true
        $b = Export-FocusData 1 (Join-Path $TestDrive 'same') @{ Plans = $true } $true
        $a[0] | Should -Not -Be $b[0]
    }
    It 'uses Portuguese file names and headers in Portuguese' {
        Set-FocusLanguage 'pt'
        try {
            $r = Export-FocusData 1 (Join-Path $TestDrive 'pt') $all $true
            Test-Path (Join-Path $r[0] 'resumo-diario.csv') | Should -BeTrue
            (Get-Content (Join-Path $r[0] 'atividade.csv') -Encoding UTF8)[0] | Should -BeLike 'Data*'
        } finally { Set-FocusLanguage 'en' }
    }
    It 'keeps a history of exports' {
        @(Read-FocusLines $ExportHistory | Where-Object { $_ }).Count | Should -BeGreaterThan 3
    }
}
