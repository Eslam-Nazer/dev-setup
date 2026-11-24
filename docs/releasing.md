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
.\build\bump-version.ps1 -Version 0.2.0 -Commit
git push
```

`bump-version.ps1` sets `$ScriptVersion` in every tool script, moves the Unreleased notes under `## [0.2.0] - <date>`
and commits `Release v0.2.0`. Run it without `-Commit` to only edit the files.

You never push tags. On every push to `main`, `.github/workflows/release.yml` reads `$ScriptVersion`;
if there is no GitHub Release for that version yet, it:

1. Fails if the tool scripts disagree on the version or the CHANGELOG has no section for it
2. Runs PSScriptAnalyzer (errors only)
3. Builds `jahiz-<tool>-v0.2.0.zip` for each tool folder (script + its docs + README + CHANGELOG + LICENSE)
4. Adds `jahiz.ps1` / `jahiz.bat` and writes `SHA256SUMS.txt` for every asset
5. Creates the tag `v0.2.0` at that commit and publishes the GitHub Release with the zips,
   unversioned copies of each script, `SHA256SUMS.txt`, and the CHANGELOG section as notes

Pushes that do not change the version are skipped, so normal commits never create releases.
You can also run the workflow by hand from the Actions tab, or push a tag `vX.Y.Z` yourself; the tag must match `$ScriptVersion`.

If a release goes wrong, delete it and its tag on GitHub (Releases → the release → Delete, and Tags → delete),
fix the problem, then push again or re-run the workflow.

## How people download it

- Latest release page: `https://github.com/Eslam-Nazer/jahiz/releases/latest`
- A fixed link to the newest script (never changes between versions):
  `https://github.com/Eslam-Nazer/jahiz/releases/latest/download/jahiz-editor.ps1`
- A specific version: `https://github.com/Eslam-Nazer/jahiz/releases/download/v0.1.0/jahiz-editor-v0.1.0.zip`

These links only work once the repo is public, or for people who have access to it.
