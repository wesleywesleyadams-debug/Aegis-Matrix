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
		"resources": game.resources,
		"researched": {},
		"research": game.research,
		"research_queue": game.research_queue,
		"ai": game.ai._state.duplicate(true),
		"planets": {},
		"asteroids": {},
		"starbases": [],
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
			"amount": p.amount, "depleted_timer": p.depleted_timer,
			"hungry": p.hungry, "starve_timer": p.starve_timer,
			"siege_start_pop": p.siege_start_pop, "since_hit": Game.now() - p.last_hit_time, "shield": p.shield, "spice_reserve": p.spice_reserve, "max_spice_reserve": p.max_spice_reserve,
		}
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
	for s in tree.get_nodes_in_group("ships"):
		if not s.is_alive():
			continue
		data["ships"].append({
			"type": s.ship_type, "owner": s.owner_id, "pos": _v(s.global_position), "rot": s.rotation,
			"hp": s.hp, "shield": s.shield, "armor": s.armor, "cargo": s.cargo, "cargo_type": s.cargo_type,
			"order": _order_of(s),
		})
	return data

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
			return {"kind": "build", "at": _v(s.build_site)}
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
	for pid_s in data.get("researched", {}):
		var done := {}
		for t in data["researched"][pid_s]:
			if Defs.TECHS.has(t):
				done[t] = true
		game.researched[int(pid_s)] = done
	for pid_s in data.get("research", {}):
		var r: Dictionary = data["research"][pid_s]
		game.research[int(pid_s)] = r if r.is_empty() or Defs.TECHS.has(r.get("id", "")) else {}
	for pid_s in data.get("research_queue", {}):
		game.research_queue[int(pid_s)] = Array(data["research_queue"][pid_s]).filter(func(t): return Defs.TECHS.has(t))
	for pid_s in data.get("ai", {}):
		var st: Dictionary = data["ai"][pid_s]
		st["claimers"] = []
		game.ai.saved_state[int(pid_s)] = st

	# Planets and asteroids: update in place by node name.
	var planets := {}
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
		p.depleted_timer = float(d.get("depleted_timer", 0.0))
		if p.depleted_timer > 0.0:
			(p.get_node("Sprite") as Sprite2D).modulate = Color(0.45, 0.45, 0.5)
		p.hungry = float(d.get("hungry", 0.0))
		p.starve_timer = float(d.get("starve_timer", 0.0))
		p.siege_start_pop = float(d.get("siege_start_pop", 0.0))
		p.shield = float(d.get("shield", p.max_shield()))
		p.spice_reserve = float(d.get("spice_reserve", p.spice_reserve))
		p.max_spice_reserve = float(d.get("max_spice_reserve", p.max_spice_reserve))
		p.last_hit_time = Game.now() - float(d.get("since_hit", 1000.0))
		p.queue_redraw()
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
	for n in tree.get_nodes_in_group("ships") + tree.get_nodes_in_group("starbases"):
		n.remove_from_group("ships")
		n.remove_from_group("starbases")
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
			"build": s.order_build_starbase(_p(o["at"]))
			"bombard":
				if planets.has(o["target"]):
					s.order_bombard(planets[o["target"]])
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
