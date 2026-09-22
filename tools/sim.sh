#!/bin/sh
# AI-vs-AI balance batch: tools/sim.sh [runs per system] [max minutes] [label] [parallel jobs]
# Runs every named system headless and fast, JOBS matches at a time (default
# 8; each match uses about one CPU core), then prints the summary report.
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
RUNS="${1:-6}"
MINUTES="${2:-40}"
LABEL="${3:-b}"
JOBS="${4:-8}"
cd "$(dirname "$0")/.."
export G MINUTES
for sys in orion_reach vega_drift kharon_expanse tethys_cluster sable_verge; do
	for i in $(seq 1 "$RUNS"); do
		echo "$sys ${LABEL}$i"
	done
done | xargs -P "$JOBS" -L 1 sh -c 'SL_SIM="$1" SL_SIM_MINUTES="$MINUTES" SL_SYSTEM="$0" timeout 900 "$G" --headless --path . --fixed-fps 60 res://scenes/Main.tscn 2>&1 | grep "SIM RESULT\|SCRIPT ERROR"'
perl tools/sim_report.pl "$LABEL"
