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
## Secondary text that still has to be read at a glance â research times,
## "Needs:" lines, locked cards. DIM is dark enough to disappear on a panel.
const MUTED := Color("a8b4d4")
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
var _research_icon: TextureRect
var _clock: Label
var _sel_body: VBoxContainer
## The per-ship condition tiles of a multi-ship selection (see _add_fleet_tiles).
var _fleet_tiles: Array = []
## The per-side score lines above the minimap.
var _score_box: VBoxContainer
var _score_timer := 0.0
var _messages: VBoxContainer
var _overlay: Control
var _pause: Control
var _end: Control
var _end_label: Label
var _research_modal: ColorRect
var _tech_buttons := {}
## The research screen's Defenses tab button (dev captures press it).
var _defs_tab: Button
## group id -> its tab button, so a dev capture can open any page.
var _research_tabs := {}
## Layer icon per defense line (Defs.LAYER_COLORS).
const LINE_ICONS := {"shields": "icon_layer_shield", "armor": "icon_layer_armor", "hull": "icon_layer_hull", "screens": "icon_layer_screens"}
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
## The round minimap's diameter on screen.
const MINIMAP_D := 330.0   # 264 x 1.25
## Smaller than this (per minute) counts as flat, so the arrow holds still.
const TREND_DEADBAND := 1.0
## Faster than this (per minute, either way) earns a second arrow.
const TREND_STRONG := 19.0
## Faster than this earns a third.
const TREND_SURGE := 99.0
## The starbase page switch always sits in this grid cell (the bottom-right one, key C).
const PAGE_SWITCH_SLOT := 8

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
	game.message_long.connect(func(t, c, extra): _push_message(t, c, extra))
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
	var art_div: float = Defs.art_div(name)
	tr.custom_minimum_size = tr.texture.get_size() * scale_px / art_div
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## The sprite for a ship type. One hull per class now, whatever its rank.
func _ship_art(ship_type: String) -> String:
	return "ship_" + Defs.SHIPS.get(ship_type, {}).get("base", ship_type)

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

## The top row: every panel and button shares one top edge, one height and
## one gap, and the margin to the screen edge is the same on both sides. The
## resource bar is not given a width; it stretches from the left margin to
## the research button, which keeps the row even at any window width.
const TOP_Y := 8
const TOP_H := 62
const HUD_GAP := 20
const HUD_SIDE := 12
const MENU_W := 170
const SPEED_W := 368
## The research button also takes the space the match clock used to have;
## the clock now sits under the resource bar (CLOCK_W x CLOCK_H).
const RESEARCH_W := 306
const CLOCK_W := 86
const CLOCK_H := 30
const SPEED_RIGHT := -HUD_SIDE - MENU_W - HUD_GAP
const RESEARCH_RIGHT := SPEED_RIGHT - SPEED_W - HUD_GAP
const TOP_BAR_RIGHT := RESEARCH_RIGHT - RESEARCH_W - HUD_GAP

func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	# Right-aligned next to the speed controls, keeping the left side of
	# the screen free for other panels.
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.offset_left = HUD_SIDE
	bar.offset_right = TOP_BAR_RIGHT
	bar.offset_bottom = TOP_Y + TOP_H
	bar.clip_contents = true
	bar.offset_top = TOP_Y
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
		# Longest realistic text: "54.3k ▼▼▼".
		l.custom_minimum_size = Vector2(100, 0)
		l.clip_text = true
		box.add_child(l)
		_res_labels[key] = l
		_res_boxes[key] = box
		h.add_child(box)
	_pop_label = _label("Pop 0", TEXT)
	_pop_label.custom_minimum_size = Vector2(100, 0)   # "Pop 99.9k"
	_pop_label.clip_text = true
	_pop_label.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(_pop_label)
	var fleet := HBoxContainer.new()
	fleet.add_theme_constant_override("separation", 6)
	fleet.add_child(_icon("icon_fleet"))
	_fleet_label = _label("0/0")
	_fleet_label.custom_minimum_size = Vector2(260, 0)   # "999 ships · upkeep x9.99"
	_fleet_label.clip_text = true
	fleet.add_child(_fleet_label)
	h.add_child(fleet)

