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
| `-DryRun` | switch | Check that every package id / installer / npm package is still available; install nothing (see [Dry run](#dry-run)). |
| `-Yes` | switch | Accept every default: installs everything missing except optional tools (Docker, editors, databases, GUI clients), Herd for PHP, latest versions. |
| `-MaxRetries` | number (default 4) | Retries per network step. |
| `-Version` | switch | Print the version and exit. |

Examples:

```powershell
# See what is missing, change nothing
.\env\setup-dev-env.ps1 -CheckOnly

# Install everything missing with defaults, no questions
.\env\setup-dev-env.ps1 -Yes

# Is the catalogue still valid? (installs nothing)
.\env\setup-dev-env.ps1 -DryRun
```

## What it checks, in order

| # | Tool | How it is detected | How it is installed | Notes |
|---|---|---|---|---|
| 1 | PHP environment | Herd (`Herd.exe` or `~\.config\herd\bin`), Laragon (`laragon.exe` in `C:\laragon`, `D:\laragon`, `~\laragon`) | winget: `BeyondCode.Herd` / `Laravel.Herd`, `LeNgocKhoa.Laragon`, or official PHP | You pick **one** (see below). Warns if both are installed. |
| 2 | PHP versions | Herd's `php*` folders | `herd php:install <ver>` | Only when Herd is installed or chosen. |
| 3 | PHP | `php --version` | Comes with Herd / Laragon / official PHP | Not installed on its own. |
| 4 | Composer | `composer --version` | Official `Composer-Setup.exe` from getcomposer.org (no winget package exists); its Authenticode signature must be valid before it runs | Comes with Herd / Laragon. Needs PHP first. |
| 5 | Git | `git --version` | winget `Git.Git` | |
| 6 | Node.js (+npm) | `node --version` | `herd node:install` with Herd, otherwise winget `OpenJS.NodeJS.LTS` | |
| 7 | NestJS CLI | `nest --version` | `npm install -g @nestjs/cli` | Needs Node.js first. |
| 8 | Docker Desktop | `docker --version` | winget `Docker.DockerDesktop` | **Optional** (question defaults to No, `-Yes` skips it): ~1 GB, needs WSL 2, free for personal use and small companies only. Restart Windows afterwards. |
| 9 | Editors | usual install folders (incl. JetBrains Toolbox for PhpStorm), then the `code` / `cursor` command, then `winget list` | winget `JetBrains.PhpStorm`, `Microsoft.VisualStudioCode`, `Anysphere.Cursor` | **Optional**, pick any (see [Editors](#editors)). |
| 10 | Databases | Windows service (`postgresql*`, `MySQL*`, `MariaDB*`, `Memurai*`, `MongoDB*`) | official installer via winget, **interactive** | **Optional**, pick any (see [Databases](#databases)). |
| 11 | DB GUI clients | `winget list` (programs already on the PC) | winget | **Optional**, pick any. |

## Choosing the PHP environment

If neither Herd nor Laragon is found, it asks:

1. **Laravel Herd** (recommended): PHP, Composer, Laravel installer, Node via nvm
2. **Laragon**: PHP, Apache/Nginx, MySQL in one place
3. **Official PHP**: the php.net build via winget (`PHP.PHP.<major.minor>`, for example `PHP.PHP.8.4`); Composer is installed next
4. **Skip**

Choose only one. Herd and Laragon both put their own PHP first in PATH, so having both makes it unclear which `php` runs.

## Dry run

`-DryRun` checks the whole catalogue without installing anything: every winget id (with `winget` when it is
installed, otherwise in the [winget-pkgs](https://github.com/microsoft/winget-pkgs) repository), the official
installer URLs (Composer), and the npm packages (also flagged when deprecated).
Exit code `0` = all available, `2` = something is missing, `3` = some lookups could not be checked.
CI runs it on real Windows on every push and every Monday (see [Testing](../testing.md)).

## Editors

The tool checks for **PhpStorm**, **VS Code** and **Cursor** before downloading anything. All three are listed; the ones
already on the PC are shown in green as `[installed]` (with their version), and picking one of those just says it is already installed.
Pick any number (`1,2`), or press Enter for none. `-Yes` installs none (editors are large). You also pick the version.

| Editor | winget package | Detected at | Cost |
|---|---|---|---|
| PhpStorm | `JetBrains.PhpStorm` | `Program Files\JetBrains\PhpStorm*`, `%LOCALAPPDATA%\Programs\PhpStorm*`, JetBrains Toolbox apps | Paid: 30-day trial, free for students and open-source projects |
| VS Code | `Microsoft.VisualStudioCode` | `%LOCALAPPDATA%\Programs\Microsoft VS Code`, `Program Files\Microsoft VS Code`, `code` | Free |
| Cursor | `Anysphere.Cursor` | `%LOCALAPPDATA%\Programs\cursor`, `cursor` | Free to install; AI features have free-plan limits |

After installing VS Code or Cursor, run the editor tool to add the extensions and settings.
Edit the list in `$EditorApps` (`Name`, `Winget`, `Paths`, optional `Cmd`, `Warning`, `Url`).

## Databases

Everything is checked **before** anything is downloaded: a database counts as installed when its Windows service exists,
and a GUI client when `winget list` finds it. Every item is listed; installed ones are shown in green as `[installed]`
and are skipped if you pick them.

You pick any number from a list (`1,3`), or press Enter for none. `-Yes` installs none (databases are heavy).

| Database | winget package | Service | Notes |
|---|---|---|---|
| PostgreSQL | `PostgreSQL.PostgreSQL.<major>` (18, 17, 16, 15: the ones winget has are offered) | `postgresql-x64-<major>` | You pick the major version |
| MySQL Community Server | `Oracle.MySQL` | `MySQL<nn>` | Version from the winget list |
| MariaDB Server | `MariaDB.Server` | `MariaDB` | Version from the winget list |
| Redis | `Memurai.MemuraiDeveloper` | `Memurai` | Redis has no official Windows build; Memurai Developer is a free Redis-compatible server for development (check its licence) |
| MongoDB Community Server | `MongoDB.Server` | `MongoDB` | Version from the winget list |

- **Installers run interactively** (`winget --interactive`): the product's own setup window opens, so **you** choose the
  admin / root password there. The script never sees or stores it.
- **Lighter on the machine:** database services normally start with Windows and keep using memory. After installing,
  the script lists the services set to *Automatic* and offers to switch them to **Manual** (one UAC prompt).
  Start one when you need it, from an admin terminal: `net start <service>`; stop it with `net stop <service>`
  (or use `services.msc`).

GUI clients you can pick (any or none):

| Client | winget package | Works with |
|---|---|---|
| DBeaver Community | `DBeaver.DBeaver.Community` (fallback `dbeaver.dbeaver`) | all of the above |
| HeidiSQL | `HeidiSQL.HeidiSQL` | MySQL, MariaDB, PostgreSQL |
| pgAdmin 4 | `PostgreSQL.pgAdmin` | PostgreSQL |
| MySQL Workbench | `Oracle.MySQLWorkbench` | MySQL |
| MongoDB Compass | `MongoDB.Compass.Full` (fallback `MongoDB.Compass.Community`) | MongoDB |
| Redis Insight | `RedisInsight.RedisInsight` | Redis / Memurai |

For a database extension inside the editor instead of (or as well as) a separate app, see the editor tool.

## Waiting for installers and first-run setup

- **Installers:** `winget` waits until the installer has finished before the script continues, both for silent
  installs and for interactive ones (where you click Next → Finish, e.g. databases). If an installer closes early and
  keeps working in the background, the check after the install reports it as "not detected yet" instead of "installed".
- **Herd:** its installer only installs the app; PHP is downloaded the first time Herd is opened. After installing Herd
  (or when Herd is installed but has no PHP yet), the script opens Herd and **waits** until PHP appears (up to 10 minutes,
  `$HerdWaitSeconds`), then continues. Press Enter to stop waiting.
- **Laragon:** the script opens Laragon and waits for you to choose *Menu > Tools > Path > Add Laragon to Path*, then press Enter.

## Herd path

Used **only** when Herd is installed or you chose it:

| Task | Command |
|---|---|
| List available PHP versions | `herd php:list` |
| Install a PHP version | `herd php:install <version>` |
| Set the global PHP version | `herd use <version>` |
| Install Node.js | `herd node:install <version or lts>` (Herd ships nvm; falls back to `nvm install` if it fails) |

Without Herd, every tool comes from its official publisher through winget
(`OpenJS.NodeJS.LTS`, `Git.Git`, `Docker.DockerDesktop`), and Composer from its official installer.

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

`%LOCALAPPDATA%\dev-setup\env-YYYYMMDD-HHMMSS.log`. A summary table is printed at the end.

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

- Databases: `$Databases` (`Name`, `Winget` or `Lines` + `IdFormat`, `Service` pattern, `Url`, optional `Warning`).
  Add a new PostgreSQL major to its `Lines` when it ships.
- GUI clients: `$DbClients` (`Name`, `Winget`, `Url`).


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
