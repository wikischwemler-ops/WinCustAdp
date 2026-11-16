# CR95HF NFC-Tool (MB1054A)

- `firmware/` – STM32F103CB als USB-CDC-zu-SPI-Brücke zum CR95HF (libopencm3).
- `pc/` – WinForms-Programm: Tag lesen, als Hex anzeigen, geänderte Blöcke zurückschreiben.

Unterstützt: ISO 15693 und NTAG/Ultralight (Lesen und Schreiben), MIFARE Classic, 14443A Typ 4, 14443B und FeliCa (nur UID).

## Firmware bauen und flashen

Benötigt: Arm GNU Toolchain, `make` und Git-Bash (libopencm3 wird beim ersten Build geklont).

```bash
cd nfc-cr95hf/firmware && make && make flash
```

Ermittelt am Board: USB-Pull-up über PB0 (aktiv low), CR95HF an SPI1 (PA4 NSS, PA5–7). Den Pin für das Wecksignal (IRQ_IN) findet die Firmware beim Start selbst (Befehl `F1` meldet die gefundene Verbindung). Getestet mit einer MIFARE Ultralight EV1: Lesen und Schreiben funktionieren.

Test über die Kommandozeile (`--write` ändert den letzten Nutzerblock und stellt ihn wieder her):

```bash
nfc-cr95hf/pc/bin/Debug/net10.0-windows/Cr95hfTool.exe --write          # Port wird automatisch erkannt, optional COMx angeben
```

## PC-Software

```bash
dotnet run --project nfc-cr95hf/pc
```

Der COM-Port des MB1054A wird beim Start automatisch erkannt und verbunden (USB-Kennung 0483:5740), danach **Lesen**, Hex-Werte ändern und **Zurückschreiben**. Grau markierte Blöcke (Herstellerdaten und Konfiguration) sind gesperrt.
