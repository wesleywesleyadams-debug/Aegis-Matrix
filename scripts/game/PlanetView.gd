class_name PlanetView
extends Control
## In-place planet close-up. Clicking a planet centers the camera on it,
## the planet grows where it sits, and its building fields fade in across
## its face. Bigger worlds (more fields) grow bigger. On your own planets,
## click an empty field to order a building, click a building to demolish
## it, or click one under construction to cancel it. Stats live in the
## selection panel (see `stats`). The game keeps running.

## Field slots are a fixed size; the planet art is scaled up (whole-pixel
## steps) until every slot fits on its face.
const SLOT := 64
const SLOT_GAP := 6
## Smallest the close-up planet is drawn, even with few fields.
const GLOBE_MIN := 320
## Ring of open planet surface kept around the slot block (px).
const GLOBE_MARGIN := 64
## Grow animation length in real seconds (independent of game speed).
const GROW_TIME := 0.28

var game: Game
var planet: Planet

var _globe: Control
var _art: TextureRect
var _title: Label
var _subtitle: Label
var _details: RichTextLabel
var _details_right := true
var _pause_btn: Button
## Draws the subtle ring around the planet, the leader line and the name bubble.
var _deco: Control
## Reserve bars, on their own layer above the planet and the field slots.
var _bars: Control
var _ring_color := Color(1, 1, 1, 0.5)
var _ring := {}
var _picker: PopupPanel
## Grid hotkeys for the build picker's rows (same letters as the selection
## panel: Q W E / A S D / Z X C), assigned in the order the rows are added.
var _picker_keys := {}
var _picker_list: VBoxContainer
var _menu_field: int = -1
var _field_buttons: Array[Button] = []
var _slot_layer: Control
var _target_d: float = 0.0
var _grow: float = 1.0
var _last_us: int = 0
## Latest stats summary for the selection panel.
var stats: String = ""
## Callout layout picked by _choose_layout: bubble angle (radians, screen
## space) and details placement (x: 1 right, -1 left, 2 above, 3 below of
## the globe; y: vertical step for the sides).
var _lay_ang: float = PI * 1.25
var _lay_det := Vector2i(1, 0)
var _layout_key: Array = []
var _lay_snap := true
var _lay_dt: float = 0.0
var _lay_center := Vector2.INF
## Shown positions relative to the planet center, eased toward the picks.
var _bub_rel := Vector2.ZERO
var _det_rel := Vector2.ZERO
## Groups of things that never move and so are kept clear of the callouts.
const STATIONARY_GROUPS := ["planets", "stars", "asteroids", "starbases", "mining_stations", "depots", "forts"]

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_globe = Control.new()
	_globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_globe)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_globe.add_child(_art)
	_slot_layer = Control.new()
	_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_globe.add_child(_slot_layer)

	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_deco)
	add_child(_deco)
	move_child(_deco, 0)
	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	add_child(_bars)
	_title = _float_label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle = _float_label(12, HORIZONTAL_ALIGNMENT_CENTER)
	# Rich text, so resources show as their icons.
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.fit_content = true
	_details.scroll_active = false
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("normal_font_size", 14)
	_details.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_details.add_theme_constant_override("outline_size", 6)
	# PASS so its [hint] tooltips show (the pop and reserve lines).
	_details.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_details)

	# Switch for this world's Mining Complexes (they dig its finite crust).
	_pause_btn = Button.new()
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.add_theme_font_size_override("font_size", 14)
	_pause_btn.tooltip_text = "Switch this world's Mining Complexes off or on. Paused, they produce nothing and dig nothing. A world whose crust is mined out implodes."
	_pause_btn.pressed.connect(func():
		if is_instance_valid(planet) and planet.owner_id == game.player_id:
			planet.mining_paused = not planet.mining_paused
			game.sfx.play_ui("click")
			refresh())
	add_child(_pause_btn)

	_picker = PopupPanel.new()
	_picker_list = VBoxContainer.new()
	_picker_list.add_theme_constant_override("separation", 4)
	_picker.add_child(_picker_list)
	add_child(_picker)
	_picker.window_input.connect(_on_picker_input)

