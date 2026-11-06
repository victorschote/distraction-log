# Tests for common.ps1: labels, categories, settings, translation, focus sessions and plans.
# Each run works on a copy in Pester's temporary drive, so your real data is never touched.
# Run:  Invoke-Pester .\tests
# Keep this file ASCII-only (build other characters with [char]).

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $work = Join-Path $TestDrive 'app'
    New-Item -ItemType Directory -Force (Join-Path $work 'logs') | Out-Null
    Copy-Item (Join-Path $root 'common.ps1'), (Join-Path $root 'pt.json') $work
    . (Join-Path $work 'common.ps1')

    # Record notifications instead of showing them
    $script:Toasts = New-Object System.Collections.Generic.List[object]
    function Show-FocusToast([string]$title, [string]$body, [string]$launch = '') { $script:Toasts.Add(@($title, $body, $launch)) }

    $EmDash = [string][char]0x2014
}

Describe 'Labels and categories' {
    It 'names a distracting site in a browser' {
        Get-FocusLabel 'firefox' ("Funny cats - YouTube $EmDash Mozilla Firefox") | Should -Be 'Firefox: YouTube'
    }
    It 'names other sites by the last part of the title' {
        Get-FocusLabel 'chrome' 'Dashboard - Grafana - Google Chrome' | Should -Be 'Chrome: Grafana'
    }
    It 'uses friendly names for known apps' {
        Get-FocusLabel 'WINWORD' 'Report.docx - Word' | Should -Be 'Word'
        Get-FocusLabel 'SomeTool' 'Window' | Should -Be 'SomeTool'
    }
    It 'sorts apps into work, neutral and distracting' {
        Get-FocusCategory 'Firefox: YouTube' 'YouTube' | Should -Be 'distract'
        Get-FocusCategory 'Spotify' 'Spotify' | Should -Be 'neutral'
        Get-FocusCategory 'Word' 'Report.docx - Word' | Should -Be 'work'
        Test-FocusDistracting 'Firefox: Instagram' 'Instagram' | Should -BeTrue
    }
    It 'lets your own choice win over the keyword list' {
        Save-FocusCategories @{ 'Firefox: YouTube' = 'work' }
        $FocusCatMap = Import-FocusCategories
        Get-FocusCategory 'Firefox: YouTube' 'YouTube' | Should -Be 'work'
        Get-FocusCategory 'Firefox: YouTube' 'YouTube' -Default | Should -Be 'distract'
        Remove-Item $CategoryFile
    }
    It 'ignores invalid category values' {
        '{"Word":"banana","Excel":"neutral"}' | Set-Content $CategoryFile
        $m = Import-FocusCategories
        $m.ContainsKey('Word') | Should -BeFalse
        $m['Excel'] | Should -Be 'neutral'
        Remove-Item $CategoryFile
    }
}

Describe 'Activity log rows' {
    It 'reads today''s log with labels and categories' {
        $start = (Get-Date).Date.AddHours(9)
        $lines = @(
            ("{0}`t120`tWINWORD`tReport.docx - Word" -f $start.ToString('s'))
            ("{0}`t60`tfirefox`tYouTube - Mozilla Firefox" -f $start.AddMinutes(2).ToString('s'))
            'broken line'
        )
        [IO.File]::WriteAllLines((Join-Path $FocusDir ("logs\{0}.tsv" -f $start.ToString('yyyy-MM-dd'))), $lines)
        $rows = @(Get-FocusRows 1)
        $rows.Count | Should -Be 2
        $rows[0].Label | Should -Be 'Word'
        $rows[0].Cat | Should -Be 'work'
        $rows[1].Distracting | Should -BeTrue
        $rows[1].Hour | Should -Be 9
    }
}

Describe 'Settings' {
    It 'uses defaults when there is no settings file' {
        $s = Get-FocusSettings
        $s.GoalMinutes | Should -Be 240
        $s.SessionMinutes | Should -Be 25
        $s.Language | Should -Be 'en'
    }
    It 'keeps saved values and ignores unknown ones' {
        '{"GoalMinutes":120,"Language":"pt","Bogus":1}' | Set-Content $SettingsFile
        $s = Get-FocusSettings
        $s.GoalMinutes | Should -Be 120
        $s.Language | Should -Be 'pt'
        $s.PSObject.Properties.Name | Should -Not -Contain 'Bogus'
        $s.DailyLimitMinutes | Should -Be 30
        Remove-Item $SettingsFile
    }
}

Describe 'Time format' {
    It 'formats seconds as minutes and hours' -TestCases @(
        @{ s = 0; e = '0m' }, @{ s = 20; e = '<1m' }, @{ s = 300; e = '5m' }, @{ s = 3720; e = '1h 02m' }
    ) {
        Format-FocusTime $s | Should -Be $e
    }
}

