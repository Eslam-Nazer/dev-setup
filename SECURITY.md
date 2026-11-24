# Security Policy

## Supported versions

Only the **latest release** receives fixes. Please update before reporting.

## Report a vulnerability

Report privately. Do **not** open a public issue.

Use GitHub's **Report a vulnerability** button (private security advisory) on the
[Eslam-Nazer/jahiz](https://github.com/Eslam-Nazer/jahiz) repository: Security tab, then *Report a vulnerability*.

Include what you found, the version (`-Version`), and steps to reproduce.

## What the scripts do for safety

- **Verified downloads:** every release has a `SHA256SUMS.txt`. `jahiz.ps1` verifies the tools against it before running them.
- **Composer installer:** runs only when it has a valid Authenticode signature.
- **Trusted sources only:** installs come from winget (official publishers' packages), Open VSX / VS Code Marketplace, npm, and official vendor installers.
- **No passwords:** database installers run interactively, so you set the passwords yourself. The scripts never see or store passwords.
- **Logs contain no secrets.**
- **Consent:** nothing is installed without asking. `-Yes` accepts defaults but still skips optional heavy tools.
- **Safe checks:** `-DryRun` and `-CheckOnly` install nothing.

## Verify a download

Compute the hash and compare it with the matching line in `SHA256SUMS.txt` from the same release:

```powershell
(Get-FileHash .\jahiz.ps1 -Algorithm SHA256).Hash
```
