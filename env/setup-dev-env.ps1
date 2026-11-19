<#
  setup-dev-env.ps1  (dev-setup / env)
  Checks the development tools a Laravel + NestJS machine needs and installs
  the missing ones with winget, asking before each install.

  Checked, in this order:
    PHP environment  Laravel Herd, Laragon, or official PHP from php.net (pick ONE)
    PHP versions     with Herd: install more versions (herd php:install) and set the global one (herd use)
    PHP              comes with Herd / Laragon
    Composer         comes with Herd / Laragon; installed separately only if PHP exists but Composer doesn't
    Git
    Node.js          with Herd: herd node:install (Herd ships nvm); otherwise the official Node.js LTS (winget)

  Herd's own commands are used only when Herd is installed or chosen.
  Otherwise every tool comes from its official publisher through winget.
    NestJS CLI       npm install -g @nestjs/cli
    Docker Desktop   optional
    Editors          optional, pick any: PhpStorm, VS Code, Cursor (checked first; only missing ones are offered)
    Databases        optional, pick any: PostgreSQL, MySQL, MariaDB, Redis (Memurai), MongoDB
                     native official installers (their own setup window asks for the admin password);
                     services can be switched to Manual start so they do not use RAM at boot
    DB GUI clients   optional, pick any: DBeaver, HeidiSQL, pgAdmin, MySQL Workbench, Compass, Redis Insight

  For every install it asks: latest version, or pick one from the list of available versions.

  Run:  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-dev-env.ps1
  Options:
    -CheckOnly   report what is installed / missing, install nothing
    -Yes         accept every default (installs everything missing except optional tools: Docker, editors, databases, GUI clients; Herd for PHP)
    -MaxRetries  retries per network step (default 4)
    -Version     print the version and exit

  Exit code: 0 when PHP and Node.js are available at the end, 1 otherwise.
  Other tools (e.g. editor/setup-dev-extensions.ps1) call this script and read the exit code.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Yes,
    [int]$MaxRetries = 4,
    [switch]$Version
)

# Bumped by build/bump-version.ps1; must match the git tag (vX.Y.Z) on release.
$ScriptVersion = '0.1.0'
if ($Version) { Write-Output "setup-dev-env $ScriptVersion"; return }

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$LogDir  = Join-Path $env:LOCALAPPDATA 'dev-ext-installer'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("env-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
# Keep the log folder small: this run + the 9 newest older logs of this tool
Get-ChildItem $LogDir -Filter 'env-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 9 | Remove-Item -Force -ErrorAction SilentlyContinue

function Log([string]$msg, [string]$color = 'Gray') {
    Write-Host $msg -ForegroundColor $color
    Add-Content -Path $LogFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg)
}
function Step($m) { Log "`n==> $m" 'Cyan' }
function Ok($m)   { Log "  [OK]   $m" 'Green' }
function Info($m) { Log "  [..]   $m" 'Gray' }
function Warn($m) { Log "  [WARN] $m" 'Yellow' }
function Err($m)  { Log "  [FAIL] $m" 'Red' }

Log "dev-setup / env  v$ScriptVersion" 'Cyan'

# ---------------------------------------------------------------------------
# Questions (same helpers as the other dev-setup tools; each tool is self-contained)
# ---------------------------------------------------------------------------
function Ask-YesNo([string]$Question, [bool]$Default = $true) {
    if ($Yes) { return $Default }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = Read-Host "$Question $hint"
        if ($null -eq $a) { return $Default }   # no console input (piped / closed)
        $a = $a.Trim().ToLower()
        if (-not $a) { return $Default }
        if ($a -in 'y', 'yes', '1') { return $true }
        if ($a -in 'n', 'no', '0')  { return $false }
    }
}
function Ask-Choice([string]$Question, [string[]]$Options, [int]$Default = 1) {
    if ($Yes) { return $Default }
    Write-Host ''
    Write-Host $Question -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i]) }
    while ($true) {
        $a = Read-Host "Choose 1-$($Options.Count) [default $Default]"
        if ($null -eq $a) { return $Default }
        $a = $a.Trim()
        if (-not $a) { return $Default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n }
    }
}

