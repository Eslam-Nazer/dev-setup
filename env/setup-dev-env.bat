@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-dev-env.ps1" %*
pause
