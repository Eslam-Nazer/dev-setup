<#
  build/bump-version.ps1
  Prepare a release: sets $ScriptVersion in every tool script, turns the
  "## [Unreleased]" part of CHANGELOG.md into "## [X.Y.Z] - date",
  and (with -Tag) commits and creates the annotated git tag vX.Y.Z.

  Usage (from the repo root):
    .\build\bump-version.ps1 -Version 0.2.0            # edit files only
    .\build\bump-version.ps1 -Version 0.2.0 -Tag       # edit + commit + tag
    .\build\bump-version.ps1 -Version 0.3.0-beta.1 -Tag   # pre-release

  Then publish:  git push --follow-tags
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$Tag
)
$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z\.-]+)?$') {
    throw "Version '$Version' is not semantic (expected X.Y.Z or X.Y.Z-suffix)."
}
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($Tag) {
    $dirty = git status --porcelain
    if ($dirty) { throw "Working tree has uncommitted changes. Commit them first, then run with -Tag." }
    if (git tag --list "v$Version") { throw "Tag v$Version already exists." }
}

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

if ($Tag) {
    git add -A
    git commit -m "Release v$Version"
    git tag -a "v$Version" -m "v$Version"
    Write-Host "`nCreated commit and tag v$Version. Publish with:  git push --follow-tags" -ForegroundColor Cyan
} else {
    Write-Host "`nReview the changes, then:  git commit -am 'Release v$Version'; git tag -a v$Version -m v$Version; git push --follow-tags" -ForegroundColor Cyan
}