## Research button and match clock, in their own panel between the resource
## bar and the speed controls.
func _build_research_panel(root: Control) -> void:
	# The research button stands on its own, like the Menu button, at one
	# fixed size whether or not anything is being researched.
	_research_button = Button.new()
	_research_button.text = "Research [R]"
	_research_button.clip_text = true
	_research_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_research_button.add_theme_font_size_override("font_size", 13)
	_research_button.focus_mode = Control.FOCUS_NONE
	# The active tech's picture rides beside its name and progress.
	_research_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_research_button.anchor_left = 1.0
	_research_button.anchor_right = 1.0
	_research_button.offset_right = RESEARCH_RIGHT
	_research_button.offset_left = RESEARCH_RIGHT - RESEARCH_W
	_research_button.offset_top = TOP_Y
	_research_button.offset_bottom = TOP_Y + TOP_H
	_research_button.pressed.connect(toggle_research)
	root.add_child(_research_button)
	# The active tech's icon fills the button top to bottom. It is a child
	# image rather than Button.icon (which would add padding and grow the
	# button), drawn from the research panel's full-size icon scaled down
	# smoothly; the text is moved right to clear it.
	_research_icon = TextureRect.new()
	_research_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_research_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_research_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_research_icon.position = Vector2(2, 2)
	_research_icon.size = Vector2(TOP_H - 4, TOP_H - 4)
	_research_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_icon.visible = false
	_research_button.add_child(_research_icon)
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := _research_button.get_theme_stylebox(state)
		if sb:
			sb = sb.duplicate()
			sb.content_margin_left = TOP_H + 4
			_research_button.add_theme_stylebox_override(state, sb)
	# Progress shows as a green bar growing left to right across the button.
	_research_fill = ColorRect.new()
	_research_fill.color = Color(GOOD.r, GOOD.g, GOOD.b, 0.3)
	_research_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_fill.visible = false
	_research_fill.anchor_left = 1.0
	_research_fill.anchor_right = 1.0
	_research_fill.offset_top = TOP_Y + 2
	_research_fill.offset_bottom = TOP_Y + TOP_H - 2
	root.add_child(_research_fill)

	# The match clock: top left, just under the resource bar.
	var panel := PanelContainer.new()
	panel.offset_left = HUD_SIDE
	panel.offset_right = HUD_SIDE + CLOCK_W
	panel.offset_top = TOP_Y + TOP_H + 6
	panel.offset_bottom = TOP_Y + TOP_H + 6 + CLOCK_H
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(4))
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
	b.offset_left = -HUD_SIDE - MENU_W
	b.offset_right = -HUD_SIDE
	b.offset_top = TOP_Y
	b.offset_bottom = TOP_Y + TOP_H
	b.pressed.connect(func(): show_pause(true))
	root.add_child(b)

## Game speed slider (top-right, just left of the Menu button). The notch labelled NORMAL is 1x.
func _build_speed(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = SPEED_RIGHT - SPEED_W
	panel.offset_right = SPEED_RIGHT
	panel.offset_top = TOP_Y
	panel.offset_bottom = TOP_Y + TOP_H
	panel.add_theme_stylebox_override("panel", _panel_style(6))
	root.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(h)
	_play_button = Button.new()
	_play_button.custom_minimum_size = Vector2(92, TOP_H - 16)
	_play_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _play_button.get_theme_stylebox(st).duplicate() as StyleBox
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		_play_button.add_theme_stylebox_override(st, sb)
	_play_button.focus_mode = Control.FOCUS_NONE
	_play_button.tooltip_text = "Pause / resume the game (Pause key). You can still give orders while paused."
	_play_button.pressed.connect(toggle_play)
	h.add_child(_play_button)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_speed_label = _label("Speed 1x (normal)", TEXT, 13)
	v.add_child(_speed_label)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0
	_speed_slider.max_value = SPEEDS.size() - 1
	_speed_slider.step = 1
	_speed_slider.tick_count = SPEEDS.size()
	_speed_slider.ticks_on_borders = true
	_speed_slider.custom_minimum_size = Vector2(200, 18)
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
	frame.offset_left = -12 - MINIMAP_D
	frame.offset_top = -12 - MINIMAP_D
	frame.offset_right = -12
	frame.offset_bottom = -12
	# No box: a round mask (a fully rounded panel that clips the map to its
	# disc), so the round system shows as a disc and nothing else.
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(BG, 0.94)
	disc.set_corner_radius_all(int(MINIMAP_D))
	disc.corner_detail = 32
	frame.add_theme_stylebox_override("panel", disc)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	root.add_child(frame)
	var mm := Minimap.new()
	mm.game = game
	minimap = mm
	frame.add_child(mm)
	# The system's name just above the map, in its star's colour, so the
	# player always knows which map they are on.
	var name_tag := _label("", TEXT, 18)
	name_tag.anchor_left = 1.0
	name_tag.anchor_right = 1.0
	name_tag.anchor_top = 1.0
	name_tag.anchor_bottom = 1.0
	name_tag.offset_left = -12 - MINIMAP_D
	name_tag.offset_right = -14
	name_tag.offset_top = -12 - MINIMAP_D - 30
	name_tag.offset_bottom = -12 - MINIMAP_D - 4
	name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_tag.add_theme_constant_override("outline_size", 6)
	root.add_child(name_tag)
	# Above it, one line per side: name and running score (MatchStats.score).
	_score_box = VBoxContainer.new()
	_score_box.anchor_left = 1.0
	_score_box.anchor_right = 1.0
	_score_box.anchor_top = 1.0
	_score_box.anchor_bottom = 1.0
	_score_box.offset_left = -12 - MINIMAP_D
	_score_box.offset_right = -14
	# A clear gap above the system name, split by a faint rule.
	_score_box.offset_top = -12 - MINIMAP_D - 30 - 18 - 52
	_score_box.offset_bottom = -12 - MINIMAP_D - 30 - 18
	_score_box.alignment = BoxContainer.ALIGNMENT_END
	_score_box.add_theme_constant_override("separation", 0)
	_score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_score_box)
	var rule := ColorRect.new()
	rule.color = Color(TEXT, 0.2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.anchor_left = 1.0
	rule.anchor_right = 1.0
	rule.anchor_top = 1.0
	rule.anchor_bottom = 1.0
	rule.offset_left = -12 - 220
	rule.offset_right = -14
	rule.offset_top = -12 - MINIMAP_D - 30 - 9
	rule.offset_bottom = -12 - MINIMAP_D - 30 - 8
	root.add_child(rule)
	for pid in [game.player_id] + game.players.filter(func(p): return p != game.player_id):
		var l := _label("", Defs.team_color(pid), 16)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 6)
		l.set_meta("pid", pid)
		_score_box.add_child(l)
	_update_scores()
	# Filled once the system is built (Game sets it up before the first frame).
	(func():
		var sys := SystemGen.find(GameState.system_id)
		var st: Dictionary = game.system_settings
		# Random has no name of its own: it is called after the star drawn for it.
		name_tag.text = "%s System" % st.get("star_name", "Uncharted") if GameState.system_id == "random" else str(sys.get("name", ""))
		name_tag.add_theme_color_override("font_color", Defs.STAR_TYPES.get(st.get("star", "yellow"), {}).get("tint", TEXT))
	).call_deferred()

