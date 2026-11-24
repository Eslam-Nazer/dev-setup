# Usage

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\editor\jahiz-editor.ps1 [options]
```

| Option | Values | Meaning |
|---|---|---|
| `-Target` | `cursor`, `code`, `both` | Which editor to set up. Asked if omitted. |
| `-Source` | `phpstorm`, `vscode`, `recommended`, `author` | Where settings come from. Asked if omitted. (`builtin` still works as `author`.) |
| `-Yes` | switch | Accept every default, ask nothing. |
| `-SkipSettings` | switch | Install extensions only; leave settings and shortcuts alone. |
| `-MaxRetries` | number (default 8) | Retries per network step. |
| `-SkipEnvCheck` | switch | Do not check for PHP / Node.js or offer to run the env tool. |
| `-DryRun` | switch | Check every extension (exists, not deprecated) in Open VSX / Marketplace; install and change nothing. Exit `0` ok, `2` missing. |
| `-Restore` | switch | Put `settings.json` / `keybindings.json` back from one of the backups this script made (you pick which). |
| `-Version` | switch | Print the version and exit. |

Examples:

```powershell
# Cursor, settings from PhpStorm, no questions
.\editor\jahiz-editor.ps1 -Target cursor -Source phpstorm -Yes

# Extensions only, both editors
.\editor\jahiz-editor.ps1 -Target both -SkipSettings

# Check the catalogue without installing anything
.\editor\jahiz-editor.ps1 -DryRun -Target both

# Undo the settings changes
.\editor\jahiz-editor.ps1 -Restore -Target cursor
```

## Dev tools check

Before installing anything, the script checks that `php` and `node` are on PATH.
If one is missing it asks "Run the dev tools setup (env) first?" (default yes).

- It finds the env tool at `..\env\jahiz-env.ps1` (clone), in the same folder, or downloads it from the latest release.
- `env` exit code 0 means PHP and Node.js are available. The editor refreshes PATH and continues.
  If something is still missing it warns and carries on.
- Answer no, or pass `-SkipEnvCheck`, to skip it.

See [How this repo is organized](../architecture.md) and the [env tool](../env/usage.md).

## Settings sources

- **PhpStorm**: reads the newest `%APPDATA%\JetBrains\PhpStorm*` folder at run time: active keymap and its parent,
  custom shortcuts, color scheme, UI density, smooth caret, registered PHP interpreters.
  If the keymap is VS Code-based, native VS Code shortcuts are kept; otherwise the IntelliJ keymap extension is installed.
- **VS Code**: copies `settings.json` and `keybindings.json` from VS Code into Cursor, and installs the extension
  that provides your VS Code theme.
- **Recommended defaults**: neutral. No theme change, VS Code keymap, no layout changes. Works on any PC.
- **Author's preset**: the author's own setup (poimandres theme, compact tabs, smooth caret, `Ctrl+Space` terminal completion).
  Optional; pick it only if you like that look.

## Opinionated settings are asked, not forced

After the source, the script asks (default yes for each, `-Yes` accepts all):

| Question | What it changes |
|---|---|
| Performance settings | See [Performance settings](#performance-settings) |
| Recommended editor settings | Pint as PHP formatter, Prettier for TS/JS/JSON/Vue, Intelephense as the PHP engine, breadcrumbs nav bar, command center, auto save on focus change, linked tag editing |
| PhpStorm-style shortcuts | `Shift Shift` = search, `Alt+Home` = nav bar, `Ctrl+Alt+N` = new file at path |
| JetBrains-style file icons | Installs the icon theme and selects it |

Answer no to keep your editor exactly as it is in that area.

## PHP interpreter

Candidates come from PhpStorm, Herd (`%USERPROFILE%\.config\herd\bin\php*`) and `php.exe` on PATH.
Each one is run once to read its real version. You choose the latest or pick from the list.

## Safety

- `settings.json` and `keybindings.json` are backed up as `*.bak-YYYYMMDD-HHMMSS` before any change.
- `-Restore` lists the backups (newest first) and puts the chosen one back; the current file is kept as `*.before-restore-*`.
  Extensions are not removed.
- Log: `%LOCALAPPDATA%\jahiz\install-*.log`.
- Re-running is safe: installed extensions are skipped and duplicate shortcuts are not added.

## Performance settings

To keep the editor light in Laravel / NestJS projects, the script adds these (your existing entries are kept):

| Setting | Value | Why |
|---|---|---|
| `files.watcherExclude` | `vendor`, `node_modules`, `storage`, `bootstrap/cache`, `dist`, `.git/objects` | No file watching in dependency/cache folders |
| `search.exclude` | `vendor`, `node_modules`, `storage`, `bootstrap/cache`, `dist` | Faster search. Toggle *Use Exclude Settings* in the search panel to search them anyway |
| `intelephense.files.exclude` | defaults + `storage`, `bootstrap/cache` | `vendor` stays indexed for completion; its tests do not |
| `jest.runMode` | `on-demand` | Tests run when you ask, not on every save |
| `gitlens.codeLens.enabled` | `false` | Fewer git calls while typing |

The Docker extension is installed only when `docker` is available on the PC.

## Database extensions

Before installing, the script asks which database extension to add (pick any or none; `-Yes` picks none).
Extensions already installed are marked `[installed]` and are skipped.

| Choice | Extensions | Works with |
|---|---|---|
| Database Client | `cweijan.vscode-database-client2` | MySQL, MariaDB, PostgreSQL, SQLite, Redis, MongoDB in one panel |
| SQLTools | `mtxr.sqltools` + `mtxr.sqltools-driver-pg` + `mtxr.sqltools-driver-mysql` | PostgreSQL, MySQL, MariaDB |
| MongoDB for VS Code | `mongodb.mongodb-vscode` | MongoDB |

To install the database servers and GUI clients themselves, use the env tool (`env/jahiz-env.ps1`).
Edit the list in `$DbExtensionChoices`.
