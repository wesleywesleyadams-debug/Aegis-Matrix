#!/bin/sh
# AI-vs-AI balance batch: tools/sim.sh [runs per system] [max minutes] [label] [parallel jobs]
# Runs every named system (or those in $SYSTEMS) headless and fast, JOBS
# matches at a time (default 5: one per physical core, one core left free), prints
# "[done / total]" as matches finish, then the summary report.
# Check a batch running elsewhere with: tools/sim_progress.sh <label> <total>
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
RUNS="${1:-6}"
MINUTES="${2:-45}"
LABEL="${3:-b}"
JOBS="${4:-5}"
cd "$(dirname "$0")/.."
SYS_LIST="${SYSTEMS:-orion_reach vega_drift kharon_expanse tethys_cluster sable_verge}"
TOTAL=$(($(echo $SYS_LIST | wc -w) * RUNS))
export G MINUTES LABEL TOTAL
for sys in $SYS_LIST; do
	for i in $(seq 1 "$RUNS"); do
		echo "$sys ${LABEL}$i"
	done
done | xargs -P "$JOBS" -L 1 sh -c '
	SL_SIM="$1" SL_SIM_MINUTES="$MINUTES" SL_SYSTEM="$0" timeout 2400 "$G" --headless --path . --fixed-fps 60 res://scenes/Main.tscn 2>&1 | grep "SIM RESULT\|SCRIPT ERROR"
	n=$(ls "$APPDATA/Godot/app_userdata/Star Lords/sims" | grep -c "_${LABEL}[0-9]*\.json")
	echo "[$n / $TOTAL done]"
'
n=$(ls "$APPDATA/Godot/app_userdata/Star Lords/sims" | grep -c "_${LABEL}[0-9]*.json")
[ "$n" -lt "$TOTAL" ] && echo "WARNING: only $n of $TOTAL matches finished (the rest hit the 40-minute real-time limit)"
perl tools/sim_report.pl "$LABEL"