func _build_messages(root: Control) -> void:
	_messages = VBoxContainer.new()
	_messages.anchor_left = 0.5
	_messages.anchor_right = 0.5
	# Centred on the screen: a line wider than the box grows it equally both
	# ways (not just to the right), and it sits clear of the top bar.
	_messages.offset_left = -420
	_messages.offset_right = 420
	_messages.offset_top = 112
	_messages.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
		if pair[0] == "Quit to Title":
			MenuStyle.leave(b)
		v.add_child(b)

func _build_end(root: Control) -> void:
	var parts := _modal(root, "")
	_end = parts[0]
	_end_label = parts[2]
	for pair in [["View Stats", func(): _show_stats(true)], ["View Map", _enter_map_view], ["Return to Title", _quit_to_title]]:
		var b := Button.new()
		b.text = pair[0]
		MenuStyle.button(b)
		if pair[0] == "Return to Title":
			MenuStyle.leave(b)
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
## Every tab reserves the same box: as tall as the deepest page (War Ships,
## five rows), so the modal keeps one size and a card never shifts when the
## player tabs across.
const PAGE_SIZE := Vector2(1320, 740)

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

	# Every tab is the same grid: a row-header column, then one column per
	# tier. A card is the same size and lands in the same place whichever tab
	# is open, so the eye does not have to re-find anything when tabbing.
	# Named rows, like Defense: each row is one line of upgrades.
	for group in TECH_ROWS:
		var named: Array = []
		for r in TECH_ROWS[group]:
			named.append([_row_head(r[0], TechIcons.GROUP_COLORS[group], ""), r[1]])
		pages[group] = _tech_page(v, named)
	for group in ["general"]:
		var rows: Array = []
		var by_tier := {1: [], 2: [], 3: []}
		for id in Defs.TECHS:
			if Defs.TECHS[id].get("group", "general") == group:
				by_tier[Defs.TECHS[id]["tier"]].append(id)
		var deepest: int = maxi(by_tier[1].size(), maxi(by_tier[2].size(), by_tier[3].size()))
		# A group has no natural row names, so the header cells are blank and
		# the cards still line up with the named rows on the other tabs.
		for r in deepest:
			var row: Array = []
			for tier in [1, 2, 3]:
				row.append(by_tier[tier][r] if r < by_tier[tier].size() else "")
			rows.append([null, row])
		if deepest > 0:
			pages[group] = _tech_page(v, rows)

	# War Ships: the unlocks along the top, then one row per class.
	# Depots lives on the Constructs page; a tech can only own one card, since
	# _refresh_research keys its widgets by id.
	var war_rows: Array = [[_row_head("UNLOCKS", DIM, ""), ["destroyers", "cruisers", "carriers"]]]
	for cls in Defs.MARK_LINES:
		war_rows.append([_row_head(Defs.SHIPS[cls]["name"].to_upper(), TEXT, ""),
			["%s_mk2" % cls, "%s_mk3" % cls, "%s_mk4" % cls]])
	pages["warships"] = _tech_page(v, war_rows)

	# Defense: one row per layer line.
	var def_rows: Array = []
	for line in [["shields", "SHIELDS", Defs.LAYER_COLORS["shield"]], ["armor", "ARMOR", Defs.LAYER_COLORS["armor"]], ["hull", "HULL", Defs.LAYER_COLORS["hull"]], ["screens", "SCREENS", Color("c9b6ff")]]:
		var ids: Array = ["", "", ""]
		for id in Defs.TECHS:
			if Defs.TECHS[id].get("line", "") == line[0]:
				ids[Defs.TECHS[id]["tier"] - 1] = id
		def_rows.append([_row_head(line[1], line[2], LINE_ICONS[line[0]]), ids])
	pages["defense"] = _tech_page(v, def_rows)

	var order := [["warships", "Warships"], ["weapons", "Weapons"], ["defense", "Defense"], ["constructs", "Constructs"], ["worlds", "Worlds"], ["logistics", "Logistics"], ["general", "General"]]
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
	# Dev: every tab is reachable from a capture, so each one can be checked
	# for fit (SL_RESEARCH_TAB=weapons|constructs|worlds|logistics|defense).
	_research_tabs = buttons
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
		# The card's colour shows its state (see the legend); the title only
		# adds what the colour can't: a stall or a queue place.
		var line: String = t["name"]
		if st == "active" and cur.get("stalled", false):
			line += "  STALLED"
		if st == "queued":
			line += "  #%d" % (game.research_queue[pid].find(id) + 1)
		var req := ""
		if not t["requires"].is_empty():
			req = "\nNeeds: " + ", ".join(t["requires"].map(func(r): return Defs.TECHS[r]["name"]))
		w["label"].text = line
		w["desc"].text = t["desc"] + req
		for style in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = _panel_style(6, STATE_COLORS[st].lightened(0.3 if style == "normal" else 0.55))
			sb.bg_color = STATE_COLORS[st].darkened(0.3 if style != "hover" else 0.15)
			w["button"].add_theme_stylebox_override(style, sb)
		w["label"].add_theme_color_override("font_color", MUTED if st == "locked" else (Color.WHITE if st in ["active", "done"] else TEXT))
		w["desc"].add_theme_color_override("font_color", MUTED if st == "locked" else TEXT)
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
		box.add_child(_icon("starbase" if k == "starbase" else _ship_art(k), 2))
		box.add_child(_label("×%d" % counts[k]))
		grid.add_child(box)
	_sel_body.add_child(grid)
	_add_fleet_tiles(sel)
	if sel.any(func(e): return e is Ship and e.def["role"] == "constructor"):
		_add_constructor_buttons()
	_add_refit_buttons(sel)

