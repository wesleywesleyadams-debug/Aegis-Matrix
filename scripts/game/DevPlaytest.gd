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
	for t in ["outposts", "warp_gates", "depots"]:
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
	if which != "verify":
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