func show_planet(p: Planet) -> void:
	var was := planet
	planet = p
	visible = p != null
	if is_instance_valid(was) and was != p:
		(was.get_node("Sprite") as Sprite2D).visible = true
	if p == null:
		_picker.hide()
		return
	var sprite := p.get_node("Sprite") as Sprite2D
	var tex_w := sprite.texture.get_width()
	# Size comes from the fields: smallest circle holding them plus a ring
	# of open surface, rounded up to a whole-pixel scale of the art.
	var scale_px := maxi(1, int(ceil(float(GLOBE_MIN) / tex_w)))
	if p.fields > 0:
		var need_r := _radius_for(p.fields)
		while tex_w * scale_px / 2.0 - scale_px * 2.0 < need_r + GLOBE_MARGIN:
			scale_px += 1
	_target_d = tex_w * scale_px
	_art.texture = sprite.texture
	sprite.visible = false # the close-up replaces it while open
	for b in _field_buttons:
		b.queue_free()
	_field_buttons.clear()
	var rects: Array[Rect2] = []
	if p.fields > 0:
		rects = _layout_slots(p.fields, _radius_for(p.fields))
	for i in p.fields:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.position = rects[i].position + Vector2.ONE * _target_d / 2.0
		b.size = rects[i].size
		b.add_theme_stylebox_override("normal", _slot_style(Color(0.05, 0.06, 0.14, 0.72), HUD.EDGE_LIT))
		b.add_theme_stylebox_override("hover", _slot_style(Color(0.1, 0.14, 0.3, 0.85), Color.WHITE))
		b.add_theme_stylebox_override("pressed", _slot_style(Color(0.02, 0.03, 0.08, 0.9), Color.WHITE))
		b.add_theme_stylebox_override("disabled", _slot_style(Color(0.05, 0.06, 0.14, 0.55), HUD.EDGE))
		var art := TextureRect.new()
		art.name = "Art"
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 9
		art.offset_top = 9
		art.offset_right = -9
		art.offset_bottom = -9
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_field_pressed.bind(i))
		_slot_layer.add_child(b)
		_field_buttons.append(b)
	# Grow from the planet's current on-screen size.
	_grow = 0.0 if was != p else 1.0
	if was != p:
		_layout_key = []
		_lay_snap = true
	refresh()
	_place()

func _process(delta: float) -> void:
	if not visible or planet == null:
		return
	if not is_instance_valid(planet):
		game.clear_planet_focus()
		return
	# Real time, so it animates the same at any game speed (or paused).
	var now_us := Time.get_ticks_usec()
	var real_dt := minf((now_us - _last_us) / 1000000.0, 0.1) if _last_us > 0 else 0.0
	_last_us = now_us
	_lay_dt = real_dt
	if _grow < 1.0:
		_grow = minf(1.0, _grow + real_dt / GROW_TIME)
	_place()

## Keeps the close-up centered on the planet's screen position and applies
## the grow animation (slots fade in once it's nearly full size).
func _place() -> void:
	var xf := game.get_viewport().get_canvas_transform()
	var center: Vector2 = xf * planet.global_position
	var start_d := planet.radius * 2.0 * game.camera.zoom.x
	var k := 1.0 - pow(1.0 - _grow, 3.0)
	var d := lerpf(start_d, _target_d, k)
	var s := d / _target_d
	_globe.size = Vector2(_target_d, _target_d)
	_globe.scale = Vector2(s, s)
	_globe.position = center - Vector2.ONE * d / 2.0
	_art.size = Vector2(_target_d, _target_d)
	_slot_layer.modulate.a = clampf((_grow - 0.6) / 0.4, 0.0, 1.0)
	_slot_layer.visible = _slot_layer.modulate.a > 0.0
	# Callout: subtle ring around the planet, line out to a name bubble at
	# the upper-left, details floating beside the bubble.
	var a := _slot_layer.modulate.a if planet.fields > 0 else k
	var ring_r := d / 2.0 + 26.0
	# The bubble is sized to what it has to hold: a long name or a big world's
	# "Size 30 · 30/30 built" used to run out through the ring.
	var br := _bubble_radius()
	var vp := get_viewport_rect().size
	_details.size = Vector2(DETAILS_W, 0)
	var dsz0 := _details.get_combined_minimum_size()
	# Where the bubble and the details go is picked to keep stationary
	# things on the map (rocks, stations, other worlds, the star) visible:
	# see _choose_layout. Re-chosen only when the view changes.
	var key := [Vector2i((center / 8.0).round()), int(_target_d), snappedf(game.camera.zoom.x, 0.001), Vector2i(vp), int(br), int(dsz0.y + _pause_btn.size.y) / 8, _obstacle_count()]
	# A camera jump re-lays out from scratch rather than sliding across.
	if _lay_center.distance_to(center) > 200.0:
		_lay_snap = true
	_lay_center = center
	if key != _layout_key:
		_layout_key = key
		_choose_layout(center, _target_d / 2.0 + 26.0, br, vp)
	var tb := _bubble_at(center, ring_r, br, vp, _lay_ang)
	var td := _details_at(center, ring_r, vp, _lay_det, Vector2(DETAILS_W, _details_h()))
	if _lay_snap:
		_bub_rel = tb - center
		_det_rel = td - center
		_lay_snap = false
	else:
		var f := 1.0 - exp(-12.0 * _lay_dt)
		_bub_rel = _bub_rel.lerp(tb - center, f)
		_det_rel = _det_rel.lerp(td - center, f)
	var bubble := center + _bub_rel
	var dir := (bubble - center).normalized()
	_ring = {"center": center, "r": ring_r, "from": center + dir * ring_r, "to": bubble - dir * br, "bubble": bubble, "br": br, "alpha": a}
	_ring_color = Defs.team_color(planet.owner_id) if planet.owner_id != 0 else Color(0.8, 0.85, 1.0)
	_ring_color.a = 0.55
	_deco.queue_redraw()
	if is_instance_valid(_bars):
		_bars.queue_redraw()
	for l in [_title, _subtitle, _details, _pause_btn]:
		l.modulate.a = a
	# The build picker opens beside the globe too: the details step aside.
	_details.visible = not (_picker != null and _picker.visible)
	_title.size = Vector2(br * 2.0, 24)
	_title.position = bubble + Vector2(-br, -20)
	_subtitle.size = Vector2(br * 2.0, 18)
	_subtitle.position = bubble + Vector2(-br, 6)
	_details.position = center + _det_rel
	_details_right = _lay_det.x == -1
	# The mining switch sits under the details text.
	var dsz := _details.get_combined_minimum_size()
	_pause_btn.size = _pause_btn.get_combined_minimum_size()
	_pause_btn.position = _details.position + Vector2(maxf(_details.size.x, dsz.x) - _pause_btn.size.x if _details_right else 0.0, maxf(_details.size.y, dsz.y) + 8.0)
	_pause_btn.visible = _pause_btn.visible and _details.visible
	# Where the spice bar can go. A label's drawn width is not its box width
	# (a long line overruns it), so rather than trust the gap, the two rects
	# are compared and the bar is dropped below the text if they touch.
	var bar := Rect2(bubble + Vector2(-br - 2.0, br + SPICE_BAR_TOP - 2.0), Vector2(br * 2.0 + 4.0, SPICE_BAR_H))
	var text := Rect2(_details.position, Vector2(maxf(_details.size.x, _details.get_combined_minimum_size().x),
		maxf(_details.size.y, _details.get_combined_minimum_size().y))).grow(6.0)
	if bar.intersects(text):
		bar.position.y = text.position.y + text.size.y + 6.0
	_ring["spice_y"] = bar.position.y + 2.0