## How many ships of a selection get their own condition tile before the rest
## are summarised. A wall of tiles stops being readable long before the panel
## runs out of room.
const FLEET_TILES_MAX := 24
## The box one of those tiles occupies, sprite and bars together.
const FLEET_TILE := Vector2(46, 44)

## One selected ship: its sprite with a shield/armor/hull bar under it, so a
## glance at the panel says which ships in the fleet are hurt. Live: the HUD
## repaints them on its own refresh tick.
class FleetTile extends Control:
	var host: SpaceEntity
	const BAR_H := 3.0
	const GAP := 1.0
	const BARS_H := 3.0 * (BAR_H + GAP)

	func _draw() -> void:
		if not is_instance_valid(host):
			return
		var w := size.x - 4.0
		var y := size.y - BARS_H
		var shield_col: Color = host.shield_color() if host.has_method("shield_color") else Defs.LAYER_COLORS["shield"]
		for gauge in [[host.shield, host.max_shield, shield_col],
				[host.armor, host.max_armor, Defs.LAYER_COLORS["armor"]],
				[host.hp, host.max_hp, Defs.LAYER_COLORS["hull"]]]:
			var full: float = gauge[1]
			if full <= 0.0:
				# No such layer on this hull: leave the row empty rather than
				# draw a bar that can never fill.
				y += BAR_H + GAP
				continue
			draw_rect(Rect2(2.0, y, w, BAR_H), Color(0, 0, 0, 0.75))
			var frac: float = clampf(gauge[0] / full, 0.0, 1.0)
			if frac > 0.0:
				draw_rect(Rect2(2.0, y, w * frac, BAR_H), gauge[2])
			y += BAR_H + GAP

## A tile per selected ship (up to FLEET_TILES_MAX), so the panel shows the
## condition of the fleet and not just its composition.
func _add_fleet_tiles(sel: Array) -> void:
	_fleet_tiles.clear()
	var ships: Array = sel.filter(func(e): return e is Ship and e.owner_id == game.player_id)
	if ships.size() < 2:
		return
	# Worst first: the ships that need the player's attention lead.
	ships.sort_custom(func(a, b): return _condition(a) < _condition(b))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for e in ships.slice(0, FLEET_TILES_MAX):
		var tile := FleetTile.new()
		tile.host = e
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Every tile is the same box whatever the hull, so the bars are all
		# the same length and can be compared down the row at a glance.
		tile.custom_minimum_size = FLEET_TILE
		tile.clip_contents = true
		tile.tooltip_text = (e as Ship).def["name"]
		var hold := CenterContainer.new()
		hold.set_anchors_preset(Control.PRESET_FULL_RECT)
		hold.offset_bottom = -FleetTile.BARS_H - 1.0
		hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A big hull (an X-class cruiser, a carrier) is drawn at half scale so
		# it fits the same tile as a corvette instead of spilling over its
		# neighbours.
		var art_name := _ship_art((e as Ship).ship_type)
		var tex := Defs.tex(art_name)
		var wide: bool = tex != null and tex.get_width() * 2.0 / Defs.art_div(art_name) > FLEET_TILE.x - 4.0
		hold.add_child(_icon(art_name, 1 if wide else 2))
		tile.add_child(hold)
		row.add_child(tile)
		_fleet_tiles.append(tile)
	_sel_body.add_child(row)
	if ships.size() > FLEET_TILES_MAX:
		_sel_body.add_child(_label("+%d more" % (ships.size() - FLEET_TILES_MAX), DIM, 13))

## A ship's condition as one number (0-1), worst layer first: hull decides,
## with armor and shields breaking ties.
func _condition(e: SpaceEntity) -> float:
	var hull: float = e.hp / maxf(e.max_hp, 1.0)
	var armor: float = e.armor / maxf(e.max_armor, 1.0) if e.max_armor > 0.0 else 1.0
	var shield: float = e.shield / maxf(e.max_shield, 1.0) if e.max_shield > 0.0 else 1.0
	return hull * 100.0 + armor * 10.0 + shield

