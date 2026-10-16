#!/bin/bash
# Mark balance check: Mk N+1 of a class against Mk N of the next class up,
# at equal total cost (research included). The goal is close to a tie.
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
for m in "destroyer:1,corvette:2" "cruiser:1,destroyer:2" "carrier:1,cruiser:2" \
         "destroyer:2,corvette:3" "cruiser:2,destroyer:3" "carrier:3,cruiser:4"; do
  for x in -900 600; do
    SL_DUEL_LIMIT=900 SL_DUEL_BUDGET=${BUDGET:-4300} SL_DUEL=$m SL_DUEL_X=$x SL_NOFOG=1 timeout 950 "$G" --headless --path . scenes/Main.tscn 2>&1 | grep -E "^DUEL |SCRIPT ERROR" | sort -u | head -1
  done
done
