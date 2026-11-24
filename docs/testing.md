# Testing

Two layers: automatic checks on every push, and a manual run on a clean Windows before a big release.

## Automatic (GitHub Actions, real Windows)

| When | Workflow | What it checks |
|---|---|---|
| Every push / PR | `ci.yml` → `check` | Every `.ps1` parses in PowerShell 7 **and** Windows PowerShell 5.1; PSScriptAnalyzer (errors); `-Version` works |
| Every push / PR | `ci.yml` → `smoke` | On `windows-latest`: `env -CheckOnly` runs without crashing; `env -DryRun` finds every winget / npm package; `editor -DryRun` finds every extension in Open VSX **and** the VS Code Marketplace, none deprecated; `jahiz.ps1 -Version` |
| Mondays | `catalog-check.yml` | The same dry runs; opens (or comments on) an issue when a package or extension is missing or deprecated |
| Tag / new version on main | `release.yml` | Versions match the tag, CHANGELOG has the section, lint, then packages and publishes |

Nothing is installed on the CI machines: `-CheckOnly` and `-DryRun` only look things up.

## Dry runs on your own PC

Safe to run any time; they install and change nothing:

```powershell
.\env\jahiz-env.ps1 -CheckOnly          # what is installed / missing here
.\jahiz.ps1 -DryRun -Target both            # are all packages and extensions still available?
```

`env -DryRun` exit codes: `0` all available, `2` something missing, `3` some lookups could not be checked (network).

## Manual test on a clean Windows (Windows Sandbox)

[Windows Sandbox](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview)
is a throw-away Windows built into Windows 10/11 Pro, Enterprise and Education.
It starts in seconds, is wiped when you close it, and does not touch your own setup.
It uses RAM only while it is open (the script caps it at 4 GB; change with `-MemoryMB`).

1. Enable it once (admin PowerShell, then restart Windows):
   `Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All`
2. From the repo: `.\build\sandbox\start-sandbox.ps1`
   - Maps the repo **read-only** at `C:\jahiz`
   - Installs winget inside the sandbox (it has none) the official way: `Microsoft.WinGet.Client` → `Repair-WinGetPackageManager`
3. Run the checklist below inside the sandbox, then copy `%LOCALAPPDATA%\jahiz\*.log` out before closing.

### Checklist

| # | Run | Expect |
|---|---|---|
| 1 | `C:\jahiz\env\jahiz-env.ps1 -CheckOnly` | Lists what is missing; installs nothing; exit code 1 (no PHP/Node yet) |
| 2 | `C:\jahiz\jahiz.ps1 -DryRun -Target both` | All `[OK]`; exit code 0 |
| 3 | `C:\jahiz\jahiz.ps1` → PHP environment: **Herd** | Herd installs silently, then Herd opens and the script **waits** until PHP appears, then continues |
| 4 | Herd PHP versions: install another | `herd php:install` runs; new version listed |
| 5 | Node.js | Installed through Herd (`herd node:install`), version picked from the list |
| 6 | Git, NestJS CLI | Version question (latest or list), installed and verified |
| 7 | Docker | Question defaults to **No** |
| 8 | Editors: pick VS Code | Installed; already-present editors show `[installed]` |
| 9 | Databases: pick PostgreSQL | Official installer window opens; you set the password; script waits for Finish; offers **Manual** start (one UAC prompt) |
| 10 | GUI clients: pick DBeaver | Installed; picking an installed one says "already installed" |
| 11 | Editor tool (VS Code), source **Recommended** | Theme and layout unchanged; questions for performance / preferences / shortcuts / icons |
| 12 | Database extension: pick Database Client | Installed |
| 13 | Run `jahiz.ps1` again | Everything reported as present / already installed; nothing re-installed |
| 14 | `C:\jahiz\editor\jahiz-editor.ps1 -Restore -Target code` | Lists backups; restores the chosen one |
| 15 | Laragon path (new sandbox) | Laragon opens; script waits until you add it to PATH |
| 16 | Official PHP path (new sandbox) | PHP from php.net via winget, version picked; Composer offered next |

Report problems with the bug report template and attach the log.
