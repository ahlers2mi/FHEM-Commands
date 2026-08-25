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
#            erhalten, da intern "defmod" via AnalyzeCommand genutzt wird (kein
#            Zerlegen an ';' oder Zeilenumbruch). cfg-Stil mit ';;' und
#            '\'-Zeilenfortsetzung wird automatisch in DEF-Editor-Stil
#            (einfaches ';') konvertiert.
#
# Zusaetzlich kann das Geraet einen Link neben der oberen FHEMWEB-Befehlszeile
# einblenden (Attribut "webLink" = Auswahl der FHEMWEB-Geraete). Das noetige
# JavaScript (www/pgm2/fhemweb_custom_link.js) wird mitgeliefert; Ziel/Label
# bekommt es ueber die Query der Script-URL (?dev=<Geraet>&label=<Label>).
#
# Autor:    ahlers2mi
# Version:  v2.3.2
# Lizenz:   GPL v2 oder hoeher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use vars qw($readingFnAttributes $init_done %BC_hash %defs);

# ----------------------------------------------------------------------------
# Commands_Initialize
#   Wird von FHEM beim Laden des Moduls aufgerufen.
# ----------------------------------------------------------------------------
sub Commands_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}   = \&Commands_Define;
    $hash->{UndefFn} = \&Commands_Undef;
    $hash->{SetFn}   = \&Commands_Set;
    $hash->{AttrFn}  = \&Commands_Attr;

    $hash->{AttrList} =
          "disable:1,0 " .
          "stopOnError:1,0 " .
          "webLinkLabel " .
          "webLink " .
          "updatePost:textField-long " .
          "updateTimeout updateMinWait " .
          $readingFnAttributes;
}

# ----------------------------------------------------------------------------
# Commands_Define
#   "define <name> Commands"  -- es werden keine weiteren Parameter benoetigt.
# ----------------------------------------------------------------------------
sub Commands_Define {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);

    $hash->{FVERSION} = "98_Commands.pm:v2.3.2";

    return "Usage: define <name> Commands" if(int(@param) != 2);

    readingsSingleUpdate($hash, "state", "idle", 0);

    # Schnellzugriff: Eingabefeld direkt in der Geraeteuebersicht anzeigen,
    # damit man das Geraet nicht erst per Detailseite oeffnen muss.
    # Nur beim interaktiven Anlegen setzen (nicht beim Konfig-Laden) und nur,
    # wenn der Nutzer noch kein eigenes webCmd vergeben hat.
    if($init_done && !AttrVal($hash->{NAME}, "webCmd", undef)) {
        CommandAttr(undef, "$hash->{NAME} webCmd execute");
    }

    # Live-Dropdown der FHEMWEB-Geraete fuer das Attribut "webLink" bereitstellen.
    Commands_updateAttrList($hash->{NAME});

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

    my $list = "execute:textField-long define:textField-long update:noArg";

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

    if($cmd eq "update") {
        return "$name is disabled" if(IsDisabled($name));
        return Commands_updStart($hash);
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

    # Web-Link an den ausgewaehlten FHEMWEB-Geraeten registrieren/entfernen.
    # Nur zur Laufzeit (nicht beim Konfig-Laden) - beim Start sind die
    # JavaScripts-Eintraege der WEB-Geraete bereits aus deren eigener Konfig da.
    if($init_done && ($attr_name eq "webLink" || $attr_name eq "webLinkLabel")) {
        my $list = ($attr_name eq "webLink")
                     ? ($cmd eq "set" ? $attr_value : "")
                     : AttrVal($name, "webLink", "");
        Commands_applyWebLink($name, $list);
    }

    return undef;
}

