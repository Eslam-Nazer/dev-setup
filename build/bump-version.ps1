<#
  build/bump-version.ps1
  Prepare a release: sets $ScriptVersion in every tool script, turns the
  "## [Unreleased]" part of CHANGELOG.md into "## [X.Y.Z] - date",
  and (with -Commit) commits "Release vX.Y.Z".

  Usage (from the repo root):
    .\build\bump-version.ps1 -Version 0.2.0               # edit files only
    .\build\bump-version.ps1 -Version 0.2.0 -Commit       # edit + commit
    .\build\bump-version.ps1 -Version 0.3.0-beta.1 -Commit   # pre-release

  Then publish:  git push
  The Release workflow sees the new version on main, creates tag vX.Y.Z and the GitHub Release.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$Commit
)
$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z\.-]+)?$') {
    throw "Version '$Version' is not semantic (expected X.Y.Z or X.Y.Z-suffix)."
}
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($Commit) {
    $dirty = git status --porcelain
    if ($dirty) { throw "Working tree has uncommitted changes. Commit them first, then run with -Commit." }
}
git fetch --tags --quiet 2>$null
if (git tag --list "v$Version") { throw "Version $Version was already released (tag v$Version exists)." }

$utf8 = New-Object System.Text.UTF8Encoding($false)

# 1) $ScriptVersion in every tool script (not build/ or .github/)
$changed = @()
Get-ChildItem -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '[\\/](build|\.github)[\\/]' } | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName)
    $new = [regex]::Replace($text, "(?m)^(\`$ScriptVersion\s*=\s*')[^']*(')", "`${1}$Version`${2}")
    if ($new -ne $text) {
        [IO.File]::WriteAllText($_.FullName, $new, $utf8)
        $changed += $_.FullName.Substring($root.Length + 1)
    }
}
if (-not $changed) { Write-Warning 'No $ScriptVersion line was changed (already at this version?).' }
$changed | ForEach-Object { Write-Host "  version -> $Version : $_" -ForegroundColor Green }

# 2) CHANGELOG: move Unreleased notes under the new version
$cl = Join-Path $root 'CHANGELOG.md'
$text = [IO.File]::ReadAllText($cl)
if ($text -match "(?m)^## \[$([regex]::Escape($Version))\]") {
    Write-Host "  CHANGELOG already has [$Version]" -ForegroundColor Yellow
} elseif ($text -match '(?m)^## \[Unreleased\]') {
    $date = Get-Date -Format 'yyyy-MM-dd'
    $text = [regex]::Replace($text, '(?m)^## \[Unreleased\][^\r\n]*', "## [Unreleased]`n`n## [$Version] - $date", 1)
    [IO.File]::WriteAllText($cl, $text, $utf8)
    Write-Host "  CHANGELOG: [Unreleased] -> [$Version] - $date" -ForegroundColor Green
} else {
    throw "CHANGELOG.md has no '## [Unreleased]' section."
}

if ($Commit) {
    git add -A
    git commit -m "Release v$Version"
    Write-Host "`nCommitted 'Release v$Version'. Publish with:  git push" -ForegroundColor Cyan
} else {
    Write-Host "`nReview the changes, then:  git commit -am 'Release v$Version'; git push" -ForegroundColor Cyan
}
Write-Host "The Release workflow will create tag v$Version and the GitHub Release." -ForegroundColor Cyan
