<#
  jahiz-env.ps1  (jahiz / env)
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

  Run:  powershell -NoProfile -ExecutionPolicy Bypass -File .\jahiz-env.ps1
  Options:
    -CheckOnly   report what is installed / missing, install nothing
    -DryRun      check that every package id in the catalogue still exists (winget, or the winget-pkgs
                 repository when winget is not available) and the npm packages; installs nothing.
                 Exit code 0 = all available, 2 = something is missing, 3 = some lookups could not be checked
    -Yes         accept every default (installs everything missing except optional tools: Docker, editors, databases, GUI clients; Herd for PHP)
    -MaxRetries  retries per network step (default 4)
    -Version     print the version and exit

  Exit code: 0 when PHP and Node.js are available at the end, 1 otherwise.
  Other tools (e.g. editor/jahiz-editor.ps1) call this script and read the exit code.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Yes,
    [int]$MaxRetries = 4,
    [switch]$DryRun,
    [switch]$Version
)

# Bumped by build/bump-version.ps1; must match the git tag (vX.Y.Z) on release.
$ScriptVersion = '0.4.0'
if ($Version) { Write-Output "jahiz-env $ScriptVersion"; return }

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$LogDir  = Join-Path $env:LOCALAPPDATA 'jahiz'
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

Log "jahiz / env  v$ScriptVersion" 'Cyan'

# ---------------------------------------------------------------------------
# Questions (same helpers as the other jahiz tools; each tool is self-contained)
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

