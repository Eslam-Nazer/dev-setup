# Usage

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\editor\setup-dev-extensions.ps1 [options]
```

| Option | Values | Meaning |
|---|---|---|
| `-Target` | `cursor`, `code`, `both` | Which editor to set up. Asked if omitted. |
| `-Source` | `phpstorm`, `vscode`, `builtin` | Where settings come from. Asked if omitted. |
| `-Yes` | switch | Accept every default, ask nothing. |
| `-SkipSettings` | switch | Install extensions only; leave settings and shortcuts alone. |
| `-MaxRetries` | number (default 8) | Retries per network step. |
| `-SkipEnvCheck` | switch | Do not check for PHP / Node.js or offer to run the env tool. |
| `-Version` | switch | Print the version and exit. |

Examples:

```powershell
# Cursor, settings from PhpStorm, no questions
.\editor\setup-dev-extensions.ps1 -Target cursor -Source phpstorm -Yes

# Extensions only, both editors
.\editor\setup-dev-extensions.ps1 -Target both -SkipSettings
```

## Dev tools check

Before installing anything, the script checks that `php` and `node` are on PATH.
If one is missing it asks "Run the dev tools setup (env) first?" (default yes).

- It finds the env tool at `..\env\setup-dev-env.ps1` (clone), in the same folder, or downloads it from the latest release.
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
- **Saved values**: the `$SavedDefaults` block in the script. Works on a PC without PhpStorm.

## PHP interpreter

Candidates come from PhpStorm, Herd (`%USERPROFILE%\.config\herd\bin\php*`) and `php.exe` on PATH.
Each one is run once to read its real version. You choose the latest or pick from the list.

## Safety

- `settings.json` and `keybindings.json` are backed up as `*.bak-YYYYMMDD-HHMMSS` before any change.
- Log: `%LOCALAPPDATA%\dev-ext-installer\install-*.log`.
- Re-running is safe: installed extensions are skipped and duplicate shortcuts are not added.
