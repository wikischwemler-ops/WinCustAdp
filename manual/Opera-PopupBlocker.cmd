@echo off
rem One click: Opera without cookie banners, newsletter popups and split screen.
rem Imports registry\Opera-PopupBlocker-On.reg (needs admin), closes Opera,
rem turns split screen off (opera_prefs.py), restarts Opera and opens the
rem uBlock Origin store page if it is not installed yet.
net session >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "OPERA=%LOCALAPPDATA%\Programs\Opera\opera.exe"
set "UBO=%APPDATA%\Opera Software\Opera Stable\Default\Extensions\kccohkcpppjjkkjppopfnflnebibpida"

reg import "%~dp0..\registry\Opera-PopupBlocker-On.reg" || (echo Import fehlgeschlagen. & pause & exit /b 1)
echo Filterlisten-Richtlinie gesetzt.

rem Opera must be closed, otherwise it overwrites its settings on exit.
taskkill /im opera.exe >nul 2>&1 && echo Opera wird geschlossen, offene Tabs kommen wieder.
for /l %%i in (1,1,15) do (
  tasklist /fi "imagename eq opera.exe" | find /i "opera.exe" >nul || goto closed
  timeout /t 1 /nobreak >nul
)
taskkill /f /im opera.exe >nul 2>&1
timeout /t 2 /nobreak >nul
:closed

py -3 "%~dp0opera_prefs.py" || echo Split Screen nicht umgestellt: Python fehlt oder Fehler.

if exist "%UBO%" (
  start "" "%OPERA%"
  echo Fertig.
) else (
  start "" "%OPERA%" "https://addons.opera.com/de/extensions/details/ublock/"
  echo uBlock Origin fehlt noch: In Opera auf "Zu Opera hinzufuegen" klicken.
  echo Danach Opera einmal schliessen und neu oeffnen.
)
pause
