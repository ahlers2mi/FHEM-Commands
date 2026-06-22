##############################################################################
# 99_Commands.pm
#
# FHEM-Hilfsmodul zum Ausfuehren mehrerer FHEM-Befehle "auf einmal".
#
# Statt mehrere Befehle einzeln nacheinander in das FHEM-Kommandofeld zu
# tippen, kann ein ganzer Block (z. B. mehrere "attr"-Zeilen) auf einmal
# eingefuegt und abgearbeitet werden. Die Befehle werden zeilenweise
# ausgefuehrt; standardmaessig stoppt die Abarbeitung beim ersten Fehler.
#
# Bereitgestellt wird:
#   * das FHEM-Kommando  runcmds [-c] <befehlsblock>
#   * die Perl-Funktion  runCmds(<befehlsblock>[, <continueOnError>])
#
# Leerzeilen und mit '#' beginnende Kommentarzeilen werden ignoriert.
#
# Autor:    ahlers2mi
# Version:  v2.0.0
# Lizenz:   GPL v2 oder hoeher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use vars qw(%cmds);

# ----------------------------------------------------------------------------
# Commands_Initialize
#   Wird beim Laden des Moduls (99_*.pm werden beim FHEM-Start automatisch
#   geladen) aufgerufen und registriert das FHEM-Kommando "runcmds".
# ----------------------------------------------------------------------------
sub Commands_Initialize {
    my ($hash) = @_;

    $cmds{runcmds} = {
        Fn  => "Commands_runcmds",
        Hlp => "[-c] <befehlsblock>,fuehrt mehrere Befehle (zeilenweise) nacheinander aus; ".
               "Stopp beim ersten Fehler, -c = bei Fehler weitermachen",
    };
}

# ----------------------------------------------------------------------------
# Commands_runcmds
#   Handler fuer das FHEM-Kommando "runcmds".
#   Optionales fuehrendes "-c" laesst alle Befehle laufen, auch wenn einer
#   fehlschlaegt. Der restliche (ggf. mehrzeilige) Text ist der Befehlsblock.
# ----------------------------------------------------------------------------
sub Commands_runcmds {
    my ($cl, $param) = @_;
    $param = "" if(!defined($param));

    my $continue = 0;
    $continue = 1 if($param =~ s/^\s*-c\b[ \t]*//);

    return runCmds($param, $continue);
}

# ----------------------------------------------------------------------------
# runCmds(<block>[, <continueOnError>])
#   Fuehrt die Zeilen von <block> als FHEM-Befehle nacheinander aus.
#   Ein nicht-leerer Rueckgabewert eines Befehls wird als Fehler gewertet.
#
#   continueOnError = 0 (Standard): Abbruch beim ersten Fehler
#   continueOnError = 1           : alle Befehle ausfuehren, Fehler sammeln
#
#   Rueckgabe: Zusammenfassung bzw. Fehlermeldung(en) als Text.
# ----------------------------------------------------------------------------
sub runCmds {
    my ($block, $continue) = @_;
    $block    = ""  if(!defined($block));
    $continue = 0   if(!defined($continue));

    my @errors;
    my $done = 0;
    my $no   = 0;

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
            Log3(undef, 2, "runcmds: Fehler in Zeile $no \"$line\": $ret");
            last if(!$continue);
        } else {
            $done++;
        }
    }

    if(@errors) {
        my $msg = ($continue ? "runcmds: $done OK, " . scalar(@errors) . " Fehler:\n"
                             : "runcmds: abgebrochen nach Fehler ($done OK):\n")
                . join("\n", @errors);
        return $msg;
    }

    return "runcmds: $done Befehl(e) erfolgreich ausgefuehrt";
}

1;

=pod
=item command
=item summary Fuehrt mehrere FHEM-Befehle auf einmal aus (Stopp beim ersten Fehler)
=item summary_DE Fuehrt mehrere FHEM-Befehle auf einmal aus (Stopp beim ersten Fehler)
=begin html

<a name="Commands"></a>
<h3>runcmds</h3>
<ul>
  <p>
    <code>runcmds [-c] &lt;befehlsblock&gt;</code>
  </p>
  <p>
    Fuehrt mehrere FHEM-Befehle <i>auf einmal</i> aus, statt sie einzeln in das
    Kommandofeld zu tippen. Der Befehlsblock wird zeilenweise abgearbeitet
    (ein Befehl pro Zeile). Leerzeilen und mit <code>#</code> beginnende Zeilen
    werden ignoriert.
  </p>
  <p>
    Standardmaessig wird die Abarbeitung beim <b>ersten Fehler</b> abgebrochen
    (ein Befehl gilt als fehlerhaft, wenn er einen nicht-leeren Rueckgabewert
    liefert). Mit der Option <code>-c</code> werden alle Befehle ausgefuehrt und
    auftretende Fehler am Ende gesammelt zurueckgegeben.
  </p>

  <b>Beispiel</b>
  <ul>
    Im FHEM-Kommandofeld <code>runcmds</code> voranstellen und den ganzen Block
    auf einmal einfuegen:
    <br><br>
    <code>
    runcmds<br>
    # Sensoren<br>
    attr poolControl poolSensor   MQTT2_Sonoff_TH10_01:poolTemp<br>
    attr poolControl inflowSensor MQTT2_Sonoff_TH10_01:solarTemp<br>
    set poolControl targetTemp 30<br>
    </code>
  </ul>
  <br>

  <b>Perl-Funktion</b>
  <ul>
    Alternativ aus Perl (z. B. in notify/at/myUtils):<br>
    <code>{ runCmds("attr a room X\nattr b room Y", 0) }</code><br>
    Zweiter Parameter: <code>0</code> = Stopp bei Fehler (Standard), <code>1</code> = weitermachen.
  </ul>
</ul>

=end html
=cut
