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
## Order feedback on a target object: red = attack, white = anything else.
## Flashes twice (real time, so it looks the same at any game speed).
var _flashes: Array = []
const FLASH_TIME := 0.5
## Seconds per blink cycle of the research button: a long hold on the state
## colour, then a short one back on white.
const RESEARCH_BLINK := 2.0

var _res_labels := {}
var _res_boxes := {}
var _pop_label: Label
var _fleet_label: Label
var _research_button: Button
## Green progress fill laid over the research button while a project runs.
var _research_fill: ColorRect
var _clock: Label
var _sel_body: VBoxContainer
var _messages: VBoxContainer
var _overlay: Control
var _pause: Control
var _end: Control
var _end_label: Label
var _research_modal: ColorRect
var _tech_buttons := {}
## The research screen's Defenses tab button (dev captures press it).
var _defs_tab: Button
## Layer icon per defense line (Defs.LAYER_COLORS).
const LINE_ICONS := {"shields": "icon_layer_shield", "armor": "icon_layer_armor", "hull": "icon_layer_hull"}
var _build_buttons := {}
var _queue_row: HFlowContainer
## The minimap, so orders can be issued through it (see Minimap._gui_input).
var minimap: Minimap
var _info_label: Label
var _refresh: float = 0.0
var planet_view: PlanetView
var _speed_slider: HSlider
var _speed_label: Label
var _sel_panel: PanelContainer
## Grid hotkeys for the selection panel's buttons, assigned by position as
## the panel is rebuilt: Q W E / A S D / Z X C, then V B N if a panel needs
## more. Each button shows its letter in the corner (see _register_action).
## The player can rebind them (Options > Hotkeys, ids panel1..panel12).
static func panel_keys() -> Array:
	var out: Array = []
	for i in 12:
		out.append(Defs.key_for("panel%d" % (i + 1)))
	return out
var _panel_keys := {}

## Game speed steps as the player sees them; index NORMAL_SPEED is 1x.
## One step of "1x" runs at TIME_RATE of real time, so normal play is
## half the old pace and the top step is still fast enough to watch a
## whole match (or train) quickly.
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
const TIME_RATE := 0.5
const NORMAL_SPEED := 2
## The build queue sits between the selection panel and the minimap.
const MINIMAP_W := 380.0
## Smaller than this (per minute) counts as flat, so the arrow holds still.
const TREND_DEADBAND := 1.0
## The starbase page switch always sits in this grid cell (key Z).
const PAGE_SWITCH_SLOT := 6

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
	_build_research_panel(root)
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
	# Ship art is drawn at Defs.ART_SCALE, so it shows at a matching fraction
	# of the nominal scale and keeps the size icons had before.
	var art_div: float = Defs.ART_SCALE if name.begins_with("ship_") else 1.0
	tr.custom_minimum_size = tr.texture.get_size() * scale_px / art_div
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

const TOP_BAR_WIDTH := 980
## Breathing room between the top-row panels, so each reads as its own panel.
const HUD_GAP := 26
const MENU_W := 170
const SPEED_W := 330
const RESEARCH_W := 222
const CLOCK_W := 86
const SPEED_RIGHT := -12 - MENU_W - HUD_GAP
const CLOCK_RIGHT := SPEED_RIGHT - SPEED_W - HUD_GAP
const RESEARCH_RIGHT := CLOCK_RIGHT - CLOCK_W - HUD_GAP
const TOP_BAR_RIGHT := RESEARCH_RIGHT - RESEARCH_W - HUD_GAP

func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	# Right-aligned next to the speed controls, keeping the left side of
	# the screen free for other panels.
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_right = TOP_BAR_RIGHT
	# Fixed width sized for the longest contents, so it never resizes as
	# numbers or the research status change.
	bar.offset_left = bar.offset_right - TOP_BAR_WIDTH
	bar.clip_contents = true
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = 8
	bar.add_theme_stylebox_override("panel", _panel_style(8))
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(h)
	for key in Defs.RESOURCES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.add_child(_icon("icon_" + key))
		var l := _label("0")
		# Longest realistic text: "54.3k -12.5/s".
		l.custom_minimum_size = Vector2(150 if key == "food" else 116, 0)
		l.clip_text = true
		box.add_child(l)
		_res_labels[key] = l
		_res_boxes[key] = box
		h.add_child(box)
	_pop_label = _label("Pop 0", TEXT)
	_pop_label.custom_minimum_size = Vector2(84, 0)
	_pop_label.clip_text = true
	_pop_label.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(_pop_label)
	var fleet := HBoxContainer.new()
	fleet.add_theme_constant_override("separation", 6)
	fleet.add_child(_icon("icon_fleet"))
	_fleet_label = _label("0/0")
	_fleet_label.custom_minimum_size = Vector2(196, 0)
	_fleet_label.clip_text = true
	fleet.add_child(_fleet_label)
	h.add_child(fleet)

## Research button and match clock, in their own panel between the resource
## bar and the speed controls.
func _build_research_panel(root: Control) -> void:
	# The research button stands on its own, like the Menu button; the match
	# clock gets its own small panel beside it.
	_research_button = Button.new()
	_research_button.text = "Research [R]"
	_research_button.clip_text = true
	_research_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_research_button.add_theme_font_size_override("font_size", 13)
	_research_button.focus_mode = Control.FOCUS_NONE
	_research_button.anchor_left = 1.0
	_research_button.anchor_right = 1.0
	_research_button.offset_right = RESEARCH_RIGHT
	_research_button.offset_left = RESEARCH_RIGHT - RESEARCH_W
	_research_button.offset_top = 8
	_research_button.offset_bottom = 8 + 46
	_research_button.pressed.connect(toggle_research)
	root.add_child(_research_button)
	# Progress shows as a green bar growing left to right across the button.
	_research_fill = ColorRect.new()
	_research_fill.color = Color(GOOD.r, GOOD.g, GOOD.b, 0.3)
	_research_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_fill.visible = false
	_research_fill.anchor_left = 1.0
	_research_fill.anchor_right = 1.0
	_research_fill.offset_top = 10
	_research_fill.offset_bottom = 8 + 44
	root.add_child(_research_fill)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_right = CLOCK_RIGHT
	panel.offset_left = CLOCK_RIGHT - CLOCK_W
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 8
	panel.add_theme_stylebox_override("panel", _panel_style(8))
	root.add_child(panel)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(h)
	_clock = _label("00:00", DIM)
	_clock.custom_minimum_size = Vector2(50, 0)
	h.add_child(_clock)

