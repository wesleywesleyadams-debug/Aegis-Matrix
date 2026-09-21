class_name HUD
extends CanvasLayer
## In-match interface, built in code: resource bar, research tree, the
## selection/planet/build panel, minimap, message feed, drag box, order
## pings, starbase placement preview, pause and end screens.

const BG := Color("0c0e1f")
const EDGE := Color("2b3a6b")
const EDGE_LIT := Color("4fb4ff")
const TEXT := Color("c3cde4")
const DIM := Color("6a7596")
const GOOD := Color("6fe07a")
const BAD := Color("ff6a5a")
const STATE_COLORS := {"done": Color("3f8a4a"), "active": Color("4fb4ff"), "queued": Color("3a6fa8"), "available": Color("2b3a6b"), "locked": Color("1a1f33")}
const STATE_LABELS := {"done": "RESEARCHED", "active": "RESEARCHING", "queued": "QUEUED", "available": "AVAILABLE", "locked": "LOCKED"}

var game: Game
var _drag_rect := Rect2()
var _pings: Array = []

var _res_labels := {}
var _res_boxes := {}
var _pop_label: Label
var _fleet_label: Label
var _research_button: Button
var _clock: Label
var _sel_body: VBoxContainer
var _messages: VBoxContainer
var _overlay: Control
var _pause: Control
var _end: Control
var _end_label: Label
var _research_modal: ColorRect
var _tech_buttons := {}
var _build_buttons := {}
var _queue_row: HBoxContainer
var _info_label: Label
var _refresh: float = 0.0
var planet_view: PlanetView
var _speed_slider: HSlider
var _speed_label: Label
var _sel_panel: PanelContainer

## Game speed steps; index NORMAL_SPEED is 1x.
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]
const NORMAL_SPEED := 2

func _ready() -> void:
	game = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	root.add_child(_overlay)

	_build_top_bar(root)
	_build_speed(root)
	_build_menu_button(root)
	_build_selection_panel(root)
	_build_minimap(root)
	_build_messages(root)
	_build_help(root)
	planet_view = PlanetView.new()
	planet_view.game = game
	root.add_child(planet_view)
	# Keep the planet close-up under the HUD panels.
	root.move_child(planet_view, 1)
	_build_research(root)
	_build_pause(root)
	_build_end(root)

	game.selection_changed.connect(_rebuild_selection)
	game.message.connect(_push_message)
	game.match_over.connect(_on_match_over)
	game.tech_completed.connect(func(_p, _t): _refresh_research())
	_rebuild_selection()

