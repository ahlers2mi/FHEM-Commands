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

### 4. Update mit Nacharbeit (`update`)

Wer mehrere eigene Repos per `update add` eingebunden hat, macht nach jeder
Änderung immer dasselbe: `update`, warten, `reload <Modul>`, dann das Gerät
`modify`en oder neu einlesen. Das nimmt **`set <name> update`** ab:

```
set meineBefehle update
```

Der Ablauf:

1. Zeitstempel und Größe aller `<modpath>/FHEM/NN_*.pm` merken.
2. `update all` ausführen. Verlangt FHEM dabei einen **Neustart**, wird
   abgebrochen (`state` = `update: Neustart noetig`) – ein halb geladener
   Zustand wäre schlimmer als ein sichtbar stehengebliebenes Update.
3. Alle 5 s nachsehen, bis sich **zwei Runden lang nichts** mehr geändert hat.
   Damit ist egal, wie lange das Update braucht und ob es im Hintergrund läuft
   (`attr global updateInBackground`). Nach `updateTimeout` Sekunden
   (Standard 180) wird mit dem gearbeitet, was da ist.
4. Genau die **geänderten** Module per `reload` neu laden – `98_Commands.pm`
   als letztes, weil der laufende Aufruf in eben diesem Code steckt.
5. Die Nacharbeit aus `updatePost` ausführen, aber nur die Zeilen, deren Modul
   auch wirklich neu geladen wurde.

Es wird also **nichts aufgezählt**: was sich geändert hat, sagt das Dateisystem.
Ein neu hinzugekommenes Repo fällt von selbst mit auf, ohne dass hier etwas
nachgetragen werden muss.

Die Nacharbeit steht im Attribut `updatePost`, eine Zeile je Schritt im Format
`<Modul> = <Befehl>` (Endung `.pm` optional, `*` = immer):

```
98_FHEMVIZ = modify myViz
98_FHEMVIZ = set myViz reload
98_Gartenbewaesserung = modify bewaesserung
# nach jedem Update, egal was sich geändert hat
* = save
```

Da der Aufruf asynchron weiterläuft, steht das Ergebnis im Reading `state`
(`update: 2 Modul(e) neu geladen`), die Dateinamen in `updated`.

---

## Attribute

| Attribut        | Standard | Beschreibung                                                                 |
|-----------------|----------|------------------------------------------------------------------------------|
| `stopOnError`   | 1        | `1` = nach dem ersten Fehler abbrechen, `0` = alle Befehle ausführen          |
| `disable`       | 0        | `1` = Ausführung deaktivieren                                                 |
| `updatePost`    | –        | Nacharbeit für `set … update`: je Zeile `<Modul> = <Befehl>`, `*` = immer     |
| `updateTimeout` | 180      | Sekunden, nach denen `set … update` spätestens aufhört zu warten              |
| `webLink`       | –        | FHEMWEB-Geräte, in denen ein Link auf die Detailseite eingeblendet wird       |
| `webLinkLabel`  | Commands | Beschriftung dieses Links                                                     |

---

## Readings

| Reading            | Beschreibung                                                            |
|--------------------|-------------------------------------------------------------------------|
| `state`            | `idle` / `done (x ok)` / `error at x` / `done (x ok, y errors)`; nach `define`: `defined (<name>)` / `define error`; nach `update`: `update laeuft` / `update: x Modul(e) neu geladen` / `update: nichts Neues` / `update: x Fehler` / `update: Zeit abgelaufen` / `update: Neustart noetig` |
| `executed`         | Anzahl erfolgreich ausgeführter Befehle (`execute`)                     |
| `errorCount`       | Anzahl fehlerhafter Befehle des letzten Laufs (`execute`)               |
| `lastError`        | Zuletzt aufgetretener Fehler (bei `execute` mit Zeilennummer)           |
| `updated`          | Dateinamen der zuletzt neu geladenen Module (`update`)                  |
| `updateCount`      | Anzahl davon (`update`)                                                 |
| `updatePostCount`  | Anzahl ausgeführter Nacharbeits-Befehle (`update`)                      |

---

## Hinweise

- Bei `execute` muss ein literales Semikolon innerhalb eines Befehls wie in FHEM üblich als `;;` geschrieben werden. Bei `define` ist das **nicht** nötig (einfaches `;` wie im DEF-Editor; `;;`/`\` werden zusätzlich toleriert).
- `get`-Befehle, die einen Wert zurückliefern, werden als „Fehler" gewertet (nicht-leere Rückgabe). Das Modul ist für ausführende Befehle (`attr`, `define`, `set`, `delete`, …) gedacht.

---

## Tests

Unter `t/` liegen Szenario-Tests für `set … update`, die **ohne
FHEM-Installation** laufen:

```bash
perl t/run.pl
```

`t/FhemStub.pm` ist eine FHEM-Attrappe mit **virtueller Uhr** (`time()` liefert
`$main::NOW`, `advance()` schiebt vor und feuert dabei die fälligen
`InternalTimer`). Ein Update, das im Betrieb eine Minute wartet, läuft damit in
Millisekunden – und der Test kann zwischen zwei Ticks Dateien anfassen, genau
wie `update` es tut. Geprüft wird unter anderem: nur geänderte Module werden
geladen, das eigene Modul zuletzt, ein später Schreiber verlängert das Warten,
der Neustart-Hinweis bricht ab, und ein fehlgeschlagener `reload` überspringt
seine Nacharbeit.