## Top-right Menu button: opens the same menu as Esc (Resume, Save Game,
## Options, Quit to Title).
func _build_menu_button(root: Control) -> void:
	var b := Button.new()
	b.text = "Menu [Esc]"
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -12 - MENU_W
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
	panel.offset_left = SPEED_RIGHT - SPEED_W
	panel.offset_right = SPEED_RIGHT
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
	Engine.time_scale = 0.0 if game_paused else s * TIME_RATE
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
	panel.offset_bottom = -12
	panel.offset_top = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)
	_sel_body = VBoxContainer.new()
	_sel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_body.add_theme_constant_override("separation", 8)
	panel.add_child(_sel_body)
	# A starbase's build queue sits along the bottom, between the selection
	# panel and the minimap, and wraps when the queue is long.
	_queue_row = HFlowContainer.new()
	_queue_row.add_theme_constant_override("h_separation", 6)
	_queue_row.add_theme_constant_override("v_separation", 6)
	_queue_row.alignment = FlowContainer.ALIGNMENT_BEGIN
	_queue_row.custom_minimum_size = Vector2(0, 0)
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
	minimap = mm
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

func _build_help(_root: Control) -> void:
	pass   # the controls line lived here; the build queue uses that space now

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
	for pair in [["Resume", func(): show_pause(false)], ["Save Game", func(): game.save_game()], ["Codex", open_codex], ["Options", func(): OptionsMenu.open()], ["Quit to Title", _quit_to_title]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		MenuStyle.button(b)
		v.add_child(b)

func _build_end(root: Control) -> void:
	var parts := _modal(root, "")
	_end = parts[0]
	_end_label = parts[2]
	for pair in [["View Stats", func(): _show_stats(true)], ["View Map", _enter_map_view], ["Return to Title", _quit_to_title]]:
		var b := Button.new()
		b.text = pair[0]
		MenuStyle.button(b)
		b.pressed.connect(pair[1])
		parts[1].add_child(b)
	_build_map_bar(root)
	_build_stats(root)

# ---------------------------------------------------------------- research tree

## Research screen: four tabs — Weapons, Defense, Economy and General —
## each laid out by tier. Defense is a grid of its three lines (shields,
## armor, hull). Only one project runs at a time.
## Every research tab is this size, so the panel never jumps when you
## switch between War Ships, Weapons, Defense and Economy.
const PAGE_SIZE := Vector2(1320, 560)

func _build_research(root: Control) -> void:
	var parts := _modal(root, "RESEARCH", 1400.0)
	_research_modal = parts[0]
	_research_modal.color = Color(0, 0, 0, 0.45)
	# Clicking the dimmed area outside the panel closes the screen (Esc too).
	_research_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_research_modal.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			toggle_research()
			_research_modal.accept_event())
	var v: VBoxContainer = parts[1]
	v.add_child(_label("One project at a time. Costs are paid gradually while researching; progress pauses when you can't pay (spice covers energy shortfalls).\nClick a tech to start it; click the active one to cancel it.", DIM, 13))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 10)
	for s in ["done", "active", "available", "locked"]:
		var chip := ColorRect.new()
		chip.color = STATE_COLORS[s].lightened(0.2)
		chip.custom_minimum_size = Vector2(14, 14)
		legend.add_child(chip)
		legend.add_child(_label(STATE_LABELS[s].capitalize() + "   ", TEXT, 13))
	v.add_child(legend)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	# One line saying what the open tab is for (Defs.TECH_GROUP_DESC).
	var blurb := _label("", DIM, 14)
	blurb.custom_minimum_size = Vector2(0, 22)
	v.add_child(blurb)
	var pages := {}

	# Weapons, Economy and anything ungrouped: columns by tier.
	for group in ["weapons", "constructs", "worlds", "logistics", "general"]:
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 18)
		cols.custom_minimum_size = PAGE_SIZE
		cols.visible = false
		v.add_child(cols)
		var any := false
		for tier in [1, 2, 3]:
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 10)
			col.add_child(_label("TIER %d" % tier, DIM, 14))
			for id in Defs.TECHS:
				if Defs.TECHS[id]["tier"] == tier and Defs.TECHS[id].get("group", "general") == group:
					col.add_child(_tech_button(id))
					any = true
			cols.add_child(col)
		if any:
			pages[group] = cols
		else:
			cols.queue_free()

	# War Ships: unlocks along the top, then one row per class of the marks
	# that make that class stronger (Defs.HULL_MARKS).
	var wars := GridContainer.new()
	wars.columns = 4
	wars.custom_minimum_size = PAGE_SIZE
	wars.add_theme_constant_override("h_separation", 18)
	wars.add_theme_constant_override("v_separation", 10)
	wars.visible = false
	v.add_child(wars)
	wars.add_child(_label("UNLOCKS", DIM, 14))
	for id in ["destroyers", "cruisers", "depots"]:
		wars.add_child(_tech_button(id, 300.0))
	for cls in Defs.MARK_LINES:
		var head := VBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.custom_minimum_size = Vector2(90, 0)
		head.add_child(_label(Defs.SHIPS[cls]["name"].to_upper(), TEXT, 16))
		wars.add_child(head)
		for mk in [2, 3, 4]:
			wars.add_child(_tech_button("%s_mk%d" % [cls, mk], 300.0))
	pages["warships"] = wars

	# Defense: one row per layer line, one column per tier.
	var defs := GridContainer.new()
	defs.columns = 4
	defs.add_theme_constant_override("h_separation", 18)
	defs.add_theme_constant_override("v_separation", 10)
	defs.custom_minimum_size = PAGE_SIZE
	defs.visible = false
	v.add_child(defs)
	defs.add_child(_label("", DIM, 14))
	for tier in [1, 2, 3]:
		defs.add_child(_label("TIER %d" % tier, DIM, 14))
	for line in [["shields", "SHIELDS", Defs.LAYER_COLORS["shield"]], ["armor", "ARMOR", Defs.LAYER_COLORS["armor"]], ["hull", "HULL", Defs.LAYER_COLORS["hull"]]]:
		var head := VBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.custom_minimum_size = Vector2(90, 0)
		head.add_child(_icon(LINE_ICONS[line[0]], 3))
		head.add_child(_label(line[1], line[2], 18))
		defs.add_child(head)
		for tier in [1, 2, 3]:
			for id in Defs.TECHS:
				if Defs.TECHS[id].get("line", "") == line[0] and Defs.TECHS[id]["tier"] == tier:
					defs.add_child(_tech_button(id, 300.0))
	pages["defense"] = defs

	var order := [["warships", "War Ships"], ["weapons", "Weapons"], ["defense", "Defense"], ["constructs", "Constructs"], ["worlds", "Worlds"], ["logistics", "Logistics"], ["general", "General"]]
	var buttons := {}
	for pair in order:
		if not pages.has(pair[0]):
			continue
		var tb := Button.new()
		tb.text = pair[1]
		tb.toggle_mode = true
		tb.button_pressed = pair[0] == "warships"
		if pair[0] == "warships":
			pages["warships"].visible = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(132, 32)
		tabs.add_child(tb)
		buttons[pair[0]] = tb
	for id in buttons:
		var b: Button = buttons[id]
		b.pressed.connect(func():
			for other in pages:
				pages[other].visible = other == id
				buttons[other].button_pressed = other == id
			blurb.text = Defs.TECH_GROUP_DESC.get(id, "")
			_defs_tab = buttons.get("defense"))
	_defs_tab = buttons.get("defense")
	blurb.text = Defs.TECH_GROUP_DESC.get("warships", "")
	var close := Button.new()
	close.text = "Close [R]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_research)
	v.add_child(close)

