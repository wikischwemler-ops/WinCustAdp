@echo off
rem One-click launcher: double-click to apply all customizations.
rem Bypasses the execution policy for this run only; Customize.ps1 asks for admin rights itself.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Customize.ps1" %*
