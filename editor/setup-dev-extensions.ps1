<#
  setup-dev-extensions.ps1
  Laravel + NestJS (PHP / TypeScript) editor setup for Cursor or VS Code.

  Questions it asks (press Enter for the default):
    1. Install into Cursor, VS Code, or both?
    2. Take your settings from: PhpStorm on this PC / VS Code on this PC / the values saved in this script?
    3. Change the color theme? (yes / no)
    4. Set the PHP interpreter? -> use the latest PHP found, or pick a version from the list?

  What it does:
  - Checks every extension exists in the right registry (Open VSX for Cursor, Marketplace for VS Code)
  - Skips deprecated extensions and switches to the official replacement when one is published
  - Falls back to an alternative extension when the first choice is missing
  - Survives internet drops: waits for the connection to come back and retries with backoff
  - Resumable: already-installed extensions are skipped, so you can just run it again
  - Verifies each install afterwards
  - Copies keymap / custom shortcuts / theme / UI / PHP from the source you choose
  - Uses the IntelliJ keymap only if your PhpStorm keymap is NOT VS Code-based
  - Double Shift = Search Everywhere, JetBrains-style file icons, breadcrumbs nav bar, "new file at path"
  - Backs up settings.json / keybindings.json before touching them

  Run:  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-dev-extensions.ps1
  Optional: -Target cursor|code|both  -Source phpstorm|vscode|builtin  -Yes (accept all defaults)
            -MaxRetries 8  -SkipSettings  -SkipEnvCheck  -Version

  It also asks whether to add a database extension (Database Client, SQLTools, MongoDB); pick any or none.

  Before installing, it checks that PHP and Node.js exist. If not, it offers to run
  env/setup-dev-env.ps1 (the dev-setup "env" tool) first, then continues.
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'cursor', 'code', 'both')][string]$Target = '',
    [ValidateSet('', 'phpstorm', 'vscode', 'builtin')][string]$Source = '',
    [int]$MaxRetries = 8,
    [switch]$SkipSettings,
    [switch]$Yes,
    [switch]$SkipEnvCheck,
    [switch]$Version
)

# Bumped by build/bump-version.ps1; must match the git tag (vX.Y.Z) on release.
$ScriptVersion = '0.2.0'
if ($Version) { Write-Output "setup-dev-extensions $ScriptVersion"; return }

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$LogDir  = Join-Path $env:LOCALAPPDATA 'dev-ext-installer'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
# Keep the log folder small: this run + the 9 newest older logs of this tool
Get-ChildItem $LogDir -Filter 'install-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
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

Log "dev-setup / editor  v$ScriptVersion" 'Cyan'

# ---------------------------------------------------------------------------
# Questions
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
# Optional database extensions (you pick any or none at run time)
# ---------------------------------------------------------------------------
$DbExtensionChoices = @(
    @{ Name = 'Database Client  (MySQL, MariaDB, PostgreSQL, SQLite, Redis, MongoDB in one panel)'; Ids = @('cweijan.vscode-database-client2') }
    @{ Name = 'SQLTools         (+ PostgreSQL and MySQL/MariaDB drivers)'; Ids = @('mtxr.sqltools'); With = @('mtxr.sqltools-driver-pg', 'mtxr.sqltools-driver-mysql') }
    @{ Name = 'MongoDB for VS Code'; Ids = @('mongodb.mongodb-vscode') }
)

# ---------------------------------------------------------------------------
# Extension catalogue: each slot lists candidates in order of preference.
# ---------------------------------------------------------------------------
$Catalog = @(
    # PHP / Laravel
    @{ Name = 'PHP IntelliSense (Intelephense)'; Ids = @('bmewburn.vscode-intelephense-client') }
    @{ Name = 'Laravel (official)';              Ids = @('laravel.vscode-laravel') }
    @{ Name = 'Laravel Blade';                   Ids = @('onecentlin.laravel-blade') }
    @{ Name = 'Laravel Pint';                    Ids = @('open-southeners.laravel-pint') }
    @{ Name = 'PHP Debug (Xdebug)';              Ids = @('xdebug.php-debug') }
    @{ Name = 'PHP Namespace Resolver';          Ids = @('MehediDracula.php-namespace-resolver') }
    @{ Name = 'PHP DocBlocker';                  Ids = @('neilbrayfield.php-docblocker') }
    @{ Name = 'PHPUnit runner';                  Ids = @('calebporzio.better-phpunit', 'recca0120.vscode-phpunit') }
    # TypeScript / NestJS
    @{ Name = 'ESLint';                          Ids = @('dbaeumer.vscode-eslint') }
    @{ Name = 'Prettier';                        Ids = @('esbenp.prettier-vscode') }
    @{ Name = 'NestJS snippets';                 Ids = @('ashinzekene.nestjs') }
    @{ Name = 'Jest';                            Ids = @('Orta.vscode-jest') }
    @{ Name = 'Pretty TypeScript Errors';        Ids = @('yoavbls.pretty-ts-errors') }
    @{ Name = 'Path IntelliSense';               Ids = @('christian-kohler.path-intellisense') }
    @{ Name = 'npm IntelliSense';                Ids = @('christian-kohler.npm-intellisense') }
    # Frontend
    @{ Name = 'Vue (Volar)';                     Ids = @('Vue.volar') }
    @{ Name = 'Tailwind CSS IntelliSense';       Ids = @('bradlc.vscode-tailwindcss') }
    # General
    @{ Name = 'Docker / Containers';             Ids = @('ms-azuretools.vscode-containers', 'ms-azuretools.vscode-docker', 'docker.docker'); OnlyIf = 'docker' }
    @{ Name = 'GitLens';                         Ids = @('eamodio.gitlens') }
    @{ Name = 'DotENV';                          Ids = @('mikestead.dotenv') }
    @{ Name = 'EditorConfig';                    Ids = @('EditorConfig.EditorConfig') }
    @{ Name = 'Error Lens';                      Ids = @('usernamehw.errorlens') }
    @{ Name = 'REST Client';                     Ids = @('humao.rest-client') }
    # PhpStorm feel
    @{ Name = 'PhpStorm / IntelliJ keymap';      Ids = @('k--kato.intellij-idea-keybindings'); Role = 'keymap' }
    @{ Name = 'JetBrains-style file icons';      Ids = @('chadalen.vscode-jetbrains-icon-theme', 'PKief.material-icon-theme'); Role = 'icons' }
    @{ Name = 'New file at any path';            Ids = @('patbenatar.advanced-new-file', 'sleistner.vscode-fileutils'); Role = 'newfile' }
    # AI
    @{ Name = 'Claude Code';                     Ids = @('anthropic.claude-code') }
)

