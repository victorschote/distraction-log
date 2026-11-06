# Contributing to Distraction Log

Thanks for helping. This guide covers how the project is laid out, the few rules that keep it
working on every Windows machine, and how to test and send a change.

## Getting started

1. Fork or clone the repository to a folder that stays put.
2. Install for your user: `powershell -ExecutionPolicy Bypass -File setup.ps1`
3. Install the test tools once:

   ```powershell
   Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck -Force
   Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
   ```

See the *Files* table in [README.md](README.md#files) for what each script does.

## Rules

- **Windows PowerShell 5.1.** The app must run on the PowerShell built into Windows, with no modules to install.
- **ASCII-only `.ps1` and `.vbs` files.** PowerShell 5.1 misreads UTF-8 files without a BOM.
  Build other characters with `[char]0x2014`, and put text with accents in `pt.json`.
- **All user-facing text is English in the code** and translated through `pt.json`.
  When you add or change a text, add its Portuguese version. Use `{0}` for any text and `{0#}`
  for numbers or times (for example `"Start {0#} min": "Iniciar {0} min"`). Never translate the
  user's own text (tasks, plans, site names): mark such elements with `Tag = 'raw'`.
- **Privacy first.** Data stays on the computer. Never add network calls, and never commit
  personal data (see `.gitignore`).
- **The blocker runs as SYSTEM.** Keep `blocker.ps1` self-contained: it must only read data files
  and only write its fixed domain list. Never make it run code from the user's folder.
- Known PowerShell 5.1 traps: `[math]::Min(1, 0.5)` returns an integer (use `1.0`); a one-item
  `foreach` result is not an array (wrap in `@()`); `$args` and `$pid` are reserved names;
  `ConvertFrom-Json` treats keys case-insensitively (use `JavaScriptSerializer` for `pt.json`).

## Testing

```powershell
Invoke-Pester .\tests -Output Detailed
```

Tests run on a temporary copy, never on your real data. GitHub Actions runs the same tests on
every push and pull request.

To check the screens, use the self-test. It renders every tab and dialog to PNG files and exits:

```powershell
$env:FL_SNAPSHOT = "$env:TEMP\fl-shots"; mkdir $env:FL_SNAPSHOT -Force
powershell -STA -ExecutionPolicy Bypass -File app.ps1
```

Check both languages (switch with the EN | PT button, or set `"Language": "pt"` in `settings.json`)
and both Windows themes (light and dark).

## Sending a change

1. Create a branch: `git switch -c short-description`
2. Make the change, add tests where it makes sense, and run `Invoke-Pester .\tests`.
3. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
4. Commit with a short, clear message in the imperative ("Add weekly export", "Fix timer after sleep").
5. Push and open a pull request. The template lists what to check.

## Releasing

1. Move the **Unreleased** notes into a new version section in `CHANGELOG.md`.
2. Set the same number in `$FocusVersion` in `common.ps1` (the tests check they match).
3. Merge to `main`, then tag and publish:

   ```powershell
   git tag v1.1.0; git push origin v1.1.0
   ```

   The release workflow builds the zip and publishes the GitHub release with the changelog notes.
