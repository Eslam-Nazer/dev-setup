# Env tool: usage

`env/setup-dev-env.ps1` checks the dev tools a Laravel + NestJS machine needs and installs the missing ones.
It asks before every install.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\env\setup-dev-env.ps1 [options]
```

Or double-click the `.bat` launcher in `env\`.

| Option | Values | Meaning |
|---|---|---|
| `-CheckOnly` | switch | Report what is installed or missing; install nothing. |
| `-Yes` | switch | Accept every default: installs everything missing except optional heavy tools (Docker), Herd for PHP, latest versions. |
| `-MaxRetries` | number (default 4) | Retries per network step. |
| `-Version` | switch | Print the version and exit. |

Examples:

```powershell
# See what is missing, change nothing
.\env\setup-dev-env.ps1 -CheckOnly

# Install everything missing with defaults, no questions
.\env\setup-dev-env.ps1 -Yes
```

## What it checks, in order

| # | Tool | How it is detected | How it is installed | Notes |
|---|---|---|---|---|
| 1 | PHP environment | Herd (`Herd.exe` or `~\.config\herd\bin`), Laragon (`laragon.exe` in `C:\laragon`, `D:\laragon`, `~\laragon`) | winget: `BeyondCode.Herd` / `Laravel.Herd`, `LeNgocKhoa.Laragon`, or official PHP | You pick **one** (see below). Warns if both are installed. |
| 2 | PHP versions | Herd's `php*` folders | `herd php:install <ver>` | Only when Herd is installed or chosen. |
| 3 | PHP | `php --version` | Comes with Herd / Laragon / official PHP | Not installed on its own. |
| 4 | Composer | `composer --version` | winget `Composer.Composer` | Comes with Herd / Laragon. Needs PHP first. |
| 5 | Git | `git --version` | winget `Git.Git` | |
| 6 | Node.js (+npm) | `node --version` | `herd node:install` with Herd, otherwise winget `OpenJS.NodeJS.LTS` | |
| 7 | NestJS CLI | `nest --version` | `npm install -g @nestjs/cli` | Needs Node.js first. |
| 8 | Docker Desktop | `docker --version` | winget `Docker.DockerDesktop` | **Optional** (question defaults to No, `-Yes` skips it): ~1 GB, needs WSL 2, free for personal use and small companies only. Restart Windows afterwards. |

## Choosing the PHP environment

If neither Herd nor Laragon is found, it asks:

1. **Laravel Herd** (recommended): PHP, Composer, Laravel installer, Node via nvm
2. **Laragon**: PHP, Apache/Nginx, MySQL in one place
3. **Official PHP**: the php.net build via winget (`PHP.PHP.<major.minor>`, for example `PHP.PHP.8.4`); Composer is installed next
4. **Skip**

Choose only one. Herd and Laragon both put their own PHP first in PATH, so having both makes it unclear which `php` runs.

## Herd path

Used **only** when Herd is installed or you chose it:

| Task | Command |
|---|---|
| List available PHP versions | `herd php:list` |
| Install a PHP version | `herd php:install <version>` |
| Set the global PHP version | `herd use <version>` |
| Install Node.js | `herd node:install <version or lts>` (Herd ships nvm; falls back to `nvm install` if it fails) |

Without Herd, every tool comes from its official publisher through winget
(`OpenJS.NodeJS.LTS`, `Git.Git`, `Docker.DockerDesktop`, `Composer.Composer`).

## Version choice

For each install it asks "Install the latest X?". Answer no to pick from a list (newest first, up to 15):

| Tool | Where the list comes from |
|---|---|
| winget tools | `winget show --id <id> --versions` |
| npm tools (NestJS CLI) | `npm view <package> versions` (stable only) |
| Node.js with Herd | LTS lines from nodejs.org (newest release of each line) |
| Official PHP | Lines in `$OfficialPhpLines` that exist on winget |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | PHP and Node.js are both available at the end |
| 1 | PHP or Node.js is still missing |

Other tools read this code (the editor tool runs env when PHP or Node.js is missing).

## Logs

`%LOCALAPPDATA%\dev-ext-installer\env-YYYYMMDD-HHMMSS.log`. A summary table is printed at the end.

## Troubleshooting

| Problem | Fix |
|---|---|
| `winget` not found | Install **App Installer** from the Microsoft Store. Until then the script runs in report-only mode. |
| Tool installed but not found | Open a new terminal. For Herd, open the Herd app once so it finishes setup and adds PHP to PATH. |
| Laragon: `php` not found | Open Laragon, then **Menu > Tools > Path > Add Laragon to Path**. |
| Docker does not start | Docker Desktop needs WSL 2 / virtualization. Restart Windows, then open Docker Desktop once. |
| `herd` command fails | Make sure the Herd app is running. |
| Network drops | The script waits for the internet and retries; raise `-MaxRetries` if needed. |

## Customizing

All the data is at the top of `setup-dev-env.ps1`.

**`$PhpEnvs`**: the choices for step 1 (Herd, Laragon). Fields: `Key`, `Name`, `Detect`, `Winget`, `Url`.

**`$Tools`**: the catalogue for steps 3 to 8. Fields:

| Field | Meaning |
|---|---|
| `Key` | Short id used by `Needs` |
| `Name` | Display name |
| `Detect` | Script block returning an object with `Version` and `Path`, or `$null` |
| `Winget` | winget package ids, tried in order; the first that exists is used |
| `Npm` | Global npm package (used instead of winget) |
| `Needs` | `Key` of a tool that must be present first |
| `Url` | Manual download page, shown when it cannot be installed |
| `Note` | Message shown after installing |

**`$OfficialPhpLines`**: PHP lines offered for the official build, newest first (for example `'8.5', '8.4', '8.3', '8.2'`).
Add a new line here when PHP releases one and winget has `PHP.PHP.<line>`.