func _label(text: String, color: Color = TEXT, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l

func _icon(name: String, scale_px: int = 2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Defs.tex(name)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = tr.texture.get_size() * scale_px
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _panel_style(margin: int = 10, border: Color = EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BG, 0.94)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(margin)
	return sb

func _fmt(v: float) -> String:
	if absf(v) >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % int(v)

# ---------------------------------------------------------------- layout

func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	# Right-aligned next to the speed controls, keeping the left side of
	# the screen free for other panels.
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_right = -12 - 170 - 10 - 330 - 10
	bar.offset_left = bar.offset_right - 1100
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = 8
	bar.add_theme_stylebox_override("panel", _panel_style(8))
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(h)
	for key in Defs.RESOURCES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.add_child(_icon("icon_" + key))
		var l := _label("0")
		box.add_child(l)
		_res_labels[key] = l
		_res_boxes[key] = box
		h.add_child(box)
	_pop_label = _label("Pop 0", TEXT)
	_pop_label.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(_pop_label)
	var fleet := HBoxContainer.new()
	fleet.add_theme_constant_override("separation", 6)
	fleet.add_child(_icon("icon_fleet"))
	_fleet_label = _label("0/0")
	fleet.add_child(_fleet_label)
	h.add_child(fleet)
	_research_button = Button.new()
	_research_button.text = "Research [R]"
	_research_button.custom_minimum_size = Vector2(220, 0)
	_research_button.add_theme_font_size_override("font_size", 14)
	_research_button.focus_mode = Control.FOCUS_NONE
	_research_button.pressed.connect(toggle_research)
	h.add_child(_research_button)
	_clock = _label("00:00", DIM)
	h.add_child(_clock)

## Top-right Menu button: opens the same menu as Esc (Resume, Save Game,
## Options, Quit to Title).
func _build_menu_button(root: Control) -> void:
	var b := Button.new()
	b.text = "Menu [Esc]"
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -12 - 170
	b.offset_right = -12
	b.offset_top = 8
	b.offset_bottom = 8 + 46
	b.pressed.connect(func(): show_pause(true))
	root.add_child(b)

## Game speed slider (top-right, just left of the Menu button). The notch labelled NORMAL is 1x.
func _build_speed(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -12 - 170 - 10 - 330
	panel.offset_right = -12 - 170 - 10
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 8
	panel.add_theme_stylebox_override("panel", _panel_style(8))
	root.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	_play_button = Button.new()
	_play_button.custom_minimum_size = Vector2(92, 0)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _play_button.get_theme_stylebox(st).duplicate() as StyleBox
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		_play_button.add_theme_stylebox_override(st, sb)
	_play_button.focus_mode = Control.FOCUS_NONE
	_play_button.tooltip_text = "Pause / resume the game (Space). You can still give orders while paused."
	_play_button.pressed.connect(toggle_play)
	h.add_child(_play_button)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	_speed_label = _label("Speed 1x (normal)", TEXT, 14)
	v.add_child(_speed_label)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0
	_speed_slider.max_value = SPEEDS.size() - 1
	_speed_slider.step = 1
	_speed_slider.tick_count = SPEEDS.size()
	_speed_slider.ticks_on_borders = true
	_speed_slider.custom_minimum_size = Vector2(200, 20)
	_speed_slider.focus_mode = Control.FOCUS_NONE
	_speed_slider.tooltip_text = "Game speed. Keys: - slower, = faster, Backspace normal."
	_speed_slider.value = NORMAL_SPEED
	_speed_slider.value_changed.connect(_on_speed_changed)
	_speed_slider.value_changed.connect(func(_v): if game_paused: toggle_play())
	v.add_child(_speed_slider)
	var marks := HBoxContainer.new()
	for i in SPEEDS.size():
		var m := _label(("NORMAL" if i == NORMAL_SPEED else "%sx" % str(SPEEDS[i])), GOOD if i == NORMAL_SPEED else DIM, 10)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marks.add_child(m)
	v.add_child(marks)
	_on_speed_changed(_speed_slider.value)

## Play/pause: while paused the match is frozen (time scale 0) but input,
## the camera and menus keep working.
var game_paused := false
var _play_button: Button

func toggle_play() -> void:
	game_paused = not game_paused
	_on_speed_changed(_speed_slider.value)

## Sets the speed by step index (clamped); used by the slider and hotkeys.
func set_speed_index(i: int) -> void:
	_speed_slider.value = clampi(i, 0, SPEEDS.size() - 1)

func speed_index() -> int:
	return int(_speed_slider.value)

func _on_speed_changed(v: float) -> void:
	var s: float = SPEEDS[int(v)]
	Engine.time_scale = 0.0 if game_paused else s
	if _play_button:
		_play_button.text = "Play" if game_paused else "Pause"
		_play_button.modulate = Color("ffd46b") if game_paused else Color.WHITE
	_speed_label.text = "Speed %sx%s" % [str(s), " (normal)" if int(v) == NORMAL_SPEED else ""]
	_speed_label.add_theme_color_override("font_color", TEXT if int(v) == NORMAL_SPEED else Color("ffd46b"))
	if game_paused:
		_speed_label.text = "PAUSED"
		_speed_label.add_theme_color_override("font_color", Color("ffd46b"))

func _build_selection_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	_sel_panel = panel
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	# Pinned to the bottom-left; grows upward to fit its contents (no
	# scrolling) and shrinks back when there's less to show.
	panel.offset_left = 12
	panel.offset_right = 652
	panel.offset_bottom = -12
	panel.offset_top = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)
	_sel_body = VBoxContainer.new()
	_sel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_body.add_theme_constant_override("separation", 8)
	panel.add_child(_sel_body)
	# A starbase's build queue floats just above the panel.
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", 6)
	_queue_row.visible = false
	root.add_child(_queue_row)

func _build_minimap(root: Control) -> void:
	var frame := PanelContainer.new()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -12 - 344
	frame.offset_top = -12 - 232
	frame.offset_right = -12
	frame.offset_bottom = -12
	frame.add_theme_stylebox_override("panel", _panel_style(4))
	root.add_child(frame)
	var mm := Minimap.new()
	mm.game = game
	frame.add_child(mm)

func _build_messages(root: Control) -> void:
	_messages = VBoxContainer.new()
	_messages.anchor_left = 0.5
	_messages.anchor_right = 0.5
	_messages.offset_left = -420
	_messages.offset_right = 420
	_messages.offset_top = 70
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_messages)

func _build_help(root: Control) -> void:
	var l := _label("LMB select · drag box · RMB move/attack/mine/colonize · Ctrl+RMB attack-move · T stop · Tab warships · H home · R research · F found starbase (constructor) · Ctrl+1-9 groups · WASD/edge/MMB pan · wheel zoom · Space pause · - / = game speed · Esc menu", DIM, 13)
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.anchor_right = 1.0
	l.offset_left = 670
	l.offset_right = -370
	l.offset_top = -80
	l.offset_bottom = -12
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)

