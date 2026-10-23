extends Node
## Dev aid: SL_PLAYTEST=<scenario> plays the match through REAL input - it
## injects mouse and key InputEvents (Viewport.push_input) at screen points
## computed from world positions, so the actual HUD buttons, hotkeys and
## Game click handlers run, not the functions behind them. Prints "PT ..."
## lines and saves user://pt_<scenario>.png before quitting.
##   build   - Constructor panel: Frontier Outpost (click), Warp Gate
##             (hotkey), Weapons Depot page -> Plasma Depot (click); each
##             placed by left-clicking open space.
##   gate    - box-select warships, right-click an own Warp Gate, Eject one,
##             Eject all, garrison again, Warp hotkey + click 1,500 px away.
##   orders  - Engagement / Stance buttons and hotkeys on mixed warships.
##   save    - builds a situation (outpost, garrisoned gate, non-default
##             modes, a corvette mid-build), saves via Esc > Save Game and
##             copies the file to user://pt_save.json.
##   verify  - run with SL_LOAD=<that file>: prints the restored state.
## Run windowed, e.g. --windowed --resolution 1280x720 scenes/Main.tscn.

var game: Game
var hud: HUD

func _ready() -> void:
	game = get_parent()
	hud = game.hud
	_run.call_deferred(OS.get_environment("SL_PLAYTEST"))

func log_(s: String) -> void:
	print("PT " + s)

# ------------------------------------------------------------ input helpers

func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame

func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

func screen_of(world: Vector2) -> Vector2:
	return game.get_canvas_transform() * world

func _mouse_move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	get_viewport().push_input(m, true)

