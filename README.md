# WinCustAdp

One-Click-Anpassungen für Windows 11.

## Ausführen

**Doppelklick auf `Install.cmd`** – fertig.

Das Skript fordert Admin-Rechte an, sichert die betroffenen Registry-Schlüssel, importiert alle Registry-Tweaks, führt alle Skripte aus und startet den Explorer neu.

Optionen (über PowerShell):

```powershell
.\Install.ps1 -WhatIf              # nur anzeigen, nichts ändern
.\Install.ps1 -NoRestartExplorer   # Explorer nicht neu starten
.\Install.ps1 -NoPause             # am Ende nicht auf Enter warten
```

## Struktur

```
WinCustAdp/
├── Install.cmd     One-Click-Starter (Doppelklick)
├── Install.ps1     Master-Skript, führt alles aus
├── registry/       .reg-Dateien, eine Funktion pro Datei
├── scripts/        .ps1-Dateien für alles, was .reg nicht kann
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

## Rückgängig machen

Jeder Lauf legt unter `backups/<Zeitstempel>/` den vorherigen Zustand der betroffenen Schlüssel ab.
Die gewünschte `.reg`-Datei dort per Doppelklick importieren.
Existierte ein Schlüssel vorher nicht, gibt es keine Sicherung – dann hilft der „Undo“-Hinweis in der Tweak-Datei.

## Hinweis

`HKCU`-Tweaks gelten für das Konto, unter dem das Skript mit Admin-Rechten läuft.
Wenn du als Standardbenutzer arbeitest und dich mit einem separaten Admin-Konto anmeldest, landen sie beim Admin-Konto.
