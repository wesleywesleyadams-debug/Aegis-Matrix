class_name HUD
extends CanvasLayer
## In-match interface, built in code: resource bar, selection/build panel,
## minimap, message feed, drag box, order pings, pause and end screens.

const BG := Color("0c0e1f")
const EDGE := Color("2b3a6b")
const EDGE_LIT := Color("4fb4ff")
const TEXT := Color("c3cde4")
const DIM := Color("6a7596")

var game: Game
var _font: SystemFont
var _drag_rect := Rect2()
var _pings: Array = []

var _res_labels := {}
var _clock: Label
var _sel_panel: PanelContainer
var _sel_body: VBoxContainer
var _messages: VBoxContainer
var _overlay: Control
var _pause: Control
var _end: Control
var _end_label: Label
var _build_buttons := {}
var _queue_row: HBoxContainer
var _info_label: Label
var _start_time: float
var _refresh: float = 0.0

func _ready() -> void:
	game = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_time = Game.now()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.hinting = TextServer.HINTING_NONE

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	root.add_child(_overlay)

	_build_top_bar(root)
	_build_selection_panel(root)
	_build_minimap(root)
	_build_messages(root)
	_build_help(root)
	_build_pause(root)
	_build_end(root)

	game.selection_changed.connect(_rebuild_selection)
	game.message.connect(_push_message)
	game.match_over.connect(_on_match_over)
	_rebuild_selection()

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font
	t.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(BG, 0.92)
	panel.border_color = EDGE
	panel.set_border_width_all(2)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color("141836"), "hover": Color("1d2550"), "pressed": Color("0a0c1c"), "disabled": Color("10121f"), "focus": Color("141836")}[state]
		b.border_color = EDGE_LIT if state == "hover" else EDGE
		b.set_border_width_all(2)
		b.set_content_margin_all(6)
		if state == "focus":
			b.draw_center = false
			b.border_color = EDGE_LIT
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_color", "Label", TEXT)
	return t

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
	return tr

# ---------------------------------------------------------------- layout

func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -340
	bar.offset_right = 340
	bar.offset_top = 8
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(h)
	for key in ["minerals", "energy", "fleet"]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.add_child(_icon("icon_" + key))
		var l := _label("0")
		box.add_child(l)
		_res_labels[key] = l
		h.add_child(box)
	_clock = _label("00:00", DIM)
	h.add_child(_clock)

func _build_selection_panel(root: Control) -> void:
	_sel_panel = PanelContainer.new()
	_sel_panel.anchor_top = 1.0
	_sel_panel.anchor_bottom = 1.0
	_sel_panel.offset_left = 12
	_sel_panel.offset_top = -232
	_sel_panel.offset_right = 612
	_sel_panel.offset_bottom = -12
	root.add_child(_sel_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sel_panel.add_child(scroll)
	_sel_body = VBoxContainer.new()
	_sel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_sel_body)

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
	var sb: StyleBoxFlat = root.theme.get_stylebox("panel", "PanelContainer").duplicate()
	sb.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	root.add_child(frame)
	var mm := Minimap.new()
	mm.game = game
	frame.add_child(mm)

func _build_messages(root: Control) -> void:
	_messages = VBoxContainer.new()
	_messages.anchor_left = 0.5
	_messages.anchor_right = 0.5
	_messages.offset_left = -400
	_messages.offset_right = 400
	_messages.offset_top = 70
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_messages)

func _build_help(root: Control) -> void:
	var l := _label("LMB select · drag box · RMB move/attack/mine · Ctrl+RMB attack-move · T stop · Tab all warships · H home · Ctrl+1-9 groups · WASD/edge/MMB pan · wheel zoom · Esc menu", DIM, 13)
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.anchor_right = 1.0
	l.offset_left = 630
	l.offset_right = -370
	l.offset_top = -60
	l.offset_bottom = -12
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)

func _modal(root: Control, title: String) -> Array:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
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
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	var v: VBoxContainer = parts[1]
	for pair in [["Resume", func(): show_pause(false)], ["Options", func(): OptionsMenu.open()], ["Quit to Title", _quit_to_title]]:
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

func show_pause(on: bool) -> void:
	_pause.visible = on
	game.paused_menu = on
	get_tree().paused = on

func _unhandled_input(event: InputEvent) -> void:
	if _pause.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		show_pause(false)
		get_viewport().set_input_as_handled()

func _quit_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")

func _on_match_over(won: bool) -> void:
	_end_label.text = "VICTORY" if won else "DEFEAT"
	_end_label.add_theme_color_override("font_color", Color("6fe07a") if won else Color("ff4f5e"))
	_end.visible = true

# ---------------------------------------------------------------- selection panel

