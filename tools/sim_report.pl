#!/usr/bin/perl
# Summarizes user://sims/*_<label>N.json from tools/sim.sh.
use strict; use warnings; use JSON::PP;
my $label = shift // "b";
my $dir = "$ENV{APPDATA}/Godot/app_userdata/Star Lords/sims";
my %s;
opendir(my $dh, $dir) or die "no $dir";
my @files = map { "$dir/$_" } grep { /_\Q$label\E\d+\.json$/ } readdir($dh);
for my $f (@files) {
	open my $fh, "<", $f or next; local $/; my $d = decode_json(<$fh>); close $fh;
	my $k = $d->{system}; my $x = ($s{$k} //= {n=>0, p1=>0, p2=>0, draw=>0, min=>0, len=>[], w=>0, peak=>0, tech=>0});
	$x->{n}++; $x->{p1}++ if $d->{winner} == 1; $x->{p2}++ if $d->{winner} == 2; $x->{draw}++ if $d->{winner} == 0;
	$x->{min} += $d->{minutes}; push @{$x->{len}}, $d->{minutes};
	my $last = $d->{samples}[-1];
	$x->{w} += $last->{1}{worlds} + $last->{2}{worlds};
	my $pk = 0; for my $smp (@{$d->{samples}}) { for my $p (1, 2) { $pk = $smp->{$p}{warships} if $smp->{$p}{warships} > $pk } }
	$x->{peak} += $pk; $x->{tech} += $last->{1}{techs} + $last->{2}{techs};
}
printf "%-15s %4s %4s %4s %5s %8s  %-28s %8s %8s %8s\n", "system", "runs", "P1", "P2", "draw", "avg min", "match lengths", "worlds", "peak war", "techs";
for my $k (sort keys %s) {
	my $x = $s{$k}; my $n = $x->{n};
	printf "%-15s %4d %4d %4d %5d %8.1f  %-28s %8.1f %8.1f %8.1f\n", $k, $n, $x->{p1}, $x->{p2}, $x->{draw}, $x->{min} / $n,
		join(",", map { sprintf "%.0f", $_ } sort { $a <=> $b } @{$x->{len}}), $x->{w} / $n / 2, $x->{peak} / $n, $x->{tech} / $n / 2;
}
