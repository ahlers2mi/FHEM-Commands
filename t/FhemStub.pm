# FHEM-Attrappe fuer die Tests unter t/ - genug, damit 98_Commands.pm laeuft,
# ohne eine FHEM-Installation zu brauchen.
#
# Wichtig: die Uhr ist VIRTUELL. time() liefert $main::NOW, advance() schiebt
# vor und feuert dabei die faelligen InternalTimer. Ein Update, das im Betrieb
# eine Minute braucht, laeuft im Test in Millisekunden - und der Test kann
# genau zwischen zwei Ticks Dateien anfassen, so wie es "update" tut.
package main;

use strict;
use warnings;

our %defs;
our %attr;
our %modules;
our $init_done = 1;
our $readingFnAttributes = "event-on-change-reading";
our $NOW = 1_700_000_000;

our @LOG;        # [level, text]
our @CMD;        # ausgefuehrte FHEM-Befehle
our %CMDRET;     # Befehl (Regex-String) -> Rueckgabe
our @TIMER;      # [zeit, funktion, arg]

sub time_now { return $NOW; }
BEGIN { *CORE::GLOBAL::time = sub { return $main::NOW; }; }

sub gettimeofday { return $NOW; }

sub Log3 { my ($n, $l, $t) = @_; push @LOG, [$l, $t]; return undef; }

sub AttrVal {
    my ($d, $a, $def) = @_;
    return (defined($attr{$d}) && defined($attr{$d}{$a})) ? $attr{$d}{$a} : $def;
}
sub ReadingsVal {
    my ($d, $r, $def) = @_;
    return (defined($defs{$d}) && defined($defs{$d}{READINGS}{$r}))
        ? $defs{$d}{READINGS}{$r}{VAL} : $def;
}
sub IsDisabled { my ($n) = @_; return AttrVal($n, "disable", 0) ? 1 : 0; }

sub readingsBeginUpdate { return 1; }
sub readingsEndUpdate   { return 1; }
sub readingsBulkUpdate {
    my ($hash, $r, $v) = @_;
    $hash->{READINGS}{$r}{VAL} = $v;
    return 1;
}
sub readingsSingleUpdate {
    my ($hash, $r, $v) = @_;
    $hash->{READINGS}{$r}{VAL} = $v;
    return 1;
}

# Befehle nur mitschreiben; per %CMDRET laesst sich ein Fehler erzwingen.
sub AnalyzeCommand {
    my ($cl, $cmd) = @_;
    push @CMD, $cmd;
    foreach my $re (keys %CMDRET) { return $CMDRET{$re} if($cmd =~ /$re/); }
    return undef;
}
sub AnalyzeCommandChain { return AnalyzeCommand(@_); }
sub CommandAttr { return undef; }
sub CommandDeleteAttr { return undef; }
sub devspec2array { return (); }
sub setDevAttrList { return undef; }

sub InternalTimer {
    my ($t, $fn, $arg) = @_;
    push @TIMER, [$t, $fn, $arg];
    return undef;
}
sub RemoveInternalTimer { @TIMER = (); return undef; }

# Uhr vorschieben und dabei alles feuern, was faellig wird.
sub advance {
    my ($sek) = @_;
    my $ziel = $NOW + $sek;
    while (1) {
        my @due = grep { $_->[0] <= $ziel } @TIMER;
        last if(!@due);
        @due = sort { $a->[0] <=> $b->[0] } @due;
        my $t = shift @due;
        @TIMER = grep { $_ != $t } @TIMER;
        $NOW = $t->[0];
        no strict "refs";
        &{$t->[1]}($t->[2]);
    }
    $NOW = $ziel;
    return undef;
}

1;