func _button(p: Vector2, idx: MouseButton, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = idx
	e.pressed = pressed
	e.shift_pressed = shift
	e.button_mask = (MOUSE_BUTTON_MASK_LEFT if idx == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	get_viewport().push_input(e, true)

func click(p: Vector2, idx: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_mouse_move(p)
	await _frames(1)
	_button(p, idx, true)
	await _frames(1)
	_button(p, idx, false)
	await _frames(2)

func click_world(w: Vector2, idx: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await click(screen_of(w), idx)

func drag(a: Vector2, b: Vector2) -> void:
	_mouse_move(a)
	await _frames(1)
	_button(a, MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	for i in 6:
		_mouse_move(a.lerp(b, (i + 1) / 6.0))
		await _frames(1)
	_button(b, MOUSE_BUTTON_LEFT, false)
	await _frames(2)

func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		get_viewport().push_input(e, true)
		await _frames(1)
	await _frames(1)

func wheel(down: bool, n: int) -> void:
	var c := get_viewport().get_visible_rect().size / 2.0
	for i in n:
		_button(c, MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP, true)
		await _frames(1)

## A visible, live panel button whose text or tooltip starts with `label`.
func find_button(label: String, root: Node = null) -> Button:
	if root == null:
		root = hud
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Button and c.is_visible_in_tree() and (c.text == label or c.tooltip_text.begins_with(label)):
			return c
		var r := find_button(label, c)
		if r != null:
			return r
	return null

func click_button(label: String) -> bool:
	await _frames(2)
	var b := find_button(label)
	if b == null:
		log_("!! no button '%s'" % label)
		return false
	await click(b.get_global_rect().get_center())
	return true

## The panel hotkey stamped on that button (Q W E / A S D ...).
func key_of(label: String) -> Key:
	var b := find_button(label)
	for k in hud._panel_keys:
		if hud._panel_keys[k] == b and b != null:
			return k
	return KEY_NONE

func press_hotkey_of(label: String) -> bool:
	await _frames(2)
	var k := key_of(label)
	if k == KEY_NONE:
		log_("!! no hotkey for '%s'" % label)
		return false
	log_("pressing %s for '%s'" % [OS.get_keycode_string(k), label])
	await key(k)
	return true

func shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pt_%s.png" % name)
	log_("screenshot user://pt_%s.png" % name)

# ------------------------------------------------------------ world helpers

func home() -> Starbase:
	return game.nearest_starbase(game.player_id, Vector2.ZERO)

## An open spot for `kind` about `r` px from `c`.
func open_spot(kind: String, c: Vector2, r: float, start_ang := 0.0) -> Vector2:
	for rr in [r, r + 120.0, r + 240.0, r + 400.0]:
		for k in 36:
			var p: Vector2 = c + Vector2.from_angle(start_ang + k * TAU / 36.0) * rr
			if game.site_problem(kind, p) == "" and not game.is_blocked(p, 60.0):
				return p
	return c + Vector2(r, 0)

func finished_gate(at: Vector2) -> WarpGate:
	var g: WarpGate = game.found_fort(game.player_id, at, "gate")
	g.under_construction = false
	g.construct_progress = Defs.WARP_GATE["build_time"]
	g.refresh_stats()
	g.hp = g.max_hp
	g.shield = g.max_shield
	g.armor = g.max_armor
	g._update_look()
	return g

func setup() -> void:
	var pid := game.player_id
	for t in ["outposts", "warp_gates", "depots"] + Array(OS.get_environment("SL_PT_TECHS").split(",", false)):
		game.researched[pid][t] = true
	game.resources[pid]["minerals"] = 20000.0
	game.resources[pid]["spice"] = 5000.0
	game.resources[pid]["energy"] = 5000.0
	if hud.research_open():
		hud.toggle_research()

func sel_names() -> String:
	return ", ".join(game.selection.filter(func(e): return is_instance_valid(e)).map(func(e): return e.display_name))

func modes(ships: Array) -> String:
	return ", ".join(ships.filter(func(s): return is_instance_valid(s)).map(func(s): return "%s[%s/%s]" % [s.ship_type, Ship.ENGAGE_NAMES[int(s.engagement)], Ship.STANCE_NAMES[int(s.stance)]]))

# ------------------------------------------------------------ scenarios

func _run(which: String) -> void:
	await _secs(0.5)
	if not which.ends_with("verify"):
		setup()
	await _frames(3)
	match which:
		"build":
			await _build()
		"gate":
			await _gate()
		"orders":
			await _orders()
		"save":
			await _save()
		"verify":
			await _verify()
		"finite_gas":
			await _finite_gas()
		"finite_world":
			await _finite_world()
		"finite_fuel":
			await _finite_fuel()
		"finite_nebula":
			await _finite_nebula()
		"blackout":
			await _blackout()
		"spicecover":
			await _spicecover()
		"spicecover_verify":
			await _secs(1.0)
			log_("LOADED spice_cover_on(player)=%s dict=%s" % [str(game.spice_cover_on(game.player_id)), str(game.spice_cover)])
			game.hud._update_top_bar()
			log_("LOADED button text=%s" % hud._cover_btn.text)
		"finite_save":
			await _finite_save()
		"finite_verify":
			await _finite_dump("after load")
			await _secs(8.0)
			await _finite_dump("8 s after load")
		_:
			log_("unknown scenario '%s'" % which)
	await shot(which)
	get_tree().quit()

func _build() -> void:
	var c := home().global_position
	var cons: Array = []
	for i in 3:
		cons.append(game.spawn_ship("constructor", game.player_id, c + Vector2(150 + 40 * i, 140)))
	game.center_on(c + Vector2(200, 140))
	await _frames(3)
	var specs := [["Frontier Outpost", "outpost", "click"], ["Warp Gate", "gate", "key"], ["Plasma Depot", "depot", "page"]]
	var spots: Array = []
	for i in 3:
		var con: Ship = cons[i]
		await click_world(con.global_position)
		log_("selected: %s" % sel_names())
		var spec: Array = specs[i]
		if spec[2] == "click":
			await click_button(spec[0])
		elif spec[2] == "key":
			await press_hotkey_of(spec[0])
		else:
			# A different placement armed first: picking the depot must replace it.
			await click_button("Frontier Outpost")
			await click_button("Weapons Depot")
			log_("depot page buttons: %s" % str(["Plasma Depot", "Rail Depot", "< Back"].map(func(l): return find_button(l) != null)))
			await click_button(spec[0])
		log_("after %s button: placing_fort='%s' placing_depot=%s variant=%s" % [spec[0], game.placing_fort, str(game.placing_depot), game.placing_depot_variant])
		var spot := open_spot(spec[1], c, 420.0, 0.6 + i * 0.9)
		spots.append(spot)
		_mouse_move(screen_of(spot))
		await _frames(2)
		await click_world(spot)
		log_("clicked (%d,%d): placing now=%s con state=%s build_kind=%s site=%s" % [int(spot.x), int(spot.y), str(game.is_placing()), Ship.State.keys()[con.state], con.build_kind, str(con.build_site.round())])
	await _secs(12.0)
	for f in get_tree().get_nodes_in_group("forts") + get_tree().get_nodes_in_group("depots"):
		if f.owner_id == game.player_id:
			log_("site %s at (%d,%d) under_construction=%s progress=%.1f" % [f.display_name, int(f.global_position.x), int(f.global_position.y), str(f.under_construction), f.construct_progress])
	for i in 3:
		log_("constructor %d valid=%s" % [i, str(is_instance_valid(cons[i]))])
	game.center_on((spots[0] + spots[1] + spots[2]) / 3.0)

func _gate_fleet(at: Vector2) -> Array:
	var crew: Array = []
	for t in ["corvette", "corvette", "destroyer", "cruiser", "corvette", "destroyer"]:
		crew.append(game.spawn_ship(t, game.player_id, at + Vector2(randf_range(-70, 70), randf_range(-40, 40))))
	return crew

func _box(ships: Array) -> void:
	var r := Rect2(screen_of(ships[0].global_position), Vector2.ZERO)
	for s in ships:
		r = r.expand(screen_of(s.global_position))
	r = r.grow(30.0)
	await drag(r.position, r.end)

func _gate() -> void:
	var c := home().global_position
	var gpos := open_spot("gate", c, 360.0)
	var g := finished_gate(gpos)
	var crew := _gate_fleet(gpos + Vector2(0, 220))
	game.center_on(gpos + Vector2(0, 110))
	await _secs(0.5)
	await _box(crew)
	log_("box-selected %d: %s" % [game.selection.size(), sel_names()])
	await click_world(gpos, MOUSE_BUTTON_RIGHT)
	await _secs(8.0)
	log_("garrison after right-click: %d / %d" % [g.ships().size(), crew.size()])
	await click_world(gpos)
	log_("selected: %s; Warp button=%s key=%s" % [sel_names(), str(find_button("Warp") != null), OS.get_keycode_string(key_of("Warp"))])
	await click_button("Eject")
	log_("after one Eject: garrison=%d" % g.ships().size())
	await click_button("Eject all")
	log_("after Eject all: garrison=%d" % g.ships().size())
	await _box(crew)
	await click_world(gpos, MOUSE_BUTTON_RIGHT)
	await _secs(8.0)
	log_("garrison again: %d" % g.ships().size())
	await click_world(gpos)
	await wheel(true, 4)
	var dest: Vector2 = gpos + (-gpos).normalized() * 1500.0
	game.center_on(dest)
	await _frames(3)
	log_("dest (%d,%d) on screen at %s (viewport %s)" % [int(dest.x), int(dest.y), str(screen_of(dest).round()), str(get_viewport().get_visible_rect().size)])
	await press_hotkey_of("Warp")
	log_("warp_aiming=%s" % str(game.warp_aiming == g))
	await click_world(dest)
	log_("after click: warp_aiming=%s cooldown=%.1f garrison=%d warping=%d" % [str(game.warp_aiming != null), g.cooldown_left, g.ships().size(), crew.filter(func(s): return s.warping).size()])
	await _secs(4.0)
	for s in crew:
		log_("  %s at %d px from dest, warping=%s state=%s" % [s.ship_type, int(s.global_position.distance_to(dest)), str(s.warping), Ship.State.keys()[s.state]])

func _orders() -> void:
	var c := home().global_position
	var at := open_spot("gate", c, 380.0)
	var ships: Array = []
	for t in ["corvette", "destroyer", "cruiser", "corvette"]:
		ships.append(game.spawn_ship(t, game.player_id, at + Vector2(randf_range(-80, 80), randf_range(-50, 50))))
	ships[3].set_engagement(2)   # start mixed
	game.center_on(at)
	await _secs(0.4)
	await _box(ships)
	log_("selected %d; start: %s" % [game.selection.size(), modes(ships)])
	log_("label: %s" % hud._engage_label.text)
	await click_button("Aggressive")   # the Engagement row comes first
	log_("click Engagement Aggressive: %s" % modes(ships))
	await press_hotkey_of("Evasive")
	log_("hotkey Evasive: %s" % modes(ships))
	await click_button("Stand Ground")
	log_("click Stand Ground: %s" % modes(ships))
	var def_btns: Array = []
	_collect("Defensive", hud, def_btns)
	log_("Defensive buttons on panel: %d (engagement + stance)" % def_btns.size())
	# The second "Defensive" is the stance row's.
	var stance_def: Button = def_btns[1]
	var k := KEY_NONE
	for kk in hud._panel_keys:
		if hud._panel_keys[kk] == stance_def:
			k = kk
	log_("pressing %s for Stance Defensive" % OS.get_keycode_string(k))
	await key(k)
	log_("hotkey Stance Defensive: %s" % modes(ships))
	log_("labels: '%s' / '%s'" % [hud._engage_label.text, hud._stance_label.text])

func _collect(label: String, root: Node, out: Array) -> void:
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Button and c.is_visible_in_tree() and c.text == label:
			out.append(c)
		_collect(label, c, out)

func _save() -> void:
	var c := home().global_position
	# An outpost and a gate built for real by Constructors (placed by click).
	var gpos := open_spot("gate", c, 380.0, 0.0)
	var g := finished_gate(gpos)
	var con: Ship = game.spawn_ship("constructor", game.player_id, c + Vector2(-160, 150))
	game.center_on(c)
	await _frames(3)
	await click_world(con.global_position)
	await click_button("Frontier Outpost")
	var opos := open_spot("outpost", c, 420.0, 2.5)
	await click_world(opos)
	# Ships with modes set from the panel; four go into the gate.
	# Ships with modes set from the panel: four go into the gate, two stay
	# out with other modes. (Kept above the selection panel on screen.)
	var crew: Array = []
	for t in ["corvette", "destroyer", "cruiser", "corvette"]:
		crew.append(game.spawn_ship(t, game.player_id, gpos + Vector2(randf_range(-60, 60), 200 + randf_range(-30, 30))))
	var out1: Ship = game.spawn_ship("corvette", game.player_id, gpos + Vector2(-260, 120))
	var out2: Ship = game.spawn_ship("destroyer", game.player_id, gpos + Vector2(260, 120))
	game.center_on(gpos + Vector2(0, 230))
	await _secs(0.4)
	await _box(crew)
	await click_button("Aggressive")   # Engagement row
	var btns: Array = []
	_collect("Stand Ground", hud, btns)
	await click(btns[0].get_global_rect().get_center())
	log_("gate crew modes: %s" % modes(crew))
	await click_world(out1.global_position)
	log_("selected: %s" % sel_names())
	await click_button("Evasive")
	btns.clear()
	_collect("Defensive", hud, btns)
	await click(btns[1].get_global_rect().get_center())   # Stance row
	await click_world(out2.global_position)
	log_("selected: %s" % sel_names())
	await click_button("Defensive")   # Engagement row
	log_("outside modes: %s" % modes([out1, out2]))
	await _box(crew)
	log_("sending %d into the gate" % game.selection.size())
	await click_world(gpos, MOUSE_BUTTON_RIGHT)
	# A corvette queued at the home starbase from its panel.
	game.center_on(c)
	await _frames(2)
	await click_world(c)
	log_("selected: %s" % sel_names())
	if find_button("Military >") != null:
		await click_button("Military >")
	await click_button("Mk I Corvette")
	await _secs(9.0)
	log_("STATE before save:")
	_dump()
	# Save the real way: Esc (clears selection), Esc (pause menu), Save Game.
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	var dir := GameState.saves_dir()
	var before := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	await click_button("Save Game")
	await _frames(3)
	var after := DirAccess.get_files_at(dir)
	for f in after:
		if not before.has(f):
			# Moved out of the player's save list into a fixed dev path.
			DirAccess.copy_absolute(dir + "/" + f, "user://pt_save.json")
			DirAccess.remove_absolute(dir + "/" + f)
			log_("saved %s -> %s" % [f, ProjectSettings.globalize_path("user://pt_save.json")])
	await click_button("Resume")

func _verify() -> void:
	await _secs(1.0)
	log_("STATE after load:")
	_dump()
	for g in get_tree().get_nodes_in_group("forts"):
		if g is WarpGate and g.owner_id == game.player_id:
			game.center_on(g.global_position + Vector2(0, 80))
			game._set_selection([g], false)

func _dump() -> void:
	var pid := game.player_id
	for f in get_tree().get_nodes_in_group("forts"):
		if f.owner_id == pid:
			var extra := ""
			if f is WarpGate:
				extra = " garrison=%s" % str(f.ships().map(func(s): return "%s[%s/%s]" % [s.ship_type, Ship.ENGAGE_NAMES[int(s.engagement)], Ship.STANCE_NAMES[int(s.stance)]]))
			log_("  %s (%d,%d) under_construction=%s progress=%.1f hp=%d%s" % [f.display_name, int(f.global_position.x), int(f.global_position.y), str(f.under_construction), f.construct_progress, int(f.hp), extra])
	var odd: Array = get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid and s.is_warship() and not s.docked and (int(s.engagement) != 0 or int(s.stance) != 0))
	log_("  outside ships with non-default modes: %s" % modes(odd))
	var cons: Array = get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid and s.def["role"] == "constructor")
	for s in cons:
		log_("  constructor state=%s build_kind=%s site=%s" % [Ship.State.keys()[s.state], s.build_kind, str(s.build_site.round())])
	var hb := home()
	log_("  home starbase queue=%s build_progress=%.1f" % [str(hb.queue), hb.build_progress])

# ------------------------------------------------------------ finite economy

func _zoom(i: int) -> void:
	game._zoom_index = i
	game.camera.zoom = Vector2.ONE * Game.ZOOM_LEVELS[i]

func _starbase_at(pid: int, pos: Vector2) -> Starbase:
	var sb: Starbase = Game.STARBASE_SCENE.instantiate()
	sb.owner_id = pid
	sb.position = pos
	game.starbases_root.add_child(sb)
	sb.died.connect(game._on_starbase_died)
	return sb

func _hp(e) -> String:
	if not is_instance_valid(e) or not e.is_alive():
		return "DEAD"
	return "%d" % int(e.hp + e.shield + e.armor)

func _gas() -> Planet:
	var gs: Array = get_tree().get_nodes_in_group("planets").filter(func(p): return not p.is_habitable())
	var c := home().global_position
	gs.sort_custom(func(a, b): return a.global_position.distance_to(c) < b.global_position.distance_to(c))
	return gs[0]

## Drains a gas giant to nothing with ships, a starbase and a world in the
## blast; screenshots full size, shrunk, glowing, the blast, and after.
func _finite_gas() -> void:
	var g := _gas()
	var at := g.global_position
	log_("gas giant %s at (%d,%d) amount %d radius %.1f" % [g.planet_name, at.x, at.y, g.amount, g.radius])
	game.center_on(at)
	_zoom(1)
	await shot("gas_0_full")
	g.amount = 5000
	g.update_gas_size()
	log_("amount 5000 -> radius %.1f (base %.1f)" % [g.radius, g._base_radius])
	await shot("gas_1_half")
	g.amount = 1100
	g.update_gas_size()
	var pid := game.player_id
	var foe := 2 if pid == 1 else 1
	var c1: Ship = game.spawn_ship("corvette", pid, at + Vector2(110, 0))
	var c2: Ship = game.spawn_ship("cruiser", foe, at + Vector2(-230, 40))
	var c3: Ship = game.spawn_ship("destroyer", pid, at + Vector2(0, 380))
	var c4: Ship = game.spawn_ship("corvette", foe, at + Vector2(560, 0))
	var sb := _starbase_at(pid, at + Vector2(200, -230))
	var worlds: Array = get_tree().get_nodes_in_group("planets").filter(func(p): return p.is_habitable() and p.owner_id == 0)
	var w1: Planet = worlds[0]
	w1.colonize(foe)
	w1.pop = 4000.0
	w1.global_position = at + Vector2(-300, -260)
	var sk: Ship = game.spawn_ship("skimmer", pid, at + Vector2(-150, 160))
	sk.order_mine(g)
	for s in [c1, c2, c3, c4]:
		s.order_stop()
		s.held = true
	await _secs(0.5)
	var victims := {"own corvette @110": c1, "enemy cruiser @235": c2, "own destroyer @380": c3, "enemy corvette @560": c4, "own starbase @305": sb, "own skimmer": sk}
	for k in victims:
		log_("before %s: %s" % [k, _hp(victims[k])])
	log_("before world %s P%d shield %d pop %d" % [w1.planet_name, w1.owner_id, int(w1.shield), int(w1.pop)])
	g.amount = 900
	g.update_gas_size()
	g._check_unstable()
	await _secs(0.4)
	await shot("gas_2_glow")
	log_("glow: unstable=%s radius %.1f" % [str(g.unstable()), g.radius])
	g.amount = 1
	var got := g.extract(5)
	log_("drained: doom_timer %.1f, giant still there" % g.doom_timer)
	await _secs(4.0)
	await shot("gas_2b_countdown")
	await _secs(6.5)
	log_("extract returned %d; blasts=%d; gas giants left %d" % [got, game.blasts, get_tree().get_nodes_in_group("planets").filter(func(p): return not p.is_habitable()).size()])
	await _secs(0.25)
	await shot("gas_3_blast")
	await _secs(1.5)
	for k in victims:
		log_("after %s: %s" % [k, _hp(victims[k])])
	log_("after world %s P%d shield %d pop %d" % [w1.planet_name, w1.owner_id, int(w1.shield), int(w1.pop)])
	if is_instance_valid(sk) and sk.is_alive():
		log_("skimmer state %s" % Ship.State.keys()[sk.state])
	await shot("gas_4_after")

## A world mined to its end: glow, implosion, blast scaled by size.
func _finite_world() -> void:
	var pid := game.player_id
	var foe := 2 if pid == 1 else 1
	var worlds: Array = get_tree().get_nodes_in_group("planets").filter(func(p): return p.is_habitable() and p.owner_id == 0)
	worlds.sort_custom(func(a, b): return a.fields > b.fields)
	var w: Planet = worlds[0]
	w.colonize(foe)
	w.pop = 6000.0
	w.buildings[0] = "mine"
	w.buildings[1] = "mine"
	var at := w.global_position
	var r := w.blast_radius()
	log_("world %s size %d crust %d / %d, blast %.0f dmg over %.0f px" % [w.planet_name, w.fields, int(w.mineral_reserve), int(w.max_mineral_reserve), Defs.BLAST_DAMAGE * w.blast_scale(), r])
	var near: Planet = worlds[1]
	near.colonize(pid)
	near.pop = 3000.0
	near.global_position = at + Vector2(r * 0.5 + near.radius, 0)
	var s1: Ship = game.spawn_ship("corvette", pid, at + Vector2(0, w.radius + 40))
	var s2: Ship = game.spawn_ship("cruiser", pid, at + Vector2(0, -r * 0.6))
	var s3: Ship = game.spawn_ship("corvette", foe, at + Vector2(-r * 0.9, 0))
	for s in [s1, s2, s3]:
		s.order_stop()
		s.held = true
	game.center_on(at)
	_zoom(1 if r > 250.0 else 2)
	w.mineral_reserve = 1100.0
	await _secs(1.0)
	w.mineral_reserve = 800.0
	await _secs(1.0)
	log_("unstable=%s crust %.0f" % [str(w.unstable()), w.mineral_reserve])
	await shot("world_0_glow")
	log_("before: corvette %s cruiser %s enemy corvette %s; world %s shield %d pop %d" % [_hp(s1), _hp(s2), _hp(s3), near.planet_name, int(near.shield), int(near.pop)])
	var b0 := game.blasts
	w.mineral_reserve = 0.5
	var t0 := Game.now()
	# (The owner's AI pauses mining near the end: keep it digging.)
	var shot_doom := false
	while game.blasts == b0 and Game.now() - t0 < 25.0:
		w.mining_paused = false
		if w.doom_timer >= 0.0 and w.doom_timer < 7.0 and not shot_doom:
			shot_doom = true
			log_("countdown %.1f s left" % w.doom_timer)
			await shot("world_0b_countdown")
		await _frames(1)
	log_("imploded after %.2fs; removed %s" % [Game.now() - t0, str(game.removed_planets)])
	await _secs(0.25)
	await shot("world_1_blast")
	await _secs(1.5)
	log_("after: corvette %s cruiser %s enemy corvette %s; world %s shield %d pop %d" % [_hp(s1), _hp(s2), _hp(s3), near.planet_name, int(near.shield), int(near.pop)])
	log_("P%d planets_lost=%s defeated=%s" % [foe, str(game.stats.counters.get(foe, {}).get("planets_lost", "?")), str(game.is_defeated(foe))])

## Power-plant fuel: a minute of logs, then a mineral-less spell.
func _finite_fuel() -> void:
	var pid := game.player_id
	Engine.time_scale = 4.0
	for p in get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			log_("world %s plants %d mines %d" % [p.planet_name, p.count_building("generator"), p.count_building("mine")])
	var f0: float = game.fuel_paid.get(pid, 0.0)
	var t0 := Game.now()
	var e_sum := 0.0
	var n := 0
	while Game.now() - t0 < 60.0:
		await _secs(0.5)
		var e := 0.0
		for p in get_tree().get_nodes_in_group("planets"):
			if p.owner_id == pid:
				e += p.energy_out
		e_sum += e
		n += 1
	var paid: float = game.fuel_paid.get(pid, 0.0) - f0
	var dt := Game.now() - t0
	log_("FUEL %.1fs: avg plant energy %.2f/min -> expected fuel %.3f/min; burnt %.3f minerals = %.3f/min; fuel_per_min now %.3f" % [dt, e_sum / n, e_sum / n * Defs.FUEL_PER_ENERGY, paid, paid / dt * 60.0, game.fuel_per_min(pid)])
	for p in get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			p.mining_paused = true
	for s in get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid and s.is_harvester():
			s.order_stop()
	game.resources[pid]["minerals"] = 0.0
	game.resources[pid]["spice"] = 5000.0
	await _secs(1.0)
	var sp0: float = game.resources[pid]["spice"]
	var en0: float = game.resources[pid]["energy"]
	await _secs(20.0)
	var hp: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid)[0]
	log_("FUEL no minerals: minerals %.1f, fuel_frac %.2f, plant energy %.1f/min, spice %.1f -> %.1f, energy %.1f -> %.1f" % [game.resources[pid]["minerals"], hp.fuel_frac, hp.energy_out, sp0, game.resources[pid]["spice"], en0, game.resources[pid]["energy"]])
	Engine.time_scale = 1.0
	game.resources[pid]["minerals"] = 500.0
	await _secs(1.0)
	game._focus_planet(hp)
	game.selection_changed.emit()
	await _secs(0.5)

## A skimmer drains a spice nebula; frames over time (SL_NEB_GRID adds the
## cell overlay). SL_NEB_FAST=<n> multiplies its harvest rate for the test.
func _finite_nebula() -> void:
	var pid := game.player_id
	var c := home().global_position
	var nebs: Array = get_tree().get_nodes_in_group("nebulae")
	nebs.sort_custom(func(a, b): return a.heart_toward(c).distance_to(c) < b.heart_toward(c).distance_to(c))
	var neb: SpiceNebula = nebs[0]
	# The edge spot facing home, as nearest_nebula_pocket picks it.
	var h: Vector2 = neb.heart_toward(c)
	var dir := (c - h).normalized()
	while neb.contains(h + dir * 4.0):
		h += dir * 4.0
	var pk := game.nebula_pocket_at(h)
	log_("nebula cells %d, spice %.0f" % [neb.cells.size(), neb.remaining()])
	var sk: Ship = game.spawn_ship("skimmer", pid, pk.global_position + (c - pk.global_position).normalized() * 70.0)
	var fast := float(OS.get_environment("SL_NEB_FAST")) if OS.get_environment("SL_NEB_FAST") != "" else 100.0
	sk.def = sk.def.duplicate()
	sk.def["harvest"] = float(sk.def["harvest"]) * fast
	sk.def["cargo"] = 100000
	sk.order_mine(pk)
	var foe := 2 if pid == 1 else 1
	var hid: Ship = game.spawn_ship("scout", foe, neb.cell_center(neb.cell_of(pk.global_position)))
	hid.order_stop()
	hid.held = true
	game.center_on(pk.global_position)
	_zoom(int(OS.get_environment("SL_NEB_ZOOM")) if OS.get_environment("SL_NEB_ZOOM") != "" else 2)
	await _secs(0.3)
	await shot("neb_before")
	log_("enemy in first cell: in_nebula=%s visible=%s" % [str(game.in_nebula(hid.global_position)), str(game.vision.can_see(hid) if game.vision else true)])
	var frames := int(OS.get_environment("SL_NEB_FRAMES")) if OS.get_environment("SL_NEB_FRAMES") != "" else 8
	var gap := float(OS.get_environment("SL_NEB_GAP")) if OS.get_environment("SL_NEB_GAP") != "" else 2.5
	var cam := pk.global_position
	for i in frames:
		await _secs(gap)
		var empty: int = neb.cells.values().filter(func(v): return v <= 0.0).size()
		var pv := is_instance_valid(pk)
		log_("frame %d t=%.1f: spice left %.0f, empty cells %d, pocket (%d,%d) amount %d, skimmer %s (%d,%d) cargo %d" % [i, Game.now(), neb.remaining(), empty,
			pk.global_position.x if pv else 0, pk.global_position.y if pv else 0, pk.amount if pv else 0,
			Ship.State.keys()[sk.state], sk.global_position.x, sk.global_position.y, sk.cargo])
		game.center_on(pk.global_position if is_instance_valid(pk) else cam)
		await shot("neb_%d" % i)
	log_("enemy cell now: in_nebula=%s visible=%s" % [str(game.in_nebula(hid.global_position)), str(game.vision.can_see(hid) if game.vision else true)])

## Pause mining by real clicks, drain things, then save to user://pt_finite.json.
func _finite_save() -> void:
	var pid := game.player_id
	var hp: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid)[0]
	game.center_on(hp.global_position)
	await _frames(3)
	await click_world(hp.global_position)
	await _secs(0.3)
	log_("focused %s; paused before click=%s" % [game.focused_planet.planet_name if is_instance_valid(game.focused_planet) else "-", str(hp.mining_paused)])
	await click_button("Pause mining")
	await _frames(2)
	log_("after click: paused=%s, button 'Resume mining' shown=%s" % [str(hp.mining_paused), str(find_button("Resume mining") != null)])
	var m0: float = hp.mineral_reserve
	await _secs(5.0)
	log_("paused 5s: crust %.1f -> %.1f, minerals_out %.1f" % [m0, hp.mineral_reserve, hp.minerals_out])
	await shot("finite_pause")
	hp.mineral_reserve = 12345.0
	var g := _gas()
	g.amount = 4321
	g.update_gas_size()
	var gs: Array = get_tree().get_nodes_in_group("planets").filter(func(p): return not p.is_habitable() and p != g)
	gs[-1].amount = 1
	gs[-1].extract(5)
	await _secs(11.0)
	# The other one is counting down when the game is saved.
	g.amount = 1
	g.extract(5)
	await _secs(3.0)
	var neb: SpiceNebula = get_tree().get_nodes_in_group("nebulae")[0]
	var keys: Array = neb.cells.keys()
	for k in keys.slice(0, 20):
		neb.drain_at(neb.cell_center(k), 100.0)
	neb.drain_at(neb.cell_center(keys[25]), 40.0)
	await _frames(3)
	await _finite_dump("before save")
	var path := SaveGame.write(game, "finite test")
	DirAccess.copy_absolute(path, "user://pt_finite.json")
	DirAccess.remove_absolute(path)
	log_("saved -> %s" % ProjectSettings.globalize_path("user://pt_finite.json"))

func _finite_dump(when: String) -> void:
	await _secs(0.5)
	var pid := game.player_id
	var hp: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid)[0]
	log_("%s: home %s crust %.0f paused %s" % [when, hp.planet_name, hp.mineral_reserve, str(hp.mining_paused)])
	var gs := []
	for p in get_tree().get_nodes_in_group("planets"):
		if not p.is_habitable():
			gs.append("%s=%d(r%.0f doom %.1f)" % [p.name, p.amount, p.radius, p.doom_timer])
	log_("%s: gas giants %s; removed %s" % [when, ", ".join(gs), str(game.removed_planets)])
	var nebs := []
	for n in get_tree().get_nodes_in_group("nebulae"):
		nebs.append("%.0f in %d cells, %d empty" % [n.remaining(), n.cells.size(), n.cells.values().filter(func(v): return v <= 0.0).size()])
	log_("%s: nebulae %s" % [when, " | ".join(nebs)])