func _modal(root: Control, title: String, min_width: float = 360.0) -> Array:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(16, EDGE_LIT))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := _label(title, Color.WHITE, 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return [dim, v, t]

func _build_pause(root: Control) -> void:
	var parts := _modal(root, "PAUSED")
	_pause = parts[0]
	var v: VBoxContainer = parts[1]
	for pair in [["Resume", func(): show_pause(false)], ["Save Game", func(): game.save_game()], ["Options", func(): OptionsMenu.open()], ["Quit to Title", _quit_to_title]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		v.add_child(b)

func _build_end(root: Control) -> void:
	var parts := _modal(root, "")
	_end = parts[0]
	_end_label = parts[2]
	var b := Button.new()
	b.text = "Return to Title"
	b.pressed.connect(_quit_to_title)
	parts[1].add_child(b)

# ---------------------------------------------------------------- research tree

func _build_research(root: Control) -> void:
	var parts := _modal(root, "RESEARCH", 1100.0)
	_research_modal = parts[0]
	_research_modal.color = Color(0, 0, 0, 0.45)
	var v: VBoxContainer = parts[1]
	v.add_child(_label("Costs are paid gradually while researching; progress pauses when you can't pay (spice covers energy shortfalls).\nClick to queue a tech; click a queued or active tech to cancel it.", DIM, 13))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 10)
	for s in ["done", "active", "queued", "available", "locked"]:
		var chip := ColorRect.new()
		chip.color = STATE_COLORS[s].lightened(0.2)
		chip.custom_minimum_size = Vector2(14, 14)
		legend.add_child(chip)
		legend.add_child(_label(STATE_LABELS[s].capitalize() + "   ", TEXT, 13))
	v.add_child(legend)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	for tier in [1, 2, 3]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.add_child(_label("TIER %d" % tier, DIM, 14))
		for id in Defs.TECHS:
			if Defs.TECHS[id]["tier"] != tier:
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(340, 100)
			b.clip_contents = true
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func(): game.request_research(id); _refresh_research())
			# Title line, then the cost with resource icons, then the effect.
			var box := VBoxContainer.new()
			box.set_anchors_preset(Control.PRESET_FULL_RECT)
			box.offset_left = 10
			box.offset_top = 5
			box.offset_right = -10
			box.add_theme_constant_override("separation", 2)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lab := Label.new()
			lab.add_theme_font_size_override("font_size", 13)
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(lab)
			box.add_child(CostRow.make(Defs.TECHS[id]["cost"], 13, Defs.TECHS[id]["time"]))
			var desc := Label.new()
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(318, 0)
			desc.add_theme_font_size_override("font_size", 12)
			desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(desc)
			b.add_child(box)
			var bar := ColorRect.new()
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -6
			bar.offset_left = 2
			bar.offset_bottom = -2
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(bar)
			col.add_child(b)
			_tech_buttons[id] = {"button": b, "label": lab, "desc": desc, "bar": bar}
		cols.add_child(col)
	var close := Button.new()
	close.text = "Close [R]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_research)
	v.add_child(close)