## Height of the details text plus the mining switch under it.
func _details_h() -> float:
	var h := maxf(_details.size.y, _details.get_combined_minimum_size().y)
	if _pause_btn.visible:
		h += 8.0 + _pause_btn.get_combined_minimum_size().y
	return h

func _bubble_at(center: Vector2, ring_r: float, br: float, vp: Vector2, ang: float) -> Vector2:
	var b := center + Vector2.from_angle(ang) * (ring_r + 70.0 + br)
	return b.clamp(Vector2(br + 8, br + 80), vp - Vector2(br + 8, br + 8))

## The bubble plus the reserve bars hanging under it.
func _bubble_box(b: Vector2, br: float) -> Rect2:
	var rows := 0
	if is_instance_valid(planet):
		rows = int(planet.max_mineral_reserve > 0.0) + int(planet.max_spice_reserve > 0.0)
	return Rect2(b - Vector2(br, br), Vector2(br * 2.0, br * 2.0 + (SPICE_BAR_TOP + 30.0 * rows if rows > 0 else 0.0)))

## Top-left of the details for a placement (see _lay_det).
func _details_at(center: Vector2, ring_r: float, vp: Vector2, det: Vector2i, sz: Vector2) -> Vector2:
	var pos: Vector2
	match det.x:
		1:
			pos = Vector2(center.x + ring_r + 24.0, center.y - ring_r * 0.45 + det.y * 80.0)
		-1:
			pos = Vector2(center.x - ring_r - 24.0 - sz.x, center.y - ring_r * 0.45 + det.y * 80.0)
		2:
			pos = Vector2(center.x - sz.x / 2.0, center.y - ring_r - 24.0 - sz.y)
		_:
			pos = Vector2(center.x - sz.x / 2.0, center.y + ring_r + 24.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - 8.0 - sz.x))
	pos.y = clampf(pos.y, 90.0, maxf(90.0, vp.y - 260.0))
	return pos

func _obstacle_count() -> int:
	var n := 0
	for g in STATIONARY_GROUPS:
		n += get_tree().get_nodes_in_group(g).size()
	return n