func _entity_icon(e: SpaceEntity, px: int) -> Control:
	var tex_name := "starbase"
	if e is WeaponsDepot:
		tex_name = "ship_depot_" + (e as WeaponsDepot).variant
	elif e is MiningStation:
		tex_name = "ship_mining_station"
	elif e is Ship:
		tex_name = "ship_" + (e as Ship).def.get("base", (e as Ship).ship_type)
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
	_add_hangar_panel(s)
	match s.def["role"]:
		"colony":
			_sel_body.add_child(_label("Right-click an unowned planet to settle it with %d pops." % int(Defs.START_POP), DIM, 13))
		"constructor":
			_add_constructor_buttons()
		"miner":
			_sel_body.add_child(_label("Right-click an asteroid to mine it. Orange-flecked rocks hold spice.", DIM, 13))
		"skimmer":
			_sel_body.add_child(_label("Right-click a gas giant to mine minerals, or a spot inside a spice nebula to slowly harvest spice gas (never runs out).", DIM, 13))


## A selected carrier: what is sitting in its bays and how far along it is.
## A depot shows the same thing for refits, and a hangar is the one other
## place a ship disappears inside something of yours.
func _add_hangar_panel(s: Ship) -> void:
	if int(s.def.get("bays", 0)) <= 0:
		return
	var used := 0
	for c in s.bay_craft:
		if c != null and is_instance_valid(c):
			used += 1
	# The job line above already says what a bay does, so this is just the count.
	_sel_body.add_child(_label("Hangar bays: %d / %d full." % [used, s.bay_craft.size()], DIM, 13))
	for c in s.bay_craft:
		if c == null or not is_instance_valid(c):
			continue
		var craft: Ship = c
		# Whichever layer is being worked on, since hull comes first.
		var layer := "hull"
		var frac: float = craft.hp / maxf(craft.max_hp, 1.0)
		if craft.hp >= craft.max_hp:
			layer = "armor"
			frac = craft.armor / maxf(craft.max_armor, 1.0)
		_sel_body.add_child(_label("  %s  -  %s %d%%" % [craft.def["name"], layer, int(100.0 * frac)],
			Defs.LAYER_COLORS[layer], 13))

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
		b.tooltip_text = "%s\nShield %d  Armor %d  Hull %d  Speed %d\nUpkeep %.2f energy/min base (scales with fleet size)\nCost %s, paid over %ds" % [game.ship_name(game.player_id, t), d["shield"], d.get("armor", 0), d["hp"], d["speed"], d["upkeep"], Defs.cost_text(d["cost"]), d["build_time"]]
		if d.has("variant"):
			b.tooltip_text += "\n" + Defs.VARIANTS[d["variant"]]["desc"]
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 6
		h.add_theme_constant_override("separation", 12)
		# One icon box whatever the hull, so a carrier's name still fits.
		var art := _icon(_ship_art(t), 2)
		art.custom_minimum_size = Vector2(minf(art.custom_minimum_size.x, 52.0), minf(art.custom_minimum_size.y, 46.0))
		h.add_child(art)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_label(d.get("short", game.ship_name(game.player_id, t)), Defs.VARIANTS[d["variant"]]["color"] if d.has("variant") else TEXT, 13))
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
	_sel_body.add_child(_label("A Radiation Sail Array harvests energy inside this radiation.", DIM, 12))
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
	var owner_text := "Unclaimed" if so == 0 else ("Yours" if so == game.player_id else ("Allied (%s)" % game.player_name(so) if game.are_allies(so, game.player_id) else ("Enemy" if game.players.size() == 2 else "Enemy (%s)" % game.player_name(so))))
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
	for t in _fleet_tiles:
		if is_instance_valid(t):
			t.queue_redraw()
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
		txt += "\n" + ["Idle", "Moving", "Engaging", "Attack-moving", "En route to mine", "Mining", "Returning cargo", "Colonizing", "Flying to build site", "Bombarding planet", "Refitting at Weapons Depot", "Docking at carrier", "Docked"][s.state]
		if s.is_miner():
			txt += "   Cargo %d/%d %s" % [s.cargo, s.cargo_cap(), s.cargo_type]
		elif s.def["weapon"] != "":
			txt += "   %s %.0f dmg / %.1fs" % [s.def["weapon"].capitalize(), s.def["damage"] * game.mod(e.owner_id, "damage") * Defs.mark_mult(s.ship_type, game.mark_level(e.owner_id, s.ship_type)), s.def["cooldown"]]
		txt += "   Upkeep %.1f/min" % (s.def["upkeep"] * game.upkeep_multiplier(s.owner_id))
		if not s.order_queue.is_empty():
			txt += "\n%d queued order%s (Shift + right-click to add, T clears)" % [s.order_queue.size(), "" if s.order_queue.size() == 1 else "s"]
	elif e is Starbase:
		var sb := e as Starbase
		txt += "
