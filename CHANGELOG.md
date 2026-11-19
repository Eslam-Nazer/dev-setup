# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).
Write new entries under **[Unreleased]**; `build/bump-version.ps1` moves them into the next version.

## [Unreleased]

### Added
- `env/`: checks and installs dev tools (Herd / Laragon / official PHP, Composer, Git, Node.js, NestJS CLI, Docker) with winget, asking before each install
- `env/`: choose the latest version or pick one from the list of available versions
- `env/`: with Herd, PHP versions are managed with `herd php:install` / `herd use` and Node.js with `herd node:install`; otherwise official publishers via winget
- `editor/`: offers to run `env` first when PHP or Node.js is missing (`-SkipEnvCheck` to turn it off)
- `docs/architecture.md` (how the repo is organized, adding a tool), `docs/env/usage.md`
- MIT license

### Changed
- `editor/`: verifies installs by checking the extension folder instead of calling the editor CLI after each one (much less RAM/CPU)
- `editor/`: lighter editor settings: no file watching / search in vendor, node_modules, storage, bootstrap/cache, dist; Jest on demand; GitLens code lens off; Intelephense skips Laravel cache folders
- `editor/`: the Docker extension is installed only when Docker is installed
- Docker Desktop is optional: its question defaults to No and `-Yes` skips it (shows size, WSL 2 and licence notes first)
- Logs: only the 10 newest per tool are kept; settings backups: only the 5 newest per file

### Fixed
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
