class_name MatchLoading
extends CanvasLayer
## The match loading screen: a full-screen pixel-art scene (cycling through
## SCENES from a random start, never the same twice running), the star
## system's name, the players with their colours, a tip and a progress bar.
## It sits on the tree root above everything, loads Main.tscn on a thread
## (real progress), swaps the scene in, waits for the match's first drawn
## frame and fades out.
##
## Use MatchLoading.start(get_tree()) wherever a match begins, instead of
## change_scene_to_file("res://scenes/Main.tscn").

const MAIN := "res://scenes/Main.tscn"
const SCENES := ["scene_1_carrier_nebula", "scene_2_starbase_construction", "scene_3_inhibitor_emp",
	"scene_4_warp_gate", "scene_5_gas_giant_mining", "scene_6_frontier_outpost"]
## Scenes whose art leaves the tip block's usual spot (bottom-right) covered
## by a big subject: scene name -> [rule x, text width, font size].
const TIP_SPOT := {"scene_2_starbase_construction": [1300.0, 560.0, 24]}
const MIN_TIME := 1.2
const TYPE_LABEL := {"human": "HUMAN", "ai": "AI", "neural": "NEURAL AI"}

var _root: Control
var _bar: ProgressBar
var _status: Label
var _pct: Label
var _t := 0.0
var _shown := 0.0
var _target := 0.0
var _swapped := false
var _last_ms := 0

static func start(tree: SceneTree) -> void:
	tree.root.add_child(MatchLoading.new())

