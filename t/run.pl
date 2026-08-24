#!/usr/bin/perl
# Szenario-Tests fuer "set <name> update" (98_Commands.pm) gegen die
# FHEM-Attrappe in t/FhemStub.pm - ohne FHEM-Installation.
#
# Aufruf:  perl t/run.pl
#
# Der Test legt ein Wegwerf-Modulverzeichnis an und fasst darin Dateien an,
# waehrend die virtuelle Uhr laeuft - genau das, was "update" im Betrieb tut.
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
    # ein paar Module, die es schon gibt
    foreach my $f (qw(98_Commands.pm 98_FHEMVIZ.pm 98_Gartenbewaesserung.pm 99_myUtils.pm)) {
        open(my $fh, ">", "$root/FHEM/$f") or die $!;
        print $fh "alt\n"; close($fh);
    }
    utime(1000, 1000, glob("$root/FHEM/*.pm"));

    %main::attr = ("global" => { modpath => $root });
    @main::CMD = (); @main::LOG = (); @main::TIMER = (); %main::CMDRET = ();
    $main::NOW = 1_700_000_000;
    $hash = { NAME => "myCommander", READINGS => {} };
    $main::defs{myCommander} = $hash;
}

sub beruehren {          # Datei "neu schreiben", wie es update tut
    my (@f) = @_;
    foreach my $f (@f) {
        open(my $fh, ">", "$root/FHEM/$f") or die $!;
        print $fh "neu " . rand() . "\n"; close($fh);
        utime($main::NOW, $main::NOW, "$root/FHEM/$f");
    }
}

sub reloads { return grep { /^reload / } @main::CMD; }

# ---------------------------------------------------- 1: nur Geaendertes
aufbau();
$main::attr{myCommander}{updatePost} =
    "98_FHEMVIZ.pm = modify myViz\n"
  . "98_FHEMVIZ.pm = set myViz reload\n"
  . "98_Gartenbewaesserung.pm = modify bewaesserung\n"
  . "* = save\n";
Commands_Set($hash, "myCommander", "update");
is("1 state waehrend des Laufs", $hash->{READINGS}{state}{VAL}, "update laeuft");
main::advance(2);
beruehren("98_FHEMVIZ.pm");           # update schreibt eine Datei
main::advance(20);                    # zwei ruhige Runden abwarten
my @rl = reloads();
is("1 nur ein Modul neu geladen", scalar(@rl), 1);
is("1 und zwar FHEMVIZ", $rl[0], "reload 98_FHEMVIZ.pm");
ok("1 Nacharbeit FHEMVIZ gelaufen", (grep { $_ eq "modify myViz" } @main::CMD) == 1);
ok("1 set myViz reload gelaufen", (grep { $_ eq "set myViz reload" } @main::CMD) == 1);
ok("1 Nacharbeit Bewaesserung NICHT gelaufen",
   (grep { $_ eq "modify bewaesserung" } @main::CMD) == 0);
ok("1 Sternchen-Zeile immer gelaufen", (grep { $_ eq "save" } @main::CMD) == 1);
is("1 Zaehler", $hash->{READINGS}{updateCount}{VAL}, 1);

# ------------------------------------------------- 2: nichts hat sich getan
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(20);
is("2 kein reload", scalar(reloads()), 0);
is("2 state", $hash->{READINGS}{state}{VAL}, "update: nichts Neues");

# ------------------------------------ 3: das eigene Modul kommt als letztes
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(2);
beruehren("98_Commands.pm", "98_FHEMVIZ.pm", "99_myUtils.pm");
main::advance(20);
@rl = reloads();
is("3 drei reloads", scalar(@rl), 3);
is("3 eigenes Modul zuletzt", $rl[-1], "reload 98_Commands.pm");

# ------------------------------------------- 4: Neustart noetig -> Abbruch
aufbau();
$main::CMDRET{"^update all"} = "Please restart FHEM";
my $ret = Commands_Set($hash, "myCommander", "update");
ok("4 Rueckgabe nennt den Neustart", $ret =~ /Neustart/);
is("4 kein reload", scalar(reloads()), 0);
is("4 state", $hash->{READINGS}{state}{VAL}, "update: Neustart noetig");
ok("4 kein Timer armiert", scalar(@main::TIMER) == 0);

# --------------------------------- 5: spaeter Schreiber verlaengert das Warten
aufbau();
Commands_Set($hash, "myCommander", "update");
main::advance(6);
beruehren("98_FHEMVIZ.pm");
main::advance(6);
beruehren("98_Gartenbewaesserung.pm");   # zweite Quelle kommt spaeter
main::advance(20);
@rl = reloads();
is("5 beide Module geladen", scalar(@rl), 2);
ok("5 Bewaesserung dabei",
   (grep { $_ eq "reload 98_Gartenbewaesserung.pm" } @rl) == 1);

# ------------------------------------------- 6: reload schlaegt fehl
aufbau();
$main::CMDRET{"^reload 98_FHEMVIZ"} = "Cannot load module";
$main::attr{myCommander}{updatePost} = "98_FHEMVIZ.pm = modify myViz\n";
Commands_Set($hash, "myCommander", "update");
main::advance(2);
beruehren("98_FHEMVIZ.pm");
main::advance(20);
ok("6 state meldet Fehler", $hash->{READINGS}{state}{VAL} =~ /Fehler/);
ok("6 lastError gefuellt", $hash->{READINGS}{lastError}{VAL} =~ /Cannot load module/);
ok("6 Nacharbeit uebersprungen", (grep { $_ eq "modify myViz" } @main::CMD) == 0);

print "\n$tests Tests, $bad Fehler\n";
exit($bad ? 1 : 0);
