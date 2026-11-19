@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-dev-extensions.ps1" %*
pause