# ---------------------------------------------------------------------------
# Values saved in this script (used when you pick "saved values")
# Taken from your PhpStorm 2026.3 setup.
# ---------------------------------------------------------------------------
$SavedDefaults = @{
    ColorScheme = 'poimandres'
    ThemeExtIds = @('pmndrs.pmndrs')
    BaseKeymap  = 'VSCode'          # your PhpStorm keymap is "VSCode copy"
    Compact     = $true
    SmoothCaret = $true
    Shortcuts   = @(@{ Action = 'Terminal.CommandCompletion.Invoke'; First = 'ctrl space'; Second = '' })
}

# PhpStorm color scheme -> VS Code theme extension
$ThemeMap = @{
    'poimandres' = @('pmndrs.pmndrs')
    'darcula'    = @('rokoroku.vscode-theme-darcula')
}

# IntelliJ action id -> VS Code command (+ optional "when")
$ActionMap = @{
    'SearchEverywhere'               = @('workbench.action.quickOpen', $null)
    'GotoFile'                       = @('workbench.action.quickOpen', $null)
    'GotoClass'                      = @('workbench.action.showAllSymbols', $null)
    'GotoSymbol'                     = @('workbench.action.showAllSymbols', $null)
    'FileStructurePopup'             = @('workbench.action.gotoSymbol', $null)
    'FindInPath'                     = @('workbench.action.findInFiles', $null)
    'ReplaceInPath'                  = @('workbench.action.replaceInFiles', $null)
    'Find'                           = @('actions.find', $null)
    'Replace'                        = @('editor.action.startFindReplaceAction', $null)
    'GotoDeclaration'                = @('editor.action.revealDefinition', 'editorTextFocus')
    'GotoImplementation'             = @('editor.action.goToImplementation', 'editorTextFocus')
    'FindUsages'                     = @('references-view.findReferences', 'editorTextFocus')
    'RenameElement'                  = @('editor.action.rename', 'editorTextFocus')
    'ReformatCode'                   = @('editor.action.formatDocument', 'editorTextFocus')
    'OptimizeImports'                = @('editor.action.organizeImports', 'editorTextFocus')
    'CommentByLineComment'           = @('editor.action.commentLine', 'editorTextFocus')
    'CommentByBlockComment'          = @('editor.action.blockComment', 'editorTextFocus')
    'EditorDuplicate'                = @('editor.action.copyLinesDownAction', 'editorTextFocus')
    'EditorDeleteLine'               = @('editor.action.deleteLines', 'editorTextFocus')
    'MoveLineUp'                     = @('editor.action.moveLinesUpAction', 'editorTextFocus')
    'MoveLineDown'                   = @('editor.action.moveLinesDownAction', 'editorTextFocus')
    'RecentFiles'                    = @('workbench.action.showAllEditorsByMostRecentlyUsed', $null)
    'ShowIntentionActions'           = @('editor.action.quickFix', 'editorTextFocus')
    'GotoLine'                       = @('workbench.action.gotoLine', $null)
    'ActivateTerminalToolWindow'     = @('workbench.action.terminal.toggleTerminal', $null)
    'ActivateProjectToolWindow'      = @('workbench.view.explorer', $null)
    'Terminal.CommandCompletion.Invoke' = @('workbench.action.terminal.triggerSuggest', 'terminalFocus')
    'NewElement'                     = @('explorer.newFile', $null)
    'Back'                           = @('workbench.action.navigateBack', $null)
    'Forward'                        = @('workbench.action.navigateForward', $null)
    'CloseContent'                   = @('workbench.action.closeActiveEditor', $null)
    'SaveAll'                        = @('workbench.action.files.saveAll', $null)
    'QuickJavaDoc'                   = @('editor.action.showHover', 'editorTextFocus')
    'ParameterInfo'                  = @('editor.action.triggerParameterHints', 'editorTextFocus')
    'ShowNavBar'                     = @('breadcrumbs.focusAndSelect', 'breadcrumbsPossible')
}

