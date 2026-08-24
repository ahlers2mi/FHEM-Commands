#!/usr/bin/perl
# Szenario-Tests fuer "set <name> update" (98_Commands.pm) gegen die
# FHEM-Attrappe in t/FhemStub.pm - ohne FHEM-Installation.
#
# Aufruf:  perl t/run.pl
#
# Der Test legt ein Wegwerf-Modulverzeichnis an und fasst darin Dateien an,
# waehrend die virtuelle Uhr laeuft - genau das, was "update" im Betrieb tut.
# Wichtig dabei ist die REIHENFOLGE: FHEM laedt erst rund zehn Sekunden lang
# nur die controls_*.txt uebers Netz und schreibt die Moduldateien erst danach.
# Genau diese Luecke hat eine fruehere Fassung als "nichts Neues" gedeutet.
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin;
use lib $FindBin::Bin;

require "$FindBin::Bin/FhemStub.pm";
require "$FindBin::Bin/../FHEM/98_Commands.pm";

our %defs;
our @LOG;

my $tests = 0;
my $bad   = 0;

sub ok {
    my ($name, $wahr, $info) = @_;
    $tests++;
    if($wahr) { print "ok   $name\n"; return 1; }
    $bad++;
    print "FEHL $name" . (defined($info) ? "  ($info)" : "") . "\n";
    return 0;
}
sub is { my ($n, $ist, $soll) = @_;
    return ok($n, (defined($ist) ? $ist : "") eq $soll,
              "ist '" . (defined($ist) ? $ist : "undef") . "', soll '$soll'"); }

# ---------------------------------------------------------------- Aufbau
my $root;
my $hash;
sub aufbau {
    $root = tempdir(CLEANUP => 1);
    make_path("$root/FHEM");
    foreach my $f (qw(98_Commands.pm 98_FHEMVIZ.pm 98_Gartenbewaesserung.pm 99_myUtils.pm)) {
        open(my $fh, ">", "$root/FHEM/$f") or die $!;
        print $fh "alt\n"; close($fh);
    }
    open(my $fh, ">", "$root/fhem.pl") or die $!;
    print $fh "alt\n"; close($fh);
    utime(1000, 1000, glob("$root/FHEM/*.pm"), "$root/fhem.pl");

    %main::attr = ("global" => { modpath => $root });
    @main::CMD = (); @main::LOG = (); @main::TIMER = ();
    %main::CMDRET = (); %main::BC_hash = ();
    $main::NOW = 1_700_000_000;
    $hash = { NAME => "myCommander", READINGS => {} };
    $main::defs{myCommander} = $hash;
}

sub beruehren {          # Datei "neu schreiben", wie es update tut
    my (@f) = @_;
    foreach my $f (@f) {
        my $p = ($f eq "fhem.pl") ? "$root/$f" : "$root/FHEM/$f";
        open(my $fh, ">", $p) or die $!;
        print $fh "neu " . rand() . "\n"; close($fh);
        utime($main::NOW, $main::NOW, $p);
    }
}

sub reloads { return grep { /^reload / } @main::CMD; }
sub zustand { return $hash->{READINGS}{state}{VAL}; }

# ---------------------------------------------------------------------------
# 1: der Fall aus dem Log vom 24.08. - die Dateien kommen ERST NACH der
#    Netzwerkphase. Vorher darf nicht entschieden werden.
# ---------------------------------------------------------------------------
aufbau();
$main::attr{myCommander}{updatePost} =
    "98_FHEMVIZ.pm = modify myViz\n"
  . "98_FHEMVIZ.pm = set myViz reload\n"
  . "98_Gartenbewaesserung.pm = modify bewaesserung\n"
  . "* = save\n";
Commands_Set($hash, "myCommander", "update");
is("1 state waehrend des Laufs", zustand(), "update laeuft");
main::advance(10);                     # zwei Ticks, Verzeichnis unberuehrt
is("1 nach 10 s noch nicht entschieden", zustand(), "update laeuft");
is("1 und noch nichts geladen", scalar(reloads()), 0);
main::advance(2);
beruehren("98_FHEMVIZ.pm");            # jetzt erst schreibt update
main::advance(1);
main::bc_ende();                       # Kindprozess meldet sich ab
main::advance(6);
my @rl = reloads();
is("1 nur ein Modul neu geladen", scalar(@rl), 1);
is("1 und zwar FHEMVIZ", $rl[0], "reload 98_FHEMVIZ.pm");
ok("1 Nacharbeit FHEMVIZ gelaufen", (grep { $_ eq "modify myViz" } @main::CMD) == 1);
ok("1 set myViz reload gelaufen", (grep { $_ eq "set myViz reload" } @main::CMD) == 1);
ok("1 Nacharbeit Bewaesserung NICHT gelaufen",
   (grep { $_ eq "modify bewaesserung" } @main::CMD) == 0);
ok("1 Sternchen-Zeile immer gelaufen", (grep { $_ eq "save" } @main::CMD) == 1);
is("1 Zaehler", $hash->{READINGS}{updateCount}{VAL}, 1);

