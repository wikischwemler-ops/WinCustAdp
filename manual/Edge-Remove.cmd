@echo off
rem Uninstalls Microsoft Edge - only if another browser is installed.
rem Double-click; asks for administrator rights.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_Run.ps1" -Script "%~dp0Edge-Remove.ps1" %*
