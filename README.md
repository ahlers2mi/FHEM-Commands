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

### 3. Ein Gerät mit mehrzeiligem Perl-Block anlegen (`define`)

Für ein einzelnes Gerät, dessen Definition einen **mehrzeiligen Perl-Block** enthält (Notify/DOIF), gibt es den Set-Befehl **`define`**. Anders als `execute` zerlegt er die Eingabe **nicht** zeilenweise, sondern legt per `defmod` genau ein Gerät an bzw. aktualisiert es – der Block bleibt erhalten:

```
define n_velux_regen notify MQTT2_RAIN_SOLAR:rain:.* {
  if (ReadingsVal("MQTT2_RAIN_SOLAR","rain","false") eq "true" && ReadingsVal("Velux_1","pct",0) > 0){
    fhem("set Velux_1 pct 0");
    fhem("setreading Velux_1 auto_on off");
  }
}
```

- Einfügen wie im **DEF-Editor**: einfaches `;`, normale Zeilenumbrüche, kein `\`.
- cfg-Stil mit `;;` und `\`-Zeilenfortsetzung wird automatisch in einfaches `;` konvertiert.
- Ein voranstehendes `define`/`defmod` ist optional und wird abgeschnitten.
- `defmod` legt neu an **oder** aktualisiert – derselbe Block kann zum Ändern erneut eingefügt werden.

---

## Attribute

| Attribut       | Standard | Beschreibung                                                                 |
|----------------|----------|------------------------------------------------------------------------------|
| `stopOnError`  | 1        | `1` = nach dem ersten Fehler abbrechen, `0` = alle Befehle ausführen          |
| `disable`      | 0        | `1` = Ausführung deaktivieren                                                 |

---

## Readings

| Reading      | Beschreibung                                                            |
|--------------|-------------------------------------------------------------------------|
| `state`      | `idle` / `done (x ok)` / `error at x` / `done (x ok, y errors)`; nach `define`: `defined (<name>)` / `define error` |
| `executed`   | Anzahl erfolgreich ausgeführter Befehle (`execute`)                     |
| `errorCount` | Anzahl fehlerhafter Befehle des letzten Laufs (`execute`)               |
| `lastError`  | Zuletzt aufgetretener Fehler (bei `execute` mit Zeilennummer)           |

---

## Hinweise

- Bei `execute` muss ein literales Semikolon innerhalb eines Befehls wie in FHEM üblich als `;;` geschrieben werden. Bei `define` ist das **nicht** nötig (einfaches `;` wie im DEF-Editor; `;;`/`\` werden zusätzlich toleriert).
- `get`-Befehle, die einen Wert zurückliefern, werden als „Fehler" gewertet (nicht-leere Rückgabe). Das Modul ist für ausführende Befehle (`attr`, `define`, `set`, `delete`, …) gedacht.