func show_planet(p: Planet) -> void:
	# No close-up of the buildings on a planet out of sensor range.
	if p and not p.in_sight:
		p = null
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
			line += ", STALLED: insufficient funds"
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
		w["bar"].offset_right = -2 - (1.0 - frac) * (w["button"].custom_minimum_size.x - 4.0)
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
	_won = won
	_end_label.text = "VICTORY" if won else "DEFEAT"
	_end_label.add_theme_color_override("font_color", GOOD if won else Color("ff4f5e"))
	_end.visible = true

# ---------------------------------------------------------------- selection panel

func _rebuild_selection() -> void:
	_sel_panel.visible = not (game.selection.filter(func(e): return is_instance_valid(e)).is_empty() and is_instance_valid(game.focused_planet))
	for c in _sel_body.get_children():
		c.queue_free()
	_panel_keys.clear()
	for c in _sel_body.get_children():
		c.queue_free()
	_build_buttons.clear()
	for c in _queue_row.get_children():
		c.free()
	_queue_row.visible = false
	_info_label = null
	var sel: Array = game.selection.filter(func(e): return is_instance_valid(e))
	if sel.is_empty() and is_instance_valid(game.focused_asteroid):
		_build_asteroid_panel(game.focused_asteroid)
		return
	if sel.is_empty() and is_instance_valid(game.focused_star):
		_build_star_panel(game.focused_star)
		return
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
			elif e is WeaponsDepot:
				_build_depot_panel(e)
		return
	var counts := {}
	for e in sel:
		var k: String = e.ship_type if e is Ship else ("depot_" + (e as WeaponsDepot).variant if e is WeaponsDepot else "starbase")
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
		_add_constructor_buttons()
	_add_refit_buttons(sel)

func _entity_icon(e: SpaceEntity, px: int) -> Control:
	var tex_name := "starbase"
	if e is WeaponsDepot:
		tex_name = "ship_depot_" + (e as WeaponsDepot).variant
	elif e is MiningStation:
		tex_name = "ship_mining_station"
	elif e is Ship:
		tex_name = "ship_" + (e as Ship).ship_type
	var stack := Control.new()
	var base := _icon(tex_name, px)
	var team := _icon(tex_name + "_team", px)
	team.modulate = Defs.team_color(e.owner_id)
	stack.custom_minimum_size = base.custom_minimum_size
	stack.add_child(base)
	stack.add_child(team)
	return stack

func _build_ship_controls(s: Ship) -> void:
	_add_job_panel(s)
	_add_refit_buttons([s])
	match s.def["role"]:
		"colony":
			_sel_body.add_child(_label("Right-click an unowned planet to settle it with %d pops." % int(Defs.START_POP), DIM, 13))
		"constructor":
			_add_constructor_buttons()
		"miner":
			_sel_body.add_child(_label("Right-click an asteroid to mine it. Orange-flecked rocks hold spice.", DIM, 13))
		"skimmer":
			_sel_body.add_child(_label("Right-click a gas giant to mine minerals, or a spot inside a spice nebula to slowly harvest spice gas (never runs out).", DIM, 13))


## The panel's standard build button, as the starbase has always drawn one:
## sprite on the left, name and cost stacked beside it, hotkey letter in the
## corner (stamped by _register_action). Every agent uses this, so a
## Constructor's starbase/station/depot buttons read like a starbase's hulls.
const PANEL_BTN := Vector2(198, 62)

func _panel_build_button(tex: String, title: String, cost: Dictionary, seconds: float, tip: String, name_color: Color = TEXT) -> Button:
	var b := Button.new()
	b.custom_minimum_size = PANEL_BTN
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s — %s over %ds.
%s" % [title, Defs.cost_text(cost), int(seconds), tip] if seconds > 0.0 else tip
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.add_theme_constant_override("separation", 12)
	# One icon box whatever the sprite size, so a starbase and a corvette
	# sit in the same button.
	var art := _icon(tex, 1)
	art.custom_minimum_size = Vector2(46, 46)
	h.add_child(art)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_label(title, name_color, 13))
	v.add_child(CostRow.make(cost, 12, -1.0, 1))
	h.add_child(v)
	b.add_child(h)
	return b

## The grid every panel of buttons uses, three across like the starbase.
func _button_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	return g


## The starbase panel has two pages: the economy ships it builds most of the
## time, and the warships behind a button (see _build_starbase_controls).
var _sb_page := "war" if OS.get_environment("SL_SB_PAGE") == "war" else "eco"