## Building energy upkeep and Blackout: upkeep per building, paused/under
## construction free, multiplier ignored; then drain to 0 -> Blackout ->
## deliver minerals -> plants -> power back after BLACKOUT_RESUME_SECS.
func _blackout() -> void:
	var pid := game.player_id
	var hp: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid).reduce(func(a, b): return a if a.fields >= b.fields else b)
	for p in get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid and p != hp:
			p.buildings.fill("")
	hp.buildings.fill("")
	var ids := ["farm", "generator", "mine", "habitat", "battery", "spice_extractor"]
	for i in ids.size():
		hp.buildings[i] = ids[i]
	hp.spice_reserve = maxf(hp.spice_reserve, 500.0)
	for s in get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid and s.is_harvester():
			s.order_stop()
	log_("UPKEEP world %s fields %d: %s" % [hp.planet_name, hp.fields, str(hp.buildings.slice(0, 6))])
	log_("UPKEEP all running: world %.1f/min, empire building %.1f/min (expect 14: habitat now 0), ship upkeep %.2f/min, multiplier x%.2f" % [hp.energy_upkeep_per_min(), game.building_upkeep(pid), game.upkeep(pid), game.upkeep_multiplier(pid)])
	hp.mining_paused = true
	log_("UPKEEP mining paused: %.1f/min (expect 10)" % hp.energy_upkeep_per_min())
	hp.order_build(6, "battery")
	log_("UPKEEP + battery under construction: %.1f/min (expect 10), job=%s" % [hp.energy_upkeep_per_min(), hp.field_job(6)])
	hp.cancel_build(6)
	hp.mining_paused = false
	await _frames(2)
	game._focus_planet(hp)
	game.selection_changed.emit()
	await _secs(1.5)
	await shot("blackout_normal")
	log_("PANEL normal: %s" % hud.planet_view.stats.replace("\n", " | ") if "planet_view" in hud else "")
	_full = _outs(hp)
	log_("FULL power outputs: %s" % str(_full))
	# Measured drain: mining paused + no minerals (plants off), no spice.
	hp.mining_paused = true
	Engine.time_scale = 4.0
	game.resources[pid]["minerals"] = 0.0
	game.resources[pid]["spice"] = 0.0
	game.resources[pid]["energy"] = 60.0
	await _secs(1.0)
	var e0: float = game.resources[pid]["energy"]
	var t0 := Game.now()
	var bp0: float = game.building_upkeep_paid.get(pid, 0.0)
	await _secs(6.0)
	var dt := Game.now() - t0
	_drain_end = game.resources[pid]["energy"]
	log_("PAID building upkeep %.3f over %.2fs = %.2f/min (expect 10.00); time_scale-check real ms %d" % [game.building_upkeep_paid.get(pid, 0.0) - bp0, dt, (game.building_upkeep_paid.get(pid, 0.0) - bp0) / dt * 60.0, Time.get_ticks_msec()])
	log_("DRAIN %.1fs: energy %.2f -> %.2f = %.2f/min; expected ships %.2f + buildings %.2f = %.2f/min (shield regen may add)" % [dt, e0, game.resources[pid]["energy"], (e0 - game.resources[pid]["energy"]) / dt * 60.0, game.upkeep(pid), game.building_upkeep(pid), game.upkeep(pid) + game.building_upkeep(pid)])
	# Same window with the world's buildings removed: the difference is the
	# building upkeep alone (other drains - shield regen etc. - cancel out).
	var saved := hp.buildings.duplicate()
	for i in hp.fields:
		hp.buildings[i] = ""
	game.resources[pid]["energy"] = 60.0
	await _secs(1.0)
	var e1: float = game.resources[pid]["energy"]
	var t1 := Game.now()
	await _secs(6.0)
	var dt1 := Game.now() - t1
	var without: float = (e1 - game.resources[pid]["energy"]) / dt1 * 60.0
	log_("DRAIN without buildings %.2f/min -> building share = %.2f/min (expect 10.00)" % [without, (e0 - _drain_end) / dt * 60.0 - without])
	for i in hp.fields:
		hp.buildings[i] = saved[i]
	# Run dry -> Blackout.
	var tb := Game.now()
	game.resources[pid]["energy"] = 3.0
	while not game.in_blackout(pid) and Game.now() - tb < 60.0:
		game.resources[pid]["spice"] = 0.0 # the extractor's spice would cover energy 1:1
		await _secs(0.25)
	log_("BLACKOUT entered=%s at t=%.1f energy %.2f" % [str(game.in_blackout(pid)), Game.now(), game.resources[pid]["energy"]])
	await _secs(4.0)
	_bo_line(hp, "in blackout, no minerals")
	hp.mining_paused = false
	await _secs(1.0)
	var lo := _outs(hp)
	log_("LOW power outputs: %s" % str(lo))
	for k in lo:
		if float(_full.get(k, 0.0)) > 0.0:
			log_("RATIO %s low/full = %.3f (expect 0.250 for farm/mine/extractor/battery shield bonus/battery fire rate; 1.000 for habitat output bonus)" % [k, float(lo[k]) / float(_full[k])])
	log_("BLACKOUT upkeep drawn during blackout: paid stays %.3f (expect unchanged)" % float(game.building_upkeep_paid.get(pid, 0.0)))
	Engine.time_scale = 1.0
	await _secs(0.5)
	game.selection_changed.emit()
	await _secs(0.5)
	await shot("blackout_dark")
	log_("PANEL dark: %s" % hud.planet_view.stats.replace("\n", " | ") if "planet_view" in hud else "")
	log_("TOOLTIP energy: %s" % hud._res_boxes["energy"].tooltip_text.replace("\n", " | "))
	# Deliver minerals; log every 0.5 s.
	Engine.time_scale = 2.0
	game.resources[pid]["minerals"] = 300.0
	log_("DELIVER 300 minerals at t=%.1f" % Game.now())
	var flips := 0
	var last := game.in_blackout(pid)
	var reset_done := false
	for k in 40:
		await _secs(0.5)
		# One forced dip to 0 mid-restore: the 5 s count must restart.
		if not reset_done and float(game.blackout_restore.get(pid, 0.0)) > 2.5:
			game.resources[pid]["energy"] = 0.0
			reset_done = true
			log_("FORCED energy dip to 0 at restore=%.2f" % float(game.blackout_restore.get(pid, 0.0)))
		_bo_line(hp, "")
		if game.in_blackout(pid) != last:
			flips += 1
			last = game.in_blackout(pid)
	log_("RESULT flips=%d final blackout=%s blackout_time=%.1fs" % [flips, str(game.in_blackout(pid)), float(game.blackout_time.get(pid, 0.0))])
	Engine.time_scale = 1.0

