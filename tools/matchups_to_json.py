"""Turn round-robin duel results into data/matchups.json for the Codex.

Usage: python tools/matchups_to_json.py DUELS.txt "label"
DUELS.txt holds the 'DUEL a (n) vs b (m): ...' lines of a full round robin
(tools/rr_all16*.txt). The Codex Combat page reads the JSON for its
class-vs-class and every-weapon-vs-every-weapon tables.
"""
import json, re, sys

ORDER = ["corvette:1", "corvette:1:mod_kinetic_repeaters", "corvette:1:mod_arc_emitters", "corvette:1:mod_proton_torpedoes",
	"destroyer:1", "destroyer:1:mod_flak_cannons", "destroyer:1:mod_cluster_bombs", "destroyer:1:mod_homing_missiles",
	"cruiser:1", "cruiser:1:mod_ion_lance", "cruiser:1:mod_rail_cannons", "cruiser:1:mod_point_defense_lattice",
	"carrier:1", "carrier:1:mod_interceptor_drones", "carrier:1:mod_tractor_beams", "carrier:1:mod_missile_barrage"]
# W: wins (draw = half). G: weight, from +1 (destroys the other without
# taking damage: the winner kept all its toughness) to -1 (destroyed
# without dealing any); a draw scores the difference in toughness left.
W, G, N = {}, {}, {}
n = 0
for line in open(sys.argv[1], encoding="utf-8"):
	m = re.match(r"DUEL (\S+) \(\d+\) vs (\S+) \(\d+\): (\S+) wins with .*?, (\d+)% of their toughness left", line)
	d = re.match(r"DUEL (\S+) \(\d+\) vs (\S+) \(\d+\): draw .*?\| \S+ \d+ ships, (\d+)% toughness \| \S+ \d+ ships, (\d+)% toughness", line)
	if m:
		a, b, w, left = m.groups()
		sa = 1.0 if w == a else 0.0
		ga = (1.0 if w == a else -1.0) * int(left) / 100.0
	elif d:
		a, b, ta, tb = d.groups()
		sa = 0.5
		ga = (int(ta) - int(tb)) / 100.0
	else:
		continue
	n += 1
	for x, y, v, g in ((a, b, sa, ga), (b, a, 1.0 - sa, -ga)):
		W[(x, y)] = W.get((x, y), 0.0) + v
		G[(x, y)] = G.get((x, y), 0.0) + g
		N[(x, y)] = N.get((x, y), 0) + 1
grid = [[-1 if i == j else round(100 * W.get((ORDER[i], ORDER[j]), 0) / max(N.get((ORDER[i], ORDER[j]), 1), 1)) for j in range(16)] for i in range(16)]
weights = [[None if i == j else round(G.get((ORDER[i], ORDER[j]), 0) / max(N.get((ORDER[i], ORDER[j]), 1), 1), 2) for j in range(16)] for i in range(16)]
cweights = []
for ci in range(4):
	row = []
	for cj in range(4):
		g = sum(G.get((ORDER[ci * 4 + a], ORDER[cj * 4 + b]), 0) for a in range(4) for b in range(4) if ci * 4 + a != cj * 4 + b)
		t = sum(N.get((ORDER[ci * 4 + a], ORDER[cj * 4 + b]), 0) for a in range(4) for b in range(4) if ci * 4 + a != cj * 4 + b)
		row.append(round(g / max(t, 1), 2))
	cweights.append(row)
classes = []
for ci in range(4):
	row = []
	for cj in range(4):
		w = sum(W.get((ORDER[ci * 4 + a], ORDER[cj * 4 + b]), 0) for a in range(4) for b in range(4) if ci * 4 + a != cj * 4 + b)
		t = sum(N.get((ORDER[ci * 4 + a], ORDER[cj * 4 + b]), 0) for a in range(4) for b in range(4) if ci * 4 + a != cj * 4 + b)
		row.append(round(100 * w / max(t, 1)))
	classes.append(row)
json.dump({"label": sys.argv[2] if len(sys.argv) > 2 else "", "duels": n, "per_pair": round(2 * n / (16 * 15)),
	"sides": ORDER, "grid": grid, "classes": classes, "weights": weights, "class_weights": cweights}, open("data/matchups.json", "w"), indent=1)
print("wrote data/matchups.json from", n, "duels")