func show_planet(p: Planet) -> void:
	planet_view.show_planet(p)

func research_open() -> bool:
	return _research_modal.visible

func toggle_research() -> void:
	_research_modal.visible = not _research_modal.visible
	_refresh_research()

func _refresh_research() -> void:
	if not _research_modal.visible:
		return
	var pid := game.player_id
	var cur: Dictionary = game.research[pid]
	for id in _tech_buttons:
		var t: Dictionary = Defs.TECHS[id]
		var st := game.tech_state(pid, id)
		var w: Dictionary = _tech_buttons[id]
		var line := "%s   [%s" % [t["name"], STATE_LABELS[st]]
		if st == "active" and cur.get("stalled", false):
			line += ", STALLED"
		if st == "queued":
			line += " #%d" % (game.research_queue[pid].find(id) + 1)
		line += "]"
		var req := ""
		if not t["requires"].is_empty():
			req = "\nNeeds: " + ", ".join(t["requires"].map(func(r): return Defs.TECHS[r]["name"]))
		w["label"].text = line
		w["desc"].text = t["desc"] + req
		for style in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = _panel_style(6, STATE_COLORS[st].lightened(0.3 if style == "normal" else 0.55))
			sb.bg_color = STATE_COLORS[st].darkened(0.3 if style != "hover" else 0.15)
			w["button"].add_theme_stylebox_override(style, sb)
		w["label"].add_theme_color_override("font_color", DIM if st == "locked" else (Color.WHITE if st in ["active", "done"] else TEXT))
		w["desc"].add_theme_color_override("font_color", DIM if st == "locked" else TEXT)
		var frac := 0.0
		if st == "active":
			frac = cur["progress"] / t["time"]
		elif st == "done":
			frac = 1.0
		w["bar"].color = BAD if st == "active" and cur.get("stalled", false) else (GOOD if st == "done" else EDGE_LIT)
		w["bar"].offset_right = -2 - (1.0 - frac) * 336.0
		w["bar"].visible = frac > 0.0

func show_pause(on: bool) -> void:
	_pause.visible = on
	game.paused_menu = on
	get_tree().paused = on

func _unhandled_input(event: InputEvent) -> void:
	if _pause.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		show_pause(false)
		get_viewport().set_input_as_handled()

func _quit_to_title() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")

func _on_match_over(won: bool) -> void:
	_end_label.text = "VICTORY" if won else "DEFEAT"
	_end_label.add_theme_color_override("font_color", GOOD if won else Color("ff4f5e"))
	_end.visible = true

# ---------------------------------------------------------------- selection panel