function Ask-MultiChoice([string]$Question, [string[]]$Options) {
    # Returns the 0-based indexes picked; Enter (or -Yes) picks nothing
    if ($Yes) { return @() }
    Write-Host ''
    Write-Host $Question -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i]) }
    while ($true) {
        $a = Read-Host 'Numbers separated by commas (e.g. 1,3), Enter for none'
        if ($null -eq $a) { return @() }
        $a = $a.Trim()
        if (-not $a) { return @() }
        $res = @(); $valid = $true
        foreach ($n in ($a -split '[,\s]+' | Where-Object { $_ })) {
            $k = 0
            if ([int]::TryParse($n, [ref]$k) -and $k -ge 1 -and $k -le $Options.Count) { if ($res -notcontains ($k - 1)) { $res += ($k - 1) } }
            else { $valid = $false }
        }
        if ($valid) { return $res }
        Write-Host '  Please use numbers from the list.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Network resilience
# ---------------------------------------------------------------------------
function Test-Internet([string]$HostName) {
    try {
        $null = Invoke-WebRequest -Uri "https://$HostName" -Method Head -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        if ($_.Exception.Response) { return $true }
        return $false
    }
}
function Wait-ForInternet([string]$HostName) {
    if (Test-Internet $HostName) { return }
    Warn "No connection to $HostName. Waiting for the internet to come back (Ctrl+C to abort)..."
    $waited = 0
    while (-not (Test-Internet $HostName)) {
        Start-Sleep -Seconds 10
        $waited += 10
        Write-Host ("`r  still offline... {0}s" -f $waited) -NoNewline -ForegroundColor DarkYellow
    }
    Write-Host ''
    Ok "Back online after ${waited}s"
}
function Invoke-WithRetry([scriptblock]$Action, [string]$What, [string]$HostName) {
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try { return & $Action }
        catch {
            $delay = [Math]::Min(60, [Math]::Pow(2, $i))
            Warn ("{0} failed (attempt {1}/{2}): {3}" -f $What, $i, $MaxRetries, ($_.Exception.Message -split "`n")[0])
            Wait-ForInternet $HostName
            if ($i -lt $MaxRetries) { Start-Sleep -Seconds $delay }
        }
    }
    throw "$What failed after $MaxRetries attempts"
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
function Update-SessionPath {
    # Pick up PATH changes made by installers without opening a new terminal.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Get-CmdVersion([string]$Cmd, [string[]]$CmdArgs = @('--version')) {
    $c = Get-Command $Cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { return $null }
    $out = ''
    try { $out = (& $c.Source @CmdArgs 2>&1 | Out-String).Trim() } catch {}
    $v = if ($out -match '(\d+\.\d+(\.\d+)?)') { $Matches[1] } else { '?' }
    return [pscustomobject]@{ Version = $v; Path = $c.Source }
}

function Find-Herd {
    $bin = Join-Path $env:USERPROFILE '.config\herd\bin'
    $exe = @("$env:ProgramFiles\Herd\Herd.exe", "$env:LOCALAPPDATA\Programs\Herd\Herd.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe -and -not (Test-Path $bin)) { return $null }
    $v = '?'
    if ($exe) { try { $v = (Get-Item $exe).VersionInfo.ProductVersion } catch {} }
    return [pscustomobject]@{ Version = $v; Path = $(if ($exe) { $exe } else { $bin }); PhpBin = $bin }
}

function Find-Laragon {
    $root = @('C:\laragon', 'D:\laragon', "$env:USERPROFILE\laragon") |
            Where-Object { $_ -and (Test-Path -LiteralPath ([IO.Path]::Combine($_, 'laragon.exe')) -ErrorAction SilentlyContinue) } |
            Select-Object -First 1
    if (-not $root) { return $null }
    $exe = Join-Path $root 'laragon.exe'
    $v = '?'
    try { $v = (Get-Item $exe).VersionInfo.ProductVersion } catch {}
    $php = Get-ChildItem (Join-Path $root 'bin\php') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    return [pscustomobject]@{ Version = $v; Path = $exe; PhpBin = $(if ($php) { $php.FullName } else { $null }) }
}

# ---------------------------------------------------------------------------
# Catalogue. Edit here to add a tool (see docs/env/usage.md).
#   Detect   scriptblock returning an object with Version/Path, or $null
#   Winget   winget package ids, tried in order (the first that exists is used)
#   Npm      global npm package (instead of winget)
#   Needs    key of a tool that must be present first
#   Url      manual download page, shown when it cannot be installed
#   Note     shown after installing
#   Optional heavy or not always needed: the install question defaults to No
#   Warning  shown before asking (size, licence, requirements)
# ---------------------------------------------------------------------------
$PhpEnvs = @(
    @{ Key = 'herd';    Name = 'Laravel Herd'; Detect = { Find-Herd };    Winget = @('BeyondCode.Herd', 'Laravel.Herd'); Url = 'https://herd.laravel.com/windows' }
    @{ Key = 'laragon'; Name = 'Laragon';      Detect = { Find-Laragon }; Winget = @('LeNgocKhoa.Laragon');            Url = 'https://laragon.org/download/' }
)
$Tools = @(
    @{ Key = 'php';      Name = 'PHP';                Detect = { Get-CmdVersion php };      Bundled = $true }
    @{ Key = 'composer'; Name = 'Composer';           Detect = { Get-CmdVersion composer }; Winget = @('Composer.Composer'); Needs = 'php'; Url = 'https://getcomposer.org/download/' }
    @{ Key = 'git';      Name = 'Git';                Detect = { Get-CmdVersion git };      Winget = @('Git.Git'); Url = 'https://git-scm.com/download/win' }
    @{ Key = 'node';     Name = 'Node.js LTS (+npm)'; Detect = { Get-CmdVersion node };     Winget = @('OpenJS.NodeJS.LTS'); Url = 'https://nodejs.org/' }
    @{ Key = 'nest';     Name = 'NestJS CLI';         Detect = { Get-CmdVersion nest };     Npm = '@nestjs/cli'; Needs = 'node' }
    @{ Key = 'docker';   Name = 'Docker Desktop';     Detect = { Get-CmdVersion docker };   Winget = @('Docker.DockerDesktop'); Url = 'https://www.docker.com/products/docker-desktop/'
       Optional = $true
       Warning = 'Heavy: ~1 GB download, needs WSL 2 and uses RAM while running. Free for personal use and small companies; larger companies need a paid Docker subscription.'
       Note = 'Docker Desktop needs WSL 2 / virtualization. Restart Windows, then open Docker Desktop once.' }
)

# ---------------------------------------------------------------------------
# winget
# ---------------------------------------------------------------------------
$WingetHost = 'cdn.winget.microsoft.com'
$HasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

function Resolve-WingetId([string[]]$Ids) {
    foreach ($id in $Ids) {
        $found = Invoke-WithRetry {
            $out = winget show --id $id --exact --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) { return $true }
            if ($out -match '(?i)no package found|No package matched') { return $false }
            throw ($out.Trim() -split "`n")[-1]
        } "winget lookup $id" $WingetHost
        if ($found) { return $id }
        Warn "winget has no package '$id'"
    }
    return $null
}

function Install-WingetPackage([string]$Id, [string]$PkgVersion, [switch]$Interactive) {
    $verArgs = @()
    if ($PkgVersion) { $verArgs = @('--version', $PkgVersion) }
    # Interactive = the product's own setup window (used for databases so YOU type the admin password)
    $mode = if ($Interactive) { '--interactive' } else { '--silent' }
    Invoke-WithRetry {
        winget install --id $Id --exact @verArgs $mode --accept-package-agreements --accept-source-agreements | Out-Host
        $code = $LASTEXITCODE
        # 0 = ok, 0x8A150061 = already installed, 0x8A15002B = no newer version, 0x8A150109 = ok, restart needed
        if ($code -in 0, -1978335135, -1978335189, -1978334967) { return }
        throw "winget exit code $code"
    } "winget install $Id" $WingetHost
}

# ---------------------------------------------------------------------------
# Version choice: "latest?" -> yes, or pick from the list
# ---------------------------------------------------------------------------
function Select-Version([string]$Name, [string[]]$Versions) {
    if (-not $Versions -or $Versions.Count -eq 0) { return $null }   # unknown list -> install the default
    if (Ask-YesNo "Install the latest $Name ($($Versions[0]))?" $true) { return $Versions[0] }
    $list = @($Versions | Select-Object -First 15)
    $i = Ask-Choice "Which $Name version? (newest first)" $list 1
    return $list[$i - 1]
}

function Get-WingetVersions([string]$Id) {
    try {
        $out = Invoke-WithRetry {
            $o = winget show --id $Id --exact --versions --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw ($o.Trim() -split "`n")[-1] }
            $o
        } "winget versions $Id" $WingetHost
    } catch { return @() }
    $lines = @($out -split "`r?`n")
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*-{3,}') { $start = $i; break } }
    if ($start -lt 0) { return @() }
    return @($lines[($start + 1)..($lines.Count - 1)] | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+(\.\d+)+' })
}

function Get-NpmVersions([string]$Package) {
    try {
        $json = Invoke-WithRetry {
            $o = & npm view $Package versions --json 2>$null | Out-String
            if ($LASTEXITCODE -ne 0) { throw 'npm view failed' }
            $o
        } "npm view $Package" 'registry.npmjs.org'
        $parsed = $json | ConvertFrom-Json
        $all = @($parsed | ForEach-Object { $_ } | Where-Object { $_ -notmatch '-' })   # stable only
        [array]::Reverse($all)
        return $all
    } catch { return @() }
}

function Get-NodeLtsVersions {
    # Newest release of each LTS line, newest first (e.g. 24.x, 22.x, 20.x)
    try {
        $idx = Invoke-WithRetry { Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 30 -ErrorAction Stop } 'Node.js version list' 'nodejs.org'
        $seen = @{}; $out = @()
        foreach ($r in $idx) {
            if (-not $r.lts) { continue }
            $v = $r.version.TrimStart('v'); $major = $v.Split('.')[0]
            if (-not $seen[$major]) { $seen[$major] = $true; $out += $v }
        }
        return $out
    } catch { return @() }
}

function Install-Tool($tool) {
    if ($tool.Npm) {
        $v = Select-Version $tool.Name (Get-NpmVersions $tool.Npm)
        $spec = if ($v) { "$($tool.Npm)@$v" } else { $tool.Npm }
        Invoke-WithRetry {
            & npm install -g $spec 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "npm exit code $LASTEXITCODE" }
        } "npm install -g $spec" 'registry.npmjs.org'
        return $true
    }
    if (-not $HasWinget) { Warn "winget is not available. Install $($tool.Name) from $($tool.Url)"; return $false }
    $id = Resolve-WingetId $tool.Winget
    if (-not $id) { Err "No winget package for $($tool.Name). Download it from $($tool.Url)"; return $false }
    $v = Select-Version $tool.Name (Get-WingetVersions $id)
    Info ("Installing {0} ({1}{2})..." -f $tool.Name, $id, $(if ($v) { " $v" } else { '' }))
    Install-WingetPackage $id $v
    return $true
}

