# Versions and releases

## Version numbers

One version for the whole repo, [Semantic Versioning](https://semver.org/) `MAJOR.MINOR.PATCH`:

| Change | Bump | Example |
|---|---|---|
| Bug fix, extension id swap, doc fix | PATCH | 0.1.0 → 0.1.1 |
| New tool, new option, new extension, new question | MINOR | 0.1.1 → 0.2.0 |
| A change that breaks how people run it (renamed options, removed tool) | MAJOR | 0.9.0 → 1.0.0 |

While the version starts with `0.`, things can still change. Release `1.0.0` when you are happy for others to rely on it.

Pre-releases: `0.3.0-beta.1`. They are published as GitHub pre-releases and `releases/latest` skips them.

Every tool script carries the version in one line:

```powershell
$ScriptVersion = '0.1.0'
```

`-Version` prints it, and the log shows it at the top.

## Day to day

Add a line under `## [Unreleased]` in `CHANGELOG.md` with each change (`### Added`, `### Changed`, `### Fixed`, `### Removed`).

## Cutting a release

```powershell
.\build\bump-version.ps1 -Version 0.2.0 -Tag
git push --follow-tags
```

`bump-version.ps1` sets `$ScriptVersion` in every tool script, moves the Unreleased notes under `## [0.2.0] - <date>`,
commits `Release v0.2.0` and creates the annotated tag `v0.2.0`. Run it without `-Tag` to only edit the files.

Pushing the tag runs `.github/workflows/release.yml`, which:

1. Fails if any `$ScriptVersion` or the CHANGELOG does not match the tag
2. Runs PSScriptAnalyzer (errors only)
3. Builds `dev-setup-<tool>-v0.2.0.zip` for each tool folder (script + its docs + README + CHANGELOG + LICENSE)
4. Publishes a GitHub Release with those zips, unversioned copies of each script, and the CHANGELOG section as notes

If the workflow fails, fix the problem, then move the tag:

```powershell
git tag -d v0.2.0; git push origin :refs/tags/v0.2.0
git tag -a v0.2.0 -m v0.2.0; git push --follow-tags
```

## How people download it

- Latest release page: `https://github.com/Eslam-Nazer/dev-setup/releases/latest`
- A fixed link to the newest script (never changes between versions):
  `https://github.com/Eslam-Nazer/dev-setup/releases/latest/download/setup-dev-extensions.ps1`
- A specific version: `https://github.com/Eslam-Nazer/dev-setup/releases/download/v0.1.0/dev-setup-editor-v0.1.0.zip`

These links only work once the repo is public, or for people who have access to it.
