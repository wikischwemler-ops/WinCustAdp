@echo off
rem One-click launcher: double-click to apply all customizations.
rem Bypasses the execution policy for this run only; Install.ps1 asks for admin rights itself.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
