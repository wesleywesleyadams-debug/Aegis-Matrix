extends Control
## The boot screen: one fixed key-art scene (a starbase against a blazing
## star), the logo, a slim progress bar and a status line, shown while the
## game really loads -- the tech icons GameState is already painting on a
## worker thread (TechIcons.warm_up) plus threaded loads of the heavy
## scenes and every sprite. Then it hands over to the title menu.
## Dev and test runs (SL_* variables, headless) skip it at once; they mostly
## open their scene directly anyway.

const TITLE := "res://scenes/TitleMenu.tscn"
const ART := "res://assets/ui/loading/boot_b.png"
const LOGO := "res://assets/ui/logo_aegis_matrix.png"
const FONT := "res://assets/fonts/JetBrainsMono.ttf"
const MIN_TIME := 1.0
const SCENES := ["res://scenes/Main.tscn", "res://scenes/TitleMenu.tscn", "res://scenes/Lobby.tscn", "res://scenes/Codex.tscn"]
const GREEN := Color("6fe07a")
const SOLAR := Color("ffc93d")

## Loaded resources stay referenced here so the cache keeps them.
static var keep: Array = []

var _queue: Array[String] = []
var _done := 0
var _t := 0.0
var _bar: ProgressBar
var _status: Label
var _pct: Label
var _leaving := false

static func should_skip() -> bool:
	if OS.get_environment("SL_BOOT_SHOT") != "" or OS.get_environment("SL_LOADING_SHOT") != "":
		return false
	if DisplayServer.get_name() == "headless" or GameState._dev_run():
		return true
	for k in ["SL_LOAD", "SL_SYSTEM_TEST", "SL_DEMO_MAX", "SL_ENGAGE_TEST", "SL_MANEUVER_TEST", "SL_DRILL", "SL_MUSIC_TEST"]:
		if OS.get_environment(k) != "":
			return true
	return false

func _ready() -> void:
	if should_skip():
		get_tree().change_scene_to_file.call_deferred(TITLE)
		return
	_build_ui()
	_queue.assign(SCENES)
	for dir in ["res://assets/pixel/", "res://assets/audio/cues/"]:
		for f in ResourceLoader.list_directory(dir):
			var path: String = dir + str(f).trim_suffix(".import").trim_suffix(".remap")
			if path.get_extension() in ["png", "wav", "ogg"] and not path in _queue and ResourceLoader.exists(path):
				_queue.append(path)
	for p in _queue:
		ResourceLoader.load_threaded_request(p, "", true)
	if OS.get_environment("SL_BOOT_SHOT") != "":
		get_tree().create_timer(0.5).timeout.connect(func():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://boot_shot.png")
			print("BOOT SHOT saved"))

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("060a10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.texture = load(ART)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(art)
	LoadingUI.shade(self, 0.0, 0.30, true)   # behind the logo
	LoadingUI.shade(self, 0.86, 1.0, false)  # behind the bar
	var logo := TextureRect.new()
	logo.texture = load(LOGO)
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size = Vector2(640, 248)
	logo.size = logo.custom_minimum_size
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.position = Vector2(-320, 50)
	add_child(logo)
	var parts := LoadingUI.progress(self, 600.0, 105.0)
	_bar = parts[0]
	_status = parts[1]
	_pct = parts[2]
	var tag := LoadingUI.label("A fantasy age of space-warfare and stellar wonders", 18, Color(0.36, 0.44, 0.36))
	tag.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = Vector2(-400, -34)
	tag.size = Vector2(800, 26)
	add_child(tag)

func _process(delta: float) -> void:
	if _leaving or _bar == null:
		return
	_t += delta
	var i := 0
	while i < _queue.size():
		var st := ResourceLoader.load_threaded_get_status(_queue[i])
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			i += 1
			continue
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			keep.append(ResourceLoader.load_threaded_get(_queue[i]))
		_done += 1
		_queue.remove_at(i)
	var total := _done + _queue.size()
	var res_frac := float(_done) / maxf(1.0, total)
	var icons := TechIcons.warm_progress()
	var frac := res_frac * 0.6 + icons * 0.4
	# Never ahead of the clock's minimum, so the bar fills over MIN_TIME at least.
	_bar.value = minf(frac, _t / MIN_TIME) * 100.0
	_pct.text = "%d%%" % int(_bar.value)
	if res_frac < 0.35:
		_status.text = "Charting the void…"
	elif res_frac < 1.0:
		_status.text = "Rolling out the fleets…"
	elif icons < 1.0:
		_status.text = "Forging icons…"
	else:
		_status.text = "Lighting the stars…"
	if frac >= 1.0 and _t >= MIN_TIME:
		_leave()

func _leave() -> void:
	_leaving = true
	var title: PackedScene = load(TITLE)
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.25)
	await tw.finished
	var tree := get_tree()
	tree.change_scene_to_packed(title)
	if OS.get_environment("SL_LOADING_SHOT") != "":
		MatchLoading.dev_chain(tree)
