#!/bin/bash
# Runs the combat-balance grid (every matchup on the balance chart) with the
# SL_DUEL harness: equal mineral cost per side, two map spots each.
# Usage: bash tools/duel_grid.sh [mark]   (default 1: Mk N vs Mk N and Mk N vs Mk N+1)
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
N=${1:-1}; M=$((N+1))
for m in "carrier:$N,corvette:$N" "carrier:$N,cruiser:$N" "cruiser:$N,destroyer:$N" "destroyer:$N,corvette:$N" \
         "corvette:$N,cruiser:$N" "destroyer:$N,carrier:$N" \
         "cruiser:$N,destroyer:$M" "destroyer:$N,corvette:$M" "carrier:$N,cruiser:$M"; do
  for x in -900 600; do
    SL_DUEL_BUDGET=${BUDGET:-3500} SL_DUEL=$m SL_DUEL_X=$x SL_NOFOG=1 timeout 300 "$G" --headless --path . scenes/Main.tscn 2>&1 | grep -E "^DUEL|SCRIPT ERROR" | sort -u | head -1
  done
done