func _rebuild_selection() -> void:
	for c in _sel_body.get_children():
		c.queue_free()
	_build_buttons.clear()
	_queue_row = null
	_info_label = null
	var sel: Array = game.selection.filter(func(e): return is_instance_valid(e))
	if sel.is_empty():
		_sel_body.add_child(_label("No selection", DIM))
		_sel_body.add_child(_label("Select your starbase to build ships.", DIM, 13))
		return
	if sel.size() == 1:
		var e: SpaceEntity = sel[0]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var icon := _entity_icon(e, 3)
		head.add_child(icon)
		var col := VBoxContainer.new()
		col.add_child(_label(e.display_name, Defs.team_color(e.owner_id), 20))
		_info_label = _label("")
		col.add_child(_info_label)
		head.add_child(col)
		_sel_body.add_child(head)
		if e is Starbase and e.owner_id == game.player_id:
			_build_starbase_controls(e)
		return
	# Multi-select: counts by class.
	var counts := {}
	for e in sel:
		var k: String = e.ship_type if e is Ship else "starbase"
		counts[k] = counts.get(k, 0) + 1
	_sel_body.add_child(_label("%d selected" % sel.size(), TEXT, 20))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 18)
	for k in counts:
		var box := HBoxContainer.new()
		var tex_name: String = "starbase" if k == "starbase" else "ship_" + k
		var tr := _icon(tex_name, 2)
		box.add_child(tr)
		box.add_child(_label("×%d" % counts[k]))
		grid.add_child(box)
	_sel_body.add_child(grid)

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

func _build_starbase_controls(sb: Starbase) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for t in Defs.BUILD_ORDER:
		var d: Dictionary = Defs.SHIPS[t]
		var b := Button.new()
		b.custom_minimum_size = Vector2(136, 0)
		b.tooltip_text = "%s\nHull %d  Shield %d  Speed %d\nFleet %d  Build %ds" % [d["name"], d["hp"], d["shield"], d["speed"], d["supply"], d["build_time"]]
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := _icon("ship_" + t, 2)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		var name_l := _label("[%s] %s" % [OS.get_keycode_string(d["hotkey"]), d["name"]], TEXT, 13)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_l)
		var cost_l := _label("%d◆ %d⚡" % [d["cost"]["minerals"], d["cost"]["energy"]], Color("8fe8cf"), 13)
		cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cost_l)
		b.custom_minimum_size.y = 84
		b.add_child(v)
		b.pressed.connect(func(): game.request_build(sb, t))
		row.add_child(b)
		_build_buttons[t] = b
	_sel_body.add_child(row)
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", 6)
	_sel_body.add_child(_queue_row)
	_sel_body.add_child(_label("Right-click in space to set the rally point. Click a queued ship to cancel.", DIM, 13))

func _update_selection_info() -> void:
	var sel: Array = game.selection.filter(func(e): return is_instance_valid(e))
	if sel.size() != 1 or _info_label == null:
		return
	var e: SpaceEntity = sel[0]
	var txt := "Hull %d/%d" % [ceili(e.hp), e.max_hp]
	if e.max_shield > 0:
		txt += "   Shield %d/%d" % [ceili(e.shield), e.max_shield]
	if e is Ship:
		var s := e as Ship
		txt += "\n" + ["Idle", "Moving", "Engaging", "Attack-moving", "En route to asteroid", "Mining", "Returning cargo"][s.state]
		if s.is_miner():
			txt += "   Cargo %d/%d" % [s.cargo, s.def["cargo"]]
		elif s.def["weapon"] != "":
			txt += "   %s %.0f dmg / %.1fs" % [s.def["weapon"].capitalize(), s.def["damage"], s.def["cooldown"]]
	_info_label.text = txt
	if e is Starbase and _queue_row:
		var sb := e as Starbase
		for t in _build_buttons:
			_build_buttons[t].disabled = sb.can_queue(t) != ""
		# Rebuild the queue strip only when its length changes.
		if _queue_row.get_child_count() != sb.queue.size():
			for c in _queue_row.get_children():
				c.queue_free()
			for i in sb.queue.size():
				var qb := Button.new()
				qb.custom_minimum_size = Vector2(56, 44)
				qb.icon = Defs.tex("ship_" + sb.queue[i])
				qb.expand_icon = true
				qb.tooltip_text = "Cancel " + Defs.SHIPS[sb.queue[i]]["name"]
				var idx := i
				qb.pressed.connect(func(): sb.cancel(idx))
				_queue_row.add_child(qb)
		if sb.queue.size() > 0 and _queue_row.get_child_count() > 0:
			var first: Button = _queue_row.get_child(0)
			first.text = "%d%%" % int(100.0 * sb.build_progress / Defs.SHIPS[sb.queue[0]]["build_time"])

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.1
		var r: Dictionary = game.resources.get(game.player_id, {})
		_res_labels["minerals"].text = "%d" % int(r.get("minerals", 0))
		_res_labels["energy"].text = "%d  (+%.1f/s)" % [int(r.get("energy", 0)), game.energy_rate(game.player_id)]
		_res_labels["fleet"].text = "%d / %d" % [game.supply_used(game.player_id), Defs.FLEET_CAP]
		var t := int(Game.now() - _start_time)
		_clock.text = "%02d:%02d" % [t / 60, t % 60]
		_update_selection_info()
	var now := Game.now()
	_pings = _pings.filter(func(p): return now - p["t"] < 0.5)
	_overlay.queue_redraw()

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
	var now := Game.now()
	for p in _pings:
		var k: float = (now - p["t"]) / 0.5
		var sp: Vector2 = xf * p["pos"]
		var r := 4.0 + k * 14.0
		var c: Color = p["color"]
		c.a = 1.0 - k
		# Four pixel chevrons closing in.
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_overlay.draw_rect(Rect2(sp + d * (18.0 - r) - Vector2(2, 2), Vector2(4, 4)), c)