func _build_starbase_controls(sb: Starbase) -> void:
	var war: Array = Defs.BUILD_ORDER.filter(func(t): return Defs.SHIPS[t]["role"] == "warship")
	var eco: Array = Defs.BUILD_ORDER.filter(func(t): return Defs.SHIPS[t]["role"] != "warship")
	# 3x3 at most: eight hulls and the page switch.
	var page: Array = (war if _sb_page == "war" else eco).slice(0, 8)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for t in page:
		var d: Dictionary = Defs.SHIPS[t]
		var b := Button.new()
		b.custom_minimum_size = Vector2(198, 62)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s\nShield %d  Armor %d  Hull %d  Speed %d\nUpkeep %.0f energy/min base (scales with fleet size)\nCost %s, paid over %ds" % [game.ship_name(game.player_id, t), d["shield"], d.get("armor", 0), d["hp"], d["speed"], d["upkeep"], Defs.cost_text(d["cost"]), d["build_time"]]
		if d.has("variant"):
			b.tooltip_text += "\n" + Defs.VARIANTS[d["variant"]]["desc"]
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 6
		h.add_theme_constant_override("separation", 12)
		h.add_child(_icon("ship_" + t, 2))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_label(game.ship_name(game.player_id, t), Defs.VARIANTS[d["variant"]]["color"] if d.has("variant") else TEXT, 13))
		v.add_child(CostRow.make(d["cost"], 12, -1.0, 1))
		h.add_child(v)
		b.add_child(h)
		b.pressed.connect(func(): game.request_build(sb, t))
		_register_action(b)
		grid.add_child(b)
		_build_buttons[t] = b
	# Pad so the page switch always lands in the same cell (and on the same
	# key) whichever page is open.
	while grid.get_child_count() < PAGE_SWITCH_SLOT:
		var gap := Control.new()
		gap.custom_minimum_size = PANEL_BTN
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skip_action()
		grid.add_child(gap)
	var flip := Button.new()
	flip.custom_minimum_size = PANEL_BTN
	flip.focus_mode = Control.FOCUS_NONE
	flip.text = "< Economy" if _sb_page == "war" else "Military >"
	flip.add_theme_color_override("font_color", GOOD)
	flip.add_theme_color_override("font_hover_color", GOOD.lightened(0.3))
	flip.tooltip_text = "Switch to the %s ships the starbase can build." % ("economy" if _sb_page == "war" else "military")
	flip.pressed.connect(func():
		_sb_page = "eco" if _sb_page == "war" else "war"
		_rebuild_selection())
	_register_action(flip)
	grid.add_child(flip)
	_sel_body.add_child(grid)
	_queue_row.visible = true

func _build_star_panel(s: Star) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var ic := _icon(Defs.STAR_TYPES[s.star_type]["tex"], 1)
	ic.custom_minimum_size = Vector2(64, 64)
	head.add_child(ic)
	var col := VBoxContainer.new()
	col.add_child(_label("%s  ·  %s" % [s.star_name, s.type_label()], s.tint, 20))
	col.add_child(_label("Uninhabitable. Can't be mined.", TEXT, 14))
	head.add_child(col)
	_sel_body.add_child(head)
	_sel_body.add_child(_label("Radiation: ships and stations within %d px take damage, rising sharply closer in, up to %d/s on contact with the surface (shields absorb it first)." % [int(s.radiation_radius), int(s.max_dps)], Color("ff8a6a"), 13))
	_sel_body.add_child(_label("Future research may allow harvesting energy from stars.", DIM, 12))
	for l in _sel_body.get_children():
		if l is Label:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_asteroid_panel(a: Asteroid) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var ic := _icon(a.variant, 3)
	head.add_child(ic)
	var col := VBoxContainer.new()
	col.add_child(_label(a.display_name(), Defs.RESOURCE_COLORS[a.resource], 20))
	_info_label = _label("")
	col.add_child(_info_label)
	head.add_child(col)
	_sel_body.add_child(head)
	_sel_body.add_child(_label("Right-click with Mining Barges selected to mine it. Barges haul each load to a starbase.", DIM, 12))

func _build_planet_panel(p: Planet) -> void:
	var t := p.type_def()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var ic := _icon(p.kind, 1)
	ic.custom_minimum_size = Vector2(56, 56)
	head.add_child(ic)
	var col := VBoxContainer.new()
	# Out of sensor range the owner is only the last one seen (fog of war).
	var so := p.shown_owner()
	var owner_text := "Unclaimed" if so == 0 else ("Yours" if so == game.player_id else "Enemy")
	if not p.in_sight:
		owner_text += "  (last seen: out of sensor range)"
	col.add_child(_label(("%s  ·  %s  ·  Size %d" % [p.planet_name, t["label"], p.fields]) if p.fields > 0 else "%s  ·  %s" % [p.planet_name, t["label"]], Defs.team_color(so), 20))
	col.add_child(_label(owner_text, DIM, 14))
	head.add_child(col)
	_sel_body.add_child(head)
	_info_label = _label("")
	_sel_body.add_child(_info_label)

func _update_selection_info() -> void:
	_refresh_ability_button()
	if _info_label == null:
		return
	var sel: Array = game.selection.filter(func(e): return is_instance_valid(e))
	if sel.is_empty() and is_instance_valid(game.focused_asteroid):
		var a := game.focused_asteroid
		_info_label.text = "%s left: %d / %d  (%d%%)
Your barges mining it: %d" % [Defs.RESOURCE_NAMES[a.resource], a.amount, a.max_amount, int(100.0 * a.amount / maxf(a.max_amount, 1)), a.miners_on(game.player_id)]
		return
	if sel.is_empty() and is_instance_valid(game.focused_planet):
		if not game.focused_planet.in_sight:
			_info_label.text = "Out of sensor range: population, buildings and defenses unknown."
			return
		planet_view.refresh()
		_info_label.text = planet_view.stats
		return
	if sel.size() != 1:
		return
	var e: SpaceEntity = sel[0]
	# Defense layers in the order damage takes them: shields, armor, hull.
	var txt := ""
	if e.max_shield > 0:
		txt += "Shield %d/%d   " % [ceili(e.shield), e.max_shield]
	if e.max_armor > 0:
		txt += "Armor %d/%d   " % [ceili(e.armor), e.max_armor]
	txt += "Hull %d/%d" % [ceili(e.hp), e.max_hp]
	if e is Ship:
		var s := e as Ship
		txt += "\n" + ["Idle", "Moving", "Engaging", "Attack-moving", "En route to mine", "Mining", "Returning cargo", "Colonizing", "Flying to build site", "Bombarding planet", "Refitting at Weapons Depot"][s.state]
		if s.is_miner():
			txt += "   Cargo %d/%d %s" % [s.cargo, s.cargo_cap(), s.cargo_type]
		elif s.def["weapon"] != "":
			txt += "   %s %.0f dmg / %.1fs" % [s.def["weapon"].capitalize(), s.def["damage"] * game.mod(e.owner_id, "damage") * (1.0 + game.mark_level(e.owner_id, s.ship_type) * float(Defs.MARK_STEP["damage"])), s.def["cooldown"]]
		txt += "   Upkeep %.1f/min" % (s.def["upkeep"] * game.upkeep_multiplier(s.owner_id))
		if not s.order_queue.is_empty():
			txt += "\n%d queued order%s (Shift + right-click to add, T clears)" % [s.order_queue.size(), "" if s.order_queue.size() == 1 else "s"]
	elif e is Starbase:
		var sb := e as Starbase
		txt += "