func _rebuild_selection() -> void:
	_sel_panel.visible = not (game.selection.filter(func(e): return is_instance_valid(e)).is_empty() and is_instance_valid(game.focused_planet))
	for c in _sel_body.get_children():
		c.queue_free()
	_build_buttons.clear()
	for c in _queue_row.get_children():
		c.free()
	_queue_row.visible = false
	_info_label = null
	var sel: Array = game.selection.filter(func(e): return is_instance_valid(e))
	if sel.is_empty():
		if is_instance_valid(game.focused_planet):
			_build_planet_panel(game.focused_planet)
			return
		_sel_body.add_child(_label("No selection", DIM))
		_sel_body.add_child(_label("Select your starbase to build ships, or click a planet to inspect it.", DIM, 13))
		return
	if sel.size() == 1:
		var e: SpaceEntity = sel[0]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(_entity_icon(e, 1 if e is Starbase else 3))
		var col := VBoxContainer.new()
		col.add_child(_label(e.display_name, Defs.team_color(e.owner_id), 20))
		_info_label = _label("")
		col.add_child(_info_label)
		head.add_child(col)
		_sel_body.add_child(head)
		if e.owner_id == game.player_id:
			if e is Starbase and not e.under_construction:
				_build_starbase_controls(e)
			elif e is Ship:
				_build_ship_controls(e)
		return
	var counts := {}
	for e in sel:
		var k: String = e.ship_type if e is Ship else "starbase"
		counts[k] = counts.get(k, 0) + 1
	_sel_body.add_child(_label("%d selected" % sel.size(), TEXT, 20))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 18)
	for k in counts:
		var box := HBoxContainer.new()
		box.add_child(_icon("starbase" if k == "starbase" else "ship_" + k, 2))
		box.add_child(_label("×%d" % counts[k]))
		grid.add_child(box)
	_sel_body.add_child(grid)
	if sel.any(func(e): return e is Ship and e.def["role"] == "constructor"):
		_add_found_button()

func _entity_icon(e: SpaceEntity, px: int) -> Control:
	var tex_name: String = "starbase" if e is Starbase else "ship_" + (e as Ship).ship_type
	var stack := Control.new()
	var base := _icon(tex_name, px)
	var team := _icon(tex_name + "_team", px)
	team.modulate = Defs.team_color(e.owner_id)
	stack.custom_minimum_size = base.custom_minimum_size
	stack.add_child(base)
	stack.add_child(team)
	return stack

func _build_ship_controls(s: Ship) -> void:
	match s.def["role"]:
		"colony":
			_sel_body.add_child(_label("Right-click an unowned planet to settle it with %d pops." % int(Defs.START_POP), DIM, 13))
		"constructor":
			_add_found_button()
		"miner":
			_sel_body.add_child(_label("Right-click an asteroid to mine it. Orange-flecked rocks hold spice.", DIM, 13))
		"skimmer":
			_sel_body.add_child(_label("Right-click a gas giant to mine minerals from it.", DIM, 13))

func _add_found_button() -> void:
	var b := Button.new()
	b.text = "Found Starbase [F]"
	b.custom_minimum_size = Vector2(0, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var cost := CostRow.make(Defs.STARBASE["cost"], 13, Defs.STARBASE["build_time"])
	cost.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cost.offset_left = -230
	cost.offset_right = -10
	cost.offset_top = -12
	cost.offset_bottom = 12
	cost.alignment = BoxContainer.ALIGNMENT_END
	b.add_child(cost)
	var pid := game.player_id
	var n := game.starbase_count(pid)
	var now_u: float = n * Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(pid, n)
	var next_u: float = (n + 1) * Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(pid, n + 1)
	b.tooltip_text = "You have %d starbase%s. Starbase #%d raises total starbase upkeep from %.1f to %.1f energy/s (x%.1f each).\nUpkeep climbs steeply past 10 starbases." % [n, "" if n == 1 else "s", n + 1, now_u, next_u, game.starbase_upkeep_multiplier(pid, n + 1)]
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(game.start_starbase_placement)
	_sel_body.add_child(b)

func _build_starbase_controls(sb: Starbase) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for t in Defs.BUILD_ORDER:
		var d: Dictionary = Defs.SHIPS[t]
		var b := Button.new()
		b.custom_minimum_size = Vector2(198, 62)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s\nHull %d  Shield %d  Speed %d\nUpkeep %.2f energy/s base (scales with fleet size)\nCost %s, paid over %ds" % [d["name"], d["hp"], d["shield"], d["speed"], d["upkeep"], Defs.cost_text(d["cost"]), d["build_time"]]
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 6
		h.add_theme_constant_override("separation", 8)
		h.add_child(_icon("ship_" + t, 2))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_label("[%s] %s" % [OS.get_keycode_string(d["hotkey"]), d["name"]], TEXT, 13))
		v.add_child(CostRow.make(d["cost"], 12, -1.0, 1))
		h.add_child(v)
		b.add_child(h)
		b.pressed.connect(func(): game.request_build(sb, t))
		grid.add_child(b)
		_build_buttons[t] = b
	_sel_body.add_child(grid)
	_queue_row.visible = true
	_sel_body.add_child(_label("Right-click to set the rally point. Click a queued ship to cancel (paid share refunded).", DIM, 12))

