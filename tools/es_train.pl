#!/usr/bin/perl
# Evolution-strategies trainer for the NeuralCommander (see
# scripts/game/NeuralCommander.gd). Each generation: sample PAIRS mirrored
# noise vectors, play each perturbed network against the scripted AI from
# both sides (headless sims, JOBS at a time), rank the results, and step the
# weights toward what won (Adam). Progress is logged to rl/log.csv; weights
# are saved every generation to rl/theta.json (training resumes from it) and
# copied to res://ai/commander_latest.json; the best-evaluated network so far
# is kept as res://ai/commander.json (what the game uses).
#
# perl tools/es_train.pl [generations] [system] [minutes cap]
#   env: PAIRS (6), SEEDS per side (2), JOBS (5), SIGMA (0.1), LR (0.03),
#        EVAL_EVERY (5), EVAL_GAMES (10)
use strict; use warnings; use JSON::PP; use File::Copy;

my $GENS = shift // 20;
my $SYSTEM = shift // "orion_reach";
my $CAP = shift // 20;
my $PAIRS = $ENV{PAIRS} // 6;
my $JOBS = $ENV{JOBS} // 5;
my $SIGMA = $ENV{SIGMA} // 0.1;
my $LR = $ENV{LR} // 0.03;
my $EVAL_EVERY = $ENV{EVAL_EVERY} // 5;
my $SEEDS = $ENV{SEEDS} // 2;
my $EVAL_GAMES = $ENV{EVAL_GAMES} // 10;
my $GODOT = $ENV{GODOT} // "/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe";
my ($N_IN, $N_H, $N_OUT) = (21, 16, 9);
my $NP = $N_H * $N_IN + $N_H + $N_OUT * $N_H + $N_OUT;

my $USER = "$ENV{APPDATA}/Godot/app_userdata/Star Lords";
my $RL = "$USER/rl";
my $SIMS = "$USER/sims";
mkdir $RL; mkdir $SIMS; mkdir "ai";
# Weight files the sims load: inside the project (res://ai/train/...) because
# the user-data path contains a space, which would split the job lines.
mkdir "ai/train";
sub res_path { my $name = shift; return ("ai/train/$name", "res://ai/train/$name") }
my $json = JSON::PP->new->canonical;

sub gauss { my $u1 = rand() || 1e-12; my $u2 = rand(); return sqrt(-2 * log($u1)) * cos(6.283185307 * $u2) }
sub slurp { my $f = shift; open my $h, "<", $f or return undef; local $/; my $d = <$h>; close $h; return $d }
sub spit { my ($f, $d) = @_; open my $h, ">", $f or die "write $f: $!"; print $h $d; close $h }
sub weights_file { my ($path, $w) = @_; spit($path, $json->encode({inputs => $N_IN, hidden => $N_H, outputs => $N_OUT, weights => $w})) }

# Resume or start fresh (small random weights).
my $state = -e "$RL/theta.json" ? decode_json(slurp("$RL/theta.json")) : undef;
my @theta = $state ? @{$state->{weights}} : map { gauss() * 0.1 } 1 .. $NP;
my @m = $state && $state->{m} ? @{$state->{m}} : (0) x $NP;
my @v = $state && $state->{v} ? @{$state->{v}} : (0) x $NP;
my $gen0 = $state ? $state->{gen} : 0;
open my $LOG, ">>", "$RL/log.csv" or die;
print $LOG "gen,mean_fitness,win_rate,best_fitness,eval_win_rate,seconds\n" if $gen0 == 0;

# Plays the given weight files as the NN side; returns {tag => fitness, ...}.
sub play {
	my ($explore, @jobs) = @_;   # jobs: [tag, weights path, side, seed]
	my $list = join("", map { "$_->[0] $_->[1] $_->[2] $_->[3]\n" } @jobs);
	spit("$RL/jobs.txt", $list);
	# Training matches sample actions (exploration); evaluations play greedily.
	my $ex = $explore ? "SL_NN_EXPLORE=1 " : "";
	my $cmd = "cat \"$RL/jobs.txt\" | xargs -P $JOBS -L 1 sh -c '${ex}SL_SIM=\"\$0\" SL_NN_WEIGHTS=\"\$1\" SL_NN_SIDE=\"\$2\" SL_SEED=\"\$3\" SL_SIM_MINUTES=$CAP SL_SYSTEM=$SYSTEM timeout 2400 \"$GODOT\" --headless --path . --fixed-fps 60 res://scenes/Main.tscn > /dev/null 2>&1'";
	system($cmd);
	my %fit;
	for my $j (@jobs) {
		my $f = "$SIMS/${SYSTEM}_$j->[0].json";
		my $d = slurp($f);
		if (!defined $d) { $fit{$j->[0]} = -1.5; next }   # crashed / timed out
		unlink $f;
		my $r = decode_json($d);
		my $me = $j->[2]; my $foe = 3 - $me;
		# Sanity check: the network must actually have played this side.
		die "NN did not play side $me in $j->[0] (weights $j->[1] not loaded?)\n" unless $r->{nn_actions} && $r->{nn_actions}{$me};
		my $last = $r->{samples}[-1];
		my $score = $r->{winner} == $me ? 1 + 0.5 * ($CAP - $r->{minutes}) / $CAP : ($r->{winner} == 0 ? 0 : -1);
		$score += 0.3 * tanh_(($last->{$me}{worlds} - $last->{$foe}{worlds}) / 3);
		$score += 0.3 * tanh_(($last->{$me}{power} - $last->{$foe}{power}) / 5000);
		$fit{$j->[0]} = $score;
		$fit{"win_$j->[0]"} = $r->{winner} == $me ? 1 : 0;
	}
	return \%fit;
}
sub tanh_ { my $x = shift; my $e = exp(2 * $x); return ($e - 1) / ($e + 1) }