# ---------------------------------------------------------------------------
# Network resilience
# ---------------------------------------------------------------------------
function Test-Internet([string]$HostName) {
    try {
        $null = Invoke-WebRequest -Uri "https://$HostName" -Method Head -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        if ($_.Exception.Response) { return $true }   # any HTTP answer means we are online
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
# Registry lookups (existence + deprecation)
# ---------------------------------------------------------------------------
$script:VsCodeDeprecations = $null

function Get-VsCodeDeprecations {
    if ($null -ne $script:VsCodeDeprecations) { return $script:VsCodeDeprecations }
    $script:VsCodeDeprecations = @{}
    try {
        $m = Invoke-WithRetry { Invoke-RestMethod -Uri 'https://main.vscode-cdn.net/extensions/marketplace.json' -TimeoutSec 30 -ErrorAction Stop } 'Download deprecation list' 'main.vscode-cdn.net'
        if ($m.deprecated) {
            foreach ($p in $m.deprecated.PSObject.Properties) { $script:VsCodeDeprecations[$p.Name.ToLower()] = $p.Value }
        }
    } catch { Warn "Could not load the VS Code deprecation list; deprecation check is limited." }
    return $script:VsCodeDeprecations
}

function Get-ExtensionInfo([string]$Id, [string]$Registry) {
    $pub, $name = $Id.Split('.', 2)
    if ($Registry -eq 'openvsx') {
        $data = Invoke-WithRetry {
            try {
                Invoke-RestMethod -Uri ("https://open-vsx.org/api/{0}/{1}" -f $pub, $name) -TimeoutSec 30 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
                throw
            }
        } "Look up $Id" 'open-vsx.org'
        if ($null -eq $data -or $data.error) { return @{ Exists = $false } }
        $repl = $null
        if ($data.replacement -and $data.replacement.url -match '/extension/([^/]+)/([^/?#]+)') { $repl = "$($Matches[1]).$($Matches[2])" }
        return @{ Exists = $true; Deprecated = [bool]$data.deprecated; ReplacementId = $repl; Version = $data.version }
    }
    else {
        $body = @{ filters = @(@{ criteria = @(@{ filterType = 7; value = $Id }); pageSize = 1 }); flags = 0x200 } | ConvertTo-Json -Depth 6
        $res = Invoke-WithRetry {
            Invoke-RestMethod -Method Post -Uri 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' `
                -Headers @{ Accept = 'application/json;api-version=3.0-preview.1' } -ContentType 'application/json' -Body $body -TimeoutSec 30 -ErrorAction Stop
        } "Look up $Id" 'marketplace.visualstudio.com'
        $ext = @($res.results[0].extensions) | Select-Object -First 1
        if (-not $ext) { return @{ Exists = $false } }
        $dep = (Get-VsCodeDeprecations)[$Id.ToLower()]
        $repl = $null
        if ($dep -and $dep.extension -and $dep.extension.id) { $repl = $dep.extension.id }
        return @{ Exists = $true; Deprecated = [bool]$dep; ReplacementId = $repl; Version = $ext.versions[0].version }
    }
}

# Pick the first candidate that exists and is not deprecated (following replacements).
function Resolve-Slot($slot, [string]$Registry) {
    $queue = New-Object System.Collections.Generic.Queue[string]
    $slot.Ids | ForEach-Object { $queue.Enqueue($_) }
    $seen = @{}
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        if ($seen[$id.ToLower()]) { continue }
        $seen[$id.ToLower()] = $true
        try { $info = Get-ExtensionInfo $id $Registry }
        catch { Warn "Could not check $id : $($_.Exception.Message)"; continue }
        if (-not $info.Exists) { Warn "$id not found in $Registry"; continue }
        if ($info.Deprecated) {
            if ($info.ReplacementId) {
                Warn "$id is DEPRECATED -> trying replacement $($info.ReplacementId)"
                $queue.Enqueue($info.ReplacementId)
            } else { Warn "$id is DEPRECATED (no replacement published), trying next candidate" }
            continue
        }
        return @{ Id = $id; Version = $info.Version }
    }
    return $null
}

# ---------------------------------------------------------------------------
# JSONC helpers (settings.json allows comments / trailing commas)
# ---------------------------------------------------------------------------
function Read-Jsonc([string]$Path, [string]$Default) {
    if (-not (Test-Path $Path)) { return ($Default | ConvertFrom-Json) }
    $raw = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return ($Default | ConvertFrom-Json) }
    try { return ($raw | ConvertFrom-Json -ErrorAction Stop) } catch {}
    $clean = [regex]::Replace($raw, '("(?:\\.|[^"\\])*")|//[^\r\n]*|/\*[\s\S]*?\*/', { param($m) if ($m.Groups[1].Success) { $m.Value } else { '' } })
    $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')
    return ($clean | ConvertFrom-Json -ErrorAction Stop)
}
function Write-Json([string]$Path, $Obj) {
    $json = ConvertTo-Json -InputObject $Obj -Depth 20
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}
function Merge-Prop($Obj, [string]$Name, [hashtable]$Values) {
    # Add keys to an object-valued setting (e.g. files.watcherExclude) without dropping the user's own keys
    if (-not $Obj.PSObject.Properties[$Name] -or $null -eq $Obj.$Name -or $Obj.$Name -isnot [pscustomobject]) {
        Set-Prop $Obj $Name ([pscustomobject]@{})
    }
    foreach ($k in $Values.Keys) { if (-not $Obj.$Name.PSObject.Properties[$k]) { Set-Prop $Obj.$Name $k $Values[$k] } }
}
function Set-Prop($Obj, [string]$Name, $Value) {
    if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Backup([string]$Path) {
    if (Test-Path $Path) {
        $b = "$Path.bak-{0:yyyyMMdd-HHmmss}" -f (Get-Date)
        Copy-Item $Path $b -Force
        Info "Backup: $b"
        # keep only the 5 newest backups of this file
        $leaf = Split-Path $Path -Leaf
        Get-ChildItem (Split-Path $Path -Parent) -Filter "$leaf.bak-*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Test-ExtensionInstalled([string]$ExtDir, [string]$ExtId) {
    return [bool](Get-ChildItem -Path $ExtDir -Directory -Filter "$($ExtId.ToLower())-*" -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-ExtPackage([string]$ExtDir, [string]$ExtId) {
    $dir = Get-ChildItem -Path $ExtDir -Directory -Filter "$($ExtId.ToLower())-*" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $dir) { return $null }
    try { return (Get-Content (Join-Path $dir.FullName 'package.json') -Raw | ConvertFrom-Json) } catch { return $null }
}
function Get-IconThemeId([string]$ExtDir, [string]$ExtId) {
    $pkg = Get-ExtPackage $ExtDir $ExtId
    if ($pkg) { return @($pkg.contributes.iconThemes)[0].id }
    return $null
}
function Get-ColorThemeLabel([string]$ExtDir, [string]$ExtId, [string]$Prefer) {
    $pkg = Get-ExtPackage $ExtDir $ExtId
    if (-not $pkg) { return $null }
    $themes = @($pkg.contributes.themes)
    $match = $themes | Where-Object { $_.label -and $Prefer -and $_.label -ieq $Prefer } | Select-Object -First 1
    if (-not $match) { $match = $themes | Where-Object { $_.label -and $Prefer -and $_.label -like "*$Prefer*" } | Select-Object -First 1 }
    if (-not $match) { $match = $themes | Select-Object -First 1 }
    if ($match.id) { return $match.id }
    return $match.label
}

# ---------------------------------------------------------------------------
# Settings sources: PhpStorm / VS Code / saved values
# ---------------------------------------------------------------------------
function New-Profile([string]$SourceName) {
    [pscustomobject]@{
        Source = $SourceName; Dir = $null; Keymap = ''; BaseKeymap = 'VSCode'
        Shortcuts = @(); Removed = @(); ColorScheme = $null; ThemeExtIds = @(); ThemeLabel = $null
        Compact = $false; SmoothCaret = $false; PhpPaths = @()
        CopySettings = $null; CopyKeybindings = @()
    }
}

function Convert-IdeaKeystroke([string]$ks) {
    if (-not $ks) { return $null }
    $names = @{
        back_space = 'backspace'; enter = 'enter'; insert = 'insert'; delete = 'delete'; escape = 'escape'
        page_up = 'pageup'; page_down = 'pagedown'; open_bracket = '['; close_bracket = ']'; slash = '/'
        back_slash = '\'; minus = '-'; equals = '='; comma = ','; period = '.'; semicolon = ';'
        quote = "'"; back_quote = '`'; space = 'space'; tab = 'tab'; home = 'home'; end = 'end'
        left = 'left'; right = 'right'; up = 'up'; down = 'down'; control = 'ctrl'
    }
    $parts = $ks.Trim() -split '\s+' | Where-Object { $_ -notin 'pressed', 'released', 'typed' }
    $out = foreach ($p in $parts) { if ($names.ContainsKey($p)) { $names[$p] } else { $p.ToLower() } }
    return ($out -join '+')
}

function Get-PhpStormProfile {
    $root = Join-Path $env:APPDATA 'JetBrains'
    $dir = Get-ChildItem $root -Directory -Filter 'PhpStorm*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $dir) { return $null }
    $p = New-Profile 'PhpStorm'
    $p.Dir = $dir.FullName; $p.Keymap = '$default'; $p.BaseKeymap = '$default'
    $opt = Join-Path $dir.FullName 'options'
    function LoadXml($f) { try { if (Test-Path $f) { return [xml](Get-Content $f -Raw) } } catch {} ; return $null }

    foreach ($f in @("$opt\windows\keymap.xml", "$opt\keymap.xml")) {
        $x = LoadXml $f
        if ($x) { $n = $x.SelectSingleNode('//active_keymap'); if ($n) { $p.Keymap = $n.GetAttribute('name'); break } }
    }
    $custom = @{}
    Get-ChildItem (Join-Path $dir.FullName 'keymaps') -Filter *.xml -ErrorAction SilentlyContinue | ForEach-Object {
        $x = LoadXml $_.FullName
        if ($x) { $k = $x.SelectSingleNode('/keymap'); if ($k) { $custom[$k.GetAttribute('name')] = $k } }
    }
    $name = $p.Keymap; $chain = @(); $guard = 0
    while ($custom.ContainsKey($name) -and $guard -lt 10) { $chain += $custom[$name]; $name = $custom[$name].GetAttribute('parent'); $guard++ }
    $p.BaseKeymap = $name
    [array]::Reverse($chain)
    $acts = @{}
    foreach ($km in $chain) {
        foreach ($a in $km.SelectNodes('action')) { $acts[$a.GetAttribute('id')] = @($a.SelectNodes('keyboard-shortcut')) }
    }
    foreach ($id in $acts.Keys) {
        if ($acts[$id].Count -eq 0) { $p.Removed += $id }
        else { foreach ($k in $acts[$id]) { $p.Shortcuts += [pscustomobject]@{ Action = $id; First = $k.GetAttribute('first-keystroke'); Second = $k.GetAttribute('second-keystroke') } } }
    }

    $x = LoadXml "$opt\colors.scheme.xml"
    if ($x) { $n = $x.SelectSingleNode('//global_color_scheme'); if ($n) { $p.ColorScheme = $n.GetAttribute('name') } }
    if ($p.ColorScheme -and $ThemeMap.ContainsKey($p.ColorScheme.ToLower())) { $p.ThemeExtIds = $ThemeMap[$p.ColorScheme.ToLower()] }
    $x = LoadXml "$opt\ui.lnf.xml"
    if ($x) { $n = $x.SelectSingleNode("//option[@name='UI_DENSITY']"); if ($n -and $n.GetAttribute('value') -eq 'COMPACT') { $p.Compact = $true } }
    $x = LoadXml "$opt\editor.xml"
    if ($x) { $n = $x.SelectSingleNode("//option[@name='IS_SMOOTH_CARET_MOVEMENT']"); if ($n -and $n.GetAttribute('value') -eq 'true') { $p.SmoothCaret = $true } }
    $x = LoadXml "$opt\php-tools.xml"
    if ($x) { $p.PhpPaths = @($x.SelectNodes('//phpinfo') | ForEach-Object { $_.GetAttribute('php_cli') } | Where-Object { $_ }) }
    return $p
}

function Find-ThemeProvider([string]$ExtDir, [string]$Theme) {
    foreach ($d in (Get-ChildItem $ExtDir -Directory -ErrorAction SilentlyContinue)) {
        try {
            $pkg = Get-Content (Join-Path $d.FullName 'package.json') -Raw | ConvertFrom-Json
            foreach ($t in @($pkg.contributes.themes)) {
                if ($t -and ($t.id -eq $Theme -or $t.label -eq $Theme)) { return "$($pkg.publisher).$($pkg.name)" }
            }
        } catch {}
    }
    return $null
}

function Get-VsCodeProfile {
    $dir = Join-Path $env:APPDATA 'Code\User'
    if (-not (Test-Path (Join-Path $dir 'settings.json')) -and -not (Test-Path (Join-Path $dir 'keybindings.json'))) { return $null }
    $p = New-Profile 'VS Code'
    $p.Dir = $dir
    try { $p.CopySettings = Read-Jsonc (Join-Path $dir 'settings.json') '{}' } catch { Warn "Could not read VS Code settings.json: $($_.Exception.Message)" }
    try { $p.CopyKeybindings = @(@(Read-Jsonc (Join-Path $dir 'keybindings.json') '[]') | ForEach-Object { $_ } | Where-Object { $_ }) } catch { Warn "Could not read VS Code keybindings.json" }
    if ($p.CopySettings) {
        $theme = $p.CopySettings.'workbench.colorTheme'
        if ($theme) {
            $p.ColorScheme = $theme; $p.ThemeLabel = $theme
            $ext = Find-ThemeProvider (Join-Path $env:USERPROFILE '.vscode\extensions') $theme
            if ($ext) { $p.ThemeExtIds = @($ext) }
        }
        $php = $p.CopySettings.'php.validate.executablePath'
        if ($php) { $p.PhpPaths = @($php) }
    }
    return $p
}

function Get-SavedProfile {
    $p = New-Profile 'saved values'
    $p.ColorScheme = $SavedDefaults.ColorScheme
    $p.ThemeExtIds = $SavedDefaults.ThemeExtIds
    $p.BaseKeymap  = $SavedDefaults.BaseKeymap
    $p.Compact     = $SavedDefaults.Compact
    $p.SmoothCaret = $SavedDefaults.SmoothCaret
    $p.Shortcuts   = @($SavedDefaults.Shortcuts | ForEach-Object { [pscustomobject]$_ })
    return $p
}

function Get-PhpCandidates($Prof) {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($Prof) { foreach ($x in $Prof.PhpPaths) { $paths.Add($x) } }
    Get-ChildItem (Join-Path $env:USERPROFILE '.config\herd\bin') -Directory -Filter 'php*' -ErrorAction SilentlyContinue |
        ForEach-Object { $e = Join-Path $_.FullName 'php.exe'; if (Test-Path $e) { $paths.Add($e) } }
    $g = Get-Command php.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { $paths.Add($g.Source) }

    $seen = @{}; $out = @()
    foreach ($p in $paths) {
        if (-not $p -or $seen[$p.ToLower()] -or -not (Test-Path $p)) { continue }
        $seen[$p.ToLower()] = $true
        $v = (& $p -r 'echo PHP_VERSION;' 2>$null | Out-String).Trim()
        if ($v -match '^(\d+\.\d+(\.\d+)?)') { $out += [pscustomobject]@{ Path = $p; Version = $v; Sort = [version]$Matches[1] } }
    }
    return @($out | Sort-Object Sort -Descending)
}

# ---------------------------------------------------------------------------
# Editor detection + target question
# ---------------------------------------------------------------------------
function Find-Cli([string]$Kind) {
    if ($Kind -eq 'cursor') {
        $cmd = Get-Command cursor -ErrorAction SilentlyContinue
        $paths = @("$env:LOCALAPPDATA\Programs\cursor\resources\app\bin\cursor.cmd", "$env:ProgramFiles\Cursor\resources\app\bin\cursor.cmd")
    } else {
        $cmd = Get-Command code -ErrorAction SilentlyContinue
        $paths = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd")
    }
    if ($cmd) { return $cmd.Source }
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

$Editors = @{
    cursor = @{ Label = 'Cursor';  Registry = 'openvsx';     Host = 'open-vsx.org';                 UserDir = "$env:APPDATA\Cursor\User"; ExtDir = "$env:USERPROFILE\.cursor\extensions" }
    code   = @{ Label = 'VS Code'; Registry = 'marketplace'; Host = 'marketplace.visualstudio.com'; UserDir = "$env:APPDATA\Code\User";   ExtDir = "$env:USERPROFILE\.vscode\extensions" }
}
foreach ($k in @($Editors.Keys)) { $Editors[$k].Cli = Find-Cli $k }

if (-not $Target) {
    $c = Ask-Choice 'Where do you want to install the extensions?' @(
        ("Cursor   {0}" -f $(if ($Editors.cursor.Cli) { '(found)' } else { '(NOT found)' })),
        ("VS Code  {0}" -f $(if ($Editors.code.Cli)   { '(found)' } else { '(NOT found)' })),
        'Both') 1
    $Target = @('cursor', 'code', 'both')[$c - 1]
}
$targets = if ($Target -eq 'both') { @('cursor', 'code') } else { @($Target) }

# ---------------------------------------------------------------------------
# Dev tools check: offer to run the "env" tool when PHP or Node.js is missing
# ---------------------------------------------------------------------------
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Find-EnvScript {
    # 1) next to this script in a clone (editor/ -> ../env/), 2) same folder, 3) download the latest release
    if ($PSScriptRoot) {
        foreach ($p in @((Join-Path $PSScriptRoot '..\env\setup-dev-env.ps1'), (Join-Path $PSScriptRoot 'setup-dev-env.ps1'))) {
            if (Test-Path $p) { return (Resolve-Path $p).Path }
        }
    }
    $url = 'https://github.com/Eslam-Nazer/dev-setup/releases/latest/download/setup-dev-env.ps1'
    $dest = Join-Path $env:TEMP 'setup-dev-env.ps1'
    if (-not (Ask-YesNo "The env tool is not next to this script. Download it from the latest release?" $true)) { return $null }
    try {
        Invoke-WithRetry { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop } 'Download env tool' 'github.com'
        return $dest
    } catch {
        Warn "Could not download $url"
        return $null
    }
}

if (-not $SkipEnvCheck) {
    $missing = @()
    if (-not (Get-Command php -ErrorAction SilentlyContinue))  { $missing += 'PHP (Herd / Laragon)' }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { $missing += 'Node.js' }
    if ($missing.Count) {
        Step 'Dev tools check'
        Warn ("Missing: {0}. PHP and JS extensions need them to work." -f ($missing -join ', '))
        if (Ask-YesNo 'Run the dev tools setup (env) first?' $true) {
            $envScript = Find-EnvScript
            if ($envScript) {
                Info "Running $envScript"
                & $envScript -Yes:$Yes -MaxRetries $MaxRetries
                Update-SessionPath
                if ($LASTEXITCODE -eq 0) { Ok 'Dev tools ready, continuing with the editor setup.' }
                else { Warn 'Some dev tools are still missing; continuing with the editor setup anyway.' }
            }
        } else {
            Info 'Skipped the dev tools check (run env\setup-dev-env.ps1 later, or use -SkipEnvCheck).'
        }
    }
}

# ---------------------------------------------------------------------------
# Source question: where do the settings come from?
# ---------------------------------------------------------------------------
$Prof = $null
$ApplyTheme = $false
$PhpPick = $null

if (-not $SkipSettings) {
    Step 'Settings source'
    $psProf = Get-PhpStormProfile
    $vsProf = if ($targets -contains 'cursor') { Get-VsCodeProfile } else { $null }

    $opts = @(); $keys = @()
    if ($psProf) { $opts += "PhpStorm on this PC  ($(Split-Path $psProf.Dir -Leaf): keymap, your shortcuts, theme, UI, PHP)"; $keys += 'phpstorm' }
    if ($vsProf) { $opts += "VS Code on this PC   (copy its settings.json + keybindings.json into Cursor)"; $keys += 'vscode' }
    $opts += "Saved values in this script  (poimandres theme, compact UI, VS Code keymap + Double Shift)"; $keys += 'builtin'

    $pick = $Source
    if (-not $pick -or $keys -notcontains $pick) {
        if ($Source) { Warn "Source '$Source' is not available on this PC." }
        $pick = $keys[(Ask-Choice 'Where should I take your editor settings from?' $opts 1) - 1]
    }
    $Prof = switch ($pick) { 'phpstorm' { $psProf } 'vscode' { $vsProf } default { Get-SavedProfile } }
    Ok "Using settings from: $($Prof.Source)"
    if ($Prof.Dir) { Info "Folder: $($Prof.Dir)" }
    if ($Prof.Source -eq 'PhpStorm') {
        Info "Active keymap: $($Prof.Keymap)  (based on: $($Prof.BaseKeymap))"
        Info ("Custom shortcuts: {0}, removed shortcuts: {1}" -f $Prof.Shortcuts.Count, $Prof.Removed.Count)
    }

    # Keymap: only add the IntelliJ keymap when the source is NOT VS Code-based
    if ($Prof.BaseKeymap -like 'VSCode*') {
        Ok "Keymap is VS Code-based -> keeping native VS Code shortcuts (no IntelliJ keymap)."
        $Catalog = @($Catalog | Where-Object { $_.Role -ne 'keymap' })
    }

    # Theme question
    if ($Prof.ColorScheme -and ($Prof.ThemeExtIds.Count -or $Prof.ThemeLabel)) {
        $ApplyTheme = Ask-YesNo "Change the editor color theme to '$($Prof.ColorScheme)'?" $true
        if ($ApplyTheme -and $Prof.ThemeExtIds.Count) {
            $Catalog += @{ Name = "Color theme ($($Prof.ColorScheme))"; Ids = $Prof.ThemeExtIds; Role = 'theme' }
        }
        if (-not $ApplyTheme) { Info 'Keeping your current color theme.' }
    } elseif ($Prof.ColorScheme) {
        Warn "No known VS Code equivalent for color scheme '$($Prof.ColorScheme)'; theme left unchanged."
    }

    # PHP question: change it? latest or pick a version?
    $cands = @(Get-PhpCandidates $Prof)
    if ($cands.Count) {
        if (Ask-YesNo "Set the PHP interpreter for the editor (validation + Xdebug)?" $true) {
            if ($cands.Count -eq 1 -or (Ask-YesNo "Use the latest PHP found ($($cands[0].Version))?" $true)) {
                $PhpPick = $cands[0]
            } else {
                $i = Ask-Choice 'Which PHP version?' @($cands | ForEach-Object { "PHP $($_.Version)   $($_.Path)" }) 1
                $PhpPick = $cands[$i - 1]
            }
            Ok "PHP: $($PhpPick.Version)  ($($PhpPick.Path))"
        } else { Info 'PHP interpreter left unchanged.' }
    } else {
        Info 'No PHP interpreter found (PhpStorm, Herd or PATH); skipping PHP setting.'
    }
}

# ---------------------------------------------------------------------------
# Database extension question (checked first: already-installed ones are marked)
# ---------------------------------------------------------------------------
$dbHave = @(foreach ($c in $DbExtensionChoices) {
    $h = $false
    foreach ($t in $targets) { if (Test-ExtensionInstalled $Editors[$t].ExtDir $c.Ids[0]) { $h = $true } }
    $h
})
$dbPicked = @(Ask-MultiChoice 'Add a database extension to the editor? (pick any or none)' @($DbExtensionChoices | ForEach-Object { $_.Name }) $dbHave)
foreach ($i in $dbPicked) {
    $c = $DbExtensionChoices[$i]
    $label = ($c.Name -split '\s{2,}')[0]
    $Catalog += @{ Name = "Database: $label"; Ids = $c.Ids }
    foreach ($w in @($c.With)) { if ($w) { $Catalog += @{ Name = "Database: $w"; Ids = @($w) } } }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$summary = @()

foreach ($t in $targets) {
    $ed = $Editors[$t]
    Step "$($ed.Label)"
    if (-not $ed.Cli) {
        Err "$($ed.Label) CLI not found. In $($ed.Label): Ctrl+Shift+P -> 'Install ""$t"" command in PATH', then re-run."
        continue
    }
    Info "CLI: $($ed.Cli)"
    Wait-ForInternet $ed.Host

    $installed = @(@(& $ed.Cli --list-extensions 2>$null) | ForEach-Object { $_.Trim().ToLower() })   # always an array, even with 0 or 1 extension
    $roles = @{}

    foreach ($slot in $Catalog) {
        Log ("`n- {0}" -f $slot.Name) 'White'

        # Skip extensions for tools that are not on this machine (saves editor RAM/CPU)
        if ($slot.OnlyIf -and -not (Get-Command $slot.OnlyIf -ErrorAction SilentlyContinue)) {
            Info "Skipped: '$($slot.OnlyIf)' is not installed on this PC."
            $summary += [pscustomobject]@{ Editor = $ed.Label; Extension = ($slot.Ids[0]); Status = "skipped (no $($slot.OnlyIf))" }
            continue
        }

        $already = $slot.Ids | Where-Object { $installed -contains $_.ToLower() } | Select-Object -First 1
        if ($already) {
            Ok "$already already installed"
            if ($slot.Role) { $roles[$slot.Role] = $already }
            $summary += [pscustomobject]@{ Editor = $ed.Label; Extension = $already; Status = 'already installed' }
            continue
        }

        $pick = Resolve-Slot $slot $ed.Registry
        if (-not $pick) {
            Err "No usable extension for '$($slot.Name)' (missing or deprecated everywhere)"
            $summary += [pscustomobject]@{ Editor = $ed.Label; Extension = ($slot.Ids -join ' / '); Status = 'SKIPPED: not available' }
            continue
        }
        if ($installed -contains $pick.Id.ToLower()) {
            Ok "$($pick.Id) already installed"
            if ($slot.Role) { $roles[$slot.Role] = $pick.Id }
            continue
        }

        Info "Installing $($pick.Id) v$($pick.Version)..."
        try {
            Invoke-WithRetry {
                $out = & $ed.Cli --install-extension $pick.Id --force 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw $out.Trim() }
            } "Install $($pick.Id)" $ed.Host | Out-Null

            # Verify by looking for the extension folder: no extra editor process (each CLI call costs ~150 MB RAM)
            if (Test-ExtensionInstalled $ed.ExtDir $pick.Id) {
                Ok "$($pick.Id) installed and verified"
                $installed += $pick.Id.ToLower()
                if ($slot.Role) { $roles[$slot.Role] = $pick.Id }
                $summary += [pscustomobject]@{ Editor = $ed.Label; Extension = $pick.Id; Status = 'installed' }
            } else {
                Err "$($pick.Id) did not show up after install"
                $summary += [pscustomobject]@{ Editor = $ed.Label; Extension = $pick.Id; Status = 'FAILED: not verified' }
            }
        } catch {
            Err "$($pick.Id): $($_.Exception.Message)"
            $summary += [pscustomobject]@{ Editor = $ed.Label; Extension = $pick.Id; Status = 'FAILED' }
        }
    }

    if ($SkipSettings) { continue }

    # ------------------- settings.json -------------------
    Step "$($ed.Label): settings (from $($Prof.Source))"
    New-Item -ItemType Directory -Force -Path $ed.UserDir | Out-Null
    $settingsPath = Join-Path $ed.UserDir 'settings.json'
    try {
        $s = Read-Jsonc $settingsPath '{}'
        Backup $settingsPath

        # Copy VS Code settings first (when VS Code is the source)
        if ($Prof.CopySettings -and $ed.UserDir -ne $Prof.Dir) {
            $n = 0
            foreach ($p in $Prof.CopySettings.PSObject.Properties) {
                if (-not $ApplyTheme -and $p.Name -eq 'workbench.colorTheme') { continue }
                if (-not $PhpPick -and $p.Name -in 'php.validate.executablePath', 'php.debug.executablePath') { continue }
                Set-Prop $s $p.Name $p.Value; $n++
            }
            Ok "Copied $n settings from VS Code"
        }

        if ($roles.icons) {
            $iconId = Get-IconThemeId $ed.ExtDir $roles.icons
            if ($iconId) { Set-Prop $s 'workbench.iconTheme' $iconId; Ok "Icon theme: $iconId" }
            else { Warn "Could not read the icon theme id; choose it via 'File Icon Theme' in the command palette." }
        }
        if ($ApplyTheme) {
            $themeLabel = $null
            if ($roles.theme) { $themeLabel = Get-ColorThemeLabel $ed.ExtDir $roles.theme $Prof.ColorScheme }
            if (-not $themeLabel) { $themeLabel = $Prof.ThemeLabel }
            if ($themeLabel) { Set-Prop $s 'workbench.colorTheme' $themeLabel; Ok "Color theme: $themeLabel" }
        }
        if ($Prof.SmoothCaret) {
            Set-Prop $s 'editor.cursorSmoothCaretAnimation' 'on'
            Set-Prop $s 'editor.cursorBlinking' 'smooth'
        }
        if ($Prof.Compact) { Set-Prop $s 'window.density.editorTabHeight' 'compact' }
        if ($PhpPick) {
            Set-Prop $s 'php.validate.executablePath' $PhpPick.Path
            Set-Prop $s 'php.debug.executablePath' $PhpPick.Path
            Ok "PHP $($PhpPick.Version): $($PhpPick.Path)"
        }
        Set-Prop $s 'breadcrumbs.enabled' $true          # navigation bar above the editor
        Set-Prop $s 'breadcrumbs.filePath' 'on'
        Set-Prop $s 'breadcrumbs.symbolPath' 'on'
        Set-Prop $s 'window.commandCenter' $true
        Set-Prop $s 'files.autoSave' 'onFocusChange'     # PhpStorm saves automatically
        Set-Prop $s 'editor.linkedEditing' $true
        # --- Lighter on CPU / disk / RAM -------------------------------------------
        # Do not watch or index dependency and cache folders (biggest win in Laravel / NestJS projects)
        $heavyDirs = @{ '**/vendor/**' = $true; '**/node_modules/**' = $true; '**/storage/**' = $true; '**/bootstrap/cache/**' = $true; '**/dist/**' = $true; '**/.git/objects/**' = $true }
        Merge-Prop $s 'files.watcherExclude' $heavyDirs
        Merge-Prop $s 'search.exclude' @{ '**/vendor' = $true; '**/node_modules' = $true; '**/storage' = $true; '**/bootstrap/cache' = $true; '**/dist' = $true }
        if ($installed -contains 'bmewburn.vscode-intelephense-client') {
            # Intelephense defaults + Laravel cache folders; vendor stays indexed (needed for completion), its tests do not
            $ex = @('**/.git/**', '**/.svn/**', '**/.hg/**', '**/CVS/**', '**/.DS_Store/**', '**/node_modules/**', '**/bower_components/**',
                    '**/vendor/**/{Tests,tests}/**', '**/.history/**', '**/vendor/**/vendor/**', '**/storage/**', '**/bootstrap/cache/**')
            if ($s.PSObject.Properties['intelephense.files.exclude']) { $ex = @(@($s.'intelephense.files.exclude') + $ex | Select-Object -Unique) }
            Set-Prop $s 'intelephense.files.exclude' $ex
        }
        if ($installed -contains 'orta.vscode-jest') { Set-Prop $s 'jest.runMode' 'on-demand' }   # no test runs on every save
        if ($installed -contains 'eamodio.gitlens') { Set-Prop $s 'gitlens.codeLens.enabled' $false } # fewer git calls while typing
        Set-Prop $s 'php.suggest.basic' $false           # let Intelephense own PHP completion
        Set-Prop $s 'intelephense.format.enable' $false  # Pint handles PHP formatting
        if ($installed -contains 'open-southeners.laravel-pint') {
            Set-Prop $s '[php]' ([pscustomobject]@{ 'editor.defaultFormatter' = 'open-southeners.laravel-pint' })
        }
        if ($installed -contains 'esbenp.prettier-vscode') {
            foreach ($lang in '[typescript]', '[javascript]', '[json]', '[vue]') {
                Set-Prop $s $lang ([pscustomobject]@{ 'editor.defaultFormatter' = 'esbenp.prettier-vscode' })
            }
        }
        if ($roles.newfile -eq 'patbenatar.advanced-new-file') {
            Set-Prop $s 'advancedNewFile.showInformationMessages' $false
        }
        Write-Json $settingsPath $s
        Ok "settings.json updated"
    } catch { Err "settings.json not changed (parse error?): $($_.Exception.Message)" }

    # ------------------- keybindings.json -------------------
    $kbPath = Join-Path $ed.UserDir 'keybindings.json'
    try {
        $parsed = Read-Jsonc $kbPath '[]'
        $kb = New-Object System.Collections.ArrayList
        @($parsed | ForEach-Object { $_ }) | Where-Object { $_ } | ForEach-Object { [void]$kb.Add($_) }
        Backup $kbPath

        $wanted = @(
            [pscustomobject]@{ key = 'shift shift'; command = 'workbench.action.quickOpen' }   # Double Shift = Search Everywhere
            [pscustomobject]@{ key = 'alt+home'; command = 'breadcrumbs.focusAndSelect'; when = 'breadcrumbsPossible' }
        )
        if ($roles.newfile -eq 'patbenatar.advanced-new-file') {
            $wanted += [pscustomobject]@{ key = 'ctrl+alt+n'; command = 'extension.advancedNewFile' }
        }
        # VS Code shortcuts (when VS Code is the source)
        if ($Prof.CopyKeybindings.Count -and $ed.UserDir -ne $Prof.Dir) {
            $wanted += $Prof.CopyKeybindings
            Ok "Copying $($Prof.CopyKeybindings.Count) shortcuts from VS Code"
        }
        # PhpStorm / saved shortcut customisations
        foreach ($sc in $Prof.Shortcuts) {
            $m = $ActionMap[$sc.Action]
            if (-not $m) { Warn "PhpStorm action '$($sc.Action)' has no VS Code equivalent, skipped"; continue }
            $key = Convert-IdeaKeystroke $sc.First
            if ($sc.Second) { $key = "$key $(Convert-IdeaKeystroke $sc.Second)" }
            $entry = [pscustomobject]@{ key = $key; command = $m[0] }
            if ($m[1]) { $entry | Add-Member -NotePropertyName when -NotePropertyValue $m[1] }
            $wanted += $entry
            Info "Shortcut: $($sc.Action) -> $key = $($m[0])"
        }
        if ($Prof.Removed.Count) { Info ("Unbound in PhpStorm (nothing to copy): {0}" -f ($Prof.Removed -join ', ')) }

        foreach ($w in $wanted) {
            if (-not ($kb | Where-Object { $_.key -eq $w.key -and $_.command -eq $w.command })) { [void]$kb.Add($w) }
        }
        Write-Json $kbPath ([object[]]$kb.ToArray())
        Ok "keybindings.json updated (Double Shift = search, Alt+Home = nav bar, Ctrl+Alt+N = new file at path)"
    } catch { Err "keybindings.json not changed: $($_.Exception.Message)" }

    if ($t -eq 'cursor') {
        Warn "Cursor keeps its own AI shortcuts (Ctrl+K, Ctrl+L, Ctrl+I)."
    }
}

# ---------------------------------------------------------------------------
Step 'Summary'
$summary | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { Log $_ 'White' }
Log "Log file: $LogFile" 'DarkGray'
Log "Restart the editor to load everything. Re-run this script any time; it skips what is already installed." 'Cyan'
