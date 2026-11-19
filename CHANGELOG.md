# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).
Write new entries under **[Unreleased]**; `build/bump-version.ps1` moves them into the next version.

## [Unreleased]

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
