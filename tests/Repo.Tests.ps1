# Repository checks: script rules, translations, version and privacy.
# Keep this file ASCII-only.

BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $scripts = @(Get-ChildItem $root -Recurse -Include *.ps1, *.vbs -File | Where-Object { $_.FullName -notlike '*\.git\*' } |
        ForEach-Object { @{ Name = $_.FullName.Substring($root.Length + 1); Path = $_.FullName } })
    $ps1 = @($scripts | Where-Object { $_.Path -like '*.ps1' })
}

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Add-Type -AssemblyName System.Web.Extensions
    $ptText = [IO.File]::ReadAllText((Join-Path $root 'pt.json'), [Text.Encoding]::UTF8)
}

Describe 'Scripts' {
    It '<Name> is ASCII-only (Windows PowerShell 5.1 misreads other characters)' -TestCases $scripts {
        $bad = @([IO.File]::ReadAllBytes($Path) | Where-Object { $_ -gt 127 })
        $bad.Count | Should -Be 0
    }
    It '<Name> has no syntax errors' -TestCases $ps1 {
        $errs = $null
        [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
        @($errs | Where-Object { $_ }).Count | Should -Be 0
    }
    It 'has no PSScriptAnalyzer errors' {
        if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Set-ItResult -Skipped -Because 'PSScriptAnalyzer is not installed'; return }
        $issues = @(Invoke-ScriptAnalyzer -Path $root -Recurse -Severity Error)
        ($issues | ForEach-Object { "$($_.ScriptName):$($_.Line) $($_.RuleName)" }) -join "`n" | Should -BeNullOrEmpty
    }
}

Describe 'Translations (pt.json)' {
    It 'is valid JSON' {
        { (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject($ptText) } | Should -Not -Throw
    }
    It 'has no key twice' {
        $keys = @([regex]::Matches($ptText, '(?m)^\s*"((?:[^"\\]|\\.)*)"\s*:') | ForEach-Object { $_.Groups[1].Value })
        $dupes = @($keys | Group-Object -CaseSensitive | Where-Object Count -gt 1 | ForEach-Object Name)
        $dupes -join ', ' | Should -BeNullOrEmpty
    }
    It 'keeps every placeholder of the English text' {
        $j = (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject($ptText)
        $missing = foreach ($k in $j.Keys) {
            foreach ($m in [regex]::Matches($k, '\{(\d)#?\}')) {
                if (-not ([string]$j[$k]).Contains('{' + $m.Groups[1].Value + '}')) { $k }
            }
        }
        @($missing) -join "`n" | Should -BeNullOrEmpty
    }
    It 'has no empty translations' {
        $j = (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject($ptText)
        @($j.Keys | Where-Object { -not ([string]$j[$_]).Trim() }) -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'Version' {
    It 'matches the newest entry in CHANGELOG.md' {
        $v = [regex]::Match((Get-Content (Join-Path $root 'common.ps1') -Raw), "FocusVersion = '([^']+)'").Groups[1].Value
        $top = [regex]::Match((Get-Content (Join-Path $root 'CHANGELOG.md') -Raw), '(?m)^## \[(\d+\.\d+\.\d+)\]').Groups[1].Value
        $v | Should -Not -BeNullOrEmpty
        $v | Should -Be $top
    }
}

Describe 'Privacy' {
    It '.gitignore keeps personal data out of the repository' -TestCases @(
        @{ f = 'logs/' }, @{ f = 'sessions.tsv' }, @{ f = 'plans.json' }, @{ f = 'settings.json' },
        @{ f = 'categories.json' }, @{ f = 'focus.json' }, @{ f = 'coach-data.md' }, @{ f = 'export-history.tsv' }
    ) {
        Get-Content (Join-Path $root '.gitignore') | Should -Contain $f
    }
}
