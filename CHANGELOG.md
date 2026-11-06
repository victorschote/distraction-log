# Changelog

All notable changes to Distraction Log are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). The version shown in the app (Settings) comes from
`$FocusVersion` in `common.ps1`; the tests check that it matches the newest entry below.

## [Unreleased]

## [1.0.0] - 2026-11-06

First public version.

### Added
- Background tracker: records the app and site in front every 5 seconds; time away (2+ minutes idle) is not counted.
- Work / neutral / distracting categories, with a **Sites & apps** window to re-label anything.
- Alerts: continuous distraction, daily distraction limit, daily goal reached, end-of-day summary,
  morning top 3 and Monday weekly review. Clicking a notification opens the matching screen.
- Focus timer with breaks, task names, instant nudges during sessions and a session log.
- Today's top 3 and weekly goals; finished items fade away.
- Dashboards: Overview, Distractions, Sessions, Patterns (heatmaps, 12-week calendar, app switching,
  deep-work blocks) and Weekly review with suggestions.
- Optional site blocker (hosts file, runs as SYSTEM from a protected folder) for focus sessions and set hours.
- CSV export (activity, daily summary, sessions, plans) that opens correctly in Excel, with export history.
- English and Portuguese, switchable live; notifications and the Claude coach follow the language.
- **Ask Claude coach**: a 14-day summary opened in Claude Code for a personal coaching report.
- `setup.ps1` installer and uninstaller, documentation, tests and continuous integration.

[Unreleased]: https://github.com/victor-schote/distraction-log/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/victor-schote/distraction-log/releases/tag/v1.0.0
