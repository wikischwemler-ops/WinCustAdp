# WinCustAdp

One-Click-Anpassungen für Windows 11.

## Ausführen

**Doppelklick auf `Customize.cmd`** – fertig.

Das Skript fordert Admin-Rechte an, sichert die betroffenen Registry-Schlüssel, importiert alle Registry-Tweaks, führt alle Skripte aus und startet den Explorer neu.

Optionen (über PowerShell):

```powershell
.\Customize.ps1 -WhatIf              # nur anzeigen, nichts ändern
.\Customize.ps1 -NoRestartExplorer   # Explorer nicht neu starten
.\Customize.ps1 -NoPause             # am Ende nicht auf Enter warten
```

## Struktur

```
WinCustAdp/
├── Customize.cmd   One-Click-Starter (Doppelklick)
├── Customize.ps1   Master-Skript, führt alles aus
├── registry/       .reg-Dateien, eine Funktion pro Datei
├── scripts/        .ps1-Dateien für alles, was .reg nicht kann
├── config/         Listen für die Skripte, z. B. zu entfernende Apps
├── tools/          Hilfen fürs Repo selbst (nicht von Customize.ps1 ausgeführt)
├── .githooks/      Prüfung der Branch-Namen beim Push
├── .github/        GitHub-Ruleset für Branch-Namen
├── backups/        (automatisch) Registry-Sicherung pro Lauf
└── logs/           (automatisch) Protokoll pro Lauf
```

Reihenfolge: zuerst alle `registry/*.reg`, dann alle `scripts/*.ps1`, jeweils alphabetisch.
Dateien, die mit `_` beginnen, werden übersprungen (Vorlagen oder deaktivierte Tweaks).

## Neuen Tweak hinzufügen

**Registry:** `registry/_Template.reg` kopieren und nach Funktion benennen:
`<Bereich>-<Funktion>-<Zustand>.reg`, z. B. `Taskbar-Widgets-Off.reg`.
In jede Datei gehört ein Kommentar, was sie tut und wie man es rückgängig macht.

**Skript:** `scripts/_Template.ps1` kopieren, z. B. `Apps-RemoveBloatware.ps1`.

Einen Tweak deaktivieren: Datei mit `_` davor umbenennen.

## Enthaltene Tweaks

| Datei | Wirkung |
|---|---|
| `Explorer-AutoSuggest-Off.reg` | Keine Vorschlagsliste in der Adressleiste / im Ausführen-Dialog |
| `Explorer-InlineAutoComplete-Off.reg` | Keine Inline-Vervollständigung von Pfaden beim Tippen |
| `Explorer-ClassicContextMenu-On.reg` | Rechtsklick zeigt sofort das klassische, vollständige Kontextmenü |
| `Explorer-ContextMenu-BCVergleich-Remove.reg` | Eigenen Ordner-Eintrag „Mit Beyond Compare vergleichen“ entfernen |
| `Search-Web-Off.reg` | Suche ohne Web-/Bing-Ergebnisse |
| `Search-Permissions.reg` | *Suchberechtigungen*: SafeSearch aus, keine Cloud-Treffer (Microsoft-/Geschäftskonto), kein Suchverlauf, keine Suchhighlights |
| `Search-Indexing-Classic.reg` | *Windows durchsuchen*: Indizierung „Klassisch“ (nur Bibliotheken und Desktop), Energieeinstellungen beim Indizieren ignorieren |

Die Suche findet danach noch Apps, Einstellungen und lokale Dateien. Dateien zusätzlich ausblenden: Einstellungen → Datenschutz und Sicherheit → *Windows durchsuchen* → **Klassisch**, unter *Suchorte anpassen* alles außer dem Startmenü abwählen.

## Apps entfernen

`scripts/Apps-Remove.ps1` entfernt alle Apps aus [`config/apps-remove.json`](config/apps-remove.json) – für alle Benutzer und aus dem Windows-Abbild, damit sie für neue Benutzer nicht wiederkommen. Nicht installierte Apps werden übersprungen.

App hinzufügen: Paketnamen in die Liste `remove` eintragen. Namen finden:

```powershell
Get-AppxPackage | Where-Object { -not $_.IsFramework } | Select-Object Name | Sort-Object Name
```

Platzhalter sind erlaubt, z. B. `"Microsoft.Xbox*"`. Einzeln testen (als Admin): `.\scripts\Apps-Remove.ps1 -WhatIf`

Entfernte Apps lassen sich über den Microsoft Store neu installieren.

## Rückgängig machen

Jeder Lauf legt unter `backups/<Zeitstempel>/` den vorherigen Zustand der betroffenen Schlüssel ab.
Die gewünschte `.reg`-Datei dort per Doppelklick importieren.
Existierte ein Schlüssel vorher nicht, gibt es keine Sicherung – dann hilft der „Undo“-Hinweis in der Tweak-Datei.

## Branch-Namen

Neue Branches nur zweistufig als `xxx/yyy`, klein geschrieben: `xxx` = Präfix (`feat`, `fix`, `docs`, `chore` … oder der Windows-Benutzer wie `hp840g6`), `yyy` = funktionaler Name, z. B. `feat/taskbar-tweaks`. Flache Namen (`fix-taskbar`) und tiefere (`feat/a/b`) werden beim Anlegen abgelehnt.

- **Regeln:** `.githooks/branch-rules.json`
- **Lokal beim Push:** einmal je Klon `tools\git_hooks_einrichten.bat` ausführen (oder `git config core.hooksPath .githooks`).
- **Auf GitHub (verbindlich):** Settings → Rules → Rulesets → New ruleset → **Import a ruleset** → `.github/rulesets/branch-names.json`.
- Einzelnen Namen prüfen: `py .githooks/branch_check.py --name feat/taskbar-tweaks`

## Hinweis

`HKCU`-Tweaks gelten für das Konto, unter dem das Skript mit Admin-Rechten läuft.
Wenn du als Standardbenutzer arbeitest und dich mit einem separaten Admin-Konto anmeldest, landen sie beim Admin-Konto.