# ---------------------------------------------------------------------------
# 2: nichts hat sich getan - auch das erst melden, wenn der Lauf vorbei ist
# ---------------------------------------------------------------------------
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(10);
is("2 nach 10 s noch nicht entschieden", zustand(), "update laeuft");
main::bc_ende();
main::advance(6);
is("2 kein reload", scalar(reloads()), 0);
is("2 state", zustand(), "update: nichts Neues");

# ---------------------------------------------------------------------------
# 3: das eigene Modul kommt als letztes
# ---------------------------------------------------------------------------
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(12);
beruehren("98_Commands.pm", "98_FHEMVIZ.pm", "99_myUtils.pm");
main::bc_ende();
main::advance(6);
@rl = reloads();
is("3 drei reloads", scalar(@rl), 3);
is("3 eigenes Modul zuletzt", $rl[-1], "reload 98_Commands.pm");

# ---------------------------------------------------------------------------
# 4: fhem.pl getauscht -> Neustart noetig, NICHTS wird geladen
#    (die Meldung von update taugt dafuer nicht: 'shutdown restart is needed'
#     schreibt FHEM nach jedem Lauf, bei dem irgendetwas geladen wurde)
# ---------------------------------------------------------------------------
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(12);
beruehren("fhem.pl", "98_FHEMVIZ.pm");
main::bc_ende();
main::advance(6);
is("4 kein reload", scalar(reloads()), 0);
is("4 state", zustand(), "update: Neustart noetig");
ok("4 lastError nennt fhem.pl", $hash->{READINGS}{lastError}{VAL} =~ /fhem\.pl/);

# ---------------------------------------------------------------------------
# 5: spaeter Schreiber - der Lauf ist erst zu Ende, wenn er es sagt
# ---------------------------------------------------------------------------
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(11);
beruehren("98_FHEMVIZ.pm");
main::advance(6);
beruehren("98_Gartenbewaesserung.pm");   # zweite Quelle kommt spaeter
main::bc_ende();
main::advance(6);
@rl = reloads();
is("5 beide Module geladen", scalar(@rl), 2);
ok("5 Bewaesserung dabei",
   (grep { $_ eq "reload 98_Gartenbewaesserung.pm" } @rl) == 1);

# ---------------------------------------------------------------------------
# 6: reload schlaegt fehl -> seine Nacharbeit wird uebersprungen
# ---------------------------------------------------------------------------
aufbau();
$main::CMDRET{"^reload 98_FHEMVIZ"} = "Cannot load module";
$main::attr{myCommander}{updatePost} = "98_FHEMVIZ.pm = modify myViz\n";
Commands_Set($hash, "myCommander", "update");
main::advance(12);
beruehren("98_FHEMVIZ.pm");
main::bc_ende();
main::advance(6);
ok("6 state meldet Fehler", zustand() =~ /Fehler/);
ok("6 lastError gefuellt", $hash->{READINGS}{lastError}{VAL} =~ /Cannot load module/);
ok("6 Nacharbeit uebersprungen", (grep { $_ eq "modify myViz" } @main::CMD) == 0);

# ---------------------------------------------------------------------------
# 7: Vordergrund (updateInBackground 0) - der Befehl ist beim Ruecksprung durch
# ---------------------------------------------------------------------------
aufbau();
$main::attr{global}{updateInBackground} = 0;
$main::CMDRET{"^update all"} =
    'update finished, "shutdown restart" is needed to activate the changes.';
Commands_Set($hash, "myCommander", "update");
is("7 sofort entschieden", zustand(), "update: nichts Neues");
ok("7 kein Timer armiert", scalar(@main::TIMER) == 0);
ok("7 generische Neustart-Meldung ist KEIN Abbruchgrund", zustand() !~ /Neustart/);

# ---------------------------------------------------------------------------
# 8: keine Prozessliste sichtbar -> Ersatzweg, aber nicht vor updateMinWait
# ---------------------------------------------------------------------------
aufbau();
$main::attr{myCommander}{updateMinWait} = 30;
Commands_Set($hash, "myCommander", "update");
%main::BC_hash = ();                   # Blocking.pm meldet nichts
main::advance(12);
is("8 vor updateMinWait keine Entscheidung", zustand(), "update laeuft");
main::advance(25);
is("8 danach entschieden", zustand(), "update: nichts Neues");

# ---------------------------------------------------------------------------
# 9: update laeuft schon
# ---------------------------------------------------------------------------
aufbau();
$main::CMDRET{"^update all"} = "An update is already running";
my $ret = Commands_Set($hash, "myCommander", "update");
ok("9 Rueckgabe weitergereicht", $ret =~ /already running/);
is("9 state", zustand(), "update: laeuft schon");
ok("9 kein Timer armiert", scalar(@main::TIMER) == 0);

# ---------------------------------------------------------------------------
# 10: Zeit abgelaufen, obwohl der Lauf noch haengt
# ---------------------------------------------------------------------------
aufbau();
$main::attr{myCommander}{updateTimeout} = 60;
Commands_Set($hash, "myCommander", "update");
main::advance(90);                     # bc_ende kommt nie
is("10 state", zustand(), "update: Zeit abgelaufen");

print "\n$tests Tests, $bad Fehler\n";
exit($bad ? 1 : 0);