# ---------------------------------------------------------------------------
# Official PHP (windows.php.net builds, published on winget as PHP.PHP.<major.minor>)
# ---------------------------------------------------------------------------
$OfficialPhpLines = @('8.5', '8.4', '8.3', '8.2')   # newest first; add new lines here

function Install-OfficialPhp {
    if (-not $HasWinget) { Warn 'winget is not available. Download PHP from https://windows.php.net/download/'; return $false }
    $lines = @()
    foreach ($l in $OfficialPhpLines) { if (Resolve-WingetId @("PHP.PHP.$l")) { $lines += $l } }
    if (-not $lines.Count) { Err 'No official PHP package found on winget. Download it from https://windows.php.net/download/'; return $false }
    $l = Select-Version 'PHP' $lines
    if (-not $l) { $l = $lines[0] }
    Info "Installing PHP $l (PHP.PHP.$l)..."
    Install-WingetPackage "PHP.PHP.$l" $null
    return $true
}

# ---------------------------------------------------------------------------
# Herd helpers: PHP versions and Node.js through Herd's own CLI
# ---------------------------------------------------------------------------
function Test-HerdCli { return [bool](Get-Command herd -ErrorAction SilentlyContinue) }

function Get-HerdPhpInstalled {
    $bin = Join-Path $env:USERPROFILE '.config\herd\bin'
    $out = @()
    foreach ($d in (Get-ChildItem $bin -Directory -Filter 'php*' -ErrorAction SilentlyContinue)) {
        if ($d.Name -match '^php(\d)(\d+)$' -and (Test-Path (Join-Path $d.FullName 'php.exe'))) { $out += "$($Matches[1]).$($Matches[2])" }
    }
    return @($out | Sort-Object { [version]$_ } -Descending)
}

