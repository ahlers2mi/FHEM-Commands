##############################################################################
# 98_Commands.pm
#
# FHEM-Modul zum sequentiellen Ausfuehren mehrerer FHEM-Befehle.
#
# Das Modul fuehrt eine Liste von FHEM-Befehlen nacheinander aus. Die Befehle
# werden als Liste im Attribut "commandList" hinterlegt (ein Befehl pro Zeile)
# und ueber "set <name> execute" gestartet.
#
# Optional kann die Abarbeitung nach dem ersten fehlerhaften Befehl gestoppt
# werden (Attribut "stopOnError", Standard: aktiv). Zwischen den Befehlen kann
# eine Pause eingelegt werden (Attribut "delay"). Die Ausfuehrung erfolgt
# nicht-blockierend ueber InternalTimer.
#
# Autor:    ahlers2mi
# Version:  v1.0.0
# Lizenz:   GPL v2 oder hoeher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use vars qw($init_done);

# ----------------------------------------------------------------------------
# Commands_Initialize
#   Wird von FHEM beim Laden des Moduls aufgerufen.
#   Registriert alle Callback-Funktionen und die Attributliste.
# ----------------------------------------------------------------------------
sub Commands_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}   = \&Commands_Define;
    $hash->{UndefFn} = \&Commands_Undef;
    $hash->{SetFn}   = \&Commands_Set;
    $hash->{GetFn}   = \&Commands_Get;
    $hash->{AttrFn}  = \&Commands_Attr;

    $hash->{AttrList} =
          "disable:1,0 " .
          "stopOnError:1,0 " .
          "delay " .
          "commandList:textField-long " .
          $readingFnAttributes;
}

# ----------------------------------------------------------------------------
# Commands_Define
#   "define <name> Commands"  -- es werden keine weiteren Parameter benoetigt.
# ----------------------------------------------------------------------------
sub Commands_Define {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);

    $hash->{FVERSION} = "98_Commands.pm:v1.0.0";

    if(int(@param) != 2) {
        return "Usage: define <name> Commands";
    }

    $hash->{NAME}  = $param[0];

    readingsSingleUpdate($hash, "state", "idle", 0);

    return undef;
}

