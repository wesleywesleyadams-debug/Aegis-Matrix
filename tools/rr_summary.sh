#!/bin/bash
# Round-robin summary: tools/rr_summary.sh RUN_ID [NAME]
# Downloads the run's artifacts and prints, per side and per class, the win
# rate (win 1, draw 0.5) and the weight: average margin, i.e. the winner's
# toughness left in %, positive for the side's wins and negative for its losses.
# A draw (time out or mutual wipe) scores the difference in toughness left.
R=wesleywesleyadams-debug/Aegis-Matrix
D="${TMPDIR:-/tmp}/rr_${2:-$1}"
rm -rf "$D"; gh run download "$1" -R $R -D "$D" >/dev/null 2>&1
cat "$D"/result-*/* | grep -h "DUEL " | sed 's/^\[[^]]*\] //' > "$D.txt"
echo "$(wc -l < "$D.txt") duels"
awk '{a=$2; b=$5; if ($0 ~ / wins /){x=$0; sub(/.*: /,"",x); split(x,y," "); win=y[1]; sa=(win==a)?1:0; t=$0; sub(/% of their toughness.*/,"",t); sub(/.* /,"",t); m=t/100.0; ma=(win==a)?m:-m} else {sa=0.5; n=split($0,dq,"|"); pa=dq[2]; pb=dq[3]; sub(/% toughness.*/,"",pa); sub(/.* /,"",pa); sub(/% toughness.*/,"",pb); sub(/.* /,"",pb); ma=(pa-pb)/100.0}
	S[a]+=sa; S[b]+=1-sa; M[a]+=ma; M[b]-=ma; N[a]++; N[b]++}
	END{for(k in S){split(k,cc,":"); C[cc[1]]+=S[k]; CM[cc[1]]+=M[k]; CN[cc[1]]+=N[k]; printf "%5.1f%%  weight %+5.2f  %s\n", 100*S[k]/N[k], M[k]/N[k], k}
	for(q in C) printf "CLASS %5.1f%%  weight %+5.2f  %s\n", 100*C[q]/CN[q], CM[q]/CN[q], q}' "$D.txt" | sort -rn
