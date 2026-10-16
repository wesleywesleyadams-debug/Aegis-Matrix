#!/bin/bash
# Size-ladder balance check: every bigger class against every smaller one at
# equal mark and equal total cost (the bigger should win). Usage: bash tools/size_grid.sh [mark]
N=${1:-1}
printf '%s\n' "destroyer:$N,corvette:$N" "cruiser:$N,destroyer:$N" "carrier:$N,cruiser:$N" \
  "cruiser:$N,corvette:$N" "carrier:$N,destroyer:$N" "carrier:$N,corvette:$N" | bash "$(dirname "$0")/duel_run.sh"
