##############################################################################
# 98_Commands.pm
#
# FHEM-Modul zum Ausfuehren mehrerer FHEM-Befehle "auf einmal".
#
# Das Modul stellt einen Set-Befehl mit grossem Eingabefenster
# (textField-long) bereit. Dort kann ein ganzer Block von FHEM-Befehlen
# (z. B. mehrere "attr"-Zeilen) auf einmal eingefuegt werden. Die Befehle
# werden zeilenweise abgearbeitet; standardmaessig stoppt die Ausfuehrung
# beim ersten fehlerhaften Befehl (Attribut "stopOnError").
#
# Leerzeilen und mit '#' beginnende Kommentarzeilen werden ignoriert.
#
# Autor:    ahlers2mi
# Version:  v2.1.0
# Lizenz:   GPL v2 oder hoeher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use vars qw($readingFnAttributes $init_done);

# ----------------------------------------------------------------------------
# Commands_Initialize
#   Wird von FHEM beim Laden des Moduls aufgerufen.
# ----------------------------------------------------------------------------
sub Commands_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}  = \&Commands_Define;
    $hash->{SetFn}  = \&Commands_Set;
    $hash->{AttrFn} = \&Commands_Attr;

    $hash->{AttrList} =
          "disable:1,0 " .
          "stopOnError:1,0 " .
          $readingFnAttributes;
}

# ----------------------------------------------------------------------------
# Commands_Define
#   "define <name> Commands"  -- es werden keine weiteren Parameter benoetigt.
# ----------------------------------------------------------------------------
sub Commands_Define {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);

    $hash->{FVERSION} = "98_Commands.pm:v2.1.0";

    return "Usage: define <name> Commands" if(int(@param) != 2);

    readingsSingleUpdate($hash, "state", "idle", 0);

    # Schnellzugriff: Eingabefeld direkt in der Geraeteuebersicht anzeigen,
    # damit man das Geraet nicht erst per Detailseite oeffnen muss.
    # Nur beim interaktiven Anlegen setzen (nicht beim Konfig-Laden) und nur,
    # wenn der Nutzer noch kein eigenes webCmd vergeben hat.
    if($init_done && !AttrVal($hash->{NAME}, "webCmd", undef)) {
        CommandAttr(undef, "$hash->{NAME} webCmd execute");
    }

    return undef;
}

# ----------------------------------------------------------------------------
# Commands_Set
#   set <name> execute   -- oeffnet ein grosses Eingabefenster (textField-long);
#                           der eingefuegte Befehlsblock wird zeilenweise
#                           ausgefuehrt.
# ----------------------------------------------------------------------------
sub Commands_Set {
    my ($hash, $name, $cmd, @args) = @_;
    return "\"set $name\" needs at least one argument" if(!defined($cmd));

    my $list = "execute:textField-long";

    if($cmd eq "execute") {
        return "$name is disabled" if(IsDisabled($name));
        # set splittet die Argumente nur an Leerzeichen/Tabs; Zeilenumbrueche
        # aus dem textField-long bleiben in den Tokens erhalten und werden hier
        # durch join wieder zu einem mehrzeiligen Block zusammengefuegt.
        my $block = join(" ", @args);
        return "no commands given" if($block !~ /\S/);
        return Commands_run($hash, $block);
    }

    return "Unknown argument $cmd, choose one of $list";
}

