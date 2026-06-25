##############################################################################
# 98_Commands.pm
#
# FHEM-Modul zum Ausfuehren mehrerer FHEM-Befehle "auf einmal".
#
# Das Modul stellt zwei Set-Befehle mit grossem Eingabefenster
# (textField-long) bereit:
#
#   execute  Fuehrt einen ganzen Block von FHEM-Befehlen (ein Befehl pro
#            Zeile) nacheinander aus. Standardmaessig stoppt die Ausfuehrung
#            beim ersten fehlerhaften Befehl (Attribut "stopOnError").
#            Leerzeilen und mit '#' beginnende Kommentarzeilen werden ignoriert.
#
#   define   Legt EIN Geraet aus einer (auch mehrzeiligen) Definition an bzw.
#            aktualisiert es (defmod). Der mehrzeilige Perl-Block bleibt dabei
#            erhalten, da intern CommandDefmod genutzt wird (kein Zerlegen an
#            ';' oder Zeilenumbruch). cfg-Stil mit ';;' und '\'-Zeilenfort-
#            setzung wird automatisch in DEF-Editor-Stil (einfaches ';')
#            konvertiert.
#
# Autor:    ahlers2mi
# Version:  v2.1.0
# Lizenz:   GPL v2 oder hoeher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use vars qw($readingFnAttributes);

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
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_Set
#   set <name> execute   -- oeffnet ein grosses Eingabefenster (textField-long);
#                           der eingefuegte Befehlsblock wird zeilenweise
#                           ausgefuehrt.
#   set <name> define    -- oeffnet ein grosses Eingabefenster (textField-long);
#                           die (auch mehrzeilige) Definition wird per defmod
#                           angelegt/aktualisiert.
# ----------------------------------------------------------------------------
sub Commands_Set {
    my ($hash, $name, $cmd, @args) = @_;
    return "\"set $name\" needs at least one argument" if(!defined($cmd));

    my $list = "execute:textField-long define:textField-long";

    if($cmd eq "execute") {
        return "$name is disabled" if(IsDisabled($name));
        # set splittet die Argumente nur an Leerzeichen/Tabs; Zeilenumbrueche
        # aus dem textField-long bleiben in den Tokens erhalten und werden hier
        # durch join wieder zu einem mehrzeiligen Block zusammengefuegt.
        my $block = join(" ", @args);
        return "no commands given" if($block !~ /\S/);
        return Commands_run($hash, $block);
    }

    if($cmd eq "define") {
        return "$name is disabled" if(IsDisabled($name));
        # Wie bei execute: Zeilenumbrueche bleiben in den Tokens erhalten.
        my $block = join(" ", @args);
        return "no definition given" if($block !~ /\S/);
        return Commands_define($hash, $block);
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

# ----------------------------------------------------------------------------
# Commands_define
#   Legt EIN Geraet aus der (auch mehrzeiligen) Definition $block an bzw.
#   aktualisiert es. Im Gegensatz zu execute/AnalyzeCommandChain wird hier
#   CommandDefmod genutzt, das den DEF (inkl. mehrzeiligem Perl-Block) WOERTLICH
#   uebernimmt und NICHT an ';' oder Zeilenumbruechen zerlegt.
#
#   Eingaben im cfg-Stil (mit ';;' und '\'-Zeilenfortsetzung) werden vorher in
#   den DEF-Editor-Stil (einfaches ';', echte Zeilenumbrueche) konvertiert.
#   Ein voranstehendes "define"/"defmod" ist optional und wird abgeschnitten.
#
#   Schreibt die Readings state/lastError und liefert eine Rueckmeldung zurueck.
# ----------------------------------------------------------------------------
sub Commands_define {
    my ($hash, $block) = @_;
    my $name = $hash->{NAME};

    # cfg-Stil -> DEF-Editor-Stil:
    $block =~ s/\\\r?\n/\n/g;   # '\'-Zeilenfortsetzung entfernen, Umbruch behalten
    $block =~ s/;;/;/g;         # doppelte Semikolons -> einfache (Stored-DEF nutzt ';')
    $block =~ s/^\s+//;         # fuehrende Leerzeilen/Whitespace weg
    $block =~ s/\s+$//;         # abschliessenden Whitespace weg
    $block =~ s/^(?:define|defmod)\s+//i;   # optionales define/defmod abschneiden

    return "leere Definition" if($block !~ /\S/);

    my ($devname) = split(/[ \t]+/, $block);
    my $ret = CommandDefmod(undef, $block);

    readingsBeginUpdate($hash);
    if(defined($ret) && $ret =~ /\S/) {
        readingsBulkUpdate($hash, "lastError", $ret);
        readingsBulkUpdate($hash, "state",     "define error");
        readingsEndUpdate($hash, 1);
        Log3($name, 2, "$name: Fehler bei define \"$devname\": $ret");
        return $ret;
    }

    readingsBulkUpdate($hash, "lastError", "");
    readingsBulkUpdate($hash, "state",     "defined ($devname)");
    readingsEndUpdate($hash, 1);

    return "Definition '$devname' angelegt/aktualisiert";
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
    Der Set-Befehl <code>define</code> legt dagegen <i>ein</i> Geraet aus einer
    (auch mehrzeiligen) Definition an bzw. aktualisiert es &ndash; ideal fuer
    Notify/DOIF mit mehrzeiligem Perl-Block, der ueber <code>execute</code>
    nicht funktioniert (dort wuerde er an Zeilenumbruechen zerlegt).
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
    <li><b>define</b> &ndash; oeffnet das Eingabefenster; legt <i>ein</i> Geraet
        aus der (auch mehrzeiligen) Definition per <code>defmod</code> an bzw.
        aktualisiert es. Der mehrzeilige Perl-Block bleibt erhalten (intern
        <code>CommandDefmod</code>, kein Zerlegen an <code>;</code> oder
        Zeilenumbruch). cfg-Stil mit <code>;;</code> und <code>\</code>-Zeilen-
        fortsetzung wird automatisch in einfaches <code>;</code> konvertiert; ein
        voranstehendes <code>define</code>/<code>defmod</code> ist optional.
        Beispiel-Inhalt:
        <br><br>
        <code>
        define n_velux_regen notify MQTT2_RAIN_SOLAR:rain:.* {<br>
        &nbsp;&nbsp;if (ReadingsVal("MQTT2_RAIN_SOLAR","rain","false") eq "true" &amp;&amp; ReadingsVal("Velux_1","pct",0) &gt; 0){<br>
        &nbsp;&nbsp;&nbsp;&nbsp;fhem("set Velux_1 pct 0");<br>
        &nbsp;&nbsp;&nbsp;&nbsp;fhem("setreading Velux_1 auto_on off");<br>
        &nbsp;&nbsp;}<br>
        }<br>
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
  </ul>
  <br>

  <a name="Commandsreadings"></a>
  <b>Readings</b>
  <ul>
    <li><b>state</b> &ndash; idle / done (x ok) / error at x / done (x ok, y errors)
        bzw. nach <code>define</code>: defined (&lt;name&gt;) / define error</li>
    <li><b>executed</b> &ndash; Anzahl erfolgreich ausgefuehrter Befehle (execute)</li>
    <li><b>errorCount</b> &ndash; Anzahl fehlerhafter Befehle (execute)</li>
    <li><b>lastError</b> &ndash; zuletzt aufgetretener Fehler</li>
  </ul>
  <p>
    <b>Hinweis:</b> Bei <code>execute</code> muss ein literales Semikolon
    innerhalb eines Befehls wie in FHEM ueblich als <code>;;</code> geschrieben
    werden. Bei <code>define</code> ist das <i>nicht</i> noetig &ndash; dort kann
    der Perl-Block mit einfachem <code>;</code> (wie im DEF-Editor) eingefuegt
    werden; <code>;;</code> und <code>\</code> werden zudem automatisch toleriert.
  </p>
</ul>

=end html
=cut
