# dev-setup

[![Release](https://img.shields.io/github/v/release/Eslam-Nazer/dev-setup?sort=semver)](https://github.com/Eslam-Nazer/dev-setup/releases/latest)
[![CI](https://github.com/Eslam-Nazer/dev-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/Eslam-Nazer/dev-setup/actions/workflows/ci.yml)

Scripts to set up a Windows dev machine for **Laravel + NestJS** (PHP / TypeScript).

| Tool | What it does |
|---|---|
| [`editor/`](editor/) | One-click Cursor / VS Code setup with a PhpStorm feel |

## Download

**Newest version, one command** (PowerShell):

```powershell
irm https://github.com/Eslam-Nazer/dev-setup/releases/latest/download/setup-dev-extensions.ps1 -OutFile setup-dev-extensions.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-dev-extensions.ps1
```

**Or** grab `dev-setup-editor-vX.Y.Z.zip` from the [latest release](https://github.com/Eslam-Nazer/dev-setup/releases/latest),
unzip it and double-click `setup-dev-extensions.bat`.

Check which version you have:

```powershell
.\setup-dev-extensions.ps1 -Version
```

---

## Editor setup (`editor/`)

### Quick start (from a clone)

1. Clone this repo on Windows.
2. Double-click `editor\setup-dev-extensions.bat`.
3. Answer the questions (press Enter for the default).
4. Restart the editor.

Or from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\editor\setup-dev-extensions.ps1
```

### What it asks

1. Install into Cursor, VS Code, or both
2. Where to take settings from: PhpStorm on this PC, VS Code on this PC, or the values saved in the script
3. Whether to change the color theme
4. Whether to set the PHP interpreter, and whether to use the latest PHP found or pick a version

### Features

- Checks each extension exists (Open VSX for Cursor, Marketplace for VS Code)
- Skips deprecated extensions, follows the official replacement, falls back to alternatives
- Survives internet drops (waits and retries) and is resumable (skips what is installed)
- Verifies every install
- Copies keymap, custom shortcuts, theme, compact UI, smooth caret and PHP interpreter from the chosen source
- Double Shift = search, Alt+Home = breadcrumbs nav bar, Ctrl+Alt+N = new file at any path
- JetBrains-style file icons, Claude Code extension
- Backs up `settings.json` and `keybindings.json` before changing them

### Docs

- [Usage and options](docs/editor/usage.md)
- [Customizing the script](docs/editor/customize.md)
- [Extensions installed](docs/editor/extensions.md)

### Requirements

- Windows 10/11, PowerShell 5.1+
- Cursor and/or VS Code with its CLI in PATH (`cursor` / `code`).
  If missing: open the editor → `Ctrl+Shift+P` → *Install 'cursor' command in PATH*.

---

## Versions and releases

- [Changelog](CHANGELOG.md)
- [How versions and releases work](docs/releasing.md): `.\build\bump-version.ps1 -Version X.Y.Z -Commit` then `git push` (the workflow tags and releases)
