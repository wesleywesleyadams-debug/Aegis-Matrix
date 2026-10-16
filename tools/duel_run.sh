#!/bin/bash
# Runs SL_DUEL fights in parallel (each is its own Godot process, so results
# are the same as running them one by one). Reads "matchup" lines on stdin,
# runs each at two map spots, prints the results sorted by matchup.
# Env: BUDGET (default 6725, the medium-budget baseline), JOBS (default 6), LIMIT (default 900 s).
cd "$(dirname "$0")/.."
export G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
export BUDGET=${BUDGET:-6725} LIMIT=${LIMIT:-900}
while read -r m; do [ -n "$m" ] && for x in -900 600; do echo "$m $x"; done; done |
  xargs -P "${JOBS:-6}" -L 1 bash -c 'SL_DUEL_LIMIT=$LIMIT SL_DUEL_BUDGET=$BUDGET SL_DUEL=$0 SL_DUEL_X=$1 SL_NOFOG=1 timeout 950 "$G" --headless --path . scenes/Main.tscn 2>&1 | grep -E "^DUEL |SCRIPT ERROR" | sort -u | head -1' |
  sort