function Get-HerdPhpAvailable {
    $out = (& herd php:list 2>&1 | Out-String)
    return @([regex]::Matches($out, '\b(\d\.\d{1,2})\b') | ForEach-Object { $_.Groups[1].Value } |
             Where-Object { [version]$_ -ge [version]'7.0' } | Select-Object -Unique | Sort-Object { [version]$_ } -Descending)
}

function Invoke-Herd([string[]]$HerdArgs, [string]$What) {
    Invoke-WithRetry {
        & herd @HerdArgs 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "herd exit code $LASTEXITCODE (is the Herd app running?)" }
    } $What 'herd.laravel.com'
}

function Set-HerdPhpVersions {
    Step 'PHP versions (via Herd)'
    if (-not (Test-HerdCli)) { Warn "The 'herd' command is not on PATH yet. Open Herd once, then re-run to manage PHP versions."; return }
    $installed = Get-HerdPhpInstalled
    if ($installed) { Ok ("Installed PHP versions: {0}" -f ($installed -join ', ')) } else { Warn 'No PHP version installed in Herd yet.' }
    if ($CheckOnly) { return }

    $available = Get-HerdPhpAvailable
    while ($true) {
        $missing = @($available | Where-Object { $_ -notin $installed })
        if (-not $missing.Count) { break }
        $default = -not $installed.Count     # nothing installed -> default to yes
        if (-not (Ask-YesNo ("Install {0}PHP version with Herd? (available: {1})" -f $(if ($installed.Count) { 'another ' } else { 'a ' }), ($missing -join ', ')) $default)) { break }
        $i = Ask-Choice 'Which PHP version? (newest first)' $missing 1
        $v = $missing[$i - 1]
        try {
            Invoke-Herd @('php:install', $v) "herd php:install $v"
            Ok "PHP $v installed"
            Add-Result "PHP $v (Herd)" 'installed' ''
        } catch { Err "PHP ${v}: $($_.Exception.Message)"; Add-Result "PHP $v (Herd)" 'FAILED' 'install it from the Herd app > PHP' }
        $installed = Get-HerdPhpInstalled
        if ($Yes) { break }
    }
    if (-not $available.Count -and -not $installed.Count) {
        Warn "Could not read 'herd php:list'. Install a PHP version from the Herd app > PHP tab."
    }

    if ($installed.Count -gt 1) {
        $current = Get-CmdVersion php
        $now = if ($current) { $current.Version } else { 'none' }
        if (Ask-YesNo "Change the global PHP version (now $now)?" $false) {
            $i = Ask-Choice 'Global PHP version' $installed 1
            try { Invoke-Herd @('use', $installed[$i - 1]) "herd use $($installed[$i - 1])"; Ok "Global PHP is now $($installed[$i - 1])" }
            catch { Err $_.Exception.Message }
        }
    }
    Update-SessionPath
}