func _build_planet_panel(p: Planet) -> void:
	var t := p.type_def()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var ic := _icon(p.kind, 1)
	ic.custom_minimum_size = Vector2(56, 56)
	head.add_child(ic)
	var col := VBoxContainer.new()
	var owner_text := "Unclaimed" if p.owner_id == 0 else ("Yours" if p.owner_id == game.player_id else "Enemy")
	col.add_child(_label(("%s  ·  %s  ·  Size %d" % [p.planet_name, t["label"], p.fields]) if p.fields > 0 else "%s  ·  %s" % [p.planet_name, t["label"]], Defs.team_color(p.owner_id), 20))
	col.add_child(_label(owner_text, DIM, 14))
	head.add_child(col)
	_sel_body.add_child(head)
	_info_label = _label("")
	_sel_body.add_child(_info_label)

func _update_selection_info() -> void:
	if _info_label == null:
		return
	var sel: Array = game.selection.filter(func(e): return is_instance_valid(e))
	if sel.is_empty() and is_instance_valid(game.focused_planet):
		planet_view.refresh()
		_info_label.text = planet_view.stats
		return
	if sel.size() != 1:
		return
	var e: SpaceEntity = sel[0]
	var txt := "Hull %d/%d" % [ceili(e.hp), e.max_hp]
	if e.max_shield > 0:
		txt += "   Shield %d/%d" % [ceili(e.shield), e.max_shield]
	if e is Ship:
		var s := e as Ship
		txt += "\n" + ["Idle", "Moving", "Engaging", "Attack-moving", "En route to mine", "Mining", "Returning cargo", "Colonizing", "Flying to build site", "Flying to gas giant"][s.state]
		if s.is_miner():
			txt += "   Cargo %d/%d %s" % [s.cargo, s.cargo_cap(), s.cargo_type]
		elif s.def["weapon"] != "":
			txt += "   %s %.0f dmg / %.1fs" % [s.def["weapon"].capitalize(), s.def["damage"] * game.mod(e.owner_id, "damage"), s.def["cooldown"]]
		txt += "   Upkeep %.2f/s" % (s.def["upkeep"] * game.upkeep_multiplier(s.owner_id))
	elif e is Starbase:
		var sb := e as Starbase
		txt += "
