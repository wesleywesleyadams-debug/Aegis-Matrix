#!/bin/sh
# AI-vs-AI balance batch: tools/sim.sh [runs per system] [max minutes] [label]
# Runs every named system headless (fast), then prints the summary report.
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
RUNS="${1:-6}"
MINUTES="${2:-40}"
LABEL="${3:-b}"
cd "$(dirname "$0")/.."
for sys in orion_reach vega_drift kharon_expanse tethys_cluster sable_verge; do
	for i in $(seq 1 "$RUNS"); do
		SL_SIM="${LABEL}$i" SL_SIM_MINUTES="$MINUTES" SL_SYSTEM="$sys" timeout 900 "$G" --headless --path . --fixed-fps 60 res://scenes/Main.tscn 2>&1 | grep "SIM RESULT\|SCRIPT ERROR"
	done
done
perl tools/sim_report.pl "$LABEL"
