<#
  build/sandbox/prepare-sandbox.ps1
  Runs automatically inside the Windows Sandbox opened by start-sandbox.ps1.
  Windows Sandbox has no winget, so this installs it the official way
  (Microsoft.WinGet.Client module -> Repair-WinGetPackageManager), then shows the test steps.
#>
$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'dev-setup test sandbox'
Write-Host 'Preparing the sandbox: installing winget (2-5 minutes)...' -ForegroundColor Cyan
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -AllowClobber | Out-Null
    Import-Module Microsoft.WinGet.Client
    Repair-WinGetPackageManager -Latest -Force | Out-Null
    $v = (winget --version) 2>$null
    Write-Host "winget $v is ready." -ForegroundColor Green
} catch {
    Write-Host "Could not install winget automatically: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host 'The tools still run; installs will fall back to "download it from <url>".'
}

Write-Host @'

Test steps (see docs/testing.md for the full checklist):
  1. Check only:       C:\dev-setup\env\setup-dev-env.ps1 -CheckOnly
  2. Dry run:          C:\dev-setup\setup.ps1 -DryRun -Target both
  3. Full run:         C:\dev-setup\setup.ps1
  4. Restore settings: C:\dev-setup\editor\setup-dev-extensions.ps1 -Restore -Target code
Logs: %LOCALAPPDATA%\dev-setup\   (copy them out before closing; the sandbox is wiped on close)
'@ -ForegroundColor Cyan