Starbases %d · upkeep %.1f/s each (x%.1f)" % [game.starbase_count(sb.owner_id), Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(sb.owner_id), game.starbase_upkeep_multiplier(sb.owner_id)]
		if sb.under_construction:
			txt += "\nConstruction %d%%%s" % [int(100.0 * sb.construct_progress / Defs.STARBASE["build_time"]), "  STALLED: waiting for resources" if sb.build_stalled else ""]
		elif not sb.queue.is_empty():
			var d: Dictionary = Defs.SHIPS[sb.queue[0]]
			txt += "\nBuilding %s %d%%%s" % [d["name"], int(100.0 * sb.build_progress / d["build_time"]), "  STALLED: waiting for resources" if sb.build_stalled else ""]
	_info_label.text = txt
	if e is Starbase and _queue_row.visible:
		var sb := e as Starbase
		for t in _build_buttons:
			var why := sb.can_queue(t)
			_build_buttons[t].disabled = why != ""
			if why.begins_with("Requires"):
				_build_buttons[t].tooltip_text = why
		if _queue_row.get_child_count() != sb.queue.size():
			for c in _queue_row.get_children():
				c.free()
			for i in sb.queue.size():
				var qb := Button.new()
				qb.custom_minimum_size = Vector2(72, 48)
				for st in ["normal", "hover", "pressed"]:
					var qsb := qb.get_theme_stylebox(st).duplicate() as StyleBox
					qsb.content_margin_left = 6
					qsb.content_margin_right = 6
					qsb.content_margin_top = 4
					qsb.content_margin_bottom = 4
					qb.add_theme_stylebox_override(st, qsb)
				qb.add_theme_font_size_override("font_size", 12)
				qb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				qb.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
				qb.focus_mode = Control.FOCUS_NONE
				qb.icon = Defs.tex("ship_" + sb.queue[i])
				qb.expand_icon = true
				qb.tooltip_text = "Cancel " + Defs.SHIPS[sb.queue[i]]["name"]
				var idx := i
				qb.pressed.connect(func(): sb.cancel(idx))
				_queue_row.add_child(qb)
		if sb.queue.size() > 0 and _queue_row.get_child_count() > 0:
			var first: Button = _queue_row.get_child(0)
			first.text = "%d%%" % int(100.0 * sb.build_progress / Defs.SHIPS[sb.queue[0]]["build_time"])
			first.modulate = Color(1, 0.6, 0.55) if sb.build_stalled else Color.WHITE

func _planet_text(p: Planet) -> String:
	var t := p.type_def()
	if not p.is_habitable():
		return "Uninhabitable gas giant · %s\nGas Skimmers mine it and haul the minerals to a starbase." % [("DEPLETED, refills in %ds" % int(p.depleted_timer)) if p.depleted_timer > 0.0 else "Mineral reserve %d" % p.amount]
	if p.owner_id == 0:
		return "Size %d · Pop cap %s%s\nSend a Colony Ship (right-click) to settle it." % [p.fields, _fmt(p.max_pop()), (" · Spice %.2f/s" % t["spice"]) if t["spice"] > 0.0 else ""]
	var lines := "Population %s / %s   (+%s/min)" % [_fmt(p.pop), _fmt(p.max_pop()), _fmt(p.growth_per_min)]
	lines += "\nFood: grown %s/min · eaten %s/min · net %+d/min" % [_fmt(p.food_made_per_min), _fmt(p.food_eaten_per_min), int(p.food_made_per_min - p.food_eaten_per_min)]
	lines += "\nEnergy %.1f/s%s" % [p.energy_out, ("   Spice %.2f/s" % p.spice_out) if p.spice_out > 0.0 else ""]
	if p.starving:
		lines += "\nSTARVING: %s pops die in %ds unless fed" % [_fmt(p.hungry), int(Defs.STARVE_SECONDS - p.starve_timer)]
	return lines

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.1
		_update_top_bar()
		_update_selection_info()
		_refresh_research()
		planet_view.refresh()
	_fit_selection_panel()
	var now := Game.now()
	_pings = _pings.filter(func(p): return now - p["t"] < 0.5)
	_overlay.queue_redraw()

