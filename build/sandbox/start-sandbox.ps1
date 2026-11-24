<#
  build/sandbox/start-sandbox.ps1
  Opens a clean, throw-away Windows Sandbox with this repo mapped (read-only) at C:\jahiz,
  so you can test the tools on a fresh Windows without touching your own machine.
  Everything inside the sandbox is deleted when you close it.

  Needs Windows 10/11 Pro, Enterprise or Education with the "Windows Sandbox" feature.
  Run from the repo:  powershell -NoProfile -ExecutionPolicy Bypass -File .\build\sandbox\start-sandbox.ps1
  Options: -MemoryMB 4096 (RAM the sandbox may use; keep it modest on laptops)
#>
[CmdletBinding()]
param([int]$MemoryMB = 4096)
$ErrorActionPreference = 'Stop'

$exe = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
if (-not (Test-Path $exe)) {
    Write-Host 'Windows Sandbox is not enabled on this PC.' -ForegroundColor Yellow
    Write-Host 'Enable it once from an admin PowerShell, then restart Windows:'
    Write-Host '  Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
    Write-Host '(Windows Home does not include Windows Sandbox.)'
    exit 1
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wsb  = Join-Path $env:TEMP 'jahiz-test.wsb'
$xml = @"
<Configuration>
  <MemoryInMB>$MemoryMB</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$repo</HostFolder>
      <SandboxFolder>C:\jahiz</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File C:\jahiz\build\sandbox\prepare-sandbox.ps1</Command>
  </LogonCommand>
</Configuration>
"@
Set-Content -Path $wsb -Value $xml -Encoding UTF8
Write-Host "Starting Windows Sandbox with $repo mapped read-only at C:\jahiz ..." -ForegroundColor Cyan
Start-Process -FilePath $wsb