function Install-NodeWithHerd {
    $v = Select-Version 'Node.js (LTS)' (Get-NodeLtsVersions)
    $target = if ($v) { $v } else { 'lts' }
    try {
        Invoke-Herd @('node:install', $target) "herd node:install $target"
    } catch {
        Warn "herd node:install failed ($($_.Exception.Message)); trying nvm directly."
        Invoke-WithRetry {
            & nvm install $target 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "nvm exit code $LASTEXITCODE" }
        } "nvm install $target" 'nodejs.org'
        & nvm use $target 2>&1 | Out-Host
    }
    return $true
}

# ---------------------------------------------------------------------------
# Editors. Detected by their usual install folders first, then winget list. Edit here to add one.
# ---------------------------------------------------------------------------
$EditorApps = @(
    @{ Name = 'PhpStorm'; Winget = @('JetBrains.PhpStorm'); Url = 'https://www.jetbrains.com/phpstorm/download/'
       Paths = @("$env:ProgramFiles\JetBrains\PhpStorm*\bin\phpstorm64.exe", "$env:LOCALAPPDATA\Programs\PhpStorm*\bin\phpstorm64.exe", "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\PhpStorm\*\*\bin\phpstorm64.exe", "$env:LOCALAPPDATA\Programs\PhpStorm\bin\phpstorm64.exe")
       Warning = 'PhpStorm is paid: 30-day free trial, free for students and open-source projects.' }
    @{ Name = 'VS Code';  Winget = @('Microsoft.VisualStudioCode'); Url = 'https://code.visualstudio.com/'; Cmd = 'code'
       Paths = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe") }
    @{ Name = 'Cursor';   Winget = @('Anysphere.Cursor'); Url = 'https://cursor.com/download'; Cmd = 'cursor'
       Paths = @("$env:LOCALAPPDATA\Programs\cursor\Cursor.exe", "$env:ProgramFiles\Cursor\Cursor.exe")
       Warning = 'Cursor is free to install; its AI features have usage limits on the free plan.' }
)

function Find-EditorApp($app) {
    foreach ($p in $app.Paths) {
        $hit = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) {
            $v = '?'; try { $v = $hit.VersionInfo.ProductVersion } catch {}
            return [pscustomobject]@{ Version = $v; Path = $hit.FullName }
        }
    }
    if ($app.Cmd) { $c = Get-CmdVersion $app.Cmd; if ($c) { return $c } }
    if (Test-WingetInstalled $app.Winget) { return [pscustomobject]@{ Version = '?'; Path = '(winget)' } }
    return $null
}

function Invoke-EditorStep {
    Step 'Editors (optional)'
    $missing = @()
    foreach ($app in $EditorApps) {
        $r = Find-EditorApp $app
        if ($r) { Ok "$($app.Name) $($r.Version)  ($($r.Path))"; Add-Result $app.Name 'present' $r.Version }
        else { $missing += $app }
    }
    if (-not $missing.Count) { return }
    if ($CheckOnly) { foreach ($app in $missing) { Warn "$($app.Name) not found."; Add-Result $app.Name 'MISSING' $app.Url }; return }

    foreach ($app in $missing) { if ($app.Warning) { Info "$($app.Name): $($app.Warning)" } }
    $picked = @(Ask-MultiChoice 'Install editors? (pick any or none)' @($missing | ForEach-Object { $_.Name }))
    foreach ($i in $picked) {
        $app = $missing[$i]
        try {
            if (Install-Tool $app) {
                Update-SessionPath
                $r = Find-EditorApp $app
                if ($r) { Ok "$($app.Name) installed"; Add-Result $app.Name 'installed' $r.Version }
                else { Warn "$($app.Name) installed but not found yet (open a new terminal)."; Add-Result $app.Name 'installed (new terminal)' '' }
            } else { Add-Result $app.Name 'FAILED' $app.Url }
        } catch { Err "$($app.Name): $($_.Exception.Message)"; Add-Result $app.Name 'FAILED' $app.Url }
    }
}