## Next picture in the cycle (random first time), remembered in settings.
static func next_scene_index() -> int:
	var last := GameState.loading_scene_index
	var i := randi() % SCENES.size() if last < 0 else (last + 1) % SCENES.size()
	GameState.loading_scene_index = i
	GameState.save_global_settings()
	return i

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	ResourceLoader.load_threaded_request(MAIN, "", true)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks while loading
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color("060a10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var art := TextureRect.new()
	var scene_name: String = SCENES[next_scene_index()]
	art.texture = load("res://assets/ui/loading/%s.png" % scene_name)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_root.add_child(art)
	LoadingUI.shade(_root, 0.0, 0.17, true, 0.75)
	LoadingUI.shade(_root, 0.64, 1.0, false, 0.95)
	# Header: system name + subtitle, logo top right.
	var rnd := GameState.system_id == "random"
	var sys := SystemGen.find(GameState.system_id)
	var sys_name: String = "Uncharted Space" if rnd else str(sys.get("name", "Unknown System"))
	var title := LoadingUI.label(sys_name.to_upper(), 64, LoadingUI.SOLAR)
	title.position = Vector2(80, 36)
	_root.add_child(title)
	var sub := LoadingUI.label("A NEW SYSTEM EVERY MATCH" if rnd else str(sys.get("desc", "")).to_upper(), 24, LoadingUI.GREEN)
	sub.position = Vector2(84, 122)
	_root.add_child(sub)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/logo_aegis_matrix.png")
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	logo.position = Vector2(-380, 24)
	_root.add_child(logo)
	# Players.
	var head := LoadingUI.label("COMMANDERS", 24, LoadingUI.DIM)
	head.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	head.position = Vector2(80, -330)
	_root.add_child(head)
	var players := _players()
	for i in players.size():
		var p: Dictionary = players[i]
		var row := Control.new()
		row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		row.position = Vector2(80 + (i % 2) * 440, -284 + (i / 2) * 46)
		_root.add_child(row)
		var sw := ColorRect.new()
		sw.color = Color.WHITE
		sw.size = Vector2(26, 26)
		sw.position = Vector2(0, 6)
		row.add_child(sw)
		var inner := ColorRect.new()
		inner.color = p["color"]
		inner.size = Vector2(20, 20)
		inner.position = Vector2(3, 3)
		sw.add_child(inner)
		var nm := LoadingUI.label(p["name"], 30, Color(0.94, 0.94, 0.88))
		nm.position = Vector2(40, 0)
		row.add_child(nm)
		var kind := LoadingUI.label(p["kind"], 22, LoadingUI.GREEN if p["kind"] == "HUMAN" else LoadingUI.SOLAR)
		kind.position = Vector2(52 + nm.get_minimum_size().x, 8)
		row.add_child(kind)
	# Tip.
	var spot: Array = TIP_SPOT.get(scene_name, [980.0, 870.0, 26])
	var tx: float = spot[0]
	var rule := ColorRect.new()
	rule.color = Color(0.24, 0.43, 0.24)
	rule.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rule.position = Vector2(tx, -330)
	rule.size = Vector2(2, 170)
	_root.add_child(rule)
	var tip_head := LoadingUI.label("TIP", 24, LoadingUI.SOLAR)
	tip_head.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip_head.position = Vector2(tx + 30.0, -334)
	_root.add_child(tip_head)
	var tip := LoadingUI.label(LoadingTips.random_tip(), int(spot[2]), Color(0.8, 0.84, 0.76))
	tip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.position = Vector2(tx + 30.0, -294)
	tip.size = Vector2(float(spot[1]), 150)
	_root.add_child(tip)
	var parts := LoadingUI.progress(_root, 1760.0, 90.0)
	_bar = parts[0]
	_status = parts[1]
	_pct = parts[2]
	_status.text = "Charting hyperlanes…"

## The match's players as {name, color, kind}, from the lobby's picks (or the
## classic 1-vs-1 when none were made, e.g. resuming an old save).
func _players() -> Array:
	var out := []
	var mp: Array = GameState.match_players
	if mp.is_empty():
		mp = [{"pid": 1, "type": "human", "slot": 1}, {"pid": 2, "type": "ai", "slot": 2}]
	var ai_n := 0
	for p in mp:
		var t := str(p.get("type", "ai"))
		var slot := int(p.get("slot", p.get("pid", 1)))
		var nm := ""
		if t == "human":
			nm = GameState.active_account if not GameState.active_account.is_empty() else "Commander"
		else:
			ai_n += 1
			nm = "Rival %d" % ai_n
		var kind: String = TYPE_LABEL.get(t, "AI")
		if int(p.get("team", 0)) > 0:
			kind += " · TEAM %d" % int(p["team"])
		out.append({"name": nm, "color": Defs.TEAM_COLORS[clampi(slot, 0, Defs.TEAM_COLORS.size() - 1)], "kind": kind})
	return out.slice(0, 8)

func _process(_delta: float) -> void:
	# Real time: the match may start paused or slowed (Engine.time_scale).
	var now := Time.get_ticks_msec()
	var delta := 0.0 if _last_ms == 0 else (now - _last_ms) / 1000.0
	_last_ms = now
	_t += delta
	if not _swapped:
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(MAIN, prog)
		_target = 0.6 * (float(prog[0]) if prog.size() > 0 else 0.0)
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_target = 0.6
			if _shown >= 0.58:
				_swap(st)
	# The bar eases toward the real target, never ahead of the clock.
	_shown = move_toward(_shown, minf(_target, _t / MIN_TIME), delta * 1.5)
	_bar.value = _shown * 100.0
	_pct.text = "%d%%" % int(_bar.value)

func _swap(st: int) -> void:
	_swapped = true
	_status.text = "Building the star system…"
	_target = 0.7
	_shown = 0.7
	_bar.value = 70.0
	_pct.text = "70%"
	# Let this frame reach the screen before the (blocking) match setup.
	await RenderingServer.frame_post_draw
	var packed: PackedScene = ResourceLoader.load_threaded_get(MAIN) if st == ResourceLoader.THREAD_LOAD_LOADED else load(MAIN)
	var tree := get_tree()
	tree.change_scene_to_packed(packed)
	await tree.scene_changed
	_status.text = "Rolling out the fleets…"
	_target = 0.95
	await tree.process_frame
	await RenderingServer.frame_post_draw
	_target = 1.0
	_status.text = "Ready"
	while _shown < 0.999:
		await tree.process_frame
	await tree.create_timer(0.2, true, false, true).timeout
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_root, "modulate:a", 0.0, 0.45)
	await tw.finished
	queue_free()

## Dev aid (SL_LOADING_SHOT=1, from the boot screen): screenshots the
## title, this overlay mid-load and the match once it shows, then quits.
static func dev_chain(tree: SceneTree) -> void:
	await tree.create_timer(1.5, true, false, true).timeout
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("user://title_shot.png")
	start(tree)
	await tree.create_timer(0.6, true, false, true).timeout
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("user://loading_shot.png")
	await tree.create_timer(4.0, true, false, true).timeout
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("user://match_shot.png")
	print("LOADING SHOTS saved")
	tree.quit()