# ----------------------------------------------------------------------------
# Commands_Undef
#   Beim Loeschen des Geraets eine evtl. laufende Sequenz abbrechen.
# ----------------------------------------------------------------------------
sub Commands_Undef {
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_getList
#   Liefert die im Attribut "commandList" hinterlegten Befehle als Array.
#   Trennzeichen ist der Zeilenumbruch; Leerzeilen und mit '#' beginnende
#   Kommentarzeilen werden ignoriert.
# ----------------------------------------------------------------------------
sub Commands_getList {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $raw = AttrVal($name, "commandList", "");
    my @cmds;
    foreach my $line (split(/[\r\n]+/, $raw)) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if($line eq "" || $line =~ /^#/);
        push @cmds, $line;
    }
    return @cmds;
}

# ----------------------------------------------------------------------------
# Commands_Set
#   set <name> execute   -- Befehlsliste sequentiell ausfuehren (alias: start)
#   set <name> stop      -- laufende Sequenz abbrechen
#   set <name> add <cmd> -- Befehl an commandList anhaengen
#   set <name> clear     -- commandList leeren
# ----------------------------------------------------------------------------
sub Commands_Set {
    my ($hash, $name, $cmd, @args) = @_;
    return "\"set $name\" needs at least one argument" unless(defined($cmd));

    my $list = "execute:noArg start:noArg stop:noArg add clear:noArg";

    if($cmd eq "execute" || $cmd eq "start") {
        return "$name is disabled" if(IsDisabled($name));
        my @cmds = Commands_getList($hash);
        return "commandList is empty, please set attribute commandList" if(!@cmds);
        return Commands_Execute($hash);

    } elsif($cmd eq "stop") {
        RemoveInternalTimer($hash);
        delete $hash->{".cmds"};
        delete $hash->{".idx"};
        readingsSingleUpdate($hash, "state", "stopped", 1);
        return undef;

    } elsif($cmd eq "add") {
        return "\"set $name add\" needs a command as argument" unless(@args);
        my $new = join(" ", @args);
        my $cur = AttrVal($name, "commandList", "");
        $cur .= "\n" if($cur ne "");
        CommandAttr(undef, "$name commandList $cur$new");
        return undef;

    } elsif($cmd eq "clear") {
        CommandDeleteAttr(undef, "$name commandList");
        return undef;

    } else {
        return "Unknown argument $cmd, choose one of $list";
    }
}

# ----------------------------------------------------------------------------
# Commands_Get
#   get <name> list   -- nummerierte Anzeige der hinterlegten Befehle
# ----------------------------------------------------------------------------
sub Commands_Get {
    my ($hash, $name, $opt, @args) = @_;

    if(defined($opt) && $opt eq "list") {
        my @cmds = Commands_getList($hash);
        return "commandList is empty" if(!@cmds);
        my $i = 1;
        return join("\n", map { sprintf("%2d: %s", $i++, $_) } @cmds);
    } else {
        return "Unknown argument $opt, choose one of list:noArg";
    }
}

# ----------------------------------------------------------------------------
# Commands_Attr
#   Validiert Attributwerte beim Setzen.
# ----------------------------------------------------------------------------
sub Commands_Attr {
    my ($cmd, $name, $attr_name, $attr_value) = @_;

    if($cmd eq "set") {
        if($attr_name eq "disable" || $attr_name eq "stopOnError") {
            if($attr_value !~ /^[01]$/) {
                my $err = "Invalid value $attr_value for $attr_name. Must be 0 or 1.";
                Log3 $name, 3, "$name: $err";
                return $err;
            }
        } elsif($attr_name eq "delay") {
            if($attr_value !~ /^\d+(\.\d+)?$/) {
                my $err = "Invalid value $attr_value for delay. Must be a non-negative number (seconds).";
                Log3 $name, 3, "$name: $err";
                return $err;
            }
        }
    }
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_Execute
#   Startet die Abarbeitung der Befehlsliste. Setzt die Zaehler-Readings
#   zurueck, legt die Befehlsliste im Hash ab und ruft den ersten Schritt auf.
# ----------------------------------------------------------------------------
sub Commands_Execute {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);

    my @cmds = Commands_getList($hash);
    $hash->{".cmds"} = \@cmds;
    $hash->{".idx"}  = 0;

    my $total = scalar(@cmds);
    Log3 $name, 4, "$name: starte Sequenz mit $total Befehl(en)";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state",        "running 0/$total");
    readingsBulkUpdate($hash, "executed",     0);
    readingsBulkUpdate($hash, "errorCount",   0);
    readingsBulkUpdate($hash, "lastCommand",  "");
    readingsBulkUpdate($hash, "lastError",    "");
    readingsBulkUpdate($hash, "lastResult",   "");
    readingsEndUpdate($hash, 1);

    Commands_RunNext($hash);
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_RunNext
#   Fuehrt den naechsten Befehl der Sequenz aus und plant -- abhaengig vom
#   Attribut "delay" -- den darauf folgenden Schritt via InternalTimer.
#
#   Ein nicht-leerer Rueckgabewert von AnalyzeCommandChain wird als Fehler
#   gewertet. Ist "stopOnError" aktiv (Standard), bricht die Sequenz beim
#   ersten Fehler ab.
# ----------------------------------------------------------------------------
sub Commands_RunNext {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $cmds  = $hash->{".cmds"};
    my $idx   = $hash->{".idx"} // 0;
    my $total = $cmds ? scalar(@{$cmds}) : 0;

    # Alle Befehle abgearbeitet -> fertig
    if(!$cmds || $idx >= $total) {
        my $errors = ReadingsVal($name, "errorCount", 0);
        my $state  = $errors > 0 ? "done (errors: $errors)" : "done";
        readingsSingleUpdate($hash, "state", $state, 1);
        delete $hash->{".cmds"};
        delete $hash->{".idx"};
        Log3 $name, 4, "$name: Sequenz beendet ($state)";
        return;
    }

    my $cmd    = $cmds->[$idx];
    my $stepNo = $idx + 1;

    Log3 $name, 4, "$name: ($stepNo/$total) fuehre aus: $cmd";

    my $ret = AnalyzeCommandChain(undef, $cmd);
    $ret = "" if(!defined($ret));

    my $isError = ($ret =~ /\S/) ? 1 : 0;

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastCommand", $cmd);
    readingsBulkUpdate($hash, "lastResult",  $ret);
    readingsBulkUpdate($hash, "executed",    $stepNo);
    readingsBulkUpdate($hash, "state",       "running $stepNo/$total");

    if($isError) {
        my $errors = ReadingsVal($name, "errorCount", 0) + 1;
        readingsBulkUpdate($hash, "errorCount", $errors);
        readingsBulkUpdate($hash, "lastError",  "($stepNo) $cmd -> $ret");
        Log3 $name, 2, "$name: Fehler bei ($stepNo/$total) \"$cmd\": $ret";

        if(AttrVal($name, "stopOnError", 1)) {
            readingsBulkUpdate($hash, "state", "error at $stepNo/$total");
            readingsEndUpdate($hash, 1);
            delete $hash->{".cmds"};
            delete $hash->{".idx"};
            Log3 $name, 3, "$name: Sequenz abgebrochen (stopOnError) bei Schritt $stepNo";
            return;
        }
    }
    readingsEndUpdate($hash, 1);

    # naechsten Schritt planen
    $hash->{".idx"} = $idx + 1;
    my $delay = AttrVal($name, "delay", 0);
    InternalTimer(gettimeofday() + $delay, "Commands_RunNext", $hash);

    return;
}

1;

=pod
=item helper
=item summary Fuehrt mehrere FHEM-Befehle nacheinander aus (optional Stopp bei Fehler)
=item summary_DE Fuehrt mehrere FHEM-Befehle nacheinander aus (optional Stopp bei Fehler)
=begin html

<a name="Commands"></a>
<h3>Commands</h3>
<ul>
  <p>
    <b>Commands</b> fuehrt eine Liste von FHEM-Befehlen nacheinander aus.
    Die Befehle werden im Attribut <code>commandList</code> hinterlegt
    (ein Befehl pro Zeile) und mit <code>set &lt;name&gt; execute</code>
    gestartet. Optional kann die Abarbeitung nach dem ersten fehlerhaften
    Befehl gestoppt werden (Attribut <code>stopOnError</code>).
    Die Ausfuehrung erfolgt nicht-blockierend.
  </p>

  <a name="Commandsdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Commands</code>
    <br><br>
    Beispiel:<br>
    <code>define mySequence Commands</code><br>
    <code>attr mySequence commandList set lampe1 on&#10;set lampe2 on&#10;set rollo down</code>
  </ul>
  <br>

  <a name="Commandsset"></a>
  <b>Set</b>
  <ul>
    <li><b>execute</b> (alias <b>start</b>) &ndash; fuehrt die Befehlsliste sequentiell aus</li>
    <li><b>stop</b> &ndash; bricht eine laufende Sequenz ab</li>
    <li><b>add &lt;command&gt;</b> &ndash; haengt einen Befehl an <code>commandList</code> an</li>
    <li><b>clear</b> &ndash; leert die <code>commandList</code></li>
  </ul>
  <br>

  <a name="Commandsget"></a>
  <b>Get</b>
  <ul>
    <li><b>list</b> &ndash; zeigt die hinterlegten Befehle nummeriert an</li>
  </ul>
  <br>

  <a name="Commandsattr"></a>
  <b>Attributes</b>
  <ul>
    <li><b>commandList</b> &ndash; die auszufuehrenden FHEM-Befehle, ein Befehl pro Zeile.
        Leerzeilen sowie mit <code>#</code> beginnende Zeilen werden ignoriert.</li>
    <li><b>stopOnError</b> 1|0 &ndash; bei 1 (Standard) wird die Sequenz nach dem
        ersten fehlerhaften Befehl abgebrochen, bei 0 werden alle Befehle ausgefuehrt</li>
    <li><b>delay</b> &ndash; Pause in Sekunden zwischen den Befehlen (Standard: 0)</li>
    <li><b>disable</b> 1|0 &ndash; deaktiviert die Ausfuehrung</li>
  </ul>
  <br>

  <a name="Commandsreadings"></a>
  <b>Readings</b>
  <ul>
    <li><b>state</b> &ndash; idle / running x/n / done / error at x/n / stopped</li>
    <li><b>executed</b> &ndash; Anzahl der bisher ausgefuehrten Befehle</li>
    <li><b>errorCount</b> &ndash; Anzahl der fehlerhaften Befehle des letzten Laufs</li>
    <li><b>lastCommand</b> &ndash; zuletzt ausgefuehrter Befehl</li>
    <li><b>lastResult</b> &ndash; Rueckgabe des zuletzt ausgefuehrten Befehls</li>
    <li><b>lastError</b> &ndash; zuletzt aufgetretener Fehler</li>
  </ul>
</ul>

=end html
=cut