## Screen-space boxes of the stationary things in view (not the open world).
func _obstacles(vp: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var xf := game.get_viewport().get_canvas_transform()
	var z := game.camera.zoom.x
	var screen := Rect2(Vector2.ZERO, vp)
	for g in STATIONARY_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if n == planet or not (n is Node2D) or not n.is_inside_tree():
				continue
			var r: float = n.get("radius") if n.get("radius") != null else 16.0
			r = maxf(r * z * 1.15, 6.0)
			var box := Rect2((xf * (n as Node2D).global_position) - Vector2(r, r), Vector2(r, r) * 2.0)
			if box.intersects(screen):
				out.append(box)
	return out

static func _cover(r: Rect2, obs: Array[Rect2]) -> float:
	var t := 0.0
	for o in obs:
		if r.intersects(o):
			t += r.intersection(o).get_area()
	return t

## A box reaching into the globe (it can when clamped to the screen).
static func _hits_ring(r: Rect2, center: Vector2, ring_r: float) -> bool:
	return r.grow(4.0).has_point(center) or center.distance_to(Vector2(clampf(center.x, r.position.x, r.end.x), clampf(center.y, r.position.y, r.end.y))) < ring_r

## Picks the bubble angle and details placement that cover the least of the
## stationary things on screen. The default (bubble upper-left, details to
## the right) wins ties, and the current pick is kept unless a candidate is
## clearly better, so the callouts don't hop around.
func _choose_layout(center: Vector2, ring_r: float, br: float, vp: Vector2) -> void:
	var obs := _obstacles(vp)
	var dsz := Vector2(DETAILS_W, _details_h())
	var right_fits := center.x + ring_r + 24.0 + DETAILS_W < vp.x - 8.0
	var bubs: Array = []
	for i in 24:
		var ang := PI * 1.25 + TAU * i / 24.0
		var b := _bubble_at(center, ring_r, br, vp, ang)
		var box := _bubble_box(b, br)
		var cost := _cover(box, obs) + minf(i, 24 - i) * 150.0
		# The bubble keeps clear of the ring; the bars under it only of the
		# globe (by default they already cross the thin ring line).
		var bars := Rect2(box.position.x, b.y + br, box.size.x, box.end.y - b.y - br)
		if b.distance_to(center) < ring_r + br - 2.0 or (bars.size.y > 0.0 and _hits_ring(bars, center, ring_r - 26.0)):
			cost += 1e6
		if box.end.y > vp.y - 200.0:
			cost += (box.end.y - (vp.y - 200.0)) * 40.0
		bubs.append([ang, box, cost])
	var dets: Array = []
	for side in [1, -1, 2, 3]:
		for j in ([0] if side >= 2 else [0, -1, 1, -2, 2, -3, 3]):
			var det := Vector2i(side, j)
			var r := Rect2(_details_at(center, ring_r, vp, det, dsz), dsz).grow(12.0)
			var cost := _cover(r, obs) + absi(j) * 600.0
			if side == -1 and right_fits or side == 1 and not right_fits:
				cost += 2500.0
			elif side >= 2:
				cost += 6000.0
			if _hits_ring(r, center, ring_r):
				cost += 1e6
			dets.append([det, r, cost])
	var best := INF
	var cur := INF
	var pick := [_lay_ang, _lay_det]
	for b in bubs:
		for d in dets:
			var c: float = b[2] + d[2]
			if (b[1] as Rect2).grow(10.0).intersects(d[1]):
				c += 1e6
			if c < best:
				best = c
				pick = [b[0], d[0]]
			if is_equal_approx(b[0], _lay_ang) and d[0] == _lay_det:
				cur = c
	# Keep the current pick unless the new one is clearly better.
	if OS.get_environment("SL_LAYOUT_LOG") != "":
		print("LAYOUT obs=", obs, " best=", best, " cur=", cur, " pick=", rad_to_deg(pick[0]), " ", pick[1], " center=", center, " ring=", ring_r)
	if _layout_key.is_empty() or _lay_snap or best < cur - 1500.0 or best < cur * 0.6:
		_lay_ang = pick[0]
		_lay_det = pick[1]

## The spice reserve bar under the name bubble: how far below the bubble it
## starts, how much room it takes (bar plus its figure), and the gap anything
## beside the bubble keeps from it.
const SPICE_BAR_TOP := 10.0
## Width of the details text beside the globe.
const DETAILS_W := 380.0
const SPICE_BAR_H := 34.0
const SPICE_BAR_GAP := 28.0

## Radius the name bubble needs for the text inside it, with the widest line
## kept clear of the ring. Never smaller than it used to be, so a short name
## still gets the same bubble.
func _bubble_radius() -> float:
	var font := ThemeDB.fallback_font
	var wide: float = font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	for line in _subtitle.text.split("
"):
		wide = maxf(wide, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	return clampf(wide / 2.0 + 16.0, 58.0, 130.0)

## Borderless outlined text that floats over the map.
func _float_label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## Spice reserve and mineral crust on one line, with a tooltip on both.
func _reserves_line() -> String:
	var parts: Array[String] = []
	if planet.type_def().has("spice_reserve"):
		parts.append("%s Reserve %s%s" % [_ic("spice"), _num(planet.spice_reserve), " (exhausted)" if planet.spice_reserve <= 0.0 else ""])
	parts.append("%s Crust %s / %s%s" % [_ic("minerals"), _num(planet.mineral_reserve), _num(planet.max_mineral_reserve), " (paused)" if planet.mining_paused else ""])
	var tip := "Reserve: spice stored in this world; Spice Extractors draw it down and it never refills.\nCrust: this world's remaining minerals (%s per size); Mining Complexes dig it out. At 0 crust the world implodes, %d s later, destroying everything on it and hitting everything nearby. Pause mining to stop." % [_num(Defs.WORLD_RESERVE_PER_SIZE), int(Defs.DOOM_SECONDS)]
	return "[hint=%s]%s[/hint]" % [_hint(tip), "  ·  ".join(parts)]

## Thousands separators: 24,500.
func _num(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

## A [hint] tooltip text, with the characters that would break the tag escaped.
func _hint(t: String) -> String:
	return "\"" + t.replace("\n", " ").replace("\"", "'").replace("]", ")").replace("[", "(") + "\""

## A resource icon inline in the details text (icon_<name>.png).
func _ic(name: String) -> String:
	return "[img=16x16]%sicon_%s.png[/img]" % [Defs.PIXEL, name]

## Ring around the planet, a leader line out to a small name bubble.
func _draw_deco() -> void:
	if _ring.is_empty():
		return
	var c: Color = _ring_color
	c.a *= _ring["alpha"]
	_deco.draw_arc(_ring["center"], _ring["r"], 0.0, TAU, 128, c, 1.5, true)
	_deco.draw_line(_ring["from"], _ring["to"], c, 1.5, true)
	_deco.draw_circle(_ring["bubble"], _ring["br"], Color(0.02, 0.03, 0.08, 0.55 * _ring["alpha"]))
	_draw_info_bubble(c)
	_deco.draw_arc(_ring["bubble"], _ring["br"], 0.0, TAU, 64, c, 1.5, true)

## Reserve bars under the name bubble: the mineral crust, then the spice
## reserve below it, each in its resource color. Drawn on _bars, above the
## planet, so they stay readable where the bubble overlaps it.
func _draw_bars() -> void:
	if _ring.is_empty() or not is_instance_valid(planet):
		return
	var w: float = _ring["br"] * 2.0
	var tl := Vector2(_ring["bubble"].x - _ring["br"], _ring.get("spice_y", _ring["bubble"].y + _ring["br"] + SPICE_BAR_TOP))
	var rows: Array = []
	if planet.max_mineral_reserve > 0.0:
		rows.append(["Crust", planet.mineral_reserve, planet.max_mineral_reserve, Defs.RESOURCE_COLORS["minerals"]])
	if planet.max_spice_reserve > 0.0:
		rows.append(["Spice", planet.spice_reserve, planet.max_spice_reserve, Defs.RESOURCE_COLORS["spice"]])
	for i in rows.size():
		_reserve_bar(tl + Vector2(0, 30 * i), w, rows[i][0], rows[i][1], rows[i][2], rows[i][3])

## One reserve bar with its "Name now / max" caption centred below it.
func _reserve_bar(tl: Vector2, w: float, name: String, now: float, cap: float, sc: Color) -> void:
	var frac := clampf(now / cap, 0.0, 1.0)
	_bars.draw_rect(Rect2(tl - Vector2(2, 2), Vector2(w + 4, 12)), Color(0, 0, 0, 0.7 * _ring["alpha"]))
	_bars.draw_rect(Rect2(tl, Vector2(w * frac, 8)), Color(sc, _ring["alpha"]))
	_bars.draw_rect(Rect2(tl - Vector2(2, 2), Vector2(w + 4, 12)), Color(sc, 0.8 * _ring["alpha"]), false, 1.0)
	# Centred under the bar but never clipped to its width (big reserves
	# such as 30k / 30k run wider than the bar).
	var txt := "%s %s / %s" % [name, Defs.short_num(now), Defs.short_num(cap)]
	var tw: float = get_theme_default_font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	# A thin black outline keeps it legible over rocks and nebulae.
	_bars.draw_string_outline(get_theme_default_font(), tl + Vector2((w - tw) / 2.0, 24), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 6, Color(0, 0, 0, 0.9 * _ring["alpha"]))
	_bars.draw_string(get_theme_default_font(), tl + Vector2((w - tw) / 2.0, 24), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(sc, _ring["alpha"]))

## The world info panel sits in a rounded bubble styled like the name
## bubble, with its own leader line from the ring.
func _draw_info_bubble(c: Color) -> void:
	if not _details.visible:
		return
	var dsz := _details.get_combined_minimum_size()
	var r := Rect2(_details.position, Vector2(maxf(_details.size.x, dsz.x), maxf(_details.size.y, dsz.y)))
	if _pause_btn.visible:
		r = r.merge(Rect2(_pause_btn.position, _pause_btn.size))
	r = r.grow(12.0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.02, 0.03, 0.08, 0.55 * _ring["alpha"])
	st.border_color = c
	st.set_border_width_all(2)
	st.set_corner_radius_all(16)
	st.anti_aliasing = true
	st.draw(_deco.get_canvas_item(), r)
	# Leader line: from the ring toward the bubble's nearest side.
	var cx: Vector2 = _ring["center"]
	var edge := Vector2(r.position.x if r.get_center().x > cx.x else r.end.x, clampf(cx.y, r.position.y + 16.0, r.end.y - 16.0))
	if cx.x > r.position.x + 16.0 and cx.x < r.end.x - 16.0:
		edge = Vector2(cx.x, r.end.y if r.get_center().y < cx.y else r.position.y)
	var dir: Vector2 = (edge - _ring["center"]).normalized()
	_deco.draw_line(_ring["center"] + dir * _ring["r"], edge, c, 1.5, true)

func _slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	return st

## Smallest circle radius that fits n fixed-size slots.
func _radius_for(n: int) -> float:
	var r := float(SLOT)
	while _layout_slots(n, r).size() < n:
		r += 4.0
	return r

## Places n SLOT-sized squares in centered rows inside a circle of radius r
## (slot corners stay on the planet), using the fewest rows possible and
## trimming the widest rows so the shape stays balanced. Returns rects
## relative to the circle's center, or fewer than n if they don't fit.
func _layout_slots(n: int, r: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if n <= 0:
		return out
	var s := float(SLOT)
	var pitch := s + SLOT_GAP
	var max_rows := int((2.0 * r + SLOT_GAP) / pitch)
	for k in range(1, max_rows + 1):
		var counts: Array[int] = []
		var ys: Array[float] = []
		for j in k:
			var y := (j - (k - 1) / 2.0) * pitch
			var reach := absf(y) + s / 2.0
			if reach >= r:
				counts.append(0)
			else:
				var chord := 2.0 * sqrt(r * r - reach * reach)
				counts.append(maxi(0, int((chord + SLOT_GAP) / pitch)))
			ys.append(y)
		var total := 0
		for c in counts:
			total += c
		if total < n:
			continue
		while total > n:
			var best := 0
			for j in k:
				if counts[j] > counts[best] or (counts[j] == counts[best] and absf(ys[j]) > absf(ys[best])):
					best = j
			counts[best] -= 1
			total -= 1
		for j in k:
			var w := counts[j] * pitch - SLOT_GAP
			for c in counts[j]:
				out.append(Rect2(Vector2(-w / 2.0 + c * pitch, ys[j] - s / 2.0), Vector2(s, s)))
		return out
	return out

func refresh() -> void:
	if planet == null or not visible:
		return
	if not is_instance_valid(planet):
		game.clear_planet_focus()
		return
	var t := planet.type_def()
	var mine := planet.owner_id == game.player_id
	var used0 := planet.fields - planet.buildings.count("")
	_title.text = planet.planet_name
	_title.add_theme_color_override("font_color", Defs.team_color(planet.owner_id) if planet.owner_id != 0 else Color(0.85, 0.9, 1.0))
	_subtitle.text = ("%s · Size %d" % [t["label"], planet.fields]) if planet.fields > 0 else t["label"]
	var owner_text := "Unclaimed" if planet.owner_id == 0 else ("Your world" if mine else ("Allied world" if game.are_allies(planet.owner_id, game.player_id) else "Enemy world"))
	var s := owner_text
	# The planetary shield sits under the owner label, at the right.
	if planet.owner_id != 0 and planet.is_habitable():
		s += "\n%s Planetary shield %d / %d" % [_ic("layer_shield"), int(planet.shield), int(planet.max_shield())]
	for tr in Defs.planet_traits(planet.kind):
		s += "\n" + tr
	if not planet.is_habitable():
		s = "Uninhabitable. No regions to build on; cannot be colonized."
		s += "\nMineral reserve: %d / %d (never refills)" % [planet.amount, Defs.GAS_RESERVE]
		if planet.doom_timer >= 0.0:
			s += "\nUNSTABLE: EXPLODES IN %d s (%d damage at the centre, out to %d px)" % [int(ceil(planet.doom_timer)), int(Defs.BLAST_DAMAGE), int(Defs.BLAST_RADIUS)]
		elif planet.unstable():
			s += "\nUNSTABLE: explodes %d s after it is drained (%d damage at the centre, out to %d px)" % [int(Defs.DOOM_SECONDS), int(Defs.BLAST_DAMAGE), int(Defs.BLAST_RADIUS)]
		s += "\nMine it with Gas Skimmers (research Gas Skimming)."
		s += "\nSkimmers haul what they mine back to a starbase."
	elif planet.owner_id != 0:
		# Population and what it multiplies output by, on one line.
		s += "\n[hint=%s]%s %d / %d  (+%d/min)  ·  x%.2f output[/hint]" % [_hint("Population / cap (growth per minute). Pops multiply the output of every Farm, Power Plant, Mining Complex and Spice Extractor on this world: x%.2f here." % planet.pop_output_mult()), _ic("pop"), int(planet.pop), int(planet.max_pop()), int(planet.growth_per_min), planet.pop_output_mult()]
		if planet.under_siege():
			s += "\nUNDER BOMBARDMENT: %s, %d%% of pops left" % ["growth halted" if planet.growth_halted() else "shield holding", int(ceil(100.0 * planet.pop / maxf(planet.siege_start_pop, 1.0)))]
		# Population is the whole reason to grow a world now: it multiplies
		# what every building on it produces.
		# NET per minute this world adds to (or takes from) the stockpiles:
		# its buildings' output minus food eaten, Power Plant fuel and
		# building upkeep (Planet.net_per_min). Breakdown in the hint.
		var net := planet.net_per_min()
		var nets := ""
		for k in ["food", "energy", "minerals", "spice"]:
			var v: float = net[k]
			var c := "6fe07a" if v > 0.05 else ("ff6a5a" if v < -0.05 else "c3cde4")
			nets += "%s [color=#%s]%s[/color]   " % [_ic(k), c, HUD._signed(v)]
		var tip := "Net per minute from this world: what its buildings make minus what it uses.\nFood: grown %.1f, eaten %.1f\nEnergy: made %.1f, building upkeep %.1f%s (Farm 2, Mining Complex 4, Defense Battery 3, Spice Extractor 5; Habitats and Power Plants none)\nMinerals: dug %.1f, Power Plant fuel %.1f\nSpice: extracted %.1f\nConstruction costs are not included." % [
			planet.food_made_per_min, planet.food_eaten_per_min, planet.energy_out, planet.energy_upkeep_per_min(), " (not drawn in a Blackout)" if planet.blacked_out() else "", planet.minerals_out, planet.fuel_per_min, planet.spice_out]
		s += "\n[hint=%s]%s /min[/hint]" % [_hint(tip), nets.strip_edges()]
		if planet.count_building("generator") > 0 and planet.fuel_frac < 0.999:
			s += "\n[color=#ff6a5a]NO FUEL: Power Plants stopped (no minerals to burn)[/color]"
		if planet.blacked_out():
			s += "\n[color=#ff6a5a]BLACKOUT: buildings on LOW POWER (%d%% output, battery shield and fire rate). Deliver minerals to restart Power Plants. Restoring power: %d s[/color]" % [int(Defs.ENERGY_STARVED_FACTOR * 100.0), int(ceil(Game.instance.blackout_restore_left(planet.owner_id)))]
		if planet.doom_timer >= 0.0:
			s += "\nUNSTABLE: IMPLODES IN %d s (%d damage, %d px)" % [int(ceil(planet.doom_timer)), int(Defs.BLAST_DAMAGE * planet.blast_scale()), int(planet.blast_radius())]
		elif planet.unstable():
			s += "\nUNSTABLE: implodes %d s after the crust runs out (%d damage, %d px)" % [int(Defs.DOOM_SECONDS), int(Defs.BLAST_DAMAGE * planet.blast_scale()), int(planet.blast_radius())]
		if planet.starving:
			s += "\nSTARVING: shrinking %d/min until food recovers" % int(-planet.growth_per_min)
	else:
		s += "\nPop cap %d\nSend a Colony Ship to settle it." % int(planet.max_pop())
		if planet.colonizing_owner != 0:
			s += "\nBeing colonized: %d%%" % int(100.0 * planet.colonize_progress / Planet.COLONIZE_TIME)
	if mine and planet.fields > 0:
		if planet.construction.is_empty():
			s += "\nNo construction. Click an empty field to build." if planet.free_fields() > 0 else "\nAll fields in use."
		else:
			var cd: Dictionary = Defs.BUILDINGS[planet.construction["id"]]
			s += "\nBuilding %s: %d%%%s. %d more queued." % [cd["name"], int(100.0 * planet.construction["progress"] / cd["time"]), " (STALLED: insufficient funds)" if planet.construction_stalled else "", planet.construction_queue.size()]
	_pause_btn.visible = mine and planet.is_habitable()
	_pause_btn.text = "Resume mining" if planet.mining_paused else "Pause mining"
	stats = s
	_details.text = ("[right]%s[/right]" % s) if _details_right else s
	for i in _field_buttons.size():
		var b := _field_buttons[i]
		var built: String = planet.buildings[i]
		var job := planet.field_job(i)
		if built != "":
			(b.get_node("Art") as TextureRect).texture = Defs.tex("bld_" + built)
			# A finished building always runs; only an extractor whose reserve
			# is gone goes dark.
			var dry: bool = planet.is_dry(i) or planet.is_paused(i)
			var offline: bool = not dry and planet.power_factor(built) < 1.0
			b.text = ("PAUSED" if built == "mine" else "DRY") if dry else ("25%" if offline else "")
			b.modulate = Color(1, 1, 1, 0.4) if dry else (Color(1, 0.7, 0.45) if offline else Color.WHITE)
			(b.get_node("Art") as TextureRect).modulate = Color.WHITE
			_progress_text(b, Color("ffa040") if offline else (Color("ffd46b") if dry else Color.WHITE), 13)
			b.tooltip_text = "%s%s\n%s%s" % [Defs.BUILDINGS[built]["name"], " (dry: the reserve is gone)" if planet.is_dry(i) else (" (LOW POWER: Blackout, 25%)" if offline else ""), Defs.BUILDINGS[built]["desc"], "\nClick to demolish." if mine else ""]
		elif job != "":
			var art := b.get_node("Art") as TextureRect
			art.texture = Defs.tex("bld_" + job)
			var active: bool = planet.construction.get("field", -1) == i
			# Dim the ghosted building art, not the label on top of it: the
			# progress figure stays bright and outlined so it reads at a glance.
			b.modulate = Color.WHITE
			if active:
				b.text = "%d%%" % int(100.0 * planet.construction["progress"] / Defs.BUILDINGS[job]["time"])
				art.modulate = Color(1, 1, 1, 0.5)
				_progress_text(b, Color("ff8a7a") if planet.construction_stalled else Color("ffd46b"), 22)
			else:
				b.text = "queued"
				art.modulate = Color(1, 1, 1, 0.3)
				_progress_text(b, Color(1, 1, 1, 0.75), 13)
			b.tooltip_text = "%s under construction.\nClick to cancel (paid share refunded)." % Defs.BUILDINGS[job]["name"]
		else:
			(b.get_node("Art") as TextureRect).texture = null
			b.text = "+" if mine else ""
			b.modulate = Color.WHITE if mine else Color(1, 1, 1, 0.4)
			_progress_text(b, Color(1, 1, 1, 0.8), 16)
			b.tooltip_text = "Empty field. Click to build." if mine else "Empty field."
		b.disabled = not mine

## Big, outlined text over a build slot's ghosted art, so "62%" is readable
## against whatever the building sprite looks like.
func _progress_text(b: Button, color: Color, size: int = 20) -> void:
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 6)

func _on_field_pressed(i: int) -> void:
	if planet == null or planet.owner_id != game.player_id:
		return
	_menu_field = i
	_picker_keys.clear()
	for c in _picker_list.get_children():
		c.queue_free()
	var built: String = planet.buildings[i]
	var job := planet.field_job(i)
	if built != "":
		_add_pick("Demolish %s (no refund)" % Defs.BUILDINGS[built]["name"], "bld_" + built, {}, -1.0, 1000, "")
	elif job != "":
		_add_pick("Cancel %s (paid share refunded)" % Defs.BUILDINGS[job]["name"], "bld_" + job, {}, -1.0, 1001, "")
	else:
		for n in Defs.BUILDING_ORDER.size():
			var id: String = Defs.BUILDING_ORDER[n]
			var d: Dictionary = Defs.BUILDINGS[id]
			_add_pick(d["name"], "bld_" + id, d["cost"], d["time"], n, planet.can_build(i, id), d["desc"])
	_picker.reset_size()
	var want := Vector2i(get_viewport().get_mouse_position()) + Vector2i(12, 12)
	var win := Vector2i(get_viewport().get_visible_rect().size)
	want.x = clampi(want.x, 0, win.x - _picker.size.x - 8)
	want.y = clampi(want.y, 0, win.y - _picker.size.y - 8)
	_picker.position = want + get_window().position
	_picker.popup()
	# Size is only final once shown; nudge back inside the window if needed.
	var sz := _picker.size
	var p := _picker.position - get_window().position
	p.x = clampi(p.x, 0, win.x - sz.x - 8)
	p.y = clampi(p.y, 0, win.y - sz.y - 8)
	_picker.position = p + get_window().position

## One row in the build picker: building art, name, and its cost with
## resource icons. Disabled rows show why in their tooltip.
func _add_pick(title: String, art: String, cost: Dictionary, seconds: float, action: int, why: String, desc: String = "") -> void:
	var b := Button.new()
	var key_i := _picker_keys.size()
	var pkeys := HUD.panel_keys()
	if key_i < pkeys.size():
		var k: Key = pkeys[key_i]
		_picker_keys[k] = b
		var tag := Label.new()
		tag.text = OS.get_keycode_string(k)
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", Color(0.76, 0.81, 0.91, 0.75))
		tag.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		tag.offset_left = -14
		tag.offset_top = -17
		tag.offset_right = -3
		tag.offset_bottom = -2
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tag)
	b.custom_minimum_size = Vector2(420, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else desc
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = Defs.tex(art)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var name_l := Label.new()
	name_l.text = title
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(name_l)
	if not cost.is_empty():
		var row := CostRow.make(cost, 13, seconds)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(row)
	b.add_child(h)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.45)
	b.pressed.connect(_on_menu.bind(action))
	_picker_list.add_child(b)

func _on_menu(id: int) -> void:
	if planet == null or _menu_field < 0:
		return
	_picker.hide()
	if id == 1000:
		planet.demolish(_menu_field)
	elif id == 1001:
		planet.cancel_build(_menu_field)
	else:
		var why := planet.order_build(_menu_field, Defs.BUILDING_ORDER[id])
		_picker.hide()
		if why != "":
			game.message.emit(why + ".", HUD.BAD)
			game.sfx.play_ui("deny")
			return
	game.sfx.play_ui("click")
	refresh()

## Grid hotkeys inside the build picker: the popup is its own window, so its
## key events arrive here.
func _on_picker_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_picker.hide()
		return
	var b = _picker_keys.get(event.keycode)
	if b != null and is_instance_valid(b) and not b.disabled:
		b.pressed.emit()

## Opens the build picker on this planet's first free field (the F key).
func open_build_picker() -> bool:
	if planet == null or planet.owner_id != game.player_id:
		return false
	for i in planet.fields:
		if planet.buildings[i] == "" and planet.field_job(i) == "":
			_on_field_pressed(i)
			return true
	return false
