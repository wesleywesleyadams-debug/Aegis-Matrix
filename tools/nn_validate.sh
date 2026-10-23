#!/bin/sh
# Validate a trained NeuralCommander against the scripted AI on fresh seeds:
#   tools/nn_validate.sh [weights res:// path] [games per system] [label] [jobs]
# Plays every system, half the games from each side, and prints win / loss /
# draw per system plus the total.
W="${1:-res://ai/commander.json}"
N="${2:-10}"
LABEL="${3:-val}"
JOBS="${4:-5}"
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.."
export G W
for sys in orion_reach vega_drift kharon_expanse tethys_cluster sable_verge; do
	for i in $(seq 1 "$N"); do
		echo "$sys ${LABEL}${i} $(( i % 2 + 1 ))"
	done
done | xargs -P "$JOBS" -L 1 sh -c 'SL_SIM="$1" SL_SEED="$1" SL_NN_WEIGHTS="$W" SL_NN_SIDE="$2" SL_SIM_MINUTES=40 SL_SYSTEM="$0" timeout 2400 "$G" --headless --path . --fixed-fps 60 res://scenes/Main.tscn > /dev/null 2>&1'
perl -MJSON::PP -e '
	my ($label, $n) = @ARGV; my $dir = "$ENV{APPDATA}/Godot/app_userdata/Aegis Matrix/sims"; my (%s, @tot);
	for my $sys (qw(orion_reach vega_drift kharon_expanse tethys_cluster sable_verge)) {
		for my $i (1 .. $n) {
			my $f = "$dir/${sys}_$label$i.json"; open my $h, "<", $f or do { $s{$sys}[3]++; next }; local $/; my $r = decode_json(<$h>); close $h; unlink $f;
			my $me = $i % 2 + 1; my $k = $r->{winner} == $me ? 0 : ($r->{winner} == 0 ? 2 : 1);
			$s{$sys}[$k]++; $tot[$k]++; push @{$s{$sys}[4]}, $r->{minutes};
		}
		my $l = $s{$sys}; printf "%-15s NN wins %2d  losses %2d  draws %2d  missing %d   avg %.1f min\n", $sys, $l->[0] // 0, $l->[1] // 0, $l->[2] // 0, $l->[3] // 0, eval { my $t = 0; $t += $_ for @{$l->[4]}; $t / @{$l->[4]} } // 0;
	}
	my $all = ($tot[0] // 0) + ($tot[1] // 0) + ($tot[2] // 0);
	printf "TOTAL           NN wins %2d  losses %2d  draws %2d   -> win rate %.0f%%\n", $tot[0] // 0, $tot[1] // 0, $tot[2] // 0, 100 * ($tot[0] // 0) / ($all || 1);
' "$LABEL" "$N"