var _drain_end := 0.0
var _full := {}

## Per-building outputs used by the Blackout ratio checks (pop held fixed).
func _outs(hp: Planet) -> Dictionary:
	hp.pop = 8000.0
	var g := game
	var hands := hp.pop_output_mult()
	var ceiling_bonus := hands - (1.0 + Defs.OUTPUT_POP_BONUS * (1.0 - exp(-hp.pop / Defs.OUTPUT_POP_SCALE)))
	return {
		"farm_food": Defs.BUILDINGS["farm"]["output"]["food"] * hands * hp.power_factor("farm"),
		"mine_minerals": Defs.BUILDINGS["mine"]["output"]["minerals"] * hands * hp.power_factor("mine"),
		"extractor_spice": Defs.BUILDINGS["spice_extractor"]["output"]["spice"] * hands * hp.power_factor("spice_extractor"),
		"battery_shield_bonus": hp.max_shield() / (g.mod(hp.owner_id, "world_shield") * g.mod(hp.owner_id, "planet_shield")) - Planet.PLANET_SHIELD,
		"battery_fire_rate": Defs.BATTERY["cooldown"] / (Defs.BATTERY["cooldown"] / hp.power_factor("battery")),
		"habitat_output_bonus": ceiling_bonus,
		"live_food_made": hp.food_made_per_min, "live_minerals_out": hp.minerals_out, "live_spice_out": hp.spice_out}