Starbases %d · upkeep %.1f/s each (x%.1f)" % [game.starbase_count(sb.owner_id), Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(sb.owner_id), game.starbase_upkeep_multiplier(sb.owner_id)]
		if sb.under_construction:
			txt += "\nConstruction %d%%%s" % [int(100.0 * sb.construct_progress / Defs.STARBASE["build_time"]), "  STALLED: insufficient funds" if sb.build_stalled else ""]
		elif not sb.queue.is_empty():
			var d: Dictionary = Defs.SHIPS[sb.queue[0]]
			txt += "\nBuilding %s %d%%%s" % [d["name"], int(100.0 * sb.build_progress / d["build_time"]), "  STALLED: insufficient funds" if sb.build_stalled else ""]
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
				qb.tooltip_text = "Cancel " + game.ship_name(sb.owner_id, sb.queue[i])
				var idx := i
				qb.pressed.connect(func(): sb.cancel(idx))
				_queue_row.add_child(qb)
		if sb.queue.size() > 0 and _queue_row.get_child_count() > 0:
			var first: Button = _queue_row.get_child(0)
			first.text = "%d%%" % int(100.0 * sb.build_progress / Defs.SHIPS[sb.queue[0]]["build_time"])
			first.modulate = Color(1, 0.6, 0.55) if sb.build_stalled else Color.WHITE
			# Readable over the ship icon behind it.
			first.add_theme_font_size_override("font_size", 16)
			first.add_theme_color_override("font_color", Color.WHITE)
			first.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			first.add_theme_constant_override("outline_size", 6)

func _planet_text(p: Planet) -> String:
	var t := p.type_def()
	if not p.is_habitable():
		return "Uninhabitable gas giant · %s\nGas Skimmers mine it and haul the minerals to a starbase." % [("DEPLETED, refills in %ds" % int(p.depleted_timer)) if p.depleted_timer > 0.0 else "Mineral reserve %d" % p.amount]
	if p.owner_id == 0:
		return "Size %d · Pop cap %s%s\nSend a Colony Ship (right-click) to settle it." % [p.fields, _fmt(p.max_pop()), (" · Spice %.1f/min" % t["spice"]) if t["spice"] > 0.0 else ""]
	var lines := "Population %s / %s   (+%s/min)" % [_fmt(p.pop), _fmt(p.max_pop()), _fmt(p.growth_per_min)]
	lines += "\nFood: grown %.1f/min · eaten %.1f/min · net %+.1f/min" % [p.food_made_per_min, p.food_eaten_per_min, p.food_made_per_min - p.food_eaten_per_min]
	lines += "\nEnergy %.0f/min%s" % [p.energy_out, ("   Spice %.1f/min" % p.spice_out) if p.spice_out > 0.0 else ""]
	if p.starving:
		lines += "\nSTARVING: shrinking %d/min until food recovers" % int(-p.growth_per_min)
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
	_flashes = _flashes.filter(func(f): return is_instance_valid(f["node"]) and Time.get_ticks_msec() / 1000.0 - f["real"] < FLASH_TIME)
	_overlay.queue_redraw()