Starbases %d · upkeep %.2f/min each (x%.1f)" % [game.starbase_count(sb.owner_id), Defs.STARBASE["upkeep"] * game.starbase_upkeep_multiplier(sb.owner_id), game.starbase_upkeep_multiplier(sb.owner_id)]
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
				qb.icon = Defs.tex(_ship_art(sb.queue[i]))
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
	if not p.is_habitable():
		return "Uninhabitable gas giant · %s\nGas Skimmers mine it and haul the minerals to a starbase." % [("DEPLETED, refills in %ds" % int(p.depleted_timer)) if p.depleted_timer > 0.0 else "Mineral reserve %d" % p.amount]
	# What this world's type does differently (e.g. a Molten world's plants).
	var traits := "" if Defs.planet_traits(p.kind).is_empty() else "\n" + "  ·  ".join(Defs.planet_traits(p.kind))
	if p.owner_id == 0:
		return "Size %d · Pop cap %s · Spice reserve %d%s\nSend a Colony Ship (right-click) to settle it." % [p.fields, _fmt(p.max_pop()), int(p.spice_reserve), traits]
	var lines := "Population %s / %s   (+%s/min)%s" % [_fmt(p.pop), _fmt(p.max_pop()), _fmt(p.growth_per_min), traits]
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
		_score_timer -= 0.1
		if _score_timer <= 0.0:
			_score_timer = 1.0
			_update_scores()
		_refresh_research()
		planet_view.refresh()
	_fit_selection_panel()
	var now := Game.now()
	_pings = _pings.filter(func(p): return now - p["t"] < 0.5)
	_flashes = _flashes.filter(func(f): return is_instance_valid(f["node"]) and Time.get_ticks_msec() / 1000.0 - f["real"] < FLASH_TIME)
	_overlay.queue_redraw()

## Who each side is, for the score lines: the signed-in account (or "You")
## for the player, and the AI for the other side.
func _side_name(pid: int) -> String:
	if pid == game.player_id:
		return GameState.active_account if GameState.active_account != "" else "You"
	return "AI Opponent"

func _update_scores() -> void:
	if _score_box == null:
		return
	for l in _score_box.get_children():
		var pid: int = l.get_meta("pid")
		l.text = "%s   %d" % [_side_name(pid), game.stats.score(pid)]

