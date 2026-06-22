# FHEM-Commands

FHEM-Modul, um **mehrere FHEM-Befehle auf einmal auszuführen** – über ein großes Eingabefenster (`textField-long`), in das ein kompletter Befehlsblock eingefügt wird. Optional wird beim ersten fehlerhaften Befehl gestoppt.

---

## Übersicht

Das Modul `Commands` stellt den Set-Befehl **`execute`** bereit. Dieser öffnet im FHEMWEB ein großes Texteingabefenster, in das ein ganzer Block von Befehlen (typischerweise mehrere `attr`-, `define`- oder `set`-Zeilen) **in einem Rutsch** eingefügt werden kann.

- Ein Befehl pro Zeile.
- Leerzeilen und mit `#` beginnende Zeilen werden ignoriert.
- Standardmäßig stoppt die Abarbeitung beim **ersten Fehler** (Attribut `stopOnError`). Ein Befehl gilt als fehlerhaft, wenn er einen nicht-leeren Rückgabewert (Fehlermeldung) liefert.

---

## Installation

### Manuell

```bash
cp FHEM/98_Commands.pm /opt/fhem/FHEM/
```

Danach in der FHEM-Konsole:

```
reload 98_Commands
```

### Über FHEM Update

```
update add https://raw.githubusercontent.com/ahlers2mi/FHEM-Commands/main/controls_Commands.txt
update
```

---

## Verwendung

### 1. Gerät anlegen (einmalig)

```
define meineBefehle Commands
```

### 2. Befehle ausführen

Im FHEMWEB auf das Gerät klicken, beim Set-Befehl **`execute`** öffnet sich ein großes Eingabefenster. Dort den kompletten Block einfügen und absenden:

```
# Sensoren
attr poolControl poolSensor       MQTT2_Sonoff_TH10_01:poolTemp
attr poolControl inflowSensor     MQTT2_Sonoff_TH10_01:solarTemp

# Sollwerte
set poolControl targetTemp   30
set poolControl filterHours  5
```

Die Zeilen werden nacheinander abgearbeitet. Bei einem Fehler stoppt die Ausführung (Standard) und das Reading `lastError` nennt die betroffene Zeile.

---

## Attribute

| Attribut      | Standard | Beschreibung                                                                 |
|---------------|----------|------------------------------------------------------------------------------|
| `stopOnError` | 1        | `1` = nach dem ersten Fehler abbrechen, `0` = alle Befehle ausführen          |
| `disable`     | 0        | `1` = Ausführung deaktivieren                                                 |

---

## Readings

| Reading      | Beschreibung                                                            |
|--------------|-------------------------------------------------------------------------|
| `state`      | `idle` / `done (x ok)` / `error at x` / `done (x ok, y errors)`         |
| `executed`   | Anzahl erfolgreich ausgeführter Befehle                                 |
| `errorCount` | Anzahl fehlerhafter Befehle des letzten Laufs                           |
| `lastError`  | Zuletzt aufgetretener Fehler (mit Zeilennummer)                         |

---

## Hinweise

- Innerhalb eines Befehls muss ein literales Semikolon wie in FHEM üblich als `;;` geschrieben werden.
- `get`-Befehle, die einen Wert zurückliefern, werden als „Fehler" gewertet (nicht-leere Rückgabe). Das Modul ist für ausführende Befehle (`attr`, `define`, `set`, `delete`, …) gedacht.