func _update_top_bar() -> void:
	var pid := game.player_id
	var r: Dictionary = game.resources.get(pid, {})
	var rt: Dictionary = game.rates.get(pid, {})
	for k in Defs.RESOURCES:
		var rate: float = rt.get(k, 0.0)
		# The stockpile, then an arrow for which way it is going. The arrow
		# follows the last minute's average, so one delivery cannot flip it.
		var avg: float = game.avg_rate(pid, k)
		var arrow := "–"
		var arrow_color := DIM
		if avg > TREND_DEADBAND:
			arrow = "▲"
			arrow_color = GOOD
		elif avg < -TREND_DEADBAND:
			arrow = "▼"
			arrow_color = BAD
		_res_labels[k].text = "%s %s" % [_fmt(r.get(k, 0.0)), arrow]
		_res_labels[k].add_theme_color_override("font_color", arrow_color if arrow != "–" else TEXT)
		_res_boxes[k].tooltip_text = "%s: %d stockpiled, %+.0f/min on average over the last minute (%+.0f/min right now)." % [
			Defs.RESOURCE_NAMES[k], int(r.get(k, 0.0)), avg, rate * Defs.PER_MIN]
	if game.energy_starved(pid):
		_res_labels["energy"].add_theme_color_override("font_color", BAD)
		_res_labels["energy"].text += "  NO ENERGY"
	_res_boxes["spice"].tooltip_text += "\nSpice automatically covers shortfalls of food, minerals and energy (1:1)."
	_res_boxes["energy"].tooltip_text += "\nUpkeep: %.1f/s for ships and starbases%s" % [game.upkeep(pid), "
OUT OF ENERGY: ship production halted, ships at 25%% speed" if game.energy_starved(pid) else ""]
	_pop_label.text = "Pop %s" % _fmt(game.total_pop(pid))
	_pop_label.tooltip_text = "Population across your worlds. Each pop eats %.2f food per minute." % Defs.FOOD_PER_POP_PER_MIN
	_fleet_label.text = "%d ships · upkeep x%.2f" % [game.ship_count(pid), game.upkeep_multiplier(pid)]
	_fleet_label.tooltip_text = "Each ship's energy upkeep is multiplied by 1 + (ships / %d)^2. Starbases scale separately: x%.1f with %d starbases.
Total ship+starbase upkeep: %.0f energy/min." % [int(Defs.UPKEEP_SCALE_SHIPS), game.starbase_upkeep_multiplier(pid), game.starbase_count(pid), game.upkeep(pid)]
	_fleet_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var cur: Dictionary = game.research[pid]
	# The button blinks in real time, so it looks the same at any game speed:
	# yellow when nothing is queued, green while researching, red when stalled.
	# A long hold on the state colour, then a short one back on white.
	var phase: float = fmod(Time.get_ticks_msec() / 1000.0, RESEARCH_BLINK)
	var glow := 1.0 if phase < RESEARCH_BLINK * 0.7 else 0.0
	if cur.is_empty():
		_research_button.text = "Research [R]"
		_research_button.modulate = Color.WHITE.lerp(Color("ffd46b"), glow)
		_research_fill.visible = false
	else:
		var t: Dictionary = Defs.TECHS[cur["id"]]
		# The label stays short enough to fit: project name and percentage only.
		var frac: float = clampf(cur["progress"] / t["time"], 0.0, 1.0)
		_research_button.text = "%s %d%%" % [t["name"], int(100.0 * frac)]
		_research_button.tooltip_text = "%s: %d%% complete.%s" % [t["name"], int(100.0 * frac), "\nSTALLED: not enough resources to keep paying for it." if cur["stalled"] else ""]
		# Running: no blink, the green fill carries the progress. Stalled: the
		# button blinks red and the fill freezes where it stopped.
		_research_button.modulate = Color.WHITE.lerp(BAD, 0.35 + 0.65 * glow) if cur["stalled"] else Color.WHITE
		_research_fill.visible = true
		_research_fill.offset_left = RESEARCH_RIGHT - RESEARCH_W + 2
		_research_fill.offset_right = RESEARCH_RIGHT - RESEARCH_W + 2 + (RESEARCH_W - 4) * frac
		_research_fill.color = Color(BAD.r, BAD.g, BAD.b, 0.3) if cur["stalled"] else Color(GOOD.r, GOOD.g, GOOD.b, 0.3)
	var s := int(Game.now())
	_clock.text = "%02d:%02d" % [s / 60, s % 60]

## Shrink-wraps the bottom-left panel to its contents (it grows upward) and
## parks the build queue row just above it.
func _fit_selection_panel() -> void:
	_sel_panel.size = Vector2.ZERO
	_sel_panel.position.y = _sel_panel.get_parent_area_size().y - 12.0 - _sel_panel.size.y
	if _queue_row.visible:
		# Bottom strip: starts just right of the panel, stops at the minimap.
		var area := _queue_row.get_parent_area_size()
		var left: float = _sel_panel.position.x + _sel_panel.size.x + 12.0
		_queue_row.size = Vector2(maxf(area.x - MINIMAP_W - left, 200.0), 0.0)
		_queue_row.position = Vector2(left, area.y - 12.0 - _queue_row.size.y)

func set_drag_rect(r: Rect2) -> void:
	_drag_rect = r

## kind: "attack" (red), "colonize" (green), anything else (white).
func flash_target(node: Node2D, kind: String) -> void:
	if is_instance_valid(node):
		var c: Color = {"attack": Color("ff4a4a"), "colonize": Color("6fe07a")}.get(kind, Color.WHITE)
		_flashes.append({"node": node, "real": Time.get_ticks_msec() / 1000.0, "color": c})

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
	# Placing a construct: its hull and the ring of clear space it needs
	# (Defs.PLACEMENT_RING), green where it fits and red where it does not.
	var placing := ""
	if game.placing_starbase:
		placing = "starbase"
	elif game.placing_depot:
		placing = "depot"
	elif game.placing_station:
		placing = "station"
	if placing != "":
		var wp := game.get_global_mouse_position()
		var z := game.camera.zoom.x
		var c := GOOD if game.site_problem(placing, wp) == "" else BAD
		var sp: Vector2 = xf * wp
		_overlay.draw_arc(sp, float(Defs.construct_def(placing)["radius"]) * z, 0, TAU, 48, c, 2.0)
		_overlay.draw_arc(sp, Defs.placement_ring(placing) * z, 0, TAU, 96, Color(c, 0.35), 1.0)
	# Target flashes: a ring with corner brackets, blinking twice.
	var real_now := Time.get_ticks_msec() / 1000.0
	for f in _flashes:
		var age: float = real_now - f["real"]
		if age > FLASH_TIME:
			continue
		# Two flashes: on, off, on, off.
		if int(age / (FLASH_TIME / 4.0)) % 2 == 1:
			continue
		var node: Node2D = f["node"]
		var r: float = node.get("radius") if node.get("radius") != null else 12.0
		var center: Vector2 = xf * node.global_position
		var sr := (r + 6.0) * game.camera.zoom.x
		_overlay.draw_arc(center, sr, 0.0, TAU, 48, f["color"], 3.0)
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var c: Vector2 = center + d * sr * 0.9
			_overlay.draw_line(c, c - Vector2(d.x * 8.0, 0), f["color"], 2.0)
			_overlay.draw_line(c, c - Vector2(0, d.y * 8.0), f["color"], 2.0)
	var now := Game.now()
	for p in _pings:
		var k: float = (now - p["t"]) / 0.5
		var sp: Vector2 = xf * p["pos"]
		var r := 4.0 + k * 14.0
		var c: Color = p["color"]
		c.a = 1.0 - k
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_overlay.draw_rect(Rect2(sp + d * (18.0 - r) - Vector2(2, 2), Vector2(4, 4)), c)

# ---------------------------------------------------------------- post-game

var _map_bar: Control
var _map_bar_label: Label
var _stats_modal: Control
var _stats_body: VBoxContainer
var _won := false

## The small bar shown at the top while looking at the map after the match.
func _build_map_bar(root: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(10, EDGE_LIT))
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 70
	p.visible = false
	root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	_map_bar_label = _label("", Color.WHITE, 18)
	_map_bar_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_map_bar_label)
	for pair in [["View Stats", func(): _show_stats(true)], ["Return to Title", _quit_to_title]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		h.add_child(b)
	_map_bar = p

func _enter_map_view() -> void:
	_end.visible = false
	game.map_view = true
	_map_bar_label.text = ("VICTORY" if _won else "DEFEAT") + "  -  viewing the system (select to inspect)"
	_map_bar_label.add_theme_color_override("font_color", GOOD if _won else Color("ff4f5e"))
	_map_bar.visible = true

func _build_stats(root: Control) -> void:
	var parts := _modal(root, "MATCH STATS", 1400.0)
	_stats_modal = parts[0]
	_stats_body = VBoxContainer.new()
	_stats_body.add_theme_constant_override("separation", 14)
	parts[1].add_child(_stats_body)
	var b := Button.new()
	b.text = "Back"
	MenuStyle.button(b)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): _show_stats(false))
	parts[1].add_child(b)

