#!/bin/bash
# Size-ladder balance check: every bigger class against every smaller one at
# equal mineral cost (the bigger should win clearly). Usage: bash tools/size_grid.sh [mark]
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
N=${1:-1}
for m in "destroyer:$N,corvette:$N" "cruiser:$N,destroyer:$N" "carrier:$N,cruiser:$N" \
         "cruiser:$N,corvette:$N" "carrier:$N,destroyer:$N" "carrier:$N,corvette:$N"; do
  for x in -900 600; do
    SL_DUEL_LIMIT=${LIMIT:-900} SL_DUEL_BUDGET=${BUDGET:-4300} SL_DUEL=$m SL_DUEL_X=$x SL_NOFOG=1 timeout 950 "$G" --headless --path . scenes/Main.tscn 2>&1 | grep -E "^DUEL |SCRIPT ERROR" | sort -u | head -1
  done
done