# ---------------------------------------------------------------------------
# Databases (native, official installers). Edit here to add one.
#   Lines + IdFormat  one winget package per major version (like PostgreSQL.PostgreSQL.17)
#   Winget            package ids, tried in order
#   Service           Windows service name pattern (to detect it and to set Manual start)
# ---------------------------------------------------------------------------
$Databases = @(
    @{ Name = 'PostgreSQL';                 Lines = @('18', '17', '16', '15'); IdFormat = 'PostgreSQL.PostgreSQL.{0}'; Service = 'postgresql*'; Url = 'https://www.postgresql.org/download/windows/' }
    @{ Name = 'MySQL Community Server';     Winget = @('Oracle.MySQL');          Service = 'MySQL*';    Url = 'https://dev.mysql.com/downloads/mysql/' }
    @{ Name = 'MariaDB Server';             Winget = @('MariaDB.Server');        Service = 'MariaDB*';  Url = 'https://mariadb.org/download/' }
    @{ Name = 'Redis (Memurai Developer)';  Winget = @('Memurai.MemuraiDeveloper'); Service = 'Memurai*'; Url = 'https://www.memurai.com/get-memurai'
       Warning = 'Redis has no official Windows build. Memurai Developer is a free Redis-compatible server for development (check its licence terms).' }
    @{ Name = 'MongoDB Community Server';   Winget = @('MongoDB.Server');        Service = 'MongoDB*';  Url = 'https://www.mongodb.com/try/download/community' }
)
$DbClients = @(
    @{ Name = 'DBeaver Community  (all databases)';               Winget = @('dbeaver.dbeaver');          Url = 'https://dbeaver.io/download/' }
    @{ Name = 'HeidiSQL           (MySQL, MariaDB, PostgreSQL)';  Winget = @('HeidiSQL.HeidiSQL');        Url = 'https://www.heidisql.com/download.php' }
    @{ Name = 'pgAdmin 4          (PostgreSQL)';                  Winget = @('PostgreSQL.pgAdmin');       Url = 'https://www.pgadmin.org/download/' }
    @{ Name = 'MySQL Workbench    (MySQL)';                       Winget = @('Oracle.MySQLWorkbench');    Url = 'https://dev.mysql.com/downloads/workbench/' }
    @{ Name = 'MongoDB Compass    (MongoDB)';                     Winget = @('MongoDB.Compass.Full', 'MongoDB.Compass.Community'); Url = 'https://www.mongodb.com/try/download/compass' }
    @{ Name = 'Redis Insight      (Redis)';                       Winget = @('Redis.RedisInsight');       Url = 'https://redis.io/insight/' }
)

function Test-WingetInstalled([string[]]$Ids) {
    # Checks the programs already on this PC (no download)
    if (-not $HasWinget) { return $false }
    foreach ($id in $Ids) {
        $out = winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $out -match [regex]::Escape($id)) { return $true }
    }
    return $false
}

function Find-DbService([string]$Pattern) {
    try { return Get-Service -Name $Pattern -ErrorAction Stop | Select-Object -First 1 } catch { return $null }
}

function Install-Database($db) {
    if (-not $HasWinget) { Warn "winget is not available. Download $($db.Name) from $($db.Url)"; return $false }
    if ($db.Lines) {
        $lines = @()
        foreach ($l in $db.Lines) { if (Resolve-WingetId @($db.IdFormat -f $l)) { $lines += $l } }
        if (-not $lines.Count) { Err "No winget package for $($db.Name). Download it from $($db.Url)"; return $false }
        $l = Select-Version $db.Name $lines
        if (-not $l) { $l = $lines[0] }
        $id = $db.IdFormat -f $l; $v = $null
    } else {
        $id = Resolve-WingetId $db.Winget
        if (-not $id) { Err "No winget package for $($db.Name). Download it from $($db.Url)"; return $false }
        $v = Select-Version $db.Name (Get-WingetVersions $id)
    }
    Info "Opening the $($db.Name) installer ($id). Choose the admin password there; this script never sees it."
    Install-WingetPackage $id $v -Interactive
    return $true
}

function Set-ServicesManual([string[]]$Names) {
    $isAdmin = $false
    try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
    if ($isAdmin) {
        foreach ($n in $Names) { & sc.exe config $n start= demand | Out-Null }
    } else {
        # One UAC prompt for all services
        $cmd = ($Names | ForEach-Object { "sc.exe config '$_' start= demand" }) -join '; '
        Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', $cmd)
    }
}