## Opens (fills) or closes the Stats window; closing returns to the end
## screen, or to the map if the player was viewing it.
func _show_stats(on: bool) -> void:
	_stats_modal.visible = on
	if not on:
		_end.visible = not game.map_view
		return
	_end.visible = false
	for c in _stats_body.get_children():
		c.queue_free()
	var st: MatchStats = game.stats
	var me: int = game.player_id
	var foe: int = 3 - me
	var mins := int(Game.now() / 60.0)
	var sys: Dictionary = SystemGen.find(GameState.system_id)
	var sub := _label("%s  -  %s  -  %d:%02d" % ["VICTORY" if _won else "DEFEAT", sys.get("name", "Unknown system"), mins, int(Game.now()) % 60],
		GOOD if _won else Color("ff4f5e"), 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_body.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_stats_body.add_child(row)
	# Summary table: stat | you | enemy.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	grid.add_child(_label("", DIM))
	grid.add_child(_label("You", Defs.team_color(me), 18))
	grid.add_child(_label("Enemy", Defs.team_color(foe), 18))
	var lines := [
		["Ships built", func(p): return st.get_count(p, "ships_built")],
		["Ships lost", func(p): return st.get_count(p, "ships_lost")],
		["Enemy ships destroyed", func(p): return st.get_count(3 - p, "ships_lost")],
		["Worlds colonized / taken", func(p): return st.get_count(p, "planets_won")],
		["Worlds lost", func(p): return st.get_count(p, "planets_lost")],
		["Starbases lost", func(p): return st.get_count(p, "starbases_lost")],
		["Peak worlds", func(p): return st.peak(p, "worlds")],
		["Peak population", func(p): return st.peak(p, "pop")],
		["Peak warships", func(p): return st.peak(p, "warships")],
		["Technologies researched", func(p): return game.researched[p].size()],
	]
	for l in lines:
		grid.add_child(_label(l[0], TEXT))
		for p in [me, foe]:
			var v := _label(str(l[1].call(p)), Color.WHITE)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(v)
	# Charts over time.
	var charts := GridContainer.new()
	charts.columns = 2
	charts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	charts.add_theme_constant_override("h_separation", 16)
	charts.add_theme_constant_override("v_separation", 16)
	row.add_child(charts)
	for c in [["Worlds", "worlds"], ["Population", "pop"], ["Warships", "warships"], ["Fleet strength", "power"]]:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(_label(c[0], TEXT, 15))
		var ch := StatChart.new()
		ch.samples = st.samples
		ch.field = c[1]
		ch.sides = [[me, Defs.team_color(me)], [foe, Defs.team_color(foe)]]
		ch.custom_minimum_size = Vector2(390, 150)
		box.add_child(ch)
		charts.add_child(box)

## A small line chart of one sampled field for both sides over the match.
class StatChart extends Control:
	var samples: Array = []
	var field := ""
	var sides: Array = []   # [[pid, color], ...]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.09, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color("2b3a6b"), false, 1.0)
		if samples.size() < 2:
			return
		var t_max: float = maxf(samples[-1]["t"], 1.0)
		var v_max := 1.0
		for s in samples:
			for sd in sides:
				v_max = maxf(v_max, float(s[str(sd[0])][field]))
		var font := get_theme_default_font()
		draw_string(font, Vector2(4, 13), str(int(v_max)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("6a7596"))
		draw_string(font, Vector2(size.x - 44, size.y - 4), "%d min" % int(t_max / 60.0), HORIZONTAL_ALIGNMENT_RIGHT, 40, 11, Color("6a7596"))
		var pad := Vector2(6, 18)
		var area := size - pad * 2.0
		for sd in sides:
			var pts := PackedVector2Array()
			for s in samples:
				var x: float = pad.x + area.x * float(s["t"]) / t_max
				var y: float = pad.y + area.y * (1.0 - float(s[str(sd[0])][field]) / v_max)
				pts.append(Vector2(x, y))
			draw_polyline(pts, sd[1], 2.0, true)

# ---------------------------------------------------------------- jobs

var _ability_button: Button
var _ability_ship: Ship

## A ship's job: its name in the job's color, what it does, and for active
## jobs a Q button showing the recharge.
func _add_job_panel(s: Ship) -> void:
	_ability_button = null
	# Weapon profile vs the defense layers (see Defs.VARIANTS).
	if s.def["weapon"] != "":
		if s.def.has("variant"):
			var vd: Dictionary = Defs.VARIANTS[s.def["variant"]]
			_sel_body.add_child(_label("Weapons: %s. %s" % [vd["label"], vd["desc"]], vd["color"], 13))
		else:
			_sel_body.add_child(_label("Weapons: Generalist. Full damage to shields, armor and hull.", DIM, 13))
	var jid: String = s.def.get("job", "")
	if jid == "":
		return
	var j: Dictionary = Defs.JOBS[jid]
	var head := _label("Job: " + j["name"], j["color"], 15)
	_sel_body.add_child(head)
	var d := _label(j["desc"], DIM, 13)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(560, 0)
	_sel_body.add_child(d)
	if j.get("active", false):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_color_override("font_color", j["color"])
		b.pressed.connect(game.use_abilities)
		_register_action(b)
		_sel_body.add_child(b)
		_ability_button = b
		_ability_ship = s
		_refresh_ability_button()

func _refresh_ability_button() -> void:
	if _ability_button == null or not is_instance_valid(_ability_ship):
		return
	var j: Dictionary = Defs.JOBS[_ability_ship.def["job"]]
	var wait := Abilities.ready_in(_ability_ship)
	var name: String = {"beacon": "Drop Beacon", "field_repair": "Emergency Repair"}.get(_ability_ship.def["job"], j["name"])
	_ability_button.text = name if wait <= 0.0 else ("%s: recharging %ds" % [name, int(ceil(wait))])
	_ability_button.disabled = wait > 0.0

## One research button: name/status line, cost with resource icons, effect,
## and a progress bar along the bottom (see _refresh_research).
func _tech_button(id: String, width: float = 340.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 100)
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): game.request_research(id); _refresh_research())
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
	# Defense-line techs lead with their layer's icon, in the layer color.
	var line: String = Defs.TECHS[id].get("line", "")
	if line != "":
		var title := HBoxContainer.new()
		title.add_theme_constant_override("separation", 6)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_child(_icon(LINE_ICONS[line], 1))
		title.add_child(lab)
		box.add_child(title)
	else:
		box.add_child(lab)
	box.add_child(CostRow.make(Defs.TECHS[id]["cost"], 13, Defs.TECHS[id]["time"]))
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(width - 22.0, 0)
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
	_tech_buttons[id] = {"button": b, "label": lab, "desc": desc, "bar": bar}
	return b

# ---------------------------------------------------------------- weapons depot

## Constructor: one button per depot type. Each depot fits one variant;
## E places the last type picked.