func _update_top_bar() -> void:
	var pid := game.player_id
	var r: Dictionary = game.resources.get(pid, {})
	var rt: Dictionary = game.rates.get(pid, {})
	for k in Defs.RESOURCES:
		var rate: float = rt.get(k, 0.0)
		# The stockpile, then an arrow for which way it is going. The arrow
		# follows the last minute, so one delivery cannot flip it.
		var avg: float = game.avg_rate(pid, k)
		var arrow := "–"
		var arrow_color := DIM
		if avg > TREND_DEADBAND:
			arrow = "▲▲▲" if avg > TREND_SURGE else ("▲▲" if avg > TREND_STRONG else "▲")
			arrow_color = GOOD
		elif avg < -TREND_DEADBAND:
			arrow = "▼▼▼" if avg < -TREND_SURGE else ("▼▼" if avg < -TREND_STRONG else "▼")
			arrow_color = BAD
		_res_labels[k].text = "%s %s" % [_fmt(r.get(k, 0.0)), arrow]
		_res_labels[k].add_theme_color_override("font_color", arrow_color if arrow != "–" else TEXT)
		_res_boxes[k].tooltip_text = "%s: %d stockpiled, %+.0f/min on average over the last minute (%+.0f/min right now)." % [
			Defs.RESOURCE_NAMES[k], int(r.get(k, 0.0)), avg, rate * Defs.PER_MIN]
	if game.energy_starved(pid):
		_res_labels["energy"].add_theme_color_override("font_color", BAD)
		_res_labels["energy"].text += "  NO ENERGY"
	_res_boxes["spice"].tooltip_text += "\nSpice automatically covers shortfalls of food, minerals and energy (1:1)."
	_res_boxes["energy"].tooltip_text += "\nUpkeep: %.1f/min for ships and starbases%s" % [game.upkeep(pid), "
OUT OF ENERGY: ship production halted, ships at 25% speed" if game.energy_starved(pid) else ""]
	_pop_label.text = "Pop %s" % _fmt(game.total_pop(pid))
	_pop_label.tooltip_text = "Population across your worlds. Each pop eats %.2f food per minute." % Defs.FOOD_PER_POP_PER_MIN
	_fleet_label.text = "%d ships · upkeep x%.2f" % [game.ship_count(pid), game.upkeep_multiplier(pid)]
	_fleet_label.tooltip_text = "Each ship's energy upkeep is multiplied by 1 + (ships / %d)^2. Starbases scale separately: x%.1f with %d starbases.
Total ship+starbase upkeep: %.1f energy/min." % [int(Defs.UPKEEP_SCALE_SHIPS), game.starbase_upkeep_multiplier(pid), game.starbase_count(pid), game.upkeep(pid)]
	_fleet_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var cur: Dictionary = game.research[pid]
	# The button blinks in real time, so it looks the same at any game speed:
	# yellow when nothing is queued, green while researching, red when stalled.
	# A long hold on the state colour, then a short one back on white.
	var phase: float = fmod(Time.get_ticks_msec() / 1000.0, RESEARCH_BLINK)
	var glow := 1.0 if phase < RESEARCH_BLINK * 0.7 else 0.0
	if cur.is_empty():
		_research_button.text = "Research [R]"
		_research_icon.visible = false
		_research_button.modulate = Color.WHITE.lerp(Color("ffd46b"), glow)
		_research_fill.visible = false
	else:
		var t: Dictionary = Defs.TECHS[cur["id"]]
		# The label stays short enough to fit: project name and percentage only.
		var frac: float = clampf(cur["progress"] / t["time"], 0.0, 1.0)
		# Percentage first: if the name is cut short to fit, progress is not.
		_research_button.text = "%d%% %s" % [int(100.0 * frac), t["name"]]
		_research_icon.texture = TechIcons.icon(cur["id"])
		_research_icon.visible = true
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

## `extra` keeps a message up that many more real seconds and pins it, so
## newer messages push other lines off the stack instead of it.
func _push_message(text: String, color: Color, extra: float = 0.0) -> void:
	var l := _label(text, color, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if extra > 0.0:
		l.set_meta("pinned", true)
	_messages.add_child(l)
	while _messages.get_child_count() > 4:
		var drop: Node = null
		for c in _messages.get_children():
			if not c.has_meta("pinned"):
				drop = c
				break
		if drop == null:
			drop = _messages.get_child(0)
		drop.free()
	var tw := l.create_tween()
	if extra > 0.0:
		# Real time, so game speed does not cut the briefing short: the usual
		# hold as it plays at normal speed, plus the extra.
		tw.set_ignore_time_scale(true)
		tw.tween_interval(3.5 / TIME_RATE + extra)
	else:
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
		if pair[0] == "Return to Title":
			MenuStyle.leave(b)
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
	# You first, then everyone else in player order.
	var sides: Array = [me] + game.players.filter(func(p): return p != me)
	var mins := int(Game.now() / 60.0)
	var sys: Dictionary = SystemGen.find(GameState.system_id)
	var sub := _label("%s  -  %s  -  %d:%02d" % ["VICTORY" if _won else "DEFEAT", sys.get("name", "Unknown system"), mins, int(Game.now()) % 60],
		GOOD if _won else Color("ff4f5e"), 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_body.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_stats_body.add_child(row)
	# Summary table: stat | you | each other player.
	var grid := GridContainer.new()
	grid.columns = 1 + sides.size()
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	grid.add_child(_label("", DIM))
	for p in sides:
		grid.add_child(_label(game.player_name(p) if sides.size() > 2 or p == me else "Enemy", Defs.team_color(p), 18))
	var lines := [
		["Ships built", func(p): return st.get_count(p, "ships_built")],
		["Ships lost", func(p): return st.get_count(p, "ships_lost")],
		["Enemy ships lost", func(p): return game.players.filter(func(o): return game.is_hostile(p, o)).reduce(func(a, o): return a + st.get_count(o, "ships_lost"), 0)],
		["Worlds colonized / taken", func(p): return st.get_count(p, "planets_won")],
		["Worlds lost", func(p): return st.get_count(p, "planets_lost")],
		["Starbases lost", func(p): return st.get_count(p, "starbases_lost")],
		["Peak worlds", func(p): return st.peak(p, "worlds")],
		["Peak population", func(p): return st.peak(p, "pop")],
		["Peak warships", func(p): return st.peak(p, "warships")],
		["Technologies researched", func(p): return game.researched[p].size()],
		["Peak score", func(p): return st.peak(p, "score")],
		["Final score", func(p): return st.score(p)],
	]
	for l in lines:
		grid.add_child(_label(l[0], TEXT))
		for p in sides:
			var v := _label(str(l[1].call(p)), Color.WHITE)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(v)
	# Charts over time.
	var charts := GridContainer.new()
	charts.columns = 3
	charts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	charts.add_theme_constant_override("h_separation", 16)
	charts.add_theme_constant_override("v_separation", 16)
	row.add_child(charts)
	for c in [["Score", "score"], ["Worlds", "worlds"], ["Population", "pop"], ["Warships", "warships"], ["Fleet strength", "power"], ["Technologies", "techs"]]:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(_label(c[0], TEXT, 15))
		var ch := StatChart.new()
		ch.samples = st.samples
		ch.field = c[1]
		ch.sides = sides.map(func(p): return [p, Defs.team_color(p), "you" if p == me else ("enemy" if sides.size() == 2 else "P%d" % p)])
		ch.custom_minimum_size = Vector2(250, 150)
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
				v_max = maxf(v_max, float(s[str(sd[0])].get(field, 0)))
		var font := get_theme_default_font()
		draw_string(font, Vector2(4, 13), str(int(v_max)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("6a7596"))
		var mins := "%d min" % int(t_max / 60.0)
		draw_string(font, Vector2(size.x - 4 - font.get_string_size(mins, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, size.y - 4), mins, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("6a7596"))
		var pad := Vector2(6, 18)
		var area := size - pad * 2.0
		# The enemy first, so where the two lines sit on top of each other it is
		# the player's own that shows.
		var order := sides.duplicate()
		order.reverse()
		for sd in order:
			var pts := PackedVector2Array()
			for s in samples:
				var x: float = pad.x + area.x * float(s["t"]) / t_max
				var y: float = pad.y + area.y * (1.0 - float(s[str(sd[0])].get(field, 0)) / v_max)
				pts.append(Vector2(x, y))
			draw_polyline(pts, sd[1], 2.0, true)
		# A key, so a chart read on its own still says whose line is whose.
		var kx := size.x - 8.0
		for i in sides.size():
			var label: String = sides[i][2] if sides[i].size() > 2 else ("you" if i == 0 else "enemy")
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			kx -= w
			draw_string(font, Vector2(kx, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sides[i][1])
			kx -= 12.0

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
## The width every tech card is drawn at, on every tab, and the width of the
## row-header column beside them.
const TECH_CARD_W := 400.0
## The tech's picture on the left of its card (TechIcons), and the room it
## takes from the text.
const TECH_ICON := 120.0
const TECH_ICON_PAD := 134.0
const TECH_ROW_HEAD_W := 110.0

## One row header: a name, optionally over an icon.
func _row_head(text: String, color: Color, icon: String) -> Control:
	var head := VBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.custom_minimum_size = Vector2(TECH_ROW_HEAD_W, 0)
	if icon != "":
		head.add_child(_icon(icon, 3))
	head.add_child(_label(text, color, 16))
	return head

## One research tab: a header row of tiers, then `rows` of [header, [ids]].
## An empty id leaves a hole the size of a card, so the grid never reflows.
## The rows of the Weapons, Constructs, Worlds and Logistics tabs: a name,
## then the tier 1-3 techs of that line.
const TECH_ROWS := {
	"weapons": [
		["DAMAGE", ["ion_cannons", "particle_lances", "lance_batteries"]],
		["RANGE", ["targeting_arrays", "beam_focusing", "capital_batteries"]],
		["FIRE RATE", ["autoloaders", "heavy_mounts", "scatter_arrays"]],
		["PENETRATION", ["overcharged_coils", "burst_cyclers", "hullbreaker_rounds"]],
	],
	"constructs": [
		["FORTIFICATION", ["garrison_guns", "reinforced_docks", "citadel_protocols"]],
		["STRONGHOLDS", ["depots", "siege_platforms", "fortress_doctrine"]],
		["SHIPYARDS", ["orbital_yards", "forward_bases", "shipyard_networks"]],
		["CONSTRUCTION", ["modular_frames", "rapid_assembly", "orbital_elevators"]],
	],
	"worlds": [
		["FOOD", ["hydroponics", "orbital_farms", "terraforming"]],
		["GROWTH", ["rationing", "gene_clinics", "gene_forges"]],
		["POPULATION", ["habitat_modules", "arcologies", "deep_vaults"]],
		["COLONIES", ["colony_pods", "planetary_shields", "planetary_citadels"]],
		["ENERGY", ["solar_collectors", "plasma_reactors", "dark_matter"]],
	],
	"logistics": [
		["CARGO", ["deep_drills", "bulk_holds", "logistics_command"]],
		["HARVEST", ["cutting_lasers", "resonance_drills", "mass_drivers"]],
		["SPEED", ["ion_thrusters", "fusion_drives", "jump_drives"]],
		["SUPPLY", ["gas_skimming", "convoy_protocols", "spice_navigation"]],
	],
}

func _tech_page(into: Control, rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.custom_minimum_size = PAGE_SIZE
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	grid.visible = false
	into.add_child(grid)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(TECH_ROW_HEAD_W, 0)
	grid.add_child(spacer)
	for tier in [1, 2, 3]:
		grid.add_child(_label("TIER %d" % tier, DIM, 14))
	for row in rows:
		if row[0] == null:
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(TECH_ROW_HEAD_W, 0)
			grid.add_child(pad)
		else:
			grid.add_child(row[0])
		for id in row[1]:
			if id == "" or not Defs.TECHS.has(id):
				var hole := Control.new()
				hole.custom_minimum_size = Vector2(TECH_CARD_W, 0)
				grid.add_child(hole)
			else:
				grid.add_child(_tech_button(id))
	return grid

func _tech_button(id: String, width: float = TECH_CARD_W) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 132)
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): game.request_research(id); _refresh_research())
	# The tech's picture, top-left, with the text beside it.
	var pic := TextureRect.new()
	pic.texture = TechIcons.icon(id)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(6, 6)
	pic.size = Vector2(TECH_ICON, TECH_ICON)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = TECH_ICON_PAD
	box.offset_top = 5
	box.offset_right = -10
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 15)
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
	box.add_child(CostRow.make(Defs.TECHS[id]["cost"], 15, Defs.TECHS[id]["time"]))
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(width - TECH_ICON_PAD - 12.0, 0)
	desc.add_theme_font_size_override("font_size", 14)
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
	var sb := _panel_build_button("starbase", "Starbase", Defs.STARBASE["cost"], Defs.STARBASE["build_time"], "Found Starbase — %s over %ds.\nBuilds ships and takes deliveries. You have %d; the next raises total starbase upkeep from %.1f to %.1f energy/min." % [
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
			"Refits a generalist warship into a %s ship: %s" % [vd["label"], vd["desc"]], vd["color"])
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
	# Corvettes have a key of their own (Defs.HOTKEYS "corvettes"), so Z
	# can build a Radiation Sail Array without also meaning "corvettes".
	if Defs.BUILD_ORDER[i] == "corvette":
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