func _update_top_bar() -> void:
	var pid := game.player_id
	var r: Dictionary = game.resources.get(pid, {})
	var rt: Dictionary = game.rates.get(pid, {})
	for k in Defs.RESOURCES:
		var rate: float = rt.get(k, 0.0)
		# Food moves in per-minute terms (every pop eats 1/min); the rest per second.
		var rate_txt := ("%+d/min" % int(rate * 60.0)) if k == "food" else ("%+.1f/s" % rate)
		_res_labels[k].text = "%s %s" % [_fmt(r.get(k, 0.0)), rate_txt]
		_res_labels[k].add_theme_color_override("font_color", BAD if rate < -0.01 and r.get(k, 0.0) < 50.0 else TEXT)
		_res_boxes[k].tooltip_text = "%s: %d stockpiled, %s net" % [Defs.RESOURCE_NAMES[k], int(r.get(k, 0.0)), rate_txt]
	if game.energy_starved(pid):
		_res_labels["energy"].add_theme_color_override("font_color", BAD)
		_res_labels["energy"].text += "  NO ENERGY"
	_res_boxes["spice"].tooltip_text += "\nSpice automatically covers shortfalls of food, minerals and energy (1:1)."
	_res_boxes["energy"].tooltip_text += "\nUpkeep: %.1f/s for ships and starbases%s" % [game.upkeep(pid), "
OUT OF ENERGY: ship production halted, ships at 25%% speed" if game.energy_starved(pid) else ""]
	_pop_label.text = "Pop %s" % _fmt(game.total_pop(pid))
	_pop_label.tooltip_text = "Population across your worlds. Each pop eats 1 food per minute."
	_fleet_label.text = "%d ships · upkeep x%.2f" % [game.ship_count(pid), game.upkeep_multiplier(pid)]
	_fleet_label.tooltip_text = "Each ship's energy upkeep is multiplied by 1 + (ships / %d)^2. Starbases scale separately: x%.1f with %d starbases.
Total ship+starbase upkeep: %.1f energy/s." % [int(Defs.UPKEEP_SCALE_SHIPS), game.starbase_upkeep_multiplier(pid), game.starbase_count(pid), game.upkeep(pid)]
	_fleet_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var cur: Dictionary = game.research[pid]
	if cur.is_empty():
		_research_button.text = "No research [R]"
		_research_button.modulate = Color(1, 0.85, 0.5)
	else:
		var t: Dictionary = Defs.TECHS[cur["id"]]
		_research_button.text = "%s %d%%%s" % [t["name"], int(100.0 * cur["progress"] / t["time"]), " (stalled)" if cur["stalled"] else ""]
		_research_button.modulate = Color(1, 0.6, 0.55) if cur["stalled"] else Color.WHITE
	var s := int(Game.now())
	_clock.text = "%02d:%02d" % [s / 60, s % 60]

## Shrink-wraps the bottom-left panel to its contents (it grows upward) and
## parks the build queue row just above it.
func _fit_selection_panel() -> void:
	_sel_panel.size.y = 0.0
	_sel_panel.position.y = _sel_panel.get_parent_area_size().y - 12.0 - _sel_panel.size.y
	if _queue_row.visible:
		_queue_row.size = Vector2.ZERO
		_queue_row.position = Vector2(12.0, _sel_panel.position.y - _queue_row.size.y - 8.0)

func set_drag_rect(r: Rect2) -> void:
	_drag_rect = r

func ping(world_pos: Vector2, color: Color) -> void:
	_pings.append({"pos": world_pos, "t": Game.now(), "color": color})

func _push_message(text: String, color: Color) -> void:
	var l := _label(text, color, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_messages.add_child(l)
	while _messages.get_child_count() > 4:
		_messages.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func _draw_overlay() -> void:
	if _drag_rect.size != Vector2.ZERO:
		_overlay.draw_rect(_drag_rect, Color(0.31, 0.7, 1.0, 0.12))
		_overlay.draw_rect(_drag_rect, Color(0.31, 0.7, 1.0, 0.9), false, 1.0)
	var xf := game.get_viewport().get_canvas_transform()
	if game.placing_starbase:
		var wp := game.get_global_mouse_position()
		var ok := game.starbase_site_problem(wp) == ""
		var sp: Vector2 = xf * wp
		var z := game.camera.zoom.x
		var c := GOOD if ok else BAD
		_overlay.draw_arc(sp, Defs.STARBASE["radius"] * z, 0, TAU, 48, c, 2.0)
		_overlay.draw_arc(sp, Defs.STARBASE["min_spacing"] * z, 0, TAU, 96, Color(c, 0.35), 1.0)
	var now := Game.now()
	for p in _pings:
		var k: float = (now - p["t"]) / 0.5
		var sp: Vector2 = xf * p["pos"]
		var r := 4.0 + k * 14.0
		var c: Color = p["color"]
		c.a = 1.0 - k
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_overlay.draw_rect(Rect2(sp + d * (18.0 - r) - Vector2(2, 2), Vector2(4, 4)), c)
