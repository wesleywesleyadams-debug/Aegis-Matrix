extends SceneTree
## Headless sanity sweep for SystemGen: run with
##   godot --headless --path . --script res://tools/check_systems.gd
## Checks many seeds (plus the named systems) for keep-outs, overlaps,
## unique names and both sides getting identical resources.

func _init() -> void:
	var bad := 0
	var cases: Array = []
	for s in SystemGen.SYSTEMS:
		if s.has("seed"):
			cases.append([s["seed"], s["params"], s["name"]])
	for seed in range(1, 401):
		cases.append([seed, SystemGen.random_params(seed), "random %d" % seed])
	var tot_p := 0
	var tot_r := 0
	var min_p := 999
	for c in cases:
		var L := SystemGen.generate(c[0], c[1])
		var errs: Array = []
		var names := {}
		for p in L["planets"]:
			if names.has(p["name"]):
				errs.append("dup name " + p["name"])
			names[p["name"]] = true
			if p["pos"].length() < SystemGen.STAR_CLEAR:
				errs.append("planet near star")
			if not SystemGen._inside(p["pos"]):
				errs.append("planet outside")
			for q in L["planets"]:
				if q != p and p["pos"].distance_to(q["pos"]) < 110.0:
					errs.append("planets overlap %s/%s" % [p["name"], q["name"]])
		for a in L["asteroids"]:
			if a["pos"].length() < 260.0 or not SystemGen._inside(a["pos"]):
				errs.append("rock bad spot")
			for p in L["planets"]:
				if a["pos"].distance_to(p["pos"]) < 45.0:
					errs.append("rock on planet")
		# Fairness: each side's kinds/variants must match exactly.
		var sides := [{}, {}]
		for p in L["planets"]:
			var k: String = p["kind"]
			var sd := 0 if p["pos"].x < 0 else 1
			sides[sd][k] = sides[sd].get(k, 0) + 1
		for a in L["asteroids"]:
			var sd := 0 if a["pos"].x < 0 else 1
			sides[sd][a["variant"]] = sides[sd].get(a["variant"], 0) + 1
		if sides[0] != sides[1]:
			errs.append("unfair " + str(sides))
		if L["starbases"].size() != 2:
			errs.append("starbases")
		tot_p += L["planets"].size()
		tot_r += L["asteroids"].size()
		min_p = mini(min_p, L["planets"].size())
		if not errs.is_empty():
			bad += 1
			if bad <= 10:
				print("FAIL ", c[2], ": ", errs.slice(0, 3))
		if c[2].begins_with("random") == false:
			print("%-16s planets %2d rocks %3d" % [c[2], L["planets"].size(), L["asteroids"].size()])
	print("checked %d systems, %d failed; avg planets %.1f (min %d), avg rocks %.1f" % [cases.size(), bad, float(tot_p) / cases.size(), min_p, float(tot_r) / cases.size()])
	quit()
