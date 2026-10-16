#!/bin/bash
# One queue of AI-vs-AI games, run wherever there is room: up to LOCAL_SLOTS
# at once on this machine, and the rest as single-game GitHub Actions runs
# (Balance tests, mode=single) while fewer than GH_SLOTS are in flight. Every
# game's log lands in OUT, and a win tally is printed at the end.
#
#   bash tools/dispatch.sh [games per system]       (default 4 -> 20 games)
#
# Env: LOCAL_SLOTS (12), GH_SLOTS (20, 0 = local only), MINUTES (45),
# SPEED (4), OUT (sim_results/<batch>), SYSTEMS (the five fixed systems).
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
GH="${GH:-/c/Program Files/GitHub CLI/gh.exe}"
RUNS=${1:-4}
LOCAL_SLOTS=${LOCAL_SLOTS:-12}
GH_SLOTS=${GH_SLOTS:-20}
MINUTES=${MINUTES:-45}
SPEED=${SPEED:-4}
SYSTEMS=${SYSTEMS:-"orion_reach vega_drift kharon_expanse tethys_cluster sable_verge"}
BATCH=$(date +%s)
OUT=${OUT:-sim_results/$BATCH}
mkdir -p "$OUT"

queue=()
for s in $SYSTEMS; do for r in $(seq 1 "$RUNS"); do queue+=("$s $r"); done; done
total=${#queue[@]}
declare -A gh_tags    # tag -> 1 while in flight
local_n=0 gh_n=0

# Wrapped so a cancelled or failed GitHub run never stalls the loop.
gh_active() {
	"$GH" run list --workflow=balance.yml --limit 100 --json displayTitle,status,databaseId \
		-q ".[] | select(.displayTitle | contains(\"$BATCH-\")) | \"\(.status) \(.databaseId) \(.displayTitle)\"" 2>/dev/null
}

echo "batch $BATCH: $total games -> $OUT"
last_poll=0
while :; do
	running_local=$(jobs -rp | wc -l)
	# Collect GitHub runs that have finished.
	if [ ${#gh_tags[@]} -gt 0 ] && [ $(( $(date +%s) - last_poll )) -ge 20 ]; then
		last_poll=$(date +%s)
		while read -r status id title; do
			tag=${title##* }
			[ -n "${gh_tags[$tag]}" ] || continue
			if [ "$status" = "completed" ]; then
				"$GH" run download "$id" -n all-results -D "$OUT/gh_$tag" >/dev/null 2>&1 || echo "  ! no results from GitHub run $id ($tag)"
				unset "gh_tags[$tag]"
			fi
		done < <(gh_active)
	fi
	if [ ${#queue[@]} -gt 0 ]; then
		set -- ${queue[0]}
		sys=$1 run=$2 tag="$BATCH-$1-$2"
		if [ "$running_local" -lt "$LOCAL_SLOTS" ]; then
			queue=("${queue[@]:1}")
			local_n=$((local_n + 1))
			( SL_SYSTEM=$sys SL_SIM=d_$run SL_SEED=$tag SL_SIM_MINUTES=$MINUTES SL_SIM_SCALE=$SPEED \
				timeout 3000 "$G" --headless --fixed-fps 60 --path . scenes/Main.tscn > "$OUT/local_${sys}_$run.log" 2>&1 ) &
			continue
		elif [ ${#gh_tags[@]} -lt "$GH_SLOTS" ]; then
			if "$GH" workflow run balance.yml -f mode=single -f system="$sys" -f tag="$tag" \
					-f minutes="$MINUTES" -f speed="$SPEED" >/dev/null 2>&1; then
				queue=("${queue[@]:1}")
				gh_tags[$tag]=1
				gh_n=$((gh_n + 1))
				continue
			fi
		fi
	elif [ "$running_local" -eq 0 ] && [ ${#gh_tags[@]} -eq 0 ]; then
		break
	fi
	sleep 5
done

echo "done: $local_n local, $gh_n on GitHub"
res=$(grep -rh "SIM RESULT" "$OUT" 2>/dev/null)
echo "$res" | sort
echo "P1 wins: $(echo "$res" | grep -c 'winner=1')  P2 wins: $(echo "$res" | grep -c 'winner=2')  draws: $(echo "$res" | grep -c 'winner=0')  results: $(echo "$res" | grep -c 'SIM RESULT')/$total"
echo "script errors:"; grep -rh "SCRIPT ERROR" "$OUT" 2>/dev/null | sort | uniq -c | sort -rn | head
