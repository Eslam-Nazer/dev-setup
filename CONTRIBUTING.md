# Contributing

Thanks for helping. This repo is a set of PowerShell scripts that set up a Windows dev machine for Laravel + NestJS.

## Report a bug

Open an issue with the **bug report template** and attach the log from `%LOCALAPPDATA%\jahiz` (the newest `env-*.log` / `install-*.log`). Logs contain no secrets, but have a quick look before attaching.

## Propose a package or extension

Open an issue and include:

- the **winget id** (for packages), e.g. `Git.Git`, or the **extension id** (`publisher.name`) and where it is published (Open VSX and/or VS Code Marketplace);
- why Laravel / NestJS developers would want it;
- whether it is heavy (then it must be opt-in, default No).

## Development setup

- Windows 10/11.
- Test on **both** Windows PowerShell 5.1 and PowerShell 7. Every `.ps1` must parse on both (CI checks this).
- Scripts are self-contained: no dot-sourcing of shared files, so each one can be downloaded and run alone.

## Conventions every tool follows

Full table: [docs/architecture.md](docs/architecture.md#conventions-every-tool-follows). In short:

- **Check first:** detect what is already installed before downloading anything.
- **Ask before installing:** every question has a default (Enter accepts it). Nothing is installed without consent, except with `-Yes`.
- **Flags:** `-Yes` accepts defaults; `-DryRun` checks availability and changes nothing; `-Version` prints the version.
- **`$ScriptVersion`:** one `$ScriptVersion = 'X.Y.Z'` line near the top, the same value in every tool (`build/bump-version.ps1` updates them).
- **Logs:** written to `%LOCALAPPDATA%\jahiz\`; only the newest are kept.
- **Light on the machine:** heavy optional tools default to No; verify cheaply (files/services, not extra processes).
- **Self-contained scripts:** copy the shared helpers rather than depending on another file.

## Code style

- ASCII output only (no emoji or fancy characters in console messages).
- Print with the `Log` / `Ok` / `Warn` helpers, not bare `Write-Host`.
- No secrets in logs.
- Never handle passwords. Installers (for example databases) ask the user directly.

## Before opening a pull request

Run, from the repo root:

```powershell
.\env\jahiz-env.ps1 -DryRun
.\editor\jahiz-editor.ps1 -DryRun -Target both
```

If you can, also run the Windows Sandbox checklist in [docs/testing.md](docs/testing.md).

Then:

- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
- Update the docs for any behavior change (and the Tools table in `README.md` if relevant).

## Adding a new tool

Follow [docs/architecture.md](docs/architecture.md#adding-a-new-tool).

## Releases

Releases are done by the maintainer. See [docs/releasing.md](docs/releasing.md). Please do not bump versions in a PR.