for my $g ($gen0 + 1 .. $gen0 + $GENS) {
	my $t0 = time;
	my (@eps, @jobs);
	for my $k (0 .. $PAIRS - 1) {
		my @e = map { gauss() } 1 .. $NP;
		push @eps, \@e;
		for my $sgn (1, -1) {
			my $c = "g${g}k${k}" . ($sgn > 0 ? "p" : "n");
			my ($cfile, $cres) = res_path("$c.json");
			weights_file($cfile, [map { $theta[$_] + $sgn * $SIGMA * $e[$_] } 0 .. $NP - 1]);
			# Common random numbers: the + and - variants of pair k play the
			# same seeds, so their difference reflects the weights, not luck.
			for my $m (1 .. $SEEDS) {
				push @jobs, ["rl${c}m${m}s$_", $cres, $_, "g${g}k${k}m${m}s$_"] for (1, 2);
			}
		}
	}
	my $fit = play(1, @jobs);
	# Candidate fitness = mean over its matches; then centered ranks.
	my (%cf, $wins, $games);
	for my $j (@jobs) {
		(my $c = $j->[0]) =~ s/^rl(.*)m\d+s\d$/$1/;
		push @{$cf{$c}}, $fit->{$j->[0]};
		$wins += $fit->{"win_$j->[0]"} // 0; $games++;
	}
	my %mean = map { my $a = $cf{$_}; ($_ => (eval { my $s = 0; $s += $_ for @$a; $s / @$a })) } keys %cf;
	my @sorted = sort { $mean{$a} <=> $mean{$b} } keys %mean;
	my %rank; @rank{@sorted} = map { $_ / (@sorted - 1) - 0.5 } 0 .. $#sorted;
	my @grad = (0) x $NP;
	for my $k (0 .. $PAIRS - 1) {
		my $d = $rank{"g${g}k${k}p"} - $rank{"g${g}k${k}n"};
		$grad[$_] += $d * $eps[$k][$_] for 0 .. $NP - 1;
	}
	# Adam ascent step.
	my ($b1, $b2) = (0.9, 0.999);
	for my $i (0 .. $NP - 1) {
		my $gi = $grad[$i] / ($PAIRS * $SIGMA);
		$m[$i] = $b1 * $m[$i] + (1 - $b1) * $gi;
		$v[$i] = $b2 * $v[$i] + (1 - $b2) * $gi * $gi;
		my $mh = $m[$i] / (1 - $b1 ** $g); my $vh = $v[$i] / (1 - $b2 ** $g);
		$theta[$i] += $LR * $mh / (sqrt($vh) + 1e-8);
		$theta[$i] -= 0.005 * $LR * $theta[$i];   # light weight decay
	}
	opendir(my $dh, "ai/train"); unlink map { "ai/train/$_" } grep { /^g${g}k\d+[pn]\.json$/ } readdir($dh); closedir $dh;
	# Periodic clean evaluation of the unperturbed weights.
	my $eval = "";
	if ($g % $EVAL_EVERY == 0) {
		my ($efile, $eres) = res_path("eval.json");
		weights_file($efile, \@theta);
		# Same EVAL_GAMES seeds every time, so evaluations are comparable.
		my @ej = map { ["rle${g}_$_", $eres, ($_ % 2) + 1, "eval$_"] } 1 .. $EVAL_GAMES;
		my $ef = play(0, @ej);
		my $w = 0; $w += $ef->{"win_$_->[0]"} // 0 for @ej;
		$eval = sprintf "%.2f", $w / @ej;
		# Keep the best-evaluated network: that's the one the game ships with
		# (ai/commander.json); the latest weights are ai/commander_latest.json.
		my $prev = -e "$RL/best.json" ? decode_json(slurp("$RL/best.json")) : {eval => -1};
		if ($w / @ej >= $prev->{eval}) {
			spit("$RL/best.json", $json->encode({gen => $g, eval => $w / @ej}));
			weights_file("ai/commander.json", \@theta);
		}
	}
	my $mf = 0; $mf += $mean{$_} for keys %mean; $mf /= scalar keys %mean;
	my $best = $mean{$sorted[-1]};
	printf "gen %3d  mean fitness %+.3f  best %+.3f  candidate win rate %.2f  %s  (%ds)\n", $g, $mf, $best, $wins / $games, ($eval ne "" ? "EVAL win rate $eval" : ""), time - $t0;
	printf $LOG "%d,%.4f,%.3f,%.4f,%s,%d\n", $g, $mf, $wins / $games, $best, $eval, time - $t0;
	$LOG->flush;
	spit("$RL/theta.json", $json->encode({gen => $g, weights => \@theta, m => \@m, v => \@v}));
	weights_file("ai/commander_latest.json", \@theta);
}
close $LOG;
