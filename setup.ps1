<#
  setup.ps1  (dev-setup)
  One command for a new Windows dev machine: runs the env tool (dev tools, editors,
  databases), then the editor tool (extensions + settings).

  Where the tools come from:
    1. a clone of the repo:    env\setup-dev-env.ps1 and editor\setup-dev-extensions.ps1 next to this file
    2. the same folder:        setup-dev-env.ps1 and setup-dev-extensions.ps1 next to this file
    3. otherwise it downloads them from the GitHub release with THIS script's version
       and checks each file against that release's SHA256SUMS.txt before running it.

  Run:  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
  Options:
    -Yes          accept every default in both tools
    -DryRun       only check that every package / extension is still available; install nothing
    -Target       cursor | code | both   (passed to the editor tool)
    -Source       phpstorm | vscode | recommended | author   (passed to the editor tool)
    -SkipEnv      run only the editor tool
    -SkipEditor   run only the env tool
    -Version      print the version and exit
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$DryRun,
    [ValidateSet('', 'cursor', 'code', 'both')][string]$Target = '',
    [ValidateSet('', 'phpstorm', 'vscode', 'recommended', 'author')][string]$Source = '',
    [switch]$SkipEnv,
    [switch]$SkipEditor,
    [switch]$Version
)

# Bumped by build/bump-version.ps1; must match the git tag (vX.Y.Z) on release.
$ScriptVersion = '0.2.2'
if ($Version) { Write-Output "dev-setup $ScriptVersion"; return }

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Repo = 'Eslam-Nazer/dev-setup'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
Say "dev-setup  v$ScriptVersion" 'Cyan'

function Get-Tools {
    if ($PSScriptRoot) {
        $clone = @{ Env = Join-Path $PSScriptRoot 'env\setup-dev-env.ps1'; Editor = Join-Path $PSScriptRoot 'editor\setup-dev-extensions.ps1' }
        if ((Test-Path $clone.Env) -and (Test-Path $clone.Editor)) { Say 'Using the tools from this folder (repo clone).'; return $clone }
        $flat = @{ Env = Join-Path $PSScriptRoot 'setup-dev-env.ps1'; Editor = Join-Path $PSScriptRoot 'setup-dev-extensions.ps1' }
        if ((Test-Path $flat.Env) -and (Test-Path $flat.Editor)) { Say 'Using the tools next to this script.'; return $flat }
    }

    # Download the matching release and verify checksums
    $tag  = "v$ScriptVersion"
    $base = "https://github.com/$Repo/releases/download/$tag"
    $dir  = Join-Path $env:TEMP "dev-setup-$tag"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Say "Downloading the tools from release $tag ..."
    $files = @('SHA256SUMS.txt', 'setup-dev-env.ps1', 'setup-dev-extensions.ps1')
    foreach ($f in $files) {
        $ok = $false
        for ($i = 1; $i -le 4 -and -not $ok; $i++) {
            try { Invoke-WebRequest -Uri "$base/$f" -OutFile (Join-Path $dir $f) -UseBasicParsing -TimeoutSec 60; $ok = $true }
            catch { Say "  download of $f failed (attempt $i/4): $($_.Exception.Message)" 'Yellow'; Start-Sleep -Seconds ([Math]::Pow(2, $i)) }
        }
        if (-not $ok) { throw "Could not download $base/$f" }
    }

    $sums = @{}
    foreach ($line in Get-Content (Join-Path $dir 'SHA256SUMS.txt')) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$Matches[2].Trim()] = $Matches[1].ToLower() }
    }
    foreach ($f in 'setup-dev-env.ps1', 'setup-dev-extensions.ps1') {
        $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $dir $f)).Hash.ToLower()
        if (-not $sums.ContainsKey($f)) { throw "SHA256SUMS.txt has no entry for $f; not running it." }
        if ($sums[$f] -ne $actual) { throw "Checksum mismatch for $f (expected $($sums[$f]), got $actual). Not running it." }
        Say "  $f  checksum OK" 'Green'
    }
    return @{ Env = Join-Path $dir 'setup-dev-env.ps1'; Editor = Join-Path $dir 'setup-dev-extensions.ps1' }
}

$tools = Get-Tools
$codes = @{}

if (-not $SkipEnv) {
    Say "`n=== 1/2  Dev tools (env) ===" 'Cyan'
    $envArgs = @{}
    if ($Yes)    { $envArgs.Yes = $true }
    if ($DryRun) { $envArgs.DryRun = $true }
    & $tools.Env @envArgs
    $codes.env = $LASTEXITCODE
    # pick up PATH changes made by installers
    $env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) | Where-Object { $_ }) -join ';'
}

if (-not $SkipEditor) {
    Say "`n=== 2/2  Editor (extensions + settings) ===" 'Cyan'
    $edArgs = @{ SkipEnvCheck = $true }
    if ($Yes)    { $edArgs.Yes = $true }
    if ($DryRun) { $edArgs.DryRun = $true }
    if ($Target) { $edArgs.Target = $Target }
    if ($Source) { $edArgs.Source = $Source }
    & $tools.Editor @edArgs
    $codes.editor = $LASTEXITCODE
}

Say "`n=== Done ===" 'Cyan'
foreach ($k in $codes.Keys) { Say ("  {0,-7} exit code {1}" -f $k, $codes[$k]) }
Say 'Open a new terminal (and restart the editor) so every change is picked up.' 'Cyan'
$worst = @($codes.Values | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1)
if ($worst.Count) { exit $worst[0] } else { exit 0 }