function Ask-MultiChoice([string]$Question, [string[]]$Options, [bool[]]$Installed = @()) {
    # Returns the 0-based indexes picked; Enter (or -Yes) picks nothing.
    # Items flagged in $Installed are listed in green as [installed]; picking one just reports it.
    if ($Yes) { return @() }
    Write-Host ''
    Write-Host $Question -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($i -lt $Installed.Count -and $Installed[$i]) { Write-Host ("  {0}) {1}   [installed]" -f ($i + 1), $Options[$i]) -ForegroundColor Green }
        else { Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i]) }
    }
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
        if (-not $valid) { Write-Host '  Please use numbers from the list.' -ForegroundColor Yellow; continue }
        $out = @()
        foreach ($k in $res) {
            if ($k -lt $Installed.Count -and $Installed[$k]) { Write-Host "  $(($Options[$k] -split '\s{2,}')[0]) is already installed, skipped." -ForegroundColor Green }
            else { $out += $k }
        }
        return $out
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
            if ("$($_.Exception.Message)" -eq 'NOTFOUND') { throw }   # a definite 'does not exist': no retry
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
#   Direct   official installer URL + silent args, for tools that have no winget package
#            (downloaded to TEMP, Authenticode signature must be valid before it runs)
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
    @{ Key = 'composer'; Name = 'Composer';           Detect = { Get-CmdVersion composer }; Needs = 'php'; Url = 'https://getcomposer.org/download/'
       # Composer has no winget package; its official Windows installer is used (signature checked before running)
       Direct = @{ Url = 'https://getcomposer.org/Composer-Setup.exe'; Args = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' } }
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

function Install-Direct($tool) {
    # Official installer for tools without a winget package. The file must carry a valid Authenticode signature.
    $file = Join-Path $env:TEMP (Split-Path $tool.Direct.Url -Leaf)
    Info "Downloading the official $($tool.Name) installer: $($tool.Direct.Url)"
    Invoke-WithRetry { Invoke-WebRequest -Uri $tool.Direct.Url -OutFile $file -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop } "Download $($tool.Name)" ([uri]$tool.Direct.Url).Host
    $sig = Get-AuthenticodeSignature -FilePath $file
    if ($sig.Status -ne 'Valid') {
        Err "The $($tool.Name) installer signature is '$($sig.Status)'; not running it. Install it from $($tool.Url)"
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        return $false
    }
    Info "Signature OK ($($sig.SignerCertificate.Subject)). Running the installer..."
    $p = Start-Process -FilePath $file -ArgumentList $tool.Direct.Args -Wait -PassThru
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { Err "$($tool.Name) installer exit code $($p.ExitCode)"; return $false }
    return $true
}

function Install-Tool($tool) {
    if ($tool.Direct -and -not $tool.Winget) { return (Install-Direct $tool) }
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

$HerdWaitSeconds = 600   # how long to wait for Herd's first-run setup

function Test-EnterPressed {
    # True if the user pressed Enter (only in a real console; piped input -> False)
    try { while ([Console]::KeyAvailable) { if ([Console]::ReadKey($true).Key -eq 'Enter') { return $true } } } catch {}
    return $false
}

function Wait-HerdReady {
    # Herd's installer only installs the app; PHP is downloaded the first time Herd is opened.
    if ((Get-HerdPhpInstalled).Count) { return $true }
    $h = Find-Herd
    if ($h -and $h.Path -like '*.exe') {
        Info 'Opening Herd: finish its first-run setup there (it downloads PHP and adds it to PATH).'
        try { Start-Process -FilePath $h.Path } catch { Warn "Could not open Herd: $($_.Exception.Message)" }
    } else {
        Info 'Open Herd and finish its first-run setup (it downloads PHP and adds it to PATH).'
    }
    Info ("Waiting for Herd's PHP (up to {0} min). Press Enter to stop waiting and continue." -f [int]($HerdWaitSeconds / 60))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $HerdWaitSeconds) {
        $php = Get-HerdPhpInstalled
        if ($php.Count) {
            Update-SessionPath
            $bin = Join-Path $env:USERPROFILE '.config\herd\bin'
            if (-not (Get-Command php -ErrorAction SilentlyContinue) -and (Test-Path $bin)) { $env:Path = "$bin;$env:Path" }
            Ok ("Herd is ready (PHP {0})" -f ($php -join ', '))
            return $true
        }
        if (Test-EnterPressed) { Info 'Stopped waiting for Herd.'; return $false }
        Start-Sleep -Seconds 3
    }
    Warn 'Herd is not ready yet. Finish its setup in the Herd window, then run this script again.'
    return $false
}

function Wait-LaragonReady([string]$LaragonExe) {
    # Laragon ships PHP, but only adds it to PATH when you ask it to.
    if ($LaragonExe -and (Test-Path $LaragonExe)) { try { Start-Process -FilePath $LaragonExe } catch {} }
    Info 'In Laragon: Menu > Tools > Path > Add Laragon to Path.'
    if (-not $Yes) { $null = Read-Host 'Press Enter when done' }
    Update-SessionPath
}

function Set-HerdPhpVersions {
    Step 'PHP versions (via Herd)'
    if (-not $CheckOnly -and -not (Get-HerdPhpInstalled).Count) { $null = Wait-HerdReady; Update-SessionPath }
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
    $have = @(); $labels = @()
    foreach ($app in $EditorApps) {
        $r = Find-EditorApp $app
        $have += [bool]$r
        $labels += $(if ($r -and $r.Version -and $r.Version -ne '?') { "$($app.Name)  ($($r.Version))" } else { $app.Name })
        if ($r) { Add-Result $app.Name 'present' $r.Version }
    }
    if ($CheckOnly -or -not ($have -contains $false)) {
        for ($i = 0; $i -lt $EditorApps.Count; $i++) {
            if ($have[$i]) { Ok "$($labels[$i])  installed" } else { Warn "$($EditorApps[$i].Name) not found."; Add-Result $EditorApps[$i].Name 'MISSING' $EditorApps[$i].Url }
        }
        return
    }
    for ($i = 0; $i -lt $EditorApps.Count; $i++) { if (-not $have[$i] -and $EditorApps[$i].Warning) { Info "$($EditorApps[$i].Name): $($EditorApps[$i].Warning)" } }
    $picked = @(Ask-MultiChoice 'Install editors? (pick any or none)' $labels $have)
    foreach ($i in $picked) {
        $app = $EditorApps[$i]
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
    @{ Name = 'DBeaver Community  (all databases)';               Winget = @('DBeaver.DBeaver.Community', 'dbeaver.dbeaver'); Url = 'https://dbeaver.io/download/' }
    @{ Name = 'HeidiSQL           (MySQL, MariaDB, PostgreSQL)';  Winget = @('HeidiSQL.HeidiSQL');        Url = 'https://www.heidisql.com/download.php' }
    @{ Name = 'pgAdmin 4          (PostgreSQL)';                  Winget = @('PostgreSQL.pgAdmin');       Url = 'https://www.pgadmin.org/download/' }
    @{ Name = 'MySQL Workbench    (MySQL)';                       Winget = @('Oracle.MySQLWorkbench');    Url = 'https://dev.mysql.com/downloads/workbench/' }
    @{ Name = 'MongoDB Compass    (MongoDB)';                     Winget = @('MongoDB.Compass.Full', 'MongoDB.Compass.Community'); Url = 'https://www.mongodb.com/try/download/compass' }
    @{ Name = 'Redis Insight      (Redis)';                       Winget = @('RedisInsight.RedisInsight', 'Redis.RedisInsight'); Url = 'https://redis.io/insight/' }
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
    # 1) check what is already on this PC, before any download
    $have = @(); $labels = @()
    foreach ($db in $Databases) {
        $svc = Find-DbService $db.Service
        $have += [bool]$svc
        $labels += $(if ($svc) { "$($db.Name)  (service $($svc.Name), $($svc.StartType))" } else { $db.Name })
        if ($svc) { Add-Result $db.Name 'present' "$($svc.Name), $($svc.StartType)" }
    }
    if ($CheckOnly) {
        for ($i = 0; $i -lt $Databases.Count; $i++) { if ($have[$i]) { Ok "$($labels[$i])  installed" } }
        if (-not ($have -contains $true)) { Info 'No database server found.' }
    } elseif ($have -contains $false) {
        $picked = @(Ask-MultiChoice 'Install database servers? (native, official installers; pick any or none)' $labels $have)
        foreach ($i in $picked) {
            $db = $Databases[$i]
            if ($db.Warning) { Warn $db.Warning }
            try {
                if (Install-Database $db) {
                    $svc = Find-DbService $db.Service
                    if ($svc) { Ok "$($db.Name) installed (service '$($svc.Name)')"; Add-Result $db.Name 'installed' $svc.Name }
                    else { Warn "$($db.Name) installer finished, but no service was found (cancelled, or it needs a restart)."; Add-Result $db.Name 'not detected' '' }
                } else { Add-Result $db.Name 'FAILED' $db.Url }
            } catch { Err "$($db.Name): $($_.Exception.Message)"; Add-Result $db.Name 'FAILED' $db.Url }
        }
    } else {
        for ($i = 0; $i -lt $Databases.Count; $i++) { Ok "$($labels[$i])  installed" }
    }

    # 2) save RAM/CPU: database services should not start with Windows unless you want them to
    if (-not $CheckOnly) {
        $auto = @($Databases | ForEach-Object { Find-DbService $_.Service } | Where-Object { $_ -and "$($_.StartType)" -eq 'Automatic' })
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
    }

    # 3) GUI clients: same idea, installed ones are shown as [installed]
    $have = @(); $labels = @()
    foreach ($c in $DbClients) {
        $name = ($c.Name -split '\s{2,}')[0]
        $ok = Test-WingetInstalled $c.Winget
        $have += [bool]$ok; $labels += $c.Name
        if ($ok) { Add-Result $name 'present' '' }
    }
    if ($CheckOnly -or -not ($have -contains $false)) {
        for ($i = 0; $i -lt $DbClients.Count; $i++) { if ($have[$i]) { Ok "$(($DbClients[$i].Name -split '\s{2,}')[0])  installed" } }
        return
    }
    $picked = @(Ask-MultiChoice 'Install database GUI clients? (pick any or none)' $labels $have)
    foreach ($i in $picked) {
        $c = $DbClients[$i]
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

# ---------------------------------------------------------------------------
# -DryRun: is every package id in the catalogue still available? Installs nothing.
# ---------------------------------------------------------------------------
$script:DryUnknown = 0
function Test-WingetIdExists([string]$Id) {
    # $true = exists, $false = definitely missing, $null = could not check (network / rate limit / blocked)
    if ($HasWinget) { try { return [bool](Resolve-WingetId @($Id)) } catch { $script:DryUnknown++; return $null } }
    # No winget (e.g. CI): look the manifest folder up in github.com/microsoft/winget-pkgs
    $parts = $Id.Split('.')
    $path = "manifests/$($parts[0].Substring(0,1).ToLower())/$($parts -join '/')"
    $headers = @{ 'User-Agent' = 'jahiz' }
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }
    try {
        $null = Invoke-WithRetry {
            try { Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/contents/$path" -Headers $headers -TimeoutSec 30 -ErrorAction Stop }
            catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { throw 'NOTFOUND' } ; throw }
        } "winget-pkgs lookup $Id" 'api.github.com'
        return $true
    } catch {
        if ("$($_.Exception.Message)" -eq 'NOTFOUND') { return $false }
        $script:DryUnknown++
        Warn "Could not check $Id ($(($_.Exception.Message -split "`n")[0]))"
        return $null
    }
}

function Invoke-DryRun {
    Step ("Dry run: package ids ({0})" -f $(if ($HasWinget) { 'winget' } else { 'winget-pkgs repository' }))
    $bad = 0
    $slots = @()
    foreach ($e in $PhpEnvs)     { $slots += @{ Name = $e.Name; Ids = $e.Winget } }
    foreach ($t in $Tools)       { if ($t.Winget) { $slots += @{ Name = $t.Name; Ids = $t.Winget } } }
    foreach ($a in $EditorApps)  { $slots += @{ Name = $a.Name; Ids = $a.Winget } }
    foreach ($d in $Databases)   { if ($d.Winget) { $slots += @{ Name = $d.Name; Ids = $d.Winget } } }
    foreach ($c in $DbClients)   { $slots += @{ Name = ($c.Name -split '\s{2,}')[0]; Ids = $c.Winget } }
    $slots += @{ Name = 'Official PHP'; Ids = @($OfficialPhpLines | ForEach-Object { "PHP.PHP.$_" }); AllLines = $true }
    foreach ($d in $Databases)   { if ($d.Lines) { $slots += @{ Name = $d.Name; Ids = @($d.Lines | ForEach-Object { $d.IdFormat -f $_ }); AllLines = $true } } }

    foreach ($slot in $slots) {
        if ($slot.AllLines) {
            # one package per version line: report each, fail only if none exists
            $res = @{}; foreach ($id in $slot.Ids) { $res[$id] = Test-WingetIdExists $id }
            $found   = @($slot.Ids | Where-Object { $res[$_] -eq $true })
            $gone    = @($slot.Ids | Where-Object { $res[$_] -eq $false })
            $unknown = @($slot.Ids | Where-Object { $null -eq $res[$_] })
            if ($found.Count) { Ok ("{0,-28} {1}" -f $slot.Name, ($found -join ', ')) }
            elseif (-not $unknown.Count) { Err ("{0,-28} none of: {1}" -f $slot.Name, ($slot.Ids -join ', ')); $bad++ }
            if ($gone.Count) { Warn ("{0,-28} not available (yet): {1}" -f $slot.Name, ($gone -join ', ')) }
            continue
        }
        $hit = $null; $allMissing = $true
        foreach ($id in $slot.Ids) {
            $x = Test-WingetIdExists $id
            if ($x -eq $true) { $hit = $id; break }
            if ($null -eq $x) { $allMissing = $false }
        }
        if ($hit) {
            $note = if ($hit -ne $slot.Ids[0]) { "  (fallback for $($slot.Ids[0]))" } else { '' }
            Ok ("{0,-28} {1}{2}" -f $slot.Name, $hit, $note)
        } elseif ($allMissing) { Err ("{0,-28} none of: {1}" -f $slot.Name, ($slot.Ids -join ', ')); $bad++ }
        else { Warn ("{0,-28} could not be checked" -f $slot.Name) }
    }

    Step 'Dry run: official installers (no winget package)'
    foreach ($t in $Tools | Where-Object { $_.Direct }) {
        try {
            $null = Invoke-WithRetry { Invoke-WebRequest -Uri $t.Direct.Url -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop } "Check $($t.Direct.Url)" ([uri]$t.Direct.Url).Host
            Ok ("{0,-28} {1}" -f $t.Name, $t.Direct.Url)
        } catch { Err ("{0,-28} {1} not reachable" -f $t.Name, $t.Direct.Url); $bad++ }
    }

    Step 'Dry run: npm packages'
    foreach ($t in $Tools | Where-Object { $_.Npm }) {
        try {
            $info = Invoke-WithRetry { Invoke-RestMethod -Uri ("https://registry.npmjs.org/{0}/latest" -f ($t.Npm -replace '/', '%2f')) -TimeoutSec 30 -ErrorAction Stop } "npm lookup $($t.Npm)" 'registry.npmjs.org'
            if ($info.deprecated) { Err ("{0,-28} {1} is DEPRECATED: {2}" -f $t.Name, $t.Npm, $info.deprecated); $bad++ }
            else { Ok ("{0,-28} {1} v{2}" -f $t.Name, $t.Npm, $info.version) }
        } catch { Err ("{0,-28} {1} not found" -f $t.Name, $t.Npm); $bad++ }
    }

    Step 'Dry run summary'
    if ($bad) { Err "$bad item(s) are not available. Nothing was installed."; exit 2 }
    if ($script:DryUnknown) { Warn "$($script:DryUnknown) lookup(s) could not be checked (network or rate limit). Nothing was installed."; exit 3 }
    Ok 'Every package is available. Nothing was installed.'
    exit 0
}

if ($DryRun) { Invoke-DryRun }

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
                        # Installer done (winget waited for it). Now wait for the app's own first-run setup.
                        if ($e.Key -eq 'herd') { $null = Wait-HerdReady }
                        if ($e.Key -eq 'laragon') { Wait-LaragonReady $r.Path }
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
