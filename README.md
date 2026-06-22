# FHEM-Commands

FHEM-Hilfsmodul, um **mehrere FHEM-Befehle auf einmal auszuführen** – statt sie einzeln nacheinander in das Kommandofeld zu tippen. Optional wird beim ersten fehlerhaften Befehl gestoppt.

---

## Übersicht

Das Modul stellt das FHEM-Kommando **`runcmds`** bereit. Damit kann ein ganzer Block von Befehlen (typischerweise mehrere `attr`-, `define`- oder `set`-Zeilen) **in einem Rutsch** eingefügt und abgearbeitet werden.

- Ein Befehl pro Zeile.
- Leerzeilen und mit `#` beginnende Zeilen werden ignoriert.
- Standardmäßig stoppt die Abarbeitung beim **ersten Fehler**. Ein Befehl gilt als fehlerhaft, wenn er einen nicht-leeren Rückgabewert (Fehlermeldung) liefert.
- Kein Device, kein Attribut, keine Verwaltung nötig.

---

## Installation

### Manuell

```bash
cp FHEM/99_Commands.pm /opt/fhem/FHEM/
```

`99_`-Module werden beim FHEM-Start automatisch geladen. Einmalig ohne Neustart aktivieren:

```
reload 99_Commands
```

### Über FHEM Update

```
update add https://raw.githubusercontent.com/ahlers2mi/FHEM-Commands/main/controls_Commands.txt
update
```

---

## Verwendung

### Kommando `runcmds`

```
runcmds [-c] <befehlsblock>
```

Im FHEM-Kommandofeld einfach `runcmds` voranstellen und den kompletten Block auf einmal einfügen:

```
runcmds
# Sensoren
attr poolControl poolSensor       MQTT2_Sonoff_TH10_01:poolTemp
attr poolControl inflowSensor     MQTT2_Sonoff_TH10_01:solarTemp

# Sollwerte
set poolControl targetTemp   30
set poolControl filterHours  5
```

- Standard: Abbruch beim ersten Fehler – die Rückgabe nennt die betroffene Zeile.
- Mit `-c` werden **alle** Befehle ausgeführt und auftretende Fehler am Ende gesammelt gemeldet:

```
runcmds -c
attr a room Wohnzimmer
attr b room Küche
```

### Perl-Funktion `runCmds`

Für die Verwendung in `notify`, `at` oder `99_myUtils`:

```perl
{ runCmds("attr a room X\nattr b room Y", 0) }
```

| Parameter         | Beschreibung                                              |
|-------------------|----------------------------------------------------------|
| 1. Befehlsblock   | Befehle, durch Zeilenumbruch (`\n`) getrennt             |
| 2. continueOnError| `0` = Stopp beim ersten Fehler (Standard), `1` = weiter  |

Rückgabe: eine Zusammenfassung bzw. die gesammelten Fehlermeldungen als Text.

---

## Hinweise

- Innerhalb eines Befehls muss ein literales Semikolon wie in FHEM üblich als `;;` geschrieben werden.
- `get`-Befehle, die einen Wert zurückliefern, werden als „Fehler" gewertet (nicht-leere Rückgabe). Das Modul ist für ausführende Befehle (`attr`, `define`, `set`, `delete`, …) gedacht.