# ----------------------------------------------------------------------------
# Commands_Attr
#   Validiert die Schalter-Attribute.
# ----------------------------------------------------------------------------
sub Commands_Attr {
    my ($cmd, $name, $attr_name, $attr_value) = @_;

    if($cmd eq "set" && ($attr_name eq "disable" || $attr_name eq "stopOnError")) {
        if($attr_value !~ /^[01]$/) {
            my $err = "Invalid value $attr_value for $attr_name. Must be 0 or 1.";
            Log3($name, 3, "$name: $err");
            return $err;
        }
    }
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_run
#   Fuehrt die Zeilen des Blocks als FHEM-Befehle nacheinander aus.
#   Ein nicht-leerer Rueckgabewert eines Befehls wird als Fehler gewertet.
#   Bei stopOnError=1 (Standard) wird beim ersten Fehler abgebrochen.
#
#   Schreibt die Readings state/executed/errorCount/lastError und liefert
#   eine Zusammenfassung zurueck (wird im FHEMWEB als Dialog angezeigt).
# ----------------------------------------------------------------------------
sub Commands_run {
    my ($hash, $block) = @_;
    my $name = $hash->{NAME};

    my $stopOnError = AttrVal($name, "stopOnError", 1);

    my @errors;
    my $done = 0;
    my $no   = 0;

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastError", "");

    foreach my $line (split(/\n/, $block)) {
        $line =~ s/\r$//;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if($line eq "" || $line =~ /^#/);

        $no++;
        my $ret = AnalyzeCommandChain(undef, $line);
        $ret = "" if(!defined($ret));

        if($ret =~ /\S/) {
            push @errors, "Zeile $no: $line\n  -> $ret";
            readingsBulkUpdate($hash, "lastError", "($no) $line -> $ret");
            Log3($name, 2, "$name: Fehler in Zeile $no \"$line\": $ret");
            last if($stopOnError);
        } else {
            $done++;
        }
    }

    my $errCount = scalar(@errors);
    my $state = !$errCount       ? "done ($done ok)"
              : $stopOnError      ? "error at $no"
              :                     "done ($done ok, $errCount errors)";

    readingsBulkUpdate($hash, "executed",   $done);
    readingsBulkUpdate($hash, "errorCount", $errCount);
    readingsBulkUpdate($hash, "state",      $state);
    readingsEndUpdate($hash, 1);

    if($errCount) {
        my $head = $stopOnError
            ? "abgebrochen nach Fehler ($done ok):"
            : "$done ok, $errCount Fehler:";
        return "$head\n" . join("\n", @errors);
    }

    return "$done Befehl(e) erfolgreich ausgefuehrt";
}

1;

=pod
=item helper
=item summary Fuehrt mehrere FHEM-Befehle auf einmal aus (Eingabefenster, Stopp bei Fehler)
=item summary_DE Fuehrt mehrere FHEM-Befehle auf einmal aus (Eingabefenster, Stopp bei Fehler)
=begin html

<a name="Commands"></a>
<h3>Commands</h3>
<ul>
  <p>
    <b>Commands</b> fuehrt mehrere FHEM-Befehle <i>auf einmal</i> aus. Ueber den
    Set-Befehl <code>execute</code> oeffnet sich ein grosses Eingabefenster
    (textField-long), in das ein ganzer Befehlsblock (ein Befehl pro Zeile)
    eingefuegt werden kann. Die Zeilen werden nacheinander abgearbeitet.
  </p>
  <p>
    Standardmaessig stoppt die Ausfuehrung beim ersten fehlerhaften Befehl
    (Attribut <code>stopOnError</code>). Leerzeilen und mit <code>#</code>
    beginnende Zeilen werden ignoriert.
  </p>

  <a name="Commandsdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Commands</code><br><br>
    Beispiel: <code>define meineBefehle Commands</code>
  </ul>
  <br>

  <a name="Commandsset"></a>
  <b>Set</b>
  <ul>
    <li><b>execute</b> &ndash; oeffnet das Eingabefenster; der eingefuegte
        Befehlsblock wird zeilenweise ausgefuehrt. Beispiel-Inhalt:
        <br><br>
        <code>
        # Sensoren<br>
        attr poolControl poolSensor   MQTT2_Sonoff_TH10_01:poolTemp<br>
        attr poolControl inflowSensor MQTT2_Sonoff_TH10_01:solarTemp<br>
        set poolControl targetTemp 30<br>
        </code>
    </li>
  </ul>
  <br>

  <a name="Commandsattr"></a>
  <b>Attributes</b>
  <ul>
    <li><b>stopOnError</b> 1|0 &ndash; bei 1 (Standard) wird nach dem ersten
        fehlerhaften Befehl abgebrochen, bei 0 werden alle Befehle ausgefuehrt</li>
    <li><b>disable</b> 1|0 &ndash; deaktiviert die Ausfuehrung</li>
    <li><b>webCmd execute</b> &ndash; (FHEMWEB-Standardattribut) zeigt das
        Eingabefeld direkt in der Geraeteuebersicht an, sodass man das Geraet
        nicht erst per Detailseite oeffnen muss. Wird beim Anlegen automatisch
        gesetzt, falls noch kein webCmd vorhanden ist; kann jederzeit geaendert
        oder mit <code>deleteattr &lt;name&gt; webCmd</code> entfernt werden.</li>
  </ul>
  <br>

  <a name="Commandsreadings"></a>
  <b>Readings</b>
  <ul>
    <li><b>state</b> &ndash; idle / done (x ok) / error at x / done (x ok, y errors)</li>
    <li><b>executed</b> &ndash; Anzahl erfolgreich ausgefuehrter Befehle</li>
    <li><b>errorCount</b> &ndash; Anzahl fehlerhafter Befehle</li>
    <li><b>lastError</b> &ndash; zuletzt aufgetretener Fehler</li>
  </ul>
  <p>
    <b>Hinweis:</b> Innerhalb eines Befehls muss ein literales Semikolon wie in
    FHEM ueblich als <code>;;</code> geschrieben werden.
  </p>
</ul>

=end html
=cut
