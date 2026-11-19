# dev-setup

Scripts to set up a Windows dev machine for **Laravel + NestJS** (PHP / TypeScript).

| Tool | What it does |
|---|---|
| [`editor/`](editor/) | One-click Cursor / VS Code setup with a PhpStorm feel |

---

## Editor setup (`editor/`)

### Quick start

1. Clone or download this repo on Windows.
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
- [Changelog](CHANGELOG.md)

### Requirements

- Windows 10/11, PowerShell 5.1+
- Cursor and/or VS Code with its CLI in PATH (`cursor` / `code`).
  If missing: open the editor → `Ctrl+Shift+P` → *Install 'cursor' command in PATH*.
