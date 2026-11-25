@echo off
rem Removes the apps from config\apps-remove.json - same as in Customize.cmd, just on its own.
rem Double-click; asks for administrator rights.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_Run.ps1" -Script "%~dp0..\scripts\Apps-Remove.ps1" %*