# ----------------------------------------------------------------------------
# Commands_updateAttrList
#   Setzt die Geraete-Attributliste mit einem Live-Dropdown der vorhandenen
#   FHEMWEB-Geraete fuer "webLink" (Mehrfachauswahl).
# ----------------------------------------------------------------------------
sub Commands_updateAttrList {
    my ($name) = @_;
    my @web = devspec2array("TYPE=FHEMWEB");
    my $sel = @web ? "webLink:multiple," . join(",", @web) : "webLink";
    setDevAttrList($name,
        "disable:1,0 stopOnError:1,0 webLinkLabel $sel "
        . "updatePost:textField-long updateTimeout updateMinWait " . $readingFnAttributes);
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_applyWebLink
#   Traegt den Link (pgm2/fhemweb_custom_link.js mit dev/label in der Query)
#   in die JavaScripts der gewuenschten FHEMWEB-Geraete ein und entfernt ihn
#   aus den abgewaehlten. Idempotent, nur dieses Commands-Geraet betreffend.
# ----------------------------------------------------------------------------
sub Commands_applyWebLink {
    my ($name, $listStr) = @_;

    my $label = AttrVal($name, "webLinkLabel", "Commands");
    (my $enc = $label) =~ s/([^A-Za-z0-9_.\-])/sprintf("%%%02X", ord($1))/ge;
    my $entry = "pgm2/fhemweb_custom_link.js?dev=$name&label=$enc";

    my %want = map { $_ => 1 }
               grep { /\S/ }
               split(/[\s,]+/, defined($listStr) ? $listStr : "");

    foreach my $web (devspec2array("TYPE=FHEMWEB")) {
        my $cur = AttrVal($web, "JavaScripts", "");
        my @js  = grep { /\S/ } split(/[ \t]+/, $cur);
        # bisherige Eintraege genau dieses Commands-Geraets entfernen
        @js = grep { $_ !~ m{^pgm2/fhemweb_custom_link\.js\?dev=\Q$name\E(?:&|$)} } @js;
        push @js, $entry if($want{$web});
        my $new = join(" ", @js);
        next if($new eq $cur);
        if($new eq "") { CommandDeleteAttr(undef, "$web JavaScripts"); }
        else           { CommandAttr(undef, "$web JavaScripts $new"); }
    }
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_Undef
#   Beim Loeschen des Geraets den Link aus allen FHEMWEB-Geraeten entfernen.
# ----------------------------------------------------------------------------
sub Commands_Undef {
    my ($hash, $name) = @_;
    RemoveInternalTimer($hash);          # ein laufendes "update" nicht weiterticken
    delete $hash->{helper}{upd};
    Commands_applyWebLink($name, "") if($init_done);
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
#   "defmod" via AnalyzeCommand genutzt, das den DEF (inkl. Perl-Block) WOERTLICH
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
    # defmod ueber AnalyzeCommand aufrufen (versionsunabhaengig; zerlegt - anders
    # als AnalyzeCommandChain - NICHT an ';' oder Zeilenumbruch, der Perl-Block
    # bleibt also erhalten).
    my $ret = AnalyzeCommand(undef, "defmod " . $block);

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

# ----------------------------------------------------------------------------
# Commands_updModDir / Commands_updSnapshot
#   Verzeichnis der FHEM-Module und ein Abbild ihrer Aenderungszeiten.
#   BEWUSST keine Liste von Modulnamen: welche Module sich aendern, sagt das
#   Dateisystem. Eine gepflegte Aufzaehlung ist genau die Stelle, an der das
#   naechste Repo vergessen wird.
# ----------------------------------------------------------------------------
sub Commands_updModDir {
    my $mp = AttrVal("global", "modpath", ".");
    return "$mp/FHEM";
}

sub Commands_updSnapshot {
    my $dir = Commands_updModDir();
    my %st;
    if(opendir(my $dh, $dir)) {
        foreach my $f (readdir($dh)) {
            next if($f !~ /^\d\d_.+\.pm$/);
            my @s = stat("$dir/$f");
            $st{$f} = @s ? "$s[9]/$s[7]" : "?";   # mtime/groesse
        }
        closedir($dh);
    }
    return \%st;
}

# fhem.pl selbst - aendert die sich, hilft kein reload, sondern nur ein
# Neustart. Die Meldung von "update" taugt dafuer NICHT als Merkmal: das
# 'update finished, "shutdown restart" is needed' schreibt 98_update.pm nach
# JEDEM Lauf, bei dem irgendetwas geladen wurde.
sub Commands_updKern {
    my @s = stat(AttrVal("global", "modpath", ".") . "/fhem.pl");
    return @s ? "$s[9]/$s[7]" : "?";
}

# ----------------------------------------------------------------------------
# Commands_updRunning
#   Laeuft gerade ein "update" im Hintergrund?
#
#   "update" ist bei FHEM standardmaessig ein BlockingCall
#   (attr global updateInBackground, Default 1) und meldet sich beim Ende
#   selbst ab: das Kind ruft zuletzt BlockingInformParent("BlockingStart",...),
#   und der Elternprozess setzt daraufhin {terminated} im Eintrag. Genau das
#   fragen wir hier ab - dieselbe Bedingung, die auch "blockinginfo" anzeigt.
#
#   Warum nicht am Modulverzeichnis ablesen: die ersten rund zehn Sekunden
#   laedt "update" nur die controls_*.txt uebers Netz und fasst dabei keine
#   einzige Moduldatei an. Die Ruhe VOR dem Download ist von der Ruhe DANACH
#   nicht zu unterscheiden - wer nur hinschaut, meldet "nichts Neues", waehrend
#   die Dateien noch unterwegs sind.
# ----------------------------------------------------------------------------
sub Commands_updRunning {
    my $an = 0;
    foreach my $h (values %main::BC_hash) {
        next if(ref($h) ne "HASH" || $h->{terminated} || !$h->{pid});
        my $fn = ref($h->{fn}) ? ref($h->{fn}) : $h->{fn};
        $an++ if(defined($fn) && $fn =~ m/doUpdate/);
    }
    return $an;
}

# ----------------------------------------------------------------------------
# Commands_updStart
#   set <name> update: "update all" anstossen und danach GENAU die Module neu
#   laden, deren Datei sich geaendert hat - plus die Nacharbeit aus dem
#   Attribut updatePost.
#
#   Warum nicht einfach warten und dann reloaden: "update" kann im Hintergrund
#   laufen (attr global updateInBackground) und braucht je nach Anzahl der
#   Quellen unterschiedlich lange. Statt an Ereignisnamen zu raten, wird das
#   Modulverzeichnis beobachtet: hat sich zwei Runden lang nichts mehr
#   geruehrt, ist das Update durch.
# ----------------------------------------------------------------------------
sub Commands_updStart {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return "update laeuft bereits" if($hash->{helper}{upd});

    my $vorher = Commands_updSnapshot();
    my $kern   = Commands_updKern();
    my $bg     = AttrVal("global", "updateInBackground", 1) ? 1 : 0;

    my $ret = AnalyzeCommand(undef, "update all");
    $ret = "" if(!defined($ret));

    if($ret =~ /already running/i) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "lastError", $ret);
        readingsBulkUpdate($hash, "state",     "update: laeuft schon");
        readingsEndUpdate($hash, 1);
        return $ret;
    }

    $hash->{helper}{upd} = {
        vorher   => $vorher,
        kern     => $kern,
        letzte   => Commands_updSnapshot(),
        ruhig    => 0,
        gesehen  => 0,
        bg       => $bg,
        start    => time(),
        ausgabe  => $ret,
    };

    # Im Vordergrund ist der Befehl beim Ruecksprung schon fertig - dann gibt
    # es nichts zu beobachten.
    if(!$bg) {
        Log3($name, 3, "$name: update all im Vordergrund gelaufen");
        return Commands_updFinish($hash, 0)
            || "update fertig - Ergebnis im Reading state";
    }

    readingsSingleUpdate($hash, "state", "update laeuft", 1);
    Log3($name, 3, "$name: update all angestossen, warte auf das Ende des Hintergrundlaufs");

    InternalTimer(gettimeofday() + 5, "Commands_updTick", $hash, 0);
    return "update laeuft - das Ergebnis steht gleich im Reading state";
}

# ----------------------------------------------------------------------------
# Commands_updTick
#   Alle 5 s nachsehen, ob der Hintergrundlauf vorbei ist.
#
#   Erste Wahl ist die Prozessliste (Commands_updRunning). Nur wenn dort nie
#   ein Lauf zu sehen war - etwa weil eine kuenftige FHEM-Fassung das anders
#   loest - wird ersatzweise das Modulverzeichnis beobachtet, und auch dann
#   erst nach updateMinWait Sekunden: vorher ist die Ruhe dort nichts wert,
#   weil "update" in dieser Zeit nur Steuerdateien herunterlaedt.
# ----------------------------------------------------------------------------
sub Commands_updTick {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $u    = $hash->{helper}{upd};
    return if(!$u);

    my $alter = time() - $u->{start};
    my $frist = AttrVal($name, "updateTimeout", 180);
    my $laeuft = Commands_updRunning();
    $u->{gesehen} = 1 if($laeuft);

    if($u->{gesehen}) {
        # Der Lauf hat sich selbst abgemeldet -> alle Dateien sind geschrieben.
        return Commands_updFinish($hash, 0) if(!$laeuft);

    } else {
        my $jetzt = Commands_updSnapshot();
        my $gleich = (join("\0", map { "$_=$jetzt->{$_}" } sort keys %$jetzt)
                   eq join("\0", map { "$_=$u->{letzte}{$_}" } sort keys %{$u->{letzte}}));
        $u->{ruhig} = $gleich ? $u->{ruhig} + 1 : 0;
        $u->{letzte} = $jetzt;

        my $mind = AttrVal($name, "updateMinWait", 30);
        return Commands_updFinish($hash, 0) if($u->{ruhig} >= 2 && $alter >= $mind);
    }

    return Commands_updFinish($hash, 1) if($alter > $frist);

    InternalTimer(gettimeofday() + 5, "Commands_updTick", $hash, 0);
    return undef;
}

# ----------------------------------------------------------------------------
# Commands_updModifyAll
#   Nacharbeits-Befehl "modifyAll": alle Geraete des gerade neu geladenen
#   Moduls durch ihr Define schicken (NN_<Typ>.pm -> TYPE=<Typ>).
#
#   Warum nicht einfach "modify <geraet>" in updatePost schreiben: ein blankes
#   "modify <name>" OHNE Argumente setzt DEF auf undef (fhem.pl, CommandModify:
#   $hash->{DEF} = $a[1]). Bei Geraeten mit leerem DEF faellt das nicht auf,
#   bei allen anderen loescht es die Definition. Den DEF stattdessen in das
#   Attribut zu kopieren, waere die zweite schlechte Loesung: er veraltet dort
#   still, und bei Modulen mit Zugangsdaten in der DEF stuende das Passwort
#   noch ein zweites Mal in der Konfiguration.
#
#   Hier wird der aktuelle DEF gelesen und unveraendert wieder mitgegeben.
#   Nebenbei entfaellt damit das Aufzaehlen der Geraetenamen.
# ----------------------------------------------------------------------------
sub Commands_updModifyAll {
    my ($name, $mod) = @_;
    my @fehler;

    my ($typ) = $mod =~ m/^\d\d_(.+)\.pm$/;
    if(!defined($typ)) {
        push @fehler, "modifyAll: $mod ist kein Modulname der Form NN_<Typ>.pm";
        return @fehler;
    }

    # devspec2array liefert den Suchstring zurueck, wenn nichts passt.
    my @dev = grep { $defs{$_} } devspec2array("TYPE=$typ");
    if(!@dev) {
        Log3($name, 4, "$name: modifyAll $typ - keine Geraete");
        return @fehler;
    }

    foreach my $d (@dev) {
        my $def = InternalVal($d, "DEF", "");
        my $ret = CommandModify(undef, $d . ($def =~ /\S/ ? " $def" : ""));
        if(defined($ret) && $ret =~ /\S/) {
            push @fehler, "modify $d -> $ret";
            Log3($name, 2, "$name: modifyAll: modify $d fehlgeschlagen: $ret");
        }
    }
    Log3($name, 3, "$name: modifyAll $typ - " . scalar(@dev) . " Geraet(e)");
    return @fehler;
}

# ----------------------------------------------------------------------------
# Commands_updFinish
#   Geaenderte Module neu laden und die Nacharbeit ausfuehren.
# ----------------------------------------------------------------------------
sub Commands_updFinish {
    my ($hash, $frist) = @_;
    my $name = $hash->{NAME};
    my $u    = delete $hash->{helper}{upd};
    return if(!$u);

    # fhem.pl selbst getauscht? Dann hilft kein reload. NICHT weitermachen:
    # ein halb geladener Zustand ist schlimmer als ein Update, das sichtbar
    # stehenbleibt.
    if(Commands_updKern() ne $u->{kern}) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "lastError",
            "fhem.pl wurde getauscht - shutdown restart noetig, kein reload ausgefuehrt");
        readingsBulkUpdate($hash, "state", "update: Neustart noetig");
        readingsEndUpdate($hash, 1);
        Log3($name, 2, "$name: fhem.pl wurde getauscht, kein reload - shutdown restart noetig");
        return undef;
    }

    my $jetzt = Commands_updSnapshot();
    my @neu = grep { !defined($u->{vorher}{$_}) || $u->{vorher}{$_} ne $jetzt->{$_} }
              sort keys %$jetzt;

    # Das eigene Modul zuletzt: der laufende Aufruf steckt in genau diesem
    # Code, und ein reload mittendrin ist unnoetig heikel.
    my $selbst = "98_Commands.pm";
    @neu = ((grep { $_ ne $selbst } @neu), (grep { $_ eq $selbst } @neu));

    my @fehler;
    my @geladen;
    foreach my $f (@neu) {
        my $ret = AnalyzeCommand(undef, "reload $f");
        if(defined($ret) && $ret =~ /\S/) {
            push @fehler, "reload $f -> $ret";
            Log3($name, 2, "$name: reload $f fehlgeschlagen: $ret");
        } else {
            push @geladen, $f;
            Log3($name, 3, "$name: $f neu geladen");
        }
    }

    # Nacharbeit: "<Modul> = <Befehl>" je Zeile. "*" gilt immer, ein Modulname
    # nur, wenn genau dieses Modul auch neu geladen wurde.
    my %ist = map { $_ => 1 } @geladen;
    my $nach = 0;
    foreach my $line (split(/\n/, AttrVal($name, "updatePost", ""))) {
        $line =~ s/\r$//;
        next if($line !~ /\S/ || $line =~ /^\s*#/);
        my ($mod, $cmd) = $line =~ /^\s*(\S+)\s*=\s*(.+?)\s*$/;
        next if(!defined($cmd));
        $mod .= ".pm" if($mod ne "*" && $mod !~ /\.pm$/);
        next if($mod ne "*" && !$ist{$mod});

        if($cmd eq "modifyAll") {
            my @f = Commands_updModifyAll($name, $mod);
            push(@fehler, @f);
            $nach++ if(!@f);
            next;
        }

        my $ret = AnalyzeCommandChain(undef, $cmd);
        if(defined($ret) && $ret =~ /\S/) {
            push @fehler, "$cmd -> $ret";
            Log3($name, 2, "$name: Nacharbeit \"$cmd\" fehlgeschlagen: $ret");
        } else {
            $nach++;
        }
    }

    my $state = $frist            ? "update: Zeit abgelaufen"
              : @fehler           ? "update: " . scalar(@fehler) . " Fehler"
              : @geladen          ? "update: " . scalar(@geladen) . " Modul(e) neu geladen"
              :                     "update: nichts Neues";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "updated",    join(" ", @geladen));
    readingsBulkUpdate($hash, "updateCount", scalar(@geladen));
    readingsBulkUpdate($hash, "updatePostCount", $nach);
    readingsBulkUpdate($hash, "lastError",  @fehler ? join(" | ", @fehler) : "");
    readingsBulkUpdate($hash, "state",      $state);
    readingsEndUpdate($hash, 1);

    Log3($name, 3, "$name: $state"
        . (@geladen ? " (" . join(", ", @geladen) . ")" : ""));
    return undef;
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
  <p>
    Der Set-Befehl <code>update</code> schliesslich fasst den Ablauf
    <i>update &ndash; warten &ndash; reload &ndash; Nacharbeit</i> zusammen: er
    stoesst <code>update all</code> an, wartet, bis sich im Modulverzeichnis
    nichts mehr ruehrt, laedt genau die Module neu, deren Datei sich geaendert
    hat, und fuehrt anschliessend die zu diesen Modulen hinterlegte Nacharbeit
    aus (Attribut <code>updatePost</code>). Es muss dabei nichts aufgezaehlt
    werden &ndash; ein neues Repo faellt von selbst mit auf.
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
        <code>defmod</code> via <code>AnalyzeCommand</code>, kein Zerlegen an
        <code>;</code> oder Zeilenumbruch). cfg-Stil mit <code>;;</code> und <code>\</code>-Zeilen-
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
    <li><b>update</b> &ndash; stoesst <code>update all</code> an und raeumt
        danach selbsttaetig auf. Der Ablauf im Einzelnen:
        <ol>
          <li>Zeitstempel und Groesse aller <code>&lt;modpath&gt;/FHEM/NN_*.pm</code>
              und von <code>fhem.pl</code> merken.</li>
          <li><code>update all</code> ausfuehren.</li>
          <li>Warten, bis der Lauf zu Ende ist. <code>update</code> laeuft bei
              FHEM standardmaessig im Hintergrund
              (<code>attr global updateInBackground</code>, Default 1) und
              meldet sich am Ende selbst ab; genau das wird abgefragt (dieselbe
              Bedingung, die <code>blockinginfo</code> anzeigt).
              <b>Nicht</b> das Modulverzeichnis: die ersten rund zehn Sekunden
              laedt <code>update</code> nur die <code>controls_*.txt</code>
              uebers Netz und fasst keine einzige Moduldatei an &ndash; die Ruhe
              davor ist von der Ruhe danach nicht zu unterscheiden. Spaetestens
              nach <code>updateTimeout</code> Sekunden wird mit dem gearbeitet,
              was da ist.</li>
          <li>Wurde <code>fhem.pl</code> selbst getauscht, wird
              <i>abgebrochen</i> (state <code>update: Neustart noetig</code>)
              &ndash; da hilft kein <code>reload</code>, und ein halb geladener
              Zustand waere schlimmer als ein sichtbar stehengebliebenes
              Update. Die Meldung
              <code>update finished, "shutdown restart" is needed</code> taugt
              dafuer <b>nicht</b>: die schreibt FHEM nach jedem Lauf, bei dem
              irgendetwas geladen wurde.</li>
          <li>Genau die geaenderten Module per <code>reload</code> neu laden
              &ndash; <code>98_Commands.pm</code> als letztes, weil der laufende
              Aufruf in eben diesem Code steckt.</li>
          <li>Die Nacharbeit aus <code>updatePost</code> ausfuehren, aber nur
              die Zeilen, deren Modul auch wirklich neu geladen wurde.</li>
        </ol>
        Es wird also nichts aufgezaehlt und nichts geraten: was sich geaendert
        hat, sagt das Dateisystem.
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
    <li><b>webLink</b> &ndash; Auswahl (Mehrfach) der FHEMWEB-Geraete, in denen
        ein Link <i>neben der oberen Befehlszeile</i> auf die Detailseite dieses
        Geraets eingeblendet wird. Das Modul traegt dazu
        <code>pgm2/fhemweb_custom_link.js</code> automatisch in das
        <code>JavaScripts</code>-Attribut der gewaehlten WEB-Geraete ein und
        entfernt es aus abgewaehlten. Nach Auswahl im Browser einmal
        Strg+Shift+R.</li>
    <li><b>webLinkLabel</b> &ndash; Beschriftung des Links (Default
        <code>Commands</code>).</li>
    <li><b>updatePost</b> &ndash; Nacharbeit fuer <code>set &lt;name&gt; update</code>,
        eine Zeile je Schritt im Format <code>&lt;Modul&gt; = &lt;Befehl&gt;</code>.
        Der Befehl laeuft nur, wenn genau dieses Modul auch neu geladen wurde;
        <code>*</code> steht fuer "immer". Die Endung <code>.pm</code> darf
        weggelassen werden. Leerzeilen und <code>#</code>-Zeilen werden
        ignoriert, mehrere Zeilen zum selben Modul sind erlaubt und laufen in
        der angegebenen Reihenfolge.
        <br><br>
        <code>
        98_FHEMVIZ = modifyAll<br>
        98_FHEMVIZ = set myViz reload<br>
        98_Gartenbewaesserung = modifyAll<br>
        # nach jedem Update, egal was sich geaendert hat<br>
        * = save<br>
        </code>
        <br>
        Das Attribut ist <code>textField-long</code>, laesst sich also bequem
        im FHEMWEB-Editor pflegen.
        <br><br>
        <b>modifyAll</b> ist dabei kein FHEM-Befehl, sondern ein Schluesselwort
        dieses Moduls: es schickt <i>alle</i> Geraete des gerade neu geladenen
        Moduls durch ihr Define (<code>NN_&lt;Typ&gt;.pm</code> &rarr;
        <code>TYPE=&lt;Typ&gt;</code>) und gibt dabei den vorhandenen
        <code>DEF</code> unveraendert wieder mit. Ein von Hand geschriebenes
        <code>modify &lt;geraet&gt;</code> <b>ohne</b> Argumente wuerde den
        <code>DEF</code> loeschen (fhem.pl setzt <code>$hash-&gt;{DEF}</code> auf
        den zweiten Parameter, und den gibt es dann nicht); den DEF ins Attribut
        zu kopieren waere die zweite schlechte Loesung, weil er dort still
        veraltet und bei Modulen mit Zugangsdaten in der Definition das Passwort
        ein zweites Mal in der Konfiguration stuende. Nebenbei muessen die
        Geraetenamen so gar nicht erst aufgezaehlt werden.</li>
    <li><b>updateTimeout</b> &ndash; Sekunden, nach denen
        <code>set &lt;name&gt; update</code> spaetestens aufhoert zu warten
        (Default 180). Reading <code>state</code> lautet dann
        <code>update: Zeit abgelaufen</code>; die bis dahin geaenderten Module
        werden trotzdem geladen. Groesser setzen, wenn viele Quellen in
        <code>controls_*.txt</code> eingetragen sind oder die Leitung langsam
        ist.</li>
    <li><b>updateMinWait</b> &ndash; Notnagel (Default 30). Nur wirksam, wenn
        sich der Hintergrundlauf gar nicht auffinden laesst; dann wird
        ersatzweise das Modulverzeichnis beobachtet, aber fruehestens nach so
        vielen Sekunden entschieden. Im Normalfall wird das Attribut nie
        gebraucht.</li>
  </ul>
  <br>

  <a name="Commandsreadings"></a>
  <b>Readings</b>
  <ul>
    <li><b>state</b> &ndash; idle / done (x ok) / error at x / done (x ok, y errors)
        bzw. nach <code>define</code>: defined (&lt;name&gt;) / define error;
        waehrend und nach <code>update</code>: update laeuft /
        update: x Modul(e) neu geladen / update: nichts Neues /
        update: x Fehler / update: Zeit abgelaufen /
        update: Neustart noetig / update: laeuft schon</li>
    <li><b>executed</b> &ndash; Anzahl erfolgreich ausgefuehrter Befehle (execute)</li>
    <li><b>errorCount</b> &ndash; Anzahl fehlerhafter Befehle (execute)</li>
    <li><b>lastError</b> &ndash; zuletzt aufgetretener Fehler</li>
    <li><b>updated</b> &ndash; Dateinamen der zuletzt neu geladenen Module (update)</li>
    <li><b>updateCount</b> &ndash; Anzahl davon (update)</li>
    <li><b>updatePostCount</b> &ndash; Anzahl ausgefuehrter Nacharbeits-Befehle (update)</li>
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
