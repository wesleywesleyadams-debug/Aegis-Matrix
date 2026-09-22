#!/bin/sh
# Progress of a balance batch: tools/sim_progress.sh [label] [total]
# Counts finished matches (one JSON each) and lists them per system.
LABEL="${1:-d}"
TOTAL="${2:-30}"
S="$APPDATA/Godot/app_userdata/Star Lords/sims"
DONE=$(ls "$S" 2>/dev/null | grep -c "_${LABEL}[0-9]*\.json")
echo "batch $LABEL: $DONE / $TOTAL matches done"
ls "$S" 2>/dev/null | grep "_${LABEL}[0-9]*\.json" | sed "s/_${LABEL}[0-9]*\.json//" | sort | uniq -c
