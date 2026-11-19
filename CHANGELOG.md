# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).
Write new entries under **[Unreleased]**; `build/bump-version.ps1` moves them into the next version.

## [Unreleased]

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
