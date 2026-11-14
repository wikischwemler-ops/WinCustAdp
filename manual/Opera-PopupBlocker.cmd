@echo off
rem One click: Opera without cookie banners and newsletter popups.
rem Imports registry\Opera-PopupBlocker-On.reg (needs admin), restarts Opera
rem and opens the uBlock Origin store page if it is not installed yet.
net session >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "OPERA=%LOCALAPPDATA%\Programs\Opera\opera.exe"
set "UBO=%APPDATA%\Opera Software\Opera Stable\Default\Extensions\kccohkcpppjjkkjppopfnflnebibpida"

reg import "%~dp0..\registry\Opera-PopupBlocker-On.reg" || (echo Import fehlgeschlagen. & pause & exit /b 1)
echo Filterlisten-Richtlinie gesetzt.

tasklist /fi "imagename eq opera.exe" | find /i "opera.exe" >nul && (
  echo Opera wird neu gestartet, offene Tabs kommen wieder.
  taskkill /im opera.exe >nul 2>&1
  timeout /t 3 /nobreak >nul
)

if exist "%UBO%" (
  start "" "%OPERA%"
  echo Fertig. uBlock Origin ist installiert und nutzt die Listen beim naechsten Start.
) else (
  start "" "%OPERA%" "https://addons.opera.com/de/extensions/details/ublock/"
  echo uBlock Origin fehlt noch: In Opera auf "Zu Opera hinzufuegen" klicken.
  echo Danach Opera einmal schliessen und neu oeffnen.
)
pause