## Spice cover: warning + alert while spice covers a shortfall, the AUTO/OFF
## toggle (clicked for real), consequences with cover OFF, net-per-minute
## figures vs measured stockpile change, and a save carrying the toggle.
func _spicecover() -> void:
	var pid := game.player_id
	var msgs: Array = []
	game.message.connect(func(t, _c): msgs.append(t))
	var hp: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid).reduce(func(a, b): return a if a.fields >= b.fields else b)
	for p in get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid and p != hp:
			p.buildings.fill("")
	hp.buildings.fill("")
	hp.buildings[0] = "generator"
	hp.buildings[1] = "mine"
	hp.pop = 9000.0
	for sh in get_tree().get_nodes_in_group("ships"):
		if sh.owner_id == pid and sh.is_harvester():
			sh.order_stop()
	game.center_on(hp.global_position)
	game._focus_planet(hp)
	game.selection_changed.emit()
	# --- B1: food shortfall covered by spice (no farms).
	game.resources[pid]["food"] = 0.0
	game.resources[pid]["spice"] = 500.0
	game.resources[pid]["energy"] = 500.0
	game.resources[pid]["minerals"] = 500.0
	await _secs(4.0)
	log_("COVER food: covering food %.1f/min (eaten %.1f/min), total %.1f/min; spice %.1f" % [game.spice_covering(pid, "food"), hp.food_eaten_per_min, game.spice_covering(pid), game.resources[pid]["spice"]])
	log_("COVER alerts so far: %s" % str(msgs.filter(func(m): return "Spice is covering" in m)))
	log_("COVER label='%s' tooltip: %s" % [hud._res_labels["spice"].text, hud._res_boxes["spice"].tooltip_text.replace("\n", " | ")])
	await shot("cover_warn")
	await _secs(3.0)
	log_("COVER alerts after 7 s (expect exactly 1 food alert): %s" % str(msgs.filter(func(m): return "Spice is covering" in m)))
	# --- B2: click the toggle OFF.
	var r := hud._cover_btn.get_global_rect()
	await click(r.get_center())
	await _frames(3)
	log_("TOGGLE clicked: cover_on=%s button=%s" % [str(game.spice_cover_on(pid)), hud._cover_btn.text])
	var sp0: float = game.resources[pid]["spice"]
	await _secs(4.0)
	log_("OFF food: spice %.2f -> %.2f (expect same), starving=%s growth %.0f/min, covering %.2f/min" % [sp0, game.resources[pid]["spice"], str(hp.starving), hp.growth_per_min, game.spice_covering(pid, "food")])
	await shot("cover_off")
	# Energy with cover OFF -> Blackout even with spice in stock.
	game.resources[pid]["energy"] = 0.0
	game.resources[pid]["minerals"] = 0.0
	hp.buildings[2] = "battery"
	await _secs(2.0)
	log_("OFF energy: blackout=%s spice %.2f (expect still ~%.2f)" % [str(game.in_blackout(pid)), game.resources[pid]["spice"], sp0])
	# Minerals with cover OFF -> construction stalls.
	hp.order_build(3, "farm")
	await _secs(2.0)
	log_("OFF minerals: construction stalled=%s progress %.2f spice %.2f" % [str(hp.construction_stalled), float(hp.construction.get("progress", -1.0)), game.resources[pid]["spice"]])
	hp.cancel_build(3)
	# --- C: back ON, steady state, measure net.
	await click(r.get_center())
	await _frames(2)
	log_("TOGGLE clicked again: cover_on=%s" % str(game.spice_cover_on(pid)))
	hp.buildings[2] = ""
	hp.buildings[3] = "farm"
	hp.buildings[4] = "farm"
	hp.buildings[5] = "farm"
	for k in ["food", "energy", "minerals", "spice"]:
		game.resources[pid][k] = 3000.0
	hp.pop = hp.max_pop() # steady: no growth during the window
	await _secs(62.0) # blackout clears, the 60 s rate window refills
	var st := {}
	for k in ["food", "energy", "minerals", "spice"]:
		st[k] = game.resources[pid][k]
	var t0 := Game.now()
	await _secs(60.0)
	var dt := Game.now() - t0
	log_("NET spice hist tail: %s" % str(game._rate_hist[pid]["spice"].slice(-8)))
	var net := hp.net_per_min()
	for k in ["food", "energy", "minerals", "spice"]:
		var measured: float = (game.resources[pid][k] - st[k]) / dt * 60.0
		log_("NET %s: top bar %+.2f/min | measured stock change %+.2f/min over %.1fs | world net %+.2f/min | other drains (ships upkeep %.2f, research) diff %+.2f" % [k, game.avg_rate(pid, k), measured, dt, net[k], game.upkeep(pid), measured - net[k]])
	log_("NET world breakdown: food %.1f-%.1f energy %.1f-%.1f(bldg) minerals %.1f-%.1f(fuel) spice %.1f; blackout=%s" % [hp.food_made_per_min, hp.food_eaten_per_min, hp.energy_out, hp.energy_upkeep_per_min(), hp.minerals_out, hp.fuel_per_min, hp.spice_out, str(game.in_blackout(pid))])
	game.selection_changed.emit()
	await _secs(1.0)
	log_("PANEL: %s" % hud.planet_view.stats.replace("\n", " | ") if "planet_view" in hud else "")
	log_("TOPBAR: %s" % " ".join(["food", "energy", "minerals", "spice"].map(func(k): return hud._res_labels[k].text)))
	await shot("net_normal")
	# Save with cover OFF.
	game.set_spice_cover(pid, false)
	var path := SaveGame.write(game, "cover test")
	DirAccess.copy_absolute(path, "user://pt_cover.json")
	DirAccess.remove_absolute(path)
	log_("saved cover OFF -> %s" % ProjectSettings.globalize_path("user://pt_cover.json"))

func _bo_line(hp: Planet, tag: String) -> void:
	var pid := game.player_id
	log_("BO t=%.1f %s blackout=%s restore=%.1f energy=%.2f minerals=%.1f | plants %.1f/min fuel_frac %.0f | food %.1f min %.1f spice %.1f | shield max %d | op=%s" % [
		Game.now(), tag, str(game.in_blackout(pid)), float(game.blackout_restore.get(pid, 0.0)), game.resources[pid]["energy"], game.resources[pid]["minerals"],
		hp.energy_out, hp.fuel_frac, hp.food_made_per_min, hp.minerals_out, hp.spice_out, int(hp.max_shield()), str(hp.operating.slice(0, 6))])
