# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).
Write new entries under **[Unreleased]**; `build/bump-version.ps1` moves them into the next version.

## [Unreleased]

## [0.4.0] - 2026-11-24

### Changed
- **The project is now called Jahiz** (جاهز, "ready" in Arabic). The repository moved from `Eslam-Nazer/dev-setup` to `Eslam-Nazer/jahiz` (old links redirect). Files and assets were renamed:

  | Before | Now |
  |---|---|
  | `setup.ps1` / `setup.bat` | `jahiz.ps1` / `jahiz.bat` |
  | `env/setup-dev-env.ps1` | `env/jahiz-env.ps1` |
  | `editor/setup-dev-extensions.ps1` | `editor/jahiz-editor.ps1` |
  | `dev-setup-<tool>-vX.Y.Z.zip` | `jahiz-<tool>-vX.Y.Z.zip` |
  | logs in `%LOCALAPPDATA%\dev-setup` | logs in `%LOCALAPPDATA%\jahiz` |

### Removed
- `README.ar.md`: the docs are English only, so there is a single README to keep up to date

## [0.3.0] - 2026-11-23

### Added
- `setup.ps1` / `setup.bat`: one command that runs `env`, then `editor`. Uses the tools from a clone or the same folder, otherwise downloads them from the release matching its own version and verifies them against `SHA256SUMS.txt` before running
- Releases ship `SHA256SUMS.txt`, `setup.ps1` and `setup.bat`
- `env -DryRun` and `editor -DryRun`: check every winget id, official installer, npm package and extension (existence + deprecation) without installing anything
- `editor -Restore`: put `settings.json` / `keybindings.json` back from one of the script's backups
- `editor`: settings sources are now PhpStorm / VS Code / **recommended defaults** (neutral) / **author's preset** (the previous built-in values, now optional)
- `editor`: performance settings, recommended editor settings, PhpStorm-style shortcuts and JetBrains icons are each asked for instead of applied silently
- CI smoke tests on real Windows (`env -CheckOnly`, both dry runs) on every push; weekly catalog check that opens an issue when something is missing or deprecated
- Windows Sandbox test kit (`build/sandbox/`) and `docs/testing.md` checklist
- `README.ar.md` (Arabic), `CONTRIBUTING.md`, `SECURITY.md`, issue templates, example run image

### Fixed
- Package ids found wrong by the first dry run on real Windows: DBeaver (`DBeaver.DBeaver.Community`), Redis Insight (`RedisInsight.RedisInsight`); Composer has no winget package, so its official installer is used (only with a valid Authenticode signature)
- Cursor (Open VSX): NestJS snippets fall back to `imgildev.vscode-nestjs-snippets-extension`; the Poimandres theme (not on Open VSX) leaves the theme unchanged with a warning instead of failing
- `env -DryRun` no longer counts network / rate-limit errors as "missing"

### Changed
- Logs moved to `%LOCALAPPDATA%\dev-setup` (was `dev-ext-installer`)

## [0.2.2] - 2026-11-19

### Fixed
- `env/`: after installing Herd (or when Herd has no PHP yet) the script opens Herd and waits for its first-run setup to download PHP before continuing (Enter stops waiting); for Laragon it opens the app and waits until you add it to PATH

## [0.2.1] - 2026-11-19

### Changed
- Pick-any lists (editors, databases, GUI clients, editor DB extensions) now show every item; installed ones appear in green as `[installed]` and are skipped if picked

## [0.2.0] - 2026-11-19

### Added
- `env/`: checks and installs dev tools (Herd / Laragon / official PHP, Composer, Git, Node.js, NestJS CLI, Docker) with winget, asking before each install
- `env/`: choose the latest version or pick one from the list of available versions
- `env/`: with Herd, PHP versions are managed with `herd php:install` / `herd use` and Node.js with `herd node:install`; otherwise official publishers via winget
- `editor/`: offers to run `env` first when PHP or Node.js is missing (`-SkipEnvCheck` to turn it off)
- `docs/architecture.md` (how the repo is organized, adding a tool), `docs/env/usage.md`
- `env/`: checks for PhpStorm, VS Code and Cursor and offers to install the missing ones (pick any; PhpStorm licence noted)
- `env/`: optional databases, pick any: PostgreSQL (choose the major), MySQL, MariaDB, Redis (Memurai Developer), MongoDB; official installers run interactively so you set the admin password yourself
- `env/`: offers to switch database services to Manual start so they don't use RAM at boot
- `env/`: optional DB GUI clients, pick any: DBeaver, HeidiSQL, pgAdmin, MySQL Workbench, MongoDB Compass, Redis Insight; installed ones are detected first and not offered
- `editor/`: optional database extensions, pick any: Database Client, SQLTools (+ PostgreSQL/MySQL drivers), MongoDB for VS Code
- MIT license

### Changed
- `editor/`: verifies installs by checking the extension folder instead of calling the editor CLI after each one (much less RAM/CPU)
- `editor/`: lighter editor settings: no file watching / search in vendor, node_modules, storage, bootstrap/cache, dist; Jest on demand; GitLens code lens off; Intelephense skips Laravel cache folders
- `editor/`: the Docker extension is installed only when Docker is installed
- Docker Desktop is optional: its question defaults to No and `-Yes` skips it (shows size, WSL 2 and licence notes first)
- Logs: only the 10 newest per tool are kept; settings backups: only the 5 newest per file

### Fixed
- `editor/`: "already installed" detection failed when 0 or 1 extension was installed before the run
- Questions no longer loop forever when console input is closed; summary table prints in narrow / redirected consoles

## [0.1.0] - 2026-11-19

### Added
- `editor/`: one-click Cursor / VS Code setup for Laravel + NestJS
- Registry existence and deprecation checks, with official replacements and fallbacks
- Offline-tolerant retries, resumable runs, install verification
- Settings source choice: PhpStorm, VS Code, or the values saved in the script
- Questions for the color theme and the PHP interpreter (latest or pick a version)
- Double Shift search, breadcrumbs nav bar, new file at path, JetBrains icons, Claude Code
- `-Version` flag, CI checks, `build/bump-version.ps1`
- Automatic releases: a new `$ScriptVersion` on main creates the tag and the GitHub Release