## Everything a Constructor can build, as square icon buttons on one grid:
## a starbase, a Mining Station, and one depot per variant.
func _add_constructor_buttons() -> void:
	var pid := game.player_id
	var grid := _button_grid()
	var n := game.starbase_count(pid)
	var now_u: float = n * Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(pid, n)
	var next_u: float = (n + 1) * Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(pid, n + 1)
	var sb := _panel_build_button("starbase", "Starbase", Defs.STARBASE["cost"], Defs.STARBASE["build_time"], "Found Starbase — %s over %ds.\nBuilds ships and takes deliveries. You have %d; the next raises total starbase upkeep from %.0f to %.0f energy/min." % [
		Defs.cost_text(Defs.STARBASE["cost"]), int(Defs.STARBASE["build_time"]), n, now_u, next_u])
	sb.pressed.connect(game.start_starbase_placement)
	_register_action(sb)
	grid.add_child(sb)

	var st := _panel_build_button("ship_mining_station", "Mining Station", Defs.MINING_STATION["cost"], Defs.MINING_STATION["build_time"],
		"A drop-off: harvesters unload here instead of flying home. Builds no ships, %d hull / %d armor / %d shields and a token gun." % [
			int(Defs.MINING_STATION["hp"]), int(Defs.MINING_STATION["armor"]), int(Defs.MINING_STATION["shield"])])
	st.pressed.connect(game.start_station_placement)
	_register_action(st)
	grid.add_child(st)

	var locked := not game.has_tech(pid, str(Defs.WEAPONS_DEPOT["requires"]))
	for v in Defs.VARIANTS:
		var vd: Dictionary = Defs.VARIANTS[v]
		var b := _panel_build_button("ship_depot_" + v, "%s Depot" % vd["label"], Defs.WEAPONS_DEPOT["cost"], Defs.WEAPONS_DEPOT["build_time"],
			"Refits a generalist warship into a %s: %s" % [vd["label"], vd["desc"]], vd["color"])
		if locked:
			b.disabled = true
			b.tooltip_text = "Weapons Depots need the %s tech." % Defs.TECHS[Defs.WEAPONS_DEPOT["requires"]]["name"]
		b.pressed.connect(func(): game.start_depot_placement(v))
		_register_action(b)
		grid.add_child(b)
	_sel_body.add_child(grid)

## Generalist warships selected: one line saying how a refit happens. No
## variant buttons — the depot you send a ship to decides what it becomes,
## so the choice lives on the map, not in this panel.
func _add_refit_buttons(sel: Array) -> void:
	var bases := {}
	for e in sel:
		if e is Ship and e.owner_id == game.player_id and not e.def.has("variant") and Defs.VARIANTS_OF.has(e.ship_type):
			bases[e.ship_type] = true
	if bases.is_empty():
		return
	# Refit costs and times are per hull (Defs.SHIPS[type].refit).
	var costs: Array = []
	for b in bases:
		var r: Dictionary = Defs.SHIPS[b]["refit"]
		costs.append("%s %d minerals, %ds" % [Defs.SHIPS[b]["name"], int(r["minerals"]), int(r["time"])])
	_sel_body.add_child(_label("Right-click a Weapons Depot to refit (permanent, one way): " + ", ".join(costs), DIM, 13))

## A selected Weapons Depot: which variant it fits and the ships docked
## inside, each with a Cancel button. A cancelled ship leaves the way it went
## in — still a generalist — and minerals already spent are not refunded.
func _build_depot_panel(d: WeaponsDepot) -> void:
	if d.under_construction:
		_sel_body.add_child(_label("Under construction: %d%%" % int(100.0 * d.construct_progress / Defs.WEAPONS_DEPOT["build_time"]), DIM, 14))
		return
	var vd: Dictionary = Defs.VARIANTS[d.variant]
	var info := _label("Refits generalist warships into %s ships: %s" % [vd["label"], vd["desc"]], vd["color"], 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(560, 0)
	_sel_body.add_child(info)
	_sel_body.add_child(_label("Right-click the depot with generalists selected to send them here.  Bays: %d / %d." % [
		d.bays.size(), int(Defs.WEAPONS_DEPOT["capacity"])], DIM, 13))
	if d.bays.is_empty():
		_sel_body.add_child(_label("No ships docked.", DIM, 13))
		return
	for bay in d.bays:
		var ship = bay["ship"]
		if not is_instance_valid(ship):
			continue
		var s: Ship = ship
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lab := _label("%s  ->  %s %s   (%ds left)" % [s.def["name"], vd["label"], s.def["name"], int(ceil(bay["left"]))], vd["color"], 14)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var cancel := Button.new()
		cancel.text = "Cancel"
		cancel.custom_minimum_size = Vector2(90, 28)
		cancel.add_theme_font_size_override("font_size", 13)
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.tooltip_text = "Ejects the ship, still a generalist. Minerals already spent are lost."
		cancel.pressed.connect(func(): d.cancel(s); game.selection_changed.emit())
		row.add_child(cancel)
		_sel_body.add_child(row)
	var all := Button.new()
	all.text = "Cancel all refits"
	all.custom_minimum_size = Vector2(0, 30)
	all.focus_mode = Control.FOCUS_NONE
	all.pressed.connect(func(): d.cancel_all(); game.selection_changed.emit())
	_sel_body.add_child(all)

# ---------------------------------------------------------------- panel keys

## Gives a selection-panel button the next grid hotkey (Q W E / A S D / Z X C
## / V B N) and stamps that letter in its bottom-right corner, so the keys
## always match what is on screen.
## Burns a panel key so a fixed slot (the starbase page switch) keeps the
## same letter no matter how many buttons come before it.
func _skip_action() -> void:
	var keys := panel_keys()
	var i := _panel_keys.size()
	if i < keys.size():
		_panel_keys[keys[i]] = null

func _register_action(b: Button) -> void:
	var keys := panel_keys()
	var i := _panel_keys.size()
	if i >= keys.size():
		return
	var k: Key = keys[i]
	_panel_keys[k] = b
	var tag := _label(OS.get_keycode_string(k), Color(TEXT, 0.75), 12)
	tag.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tag.offset_left = -14
	tag.offset_top = -17
	tag.offset_right = -3
	tag.offset_bottom = -2
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tag)

## Presses the panel button wired to this key. Returns true if the key
## belongs to the open panel at all — a disabled button still swallows it, so
## a full build queue never drops you out of the starbase into "select all
## barges".
func press_panel_key(k: Key) -> bool:
	if not _panel_keys.has(k):
		return false
	var b = _panel_keys[k]
	# An empty slot on this panel still belongs to it: swallow the key rather
	# than falling through to "select every ship of that type".
	if b == null or not is_instance_valid(b):
		return true
	if b.disabled:
		game.sfx.play_ui("deny")
		return true
	b.pressed.emit()
	return true

## The ship type a grid key builds at a starbase: BUILD_ORDER in panel-key
## order (Q W E / A S D / Z X C / V B N). Used for "select every ship of that
## type" when no starbase is selected, so one key means one ship class
## wherever you are.
func build_type_for_key(k: Key) -> String:
	var i := panel_keys().find(k)
	if i < 0 or i >= Defs.BUILD_ORDER.size():
		return ""
	return Defs.BUILD_ORDER[i]

## Opens the Codex over the match (pause menu). It runs in its own layer on
## top and closes back to the game.
func open_codex() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var codex: Control = load("res://scenes/Codex.tscn").instantiate()
	codex.overlay = true
	layer.add_child(codex)
	get_tree().root.add_child(layer)
