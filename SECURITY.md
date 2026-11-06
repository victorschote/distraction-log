# Security policy

## Supported versions

Only the latest release gets fixes.

## Reporting a problem

Please do **not** open a public issue for security problems. Contact the maintainer privately
through GitHub ([@victor-schote](https://github.com/victor-schote)) or, if the repository is public,
use **Security > Report a vulnerability** on the repository page. You can expect an answer within a week.

## How Distraction Log handles risk

- **No network.** The app and tracker never send data anywhere. The only exception is
  **Ask Claude coach**, which you start yourself and which sends a summary (`coach-data.md`) to Claude.
- **Sensitive data stays local.** The activity log contains window titles (document names, email
  subjects, page titles). It is kept in the app folder and is excluded from git. Exports can leave titles out.
- **Least privilege.** Everything runs as the signed-in user except the optional site blocker.
- **The site blocker** runs as SYSTEM because it edits the `hosts` file. To keep that safe:
  - the copy that runs lives in `C:\ProgramData\DistractionLog`, where only SYSTEM and Administrators can write;
  - it only *reads* `settings.json` and `focus.json` from the user folder, as data;
  - it only writes its own fixed list of domains between marker lines in `hosts`;
  - installing or updating it needs an explicit admin approval.
- **CSV export** prefixes text that starts with `=`, `+`, `-` or `@`, so Excel does not run it as a formula.
- **Notification links** (`distractionlog:`) only accept letters and only switch screens in the app.