function Invoke-DatabaseStep {
    Step 'Databases (optional)'
    $present = @(); $missing = @()
    foreach ($db in $Databases) {
        $svc = Find-DbService $db.Service
        if ($svc) { Ok "$($db.Name): service '$($svc.Name)' ($($svc.StartType))"; $present += $db; Add-Result $db.Name 'present' "$($svc.Name), $($svc.StartType)" }
        else { $missing += $db }
    }
    if ($CheckOnly) { if (-not $present.Count) { Info 'No database server found.' }; return }

    if ($missing.Count) {
        $picked = @(Ask-MultiChoice 'Install database servers? (native, official installers; pick any or none)' @($missing | ForEach-Object { $_.Name }))
        foreach ($i in $picked) {
            $db = $missing[$i]
            if ($db.Warning) { Warn $db.Warning }
            try {
                if (Install-Database $db) {
                    $svc = Find-DbService $db.Service
                    if ($svc) { Ok "$($db.Name) installed (service '$($svc.Name)')"; Add-Result $db.Name 'installed' $svc.Name; $present += $db }
                    else { Warn "$($db.Name) installer finished, but no service was found (cancelled, or it needs a restart)."; Add-Result $db.Name 'not detected' '' }
                } else { Add-Result $db.Name 'FAILED' $db.Url }
            } catch { Err "$($db.Name): $($_.Exception.Message)"; Add-Result $db.Name 'FAILED' $db.Url }
        }
    }

    # Save RAM/CPU: database services should not start with Windows unless you want them to
    $auto = @($present | ForEach-Object { Find-DbService $_.Service } | Where-Object { $_ -and "$($_.StartType)" -eq 'Automatic' })
    if ($auto.Count) {
        $names = @($auto | ForEach-Object { $_.Name })
        Info ("These database services start with Windows and use memory all the time: {0}" -f ($names -join ', '))
        if (Ask-YesNo 'Switch them to Manual start (start them only when you work)?' $true) {
            try {
                Set-ServicesManual $names
                $still = @($names | Where-Object { "$((Find-DbService $_).StartType)" -eq 'Automatic' })
                if ($still.Count) { Warn "Not changed (UAC declined?): $($still -join ', ')" }
                else { Ok 'Set to Manual. Start one when needed (admin terminal): net start <service>   Stop: net stop <service>' }
            } catch { Warn "Could not change the services: $($_.Exception.Message)" }
        }
    }

    # GUI clients: check what is already installed first, offer only the rest
    $clientsMissing = @()
    foreach ($c in $DbClients) {
        $name = ($c.Name -split '\s{2,}')[0]
        if (Test-WingetInstalled $c.Winget) { Ok "$name already installed"; Add-Result $name 'present' '' }
        else { $clientsMissing += $c }
    }
    if (-not $clientsMissing.Count) { return }
    $picked = @(Ask-MultiChoice 'Install database GUI clients? (pick any or none)' @($clientsMissing | ForEach-Object { $_.Name }))
    foreach ($i in $picked) {
        $c = $clientsMissing[$i]
        $name = ($c.Name -split '\s{2,}')[0]
        try {
            if (Install-Tool @{ Name = $name; Winget = $c.Winget; Url = $c.Url }) { Ok "$name installed"; Add-Result $name 'installed' '' }
            else { Add-Result $name 'FAILED' $c.Url }
        } catch { Err "${name}: $($_.Exception.Message)"; Add-Result $name 'FAILED' $c.Url }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$summary = @()
function Add-Result($name, $status, $detail) { $script:summary += [pscustomobject]@{ Tool = $name; Status = $status; Detail = $detail } }

if (-not $HasWinget -and -not $CheckOnly) {
    Warn 'winget was not found. Install "App Installer" from the Microsoft Store to let this script install tools.'
    Warn 'Continuing in report-only mode.'
    $CheckOnly = $true
}

# --- PHP environment: Herd or Laragon -------------------------------------
Step 'PHP environment (Herd / Laragon)'
$found = @{}
foreach ($e in $PhpEnvs) {
    $r = & $e.Detect
    if ($r) { $found[$e.Key] = $r; Ok "$($e.Name) $($r.Version)  ($($r.Path))" }
}
if ($found.Count -gt 1) {
    Warn 'Both Herd and Laragon are installed. They can fight over which PHP is first in PATH.'
    $first = Get-CmdVersion php
    if ($first) { Warn "PHP that runs now: $($first.Path)" }
}
if ($found.Count -eq 0) {
    Warn 'Neither Herd nor Laragon is installed.'
    if ($CheckOnly) {
        Add-Result 'PHP environment' 'MISSING' 'Herd or Laragon'
    } else {
        $c = Ask-Choice 'Install a PHP environment? (pick one)' @(
            'Laravel Herd   (recommended for Laravel: PHP, Composer, Laravel installer, Node via nvm)',
            'Laragon        (PHP, Apache/Nginx, MySQL in one place)',
            'Official PHP   (php.net build via winget; Composer installed next from getcomposer.org)',
            'Skip') 1
        if ($c -eq 3) {
            try {
                if (Install-OfficialPhp) {
                    Update-SessionPath
                    $r = Get-CmdVersion php
                    if ($r) { Ok "PHP $($r.Version) installed"; Add-Result 'PHP (official)' 'installed' $r.Version }
                    else { Warn 'PHP installed but not visible in this terminal yet (open a new terminal).'; Add-Result 'PHP (official)' 'installed (new terminal)' '' }
                } else { Add-Result 'PHP (official)' 'FAILED' 'https://windows.php.net/download/' }
            } catch { Err "PHP: $($_.Exception.Message)"; Add-Result 'PHP (official)' 'FAILED' 'https://windows.php.net/download/' }
        } elseif ($c -le 2) {
            $e = $PhpEnvs[$c - 1]
            try {
                if (Install-Tool $e) {
                    Update-SessionPath
                    $r = & $e.Detect
                    if ($r) {
                        Ok "$($e.Name) installed"; $found[$e.Key] = $r
                        Add-Result $e.Name 'installed' $r.Path
                        if ($e.Key -eq 'herd') { Info 'Open Herd once so it finishes setting up PHP and adds it to PATH.' }
                        if ($e.Key -eq 'laragon') { Info 'Open Laragon once, then Menu > Tools > Path > Add Laragon to Path.' }
                    } else { Warn "$($e.Name) installed but not detected yet; open it once, then re-run." ; Add-Result $e.Name 'installed (open it once)' '' }
                } else { Add-Result $e.Name 'FAILED' $e.Url }
            } catch { Err "$($e.Name): $($_.Exception.Message)"; Add-Result $e.Name 'FAILED' $e.Url }
        } else {
            Info 'Skipped PHP environment.'
            Add-Result 'PHP environment' 'skipped' ''
        }
    }
} else {
    foreach ($k in $found.Keys) { Add-Result (($PhpEnvs | Where-Object { $_.Key -eq $k }).Name) 'present' $found[$k].Version }
}
# Herd/Laragon PHP may not be in this session's PATH yet
foreach ($r in $found.Values) {
    if ($r.PhpBin -and (Test-Path (Join-Path $r.PhpBin 'php.exe')) -and -not (Get-Command php -ErrorAction SilentlyContinue)) {
        $env:Path = "$($r.PhpBin);$env:Path"
    }
}
$UseHerd = [bool]$found['herd']
if ($UseHerd) { Set-HerdPhpVersions }
elseif ($found['laragon']) { Info 'Laragon: add more PHP versions by unzipping them into laragon\bin\php (Menu > PHP > Version to switch).' }

# --- Other tools -----------------------------------------------------------
Step 'Tools'
$state = @{}
foreach ($t in $Tools) {
    $r = & $t.Detect
    if ($r) {
        $state[$t.Key] = $true
        Ok "$($t.Name) $($r.Version)  ($($r.Path))"
        Add-Result $t.Name 'present' $r.Version
        continue
    }
    $state[$t.Key] = $false

    if ($t.Key -eq 'composer' -and $UseHerd) {
        Warn 'Composer comes with Herd. Open Herd once so it is added to PATH.'
        Add-Result $t.Name 'MISSING' 'comes with Herd'
        continue
    }
    if ($t.Bundled) {
        Warn "$($t.Name) not found. It comes with Herd / Laragon (open the app once), or pick Official PHP above."
        Add-Result $t.Name 'MISSING' 'Herd / Laragon / official PHP'
        continue
    }
    if ($t.Needs -and -not $state[$t.Needs]) {
        Warn "$($t.Name) skipped: needs $($t.Needs) first."
        Add-Result $t.Name 'skipped' "needs $($t.Needs)"
        continue
    }
    if ($CheckOnly) {
        Warn "$($t.Name) not found."
        Add-Result $t.Name 'MISSING' $(if ($t.Url) { $t.Url } else { "npm i -g $($t.Npm)" })
        continue
    }
    if ($t.Warning) { Warn $t.Warning }
    $q = if ($t.Optional) { "$($t.Name) is not installed. Install it? (optional)" } else { "$($t.Name) is not installed. Install it?" }
    if (-not (Ask-YesNo $q (-not $t.Optional))) {
        Info "Skipped $($t.Name)."
        Add-Result $t.Name 'skipped' ''
        continue
    }
    try {
        # Herd ships nvm: install Node through Herd instead of a separate Node.js
        $ok = if ($t.Key -eq 'node' -and $UseHerd -and (Test-HerdCli)) { Install-NodeWithHerd } else { Install-Tool $t }
        if ($ok) {
            Update-SessionPath
            $r = & $t.Detect
            if ($r) {
                $state[$t.Key] = $true
                Ok "$($t.Name) $($r.Version) installed and verified"
                Add-Result $t.Name 'installed' $r.Version
            } else {
                Warn "$($t.Name) installed but not visible in this terminal yet (open a new terminal)."
                Add-Result $t.Name 'installed (new terminal)' ''
            }
            if ($t.Note) { Warn $t.Note }
        } else {
            Add-Result $t.Name 'FAILED' $t.Url
        }
    } catch {
        Err "$($t.Name): $($_.Exception.Message)"
        Add-Result $t.Name 'FAILED' $t.Url
    }
}

# --- Editors ---------------------------------------------------------------
Invoke-EditorStep

# --- Databases + GUI clients -------------------------------------------------
Invoke-DatabaseStep

# --- Summary ---------------------------------------------------------------
Step 'Summary'
$summary | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { Log $_ 'White' }
Log "Log file: $LogFile" 'DarkGray'
Log 'Tip: open a new terminal so every new tool is on PATH.' 'Cyan'

$ready = [bool](Get-Command php -ErrorAction SilentlyContinue) -and [bool](Get-Command node -ErrorAction SilentlyContinue)
if ($ready) { exit 0 } else { exit 1 }
