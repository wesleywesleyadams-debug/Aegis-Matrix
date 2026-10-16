#!/bin/bash
# Mark balance check: Mk N+1 of a class against Mk N of the next class up,
# at equal total cost (research included). The goal is close to a tie.
printf '%s\n' "destroyer:1,corvette:2" "cruiser:1,destroyer:2" "carrier:1,cruiser:2" \
  "destroyer:2,corvette:3" "cruiser:2,destroyer:3" "carrier:2,cruiser:3" \
  "destroyer:3,corvette:4" "cruiser:3,destroyer:4" "carrier:3,cruiser:4" | bash "$(dirname "$0")/duel_run.sh"