Describe 'Translation' {
    BeforeAll { Set-FocusLanguage 'pt' }
    AfterAll { Set-FocusLanguage 'en' }

    It 'loads the Portuguese texts' {
        $LangExact.Count | Should -BeGreaterThan 100
        $LangPatterns.Count | Should -BeGreaterThan 50
    }
    It 'translates exact texts, case-sensitively' {
        Tr 'Today' | Should -Be 'Hoje'
        Tr 'today' | Should -Be 'hoje'
    }
    It 'fills numbers into templates' {
        Tr 'Start 25 min' | Should -Be 'Iniciar 25 min'
        Tr '5 of 7' | Should -Be '5 de 7'
    }
    It 'only matches numeric placeholders with numbers' {
        Tr 'Start now min' | Should -Be 'Start now min'
    }
    It 'translates known phrases inside templates' {
        Tr 'No sessions today' | Should -BeLike '* hoje'
    }
    It 'keeps surrounding spaces' {
        $t = Tr ' Great focus. '
        $t | Should -Be (' ' + $LangExact['Great focus.'] + ' ')
    }
    It 'leaves unknown text alone' {
        Tr 'Firefox: State of the art' | Should -Be 'Firefox: State of the art'
    }
    It 'returns English unchanged in English mode' {
        Set-FocusLanguage 'en'
        Tr 'Today' | Should -Be 'Today'
        Set-FocusLanguage 'pt'
    }
}

Describe 'Focus sessions' {
    BeforeEach { $script:Toasts.Clear(); Remove-Item $SessionFile, $SessionLog -ErrorAction SilentlyContinue }

    It 'starts a session' {
        Start-FocusSession 'Write tests' 25
        $s = Get-FocusSession
        $s.State | Should -Be 'focus'
        $s.Task | Should -Be 'Write tests'
        $s.Minutes | Should -Be 25
    }
    It 'completes a session, logs it and starts the break' {
        Start-FocusSession 'Write tests' 25
        $s = Get-FocusSession
        $s.Start = (Get-Date).AddMinutes(-26).ToString('s'); $s.End = (Get-Date).AddMinutes(-1).ToString('s'); Save-FocusSession $s
        Add-FocusSessionDistract 30
        (Update-FocusSession).State | Should -Be 'break'
        $done = @(Get-FocusSessions 1)
        $done.Count | Should -Be 1
        $done[0].Done | Should -BeTrue
        $done[0].Secs | Should -Be 1500
        $done[0].DistractSec | Should -Be 30
        $done[0].Task | Should -Be 'Write tests'
        $script:Toasts[0][0] | Should -Be 'Focus session complete'
    }
    It 'ends the break' {
        Start-FocusSession 'x' 25
        $s = Get-FocusSession; $s.State = 'break'; $s.BreakEnd = (Get-Date).AddSeconds(-5).ToString('s'); Save-FocusSession $s
        (Update-FocusSession).State | Should -Be 'idle'
        $script:Toasts[-1][0] | Should -Be "Break's over"
    }
    It 'logs a session stopped early, but not one under a minute' {
        Start-FocusSession 'Short' 25
        Stop-FocusSession
        @(Get-FocusSessions 1).Count | Should -Be 0
        Start-FocusSession 'Longer' 25
        $s = Get-FocusSession; $s.Start = (Get-Date).AddMinutes(-3).ToString('s'); Save-FocusSession $s
        Stop-FocusSession
        $done = @(Get-FocusSessions 1)
        $done.Count | Should -Be 1
        $done[0].Done | Should -BeFalse
        (Get-FocusSession).State | Should -Be 'idle'
    }
    It 'stays quiet about a session that ended long ago' {
        Start-FocusSession 'Old' 25
        $s = Get-FocusSession; $s.Start = (Get-Date).AddHours(-3).ToString('s'); $s.End = (Get-Date).AddHours(-2).ToString('s'); Save-FocusSession $s
        (Update-FocusSession).State | Should -Be 'idle'
        $script:Toasts.Count | Should -Be 0
        @(Get-FocusSessions 1).Count | Should -Be 1
    }
}

Describe 'Plans' {
    It 'saves and reads back a plan, including accented text' {
        $acc = 'Revisar or' + [char]0x00E7 + 'amento'
        Set-FocusPlan '2026-01-05' @('Send proposal', $acc, '') @($true, $false, $false)
        $p = Get-FocusPlan '2026-01-05'
        $p.Items[0] | Should -Be 'Send proposal'
        $p.Items[1] | Should -Be $acc
        $p.Done[0] | Should -BeTrue
        $p.Done[1] | Should -BeFalse
        Test-FocusPlan $p | Should -BeTrue
    }
    It 'keeps other plans when saving one' {
        Set-FocusPlan '2026-W02' @('Goal', '', '') @($false, $false, $false)
        (Get-FocusPlan '2026-01-05').Items[0] | Should -Be 'Send proposal'
    }
    It 'returns an empty plan for unknown days' {
        Test-FocusPlan (Get-FocusPlan '1999-01-01') | Should -BeFalse
    }
    It 'makes ISO week ids' {
        Get-FocusWeekId ([datetime]'2026-01-05') | Should -Be '2026-W02'
        Get-FocusWeekId (Get-Date) | Should -Match '^\d{4}-W\d{2}$'
    }
}
