class_name SaveGame
## Match save/load. capture() turns a running match into a JSON-safe
## Dictionary; apply() rebuilds a freshly loaded Main scene from one.
## Planets and asteroids are matched by node name (they're hand-placed in
## Main.tscn); ships and starbases are respawned from the save.
##
## Saves live in GameState.saves_dir() as save_<unix time>.json and carry a
## "mode" (single / multi / campaign) that the Load Game screen sorts by.

const VERSION := 1

static func _v(p: Vector2) -> Array:
	return [p.x, p.y]

static func _p(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() == 2 else Vector2.ZERO

# ---------------------------------------------------------------- capture

static func capture(game: Game, save_name: String) -> Dictionary:
	var tree := game.get_tree()
	var data := {
		"version": VERSION,
		"name": save_name,
		"mode": GameState.game_mode,
		"system": GameState.system_id,
		"system_seed": GameState.system_seed,
		"timestamp": Time.get_unix_time_from_system(),
		"clock": Game.now(),
		"player_id": game.player_id,
		"players": game.players,
		"teams": game.teams,
		"slots": Defs.slot_of,
		"resources": game.resources,
		"researched": {},
		"research": game.research,
		"research_queue": game.research_queue,
		"research_paused": game.research_paused,
		"blackout": game.blackout,
		"blackout_time": game.blackout_time,
		"blackout_restore": game.blackout_restore,
		"mods_disabled": game.mods_disabled,
		"ai": game.ai._state.duplicate(true),
		"planets": {},
		"asteroids": {},
		"starbases": [],
		"depots": [],
		"forts": [],
		"stations": [],
		"ships": [],
		"camera": _v(game.camera.global_position),
	}
	# Fog of war: what the player has explored and last saw.
	if game.vision:
		data["fog"] = game.vision.export_state()
	for pid in game.researched:
		data["researched"][str(pid)] = game.researched[pid].keys()
	# AI claimer lists hold node refs; they're rebuilt as the AI thinks.
	for pid in data["ai"]:
		data["ai"][pid].erase("claimers")
		# The network isn't saved; it's reloaded from its weights file.
		data["ai"][pid].erase("nn")
	for p in tree.get_nodes_in_group("planets"):
		data["planets"][p.name] = {
			"owner": p.owner_id, "pop": p.pop, "buildings": Array(p.buildings),
			"construction": p.construction, "construction_queue": p.construction_queue,
			"amount": p.amount, "mineral_reserve": p.mineral_reserve, "max_mineral_reserve": p.max_mineral_reserve, "mining_paused": p.mining_paused, "doom_timer": p.doom_timer,
					"hungry": p.hungry, "fed_timer": p.fed_timer,
			"siege_start_pop": p.siege_start_pop, "since_hit": Game.now() - p.last_hit_time, "shield": p.shield, "spice_reserve": p.spice_reserve, "max_spice_reserve": p.max_spice_reserve,
		}
	# Gas giants that exploded and worlds that imploded are gone for good.
	data["removed_planets"] = Array(game.removed_planets)
	# Spice nebulae: what is left in every harvested cell, in group order (the
	# system builds them in the same order every time).
	data["nebulae"] = []
	for n in tree.get_nodes_in_group("nebulae"):
		data["nebulae"].append(n.export_cells() if n is SpiceNebula else {})
	for a in tree.get_nodes_in_group("asteroids"):
		if not a.is_queued_for_deletion():
			data["asteroids"][a.name] = a.amount
	for sb in tree.get_nodes_in_group("starbases"):
		if not sb.is_alive():
			continue
		data["starbases"].append({
			"owner": sb.owner_id, "pos": _v(sb.global_position), "hp": sb.hp, "shield": sb.shield, "armor": sb.armor,
			"queue": Array(sb.queue), "build_progress": sb.build_progress,
			"rally": _v(sb.rally_point), "has_rally": sb.has_rally,
			"under_construction": sb.under_construction, "construct_progress": sb.construct_progress,
			"seen": sb.get_meta("seen", false),
		})
	for dp in tree.get_nodes_in_group("depots"):
		if dp.is_alive():
			data["depots"].append({"owner": dp.owner_id, "pos": _v(dp.global_position), "hp": dp.hp, "armor": dp.armor, "shield": dp.shield,
				"under_construction": dp.under_construction, "construct_progress": dp.construct_progress, "seen": dp.get_meta("seen", false), "variant": dp.variant})
	for f in tree.get_nodes_in_group("forts"):
		if f.is_alive():
			data["forts"].append({"kind": "gate" if f is WarpGate else "outpost", "owner": f.owner_id, "pos": _v(f.global_position),
				"hp": f.hp, "armor": f.armor, "shield": f.shield, "under_construction": f.under_construction,
				"construct_progress": f.construct_progress, "seen": f.get_meta("seen", false),
				"cooldown": f.cooldown_left if f is WarpGate else 0.0})
	for st in tree.get_nodes_in_group("mining_stations"):
		if st.is_alive():
			data["stations"].append({"owner": st.owner_id, "pos": _v(st.global_position), "hp": st.hp, "armor": st.armor, "shield": st.shield,
				"under_construction": st.under_construction, "construct_progress": st.construct_progress, "seen": st.get_meta("seen", false)})
	for s in tree.get_nodes_in_group("ships"):
		if not s.is_alive():
			continue
		data["ships"].append({
			"type": s.ship_type, "owner": s.owner_id, "pos": _v(s.global_position), "rot": s.rotation,
			"hp": s.hp, "shield": s.shield, "armor": s.armor, "cargo": s.cargo, "cargo_type": s.cargo_type,
			"held": s.held, "engagement": int(s.engagement), "stance": int(s.stance),
			"docked": s.docked and not is_instance_valid(s.warp_gate), "docked_variant": s.refit_depot.variant if s.docked and is_instance_valid(s.refit_depot) else "",
			# Inside a Warp Gate (rebuilt at load), or mid-warp to a point.
			"garrisoned": s.docked and is_instance_valid(s.warp_gate),
			"warp_to": _v(s.warp_target) if s.warping else null,
			"refit_left": s.refit_left,
			"drones": s.drone_count(),
			"order": _order_of(s),
			"queue": s.order_queue.map(func(o): return _queued_dict(o)).filter(func(d): return not d.is_empty()),
		})
	return data

## One shift-queued order, in the same vocabulary as _order_of. Legs whose
## target cannot be named (a specific enemy ship) are dropped.
static func _queued_dict(o: Array) -> Dictionary:
	var m: String = o[0]
	var a: Array = o[1]
	match m:
		"order_move":
			return {"kind": "move", "at": _v(a[0])}
		"order_attack_move":
			return {"kind": "attack_move", "at": _v(a[0])}
		"order_return":
			return {"kind": "return"}
		"order_mine":
			return {"kind": "mine", "target": String(a[0].name)} if typeof(a[0]) == TYPE_OBJECT and is_instance_valid(a[0]) else {}
		"order_colonize":
			return {"kind": "colonize", "target": String(a[0].name)} if typeof(a[0]) == TYPE_OBJECT and is_instance_valid(a[0]) else {}
		"order_bombard":
			return {"kind": "bombard", "target": String(a[0].name)} if typeof(a[0]) == TYPE_OBJECT and is_instance_valid(a[0]) else {}
		"order_refit":
			return {"kind": "refit", "variant": str(a[0])}
	return {}

## Turns a saved leg back into [method, args]; [] when its target is gone.
static func _queued_entry(o: Dictionary, rocks: Dictionary, planets: Dictionary) -> Array:
	match str(o.get("kind", "")):
		"move":
			return ["order_move", [_p(o["at"])]]
		"attack_move":
			return ["order_attack_move", [_p(o["at"])]]
		"return":
			return ["order_return", []]
		"mine":
			var t = rocks.get(o.get("target", ""), planets.get(o.get("target", "")))
			return ["order_mine", [t]] if t else []
		"colonize":
			return ["order_colonize", [planets[o["target"]]]] if planets.has(o.get("target", "")) else []
		"bombard":
			return ["order_bombard", [planets[o["target"]]]] if planets.has(o.get("target", "")) else []
		"refit":
			return ["order_refit", [str(o.get("variant", "plasma"))]]
	return []

## What a ship was doing, in a form that survives a reload.
static func _order_of(s: Ship) -> Dictionary:
	match s.state:
		Ship.State.MOVE:
			return {"kind": "move", "at": _v(s.move_goal)}
		Ship.State.ATTACK_MOVE, Ship.State.ATTACK:
			return {"kind": "attack_move", "at": _v(s.attack_move_goal)}
		Ship.State.MINE_GO, Ship.State.MINING, Ship.State.RETURN:
			if is_instance_valid(s.mine_target):
				return {"kind": "mine", "target": String(s.mine_target.name)}
			return {"kind": "return"}
		Ship.State.COLONIZE:
			if is_instance_valid(s.colonize_target):
				return {"kind": "colonize", "target": String(s.colonize_target.name)}
		Ship.State.BUILD:
			return {"kind": "build", "at": _v(s.build_site), "what": s.build_kind}
		Ship.State.REFIT:
			return {"kind": "refit", "variant": s.refit_variant, "left": s.refit_left}
		Ship.State.BOMBARD:
			if is_instance_valid(s.bombard_target):
				return {"kind": "bombard", "target": String(s.bombard_target.name)}
	return {"kind": "idle"}

static func write(game: Game, save_name: String) -> String:
	var dir := GameState.saves_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/save_%d.json" % [dir, int(Time.get_unix_time_from_system())]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(capture(game, save_name), "\t"))
	f.close()
	return path

# ---------------------------------------------------------------- apply

static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

## Rebuilds the match from `data`. Call from Game._ready before the AI and
## starting orders run. Returns false if the save couldn't be used.
static func apply(game: Game, data: Dictionary) -> bool:
	if data.is_empty() or not data.has("planets"):
		return false
	var tree := game.get_tree()
	Game._clock = float(data.get("clock", 0.0))
	game.player_id = int(data.get("player_id", game.player_id))
	for pid_s in data.get("resources", {}):
		var pid := int(pid_s)
		for k in data["resources"][pid_s]:
			game.resources[pid][k] = float(data["resources"][pid_s][k])
	game.blackout = {}
	for pid_s in data.get("blackout", {}):
		game.blackout[int(pid_s)] = bool(data["blackout"][pid_s])
	game.blackout_time = {}
	for pid_s in data.get("blackout_time", {}):
		game.blackout_time[int(pid_s)] = float(data["blackout_time"][pid_s])
	game.blackout_restore = {}
	for pid_s in data.get("blackout_restore", {}):
		game.blackout_restore[int(pid_s)] = float(data["blackout_restore"][pid_s])
	for pid_s in data.get("researched", {}):
		var done := {}
		for t in data["researched"][pid_s]:
			if Defs.TECHS.has(t):
				done[t] = true
		game.researched[int(pid_s)] = done
	for pid_s in data.get("research", {}):
		var r: Dictionary = data["research"][pid_s]
		game.research[int(pid_s)] = r if r.is_empty() or Defs.TECHS.has(r.get("id", "")) else {}
	for pid_s in data.get("mods_disabled", {}):
		var off := {}
		for t in data["mods_disabled"][pid_s]:
			if Defs.TECHS.has(t):
				off[t] = true
		game.mods_disabled[int(pid_s)] = off
	for pid_s in data.get("research_paused", {}):
		var kept := {}
		for t in data["research_paused"][pid_s]:
			if Defs.TECHS.has(t):
				kept[t] = float(data["research_paused"][pid_s][t])
		game.research_paused[int(pid_s)] = kept
	for pid_s in data.get("research_queue", {}):
		game.research_queue[int(pid_s)] = Array(data["research_queue"][pid_s]).filter(func(t): return Defs.TECHS.has(t))
	for pid_s in data.get("ai", {}):
		var st: Dictionary = data["ai"][pid_s]
		st["claimers"] = []
		game.ai.saved_state[int(pid_s)] = st

	# Planets and asteroids: update in place by node name.
	var planets := {}
	# Bodies destroyed before the save: off the map again.
	game.removed_planets.clear()
	for nm in data.get("removed_planets", []):
		for p0 in tree.get_nodes_in_group("planets"):
			if String(p0.name) == str(nm):
				p0._gone = true
				p0.remove_from_group("planets")
				p0.queue_free()
		game.removed_planets.append(str(nm))
	for p in tree.get_nodes_in_group("planets"):
		planets[String(p.name)] = p
		var d: Dictionary = data["planets"].get(String(p.name), {})
		if d.is_empty():
			continue
		p.owner_id = int(d["owner"])
		p.pop = float(d["pop"])
		for i in p.fields:
			p.buildings[i] = str(d["buildings"][i]) if i < d["buildings"].size() else ""
		var c: Dictionary = d.get("construction", {})
		p.construction = {} if c.is_empty() else {"field": int(c["field"]), "id": str(c["id"]), "progress": float(c["progress"])}
		p.construction_queue = []
		for j in d.get("construction_queue", []):
			p.construction_queue.append({"field": int(j["field"]), "id": str(j["id"])})
		p.amount = int(d.get("amount", p.amount))
		p.update_gas_size()
		p.mineral_reserve = float(d.get("mineral_reserve", p.mineral_reserve))
		p.max_mineral_reserve = float(d.get("max_mineral_reserve", p.max_mineral_reserve))
		p.mining_paused = bool(d.get("mining_paused", false))
		p.doom_timer = float(d.get("doom_timer", -1.0))
		# Already unstable when saved: no second warning.
		p._warned = p.unstable()
		p.hungry = float(d.get("hungry", 0.0))
		p.fed_timer = float(d.get("fed_timer", Defs.REGROW_SECONDS))
		p.siege_start_pop = float(d.get("siege_start_pop", 0.0))
		p.shield = float(d.get("shield", p.max_shield()))
		p.spice_reserve = float(d.get("spice_reserve", p.spice_reserve))
		p.max_spice_reserve = float(d.get("max_spice_reserve", p.max_spice_reserve))
		p.last_hit_time = Game.now() - float(d.get("since_hit", 1000.0))
		p.queue_redraw()
	var nebs: Array = tree.get_nodes_in_group("nebulae")
	var saved_nebs: Array = data.get("nebulae", [])
	for i in mini(nebs.size(), saved_nebs.size()):
		if nebs[i] is SpiceNebula:
			nebs[i].import_cells(saved_nebs[i])
	var rocks := {}
	for a in tree.get_nodes_in_group("asteroids"):
		var key := String(a.name)
		if data["asteroids"].has(key):
			a.amount = int(data["asteroids"][key])
			rocks[key] = a
		else:
			# Mined out before the save.
			a.remove_from_group("asteroids")
			a.queue_free()

	# Replace the scene's starting ships and starbases with the saved ones.
	for n in tree.get_nodes_in_group("ships") + tree.get_nodes_in_group("starbases") + tree.get_nodes_in_group("mining_stations") + tree.get_nodes_in_group("forts"):
		n.remove_from_group("ships")
		n.remove_from_group("starbases")
		n.remove_from_group("mining_stations")
		n.remove_from_group("forts")
		n.remove_from_group("entities")
		n.get_parent().remove_child(n)
		n.free()
	for d in data.get("starbases", []):
		var sb: Starbase = Game.STARBASE_SCENE.instantiate()
		sb.owner_id = int(d["owner"])
		sb.under_construction = bool(d.get("under_construction", false))
		sb.position = _p(d["pos"])
		game.starbases_root.add_child(sb)
		sb.construct_progress = float(d.get("construct_progress", 0.0))
		sb.hp = float(d["hp"])
		sb.armor = float(d.get("armor", sb.max_armor))
		sb.shield = float(d["shield"])
		for t in d.get("queue", []):
			if Defs.SHIPS.has(t):
				sb.queue.append(t)
		sb.build_progress = float(d.get("build_progress", 0.0))
		sb.rally_point = _p(d.get("rally", [0, 0]))
		sb.has_rally = bool(d.get("has_rally", false))
		sb.set_meta("seen", bool(d.get("seen", false)))
	for d in data.get("depots", []):
		var dp := WeaponsDepot.new()
		dp.owner_id = int(d["owner"])
		dp.under_construction = bool(d.get("under_construction", false))
		dp.variant = str(d.get("variant", "plasma"))
		dp.construct_progress = float(d.get("construct_progress", 0.0))
		dp.position = _p(d["pos"])
		game.starbases_root.add_child(dp)
		dp.hp = float(d["hp"])
		dp.armor = float(d.get("armor", 0.0))
		dp.shield = float(d.get("shield", 0.0))
		dp.set_meta("seen", bool(d.get("seen", false)))
	for d in data.get("forts", []):
		var f: FortConstruct = WarpGate.new() if str(d.get("kind", "outpost")) == "gate" else FrontierOutpost.new()
		f.owner_id = int(d["owner"])
		f.under_construction = bool(d.get("under_construction", false))
		f.position = _p(d["pos"])
		game.starbases_root.add_child(f)
		f.construct_progress = float(d.get("construct_progress", 0.0))
		f.hp = float(d["hp"])
		f.armor = float(d.get("armor", 0.0))
		f.shield = float(d.get("shield", 0.0))
		if f is WarpGate:
			f.cooldown_left = float(d.get("cooldown", 0.0))
		f.set_meta("seen", bool(d.get("seen", false)))
	for d in data.get("stations", []):
		var st := MiningStation.new()
		st.owner_id = int(d["owner"])
		st.under_construction = bool(d.get("under_construction", false))
		st.construct_progress = float(d.get("construct_progress", 0.0))
		st.position = _p(d["pos"])
		game.starbases_root.add_child(st)
		st.hp = float(d["hp"])
		st.armor = float(d.get("armor", 0.0))
		st.shield = float(d.get("shield", 0.0))
		st.set_meta("seen", bool(d.get("seen", false)))
	for d in data.get("ships", []):
		if not Defs.SHIPS.has(d["type"]):
			continue
		var s := game.spawn_ship(str(d["type"]), int(d["owner"]), _p(d["pos"]))
		s.rotation = float(d.get("rot", 0.0))
		s.hp = float(d["hp"])
		s.armor = float(d.get("armor", s.max_armor))
		s.shield = float(d["shield"])
		s.cargo = int(d.get("cargo", 0))
		s.cargo_type = str(d.get("cargo_type", "minerals"))
		s.drones_saved = int(d.get("drones", 0))
		s.set_engagement(int(d.get("engagement", 0)))
		s.set_stance(int(d.get("stance", 0)))
		# After the order below, which would otherwise release the hold.
		var was_held: bool = bool(d.get("held", false))
		var o: Dictionary = d.get("order", {})
		match o.get("kind", "idle"):
			"move": s.order_move(_p(o["at"]))
			"attack_move": s.order_attack_move(_p(o["at"]))
			"mine":
				var t = rocks.get(o["target"], planets.get(o["target"]))
				if t:
					s.order_mine(t)
				elif s.cargo > 0:
					s.order_return()
			"return": s.order_return()
			"colonize":
				if planets.has(o["target"]):
					s.order_colonize(planets[o["target"]])
			"build":
				if o.get("what", "starbase") == "depot":
					s.order_build_depot(_p(o["at"]))
				elif o.get("what", "") == "station":
					s.order_build_station(_p(o["at"]))
				elif o.get("what", "") in ["outpost", "gate"]:
					s.order_build_fort(_p(o["at"]), str(o["what"]))
				else:
					s.order_build_starbase(_p(o["at"]))
			"refit":
				s.order_refit(str(o["variant"]))
				s.refit_left = float(o.get("left", s.refit_left))
			"bombard":
				if planets.has(o["target"]):
					s.order_bombard(planets[o["target"]])
		s.held = was_held
		# Shift-queued legs behind the current order.
		for q in d.get("queue", []):
			var entry := _queued_entry(q, rocks, planets)
			if not entry.is_empty():
				s.order_queue.append(entry)
	# Ships that were inside a Warp Gate go back in; ships mid-warp fly on.
	for d in data.get("ships", []):
		var garrisoned := bool(d.get("garrisoned", false))
		if not garrisoned and d.get("warp_to") == null:
			continue
		for s3 in tree.get_nodes_in_group("ships"):
			if s3.owner_id != int(d["owner"]) or s3.ship_type != str(d["type"]) or s3.docked or s3.warping or s3.global_position.distance_to(_p(d["pos"])) >= 1.0:
				continue
			if garrisoned:
				var best: WarpGate = null
				for g in tree.get_nodes_in_group("forts"):
					if g is WarpGate and g.owner_id == s3.owner_id and (best == null or g.global_position.distance_to(s3.global_position) < best.global_position.distance_to(s3.global_position)):
						best = g
				if best:
					best.admit(s3)
			else:
				s3.warping = true
				s3.warp_target = _p(d["warp_to"])
			break
	# Ships that were inside a Weapons Depot go back in where they were.
	for d in data.get("ships", []):
		if not bool(d.get("docked", false)):
			continue
		var dep := game.nearest_depot(int(d["owner"]), _p(d["pos"]), str(d.get("docked_variant", "")))
		if dep == null:
			continue
		for s2 in tree.get_nodes_in_group("ships"):
			if s2.owner_id == int(d["owner"]) and s2.ship_type == str(d["type"]) and not s2.docked and s2.global_position.distance_to(_p(d["pos"])) < 1.0:
				dep.dock(s2)
				if not dep.bays.is_empty():
					dep.bays[-1]["left"] = float(d.get("refit_left", dep.bays[-1]["left"]))
				break
	for e in tree.get_nodes_in_group("entities"):
		if e.has_method("refresh_stats"):
			var hp: float = e.hp
			var sh: float = e.shield
			var ar: float = e.armor
			e.refresh_stats()
			e.hp = minf(hp, e.max_hp)
			e.shield = minf(sh, e.max_shield)
			e.armor = minf(ar, e.max_armor)
	game.center_on(_p(data.get("camera", [0, 0])))
	return true
