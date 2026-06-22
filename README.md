# FHEM-Commands

FHEM-Modul zum **sequentiellen Ausführen mehrerer FHEM-Befehle** – mit der Option, nach dem ersten fehlerhaften Befehl zu stoppen.

---

## Inhaltsverzeichnis

- [Übersicht](#übersicht)
- [Installation](#installation)
- [Define](#define)
- [Set](#set)
- [Get](#get)
- [Attribute](#attribute)
- [Readings](#readings)
- [Beispiele](#beispiele)

---

## Übersicht

Das Modul **Commands** führt eine Liste von FHEM-Befehlen nacheinander aus. Die Befehle werden im Attribut `commandList` hinterlegt (ein Befehl pro Zeile) und über `set <name> execute` gestartet.

Die Abarbeitung erfolgt **nicht-blockierend** (über `InternalTimer`), sodass FHEM während der Ausführung – insbesondere bei gesetztem `delay` – reaktionsfähig bleibt.

Per Attribut `stopOnError` (Standard: aktiv) lässt sich festlegen, ob die Sequenz nach dem ersten fehlerhaften Befehl abgebrochen oder vollständig durchlaufen wird. Ein Befehl gilt als fehlerhaft, wenn seine Ausführung einen nicht-leeren Rückgabewert (Fehlermeldung) liefert.

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

## Define

```
define <name> Commands
```

Es werden keine weiteren Parameter benötigt. Die auszuführenden Befehle werden anschließend über das Attribut `commandList` oder per `set <name> add` festgelegt.

**Beispiel:**

```
define meineSequenz Commands
attr meineSequenz commandList set lampe1 on
set lampe2 on
set rollo down
```

---

## Set

| Befehl              | Beschreibung                                                       |
|---------------------|--------------------------------------------------------------------|
| `execute` / `start` | Führt die Befehlsliste sequentiell aus                             |
| `stop`              | Bricht eine laufende Sequenz ab                                    |
| `add <command>`     | Hängt einen Befehl an die `commandList` an                         |
| `clear`             | Leert die `commandList`                                            |

---

## Get

| Befehl | Beschreibung                                  |
|--------|-----------------------------------------------|
| `list` | Zeigt die hinterlegten Befehle nummeriert an  |

---

## Attribute

| Attribut      | Standard | Beschreibung                                                                                   |
|---------------|----------|------------------------------------------------------------------------------------------------|
| `commandList` | –        | Die auszuführenden FHEM-Befehle, ein Befehl pro Zeile. Leerzeilen und mit `#` beginnende Zeilen werden ignoriert. |
| `stopOnError` | 1        | `1` = Sequenz nach dem ersten Fehler abbrechen, `0` = alle Befehle ausführen                   |
| `delay`       | 0        | Pause in Sekunden zwischen den Befehlen                                                         |
| `disable`     | 0        | `1` = Ausführung deaktivieren                                                                   |

---

## Readings

| Reading       | Beschreibung                                                            |
|---------------|-------------------------------------------------------------------------|
| `state`       | `idle` / `running x/n` / `done` / `error at x/n` / `stopped`            |
| `executed`    | Anzahl der bisher ausgeführten Befehle                                  |
| `errorCount`  | Anzahl der fehlerhaften Befehle des letzten Laufs                       |
| `lastCommand` | Zuletzt ausgeführter Befehl                                             |
| `lastResult`  | Rückgabe des zuletzt ausgeführten Befehls                               |
| `lastError`   | Zuletzt aufgetretener Fehler                                            |

---

## Beispiele

### Mehrere Geräte nacheinander einschalten, Stopp bei Fehler

```
define gutenMorgen Commands
attr gutenMorgen commandList set kaffeemaschine on
set licht_kueche on
set rollo_wohnzimmer up
# stopOnError ist standardmäßig aktiv
```

Starten:

```
set gutenMorgen execute
```

### Alle Befehle ausführen, Fehler ignorieren, mit 2 Sekunden Pause

```
attr gutenMorgen stopOnError 0
attr gutenMorgen delay 2
set gutenMorgen execute
```

### Befehle per set verwalten

```
set gutenMorgen add set heizung comfort
get gutenMorgen list
set gutenMorgen clear
```
