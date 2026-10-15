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
var _details: Label
## Draws the subtle ring around the planet, the leader line and the name bubble.
var _deco: Control
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
	_title = _float_label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle = _float_label(12, HORIZONTAL_ALIGNMENT_CENTER)
	_details = _float_label(14, HORIZONTAL_ALIGNMENT_RIGHT)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	var dir := Vector2(-1, -1).normalized()
	# The bubble is sized to what it has to hold: a long name or a big world's
	# "Size 30 · 30/30 built" used to run out through the ring.
	var br := _bubble_radius()
	var bubble := center + dir * (ring_r + 70.0 + br)
	var vp := get_viewport_rect().size
	bubble = bubble.clamp(Vector2(br + 8, br + 80), vp - Vector2(br + 8, br + 8))
	_ring = {"center": center, "r": ring_r, "from": center + dir * ring_r, "to": bubble - (bubble - (center + dir * ring_r)).normalized() * br, "bubble": bubble, "br": br, "alpha": a}
	_ring_color = Defs.team_color(planet.owner_id) if planet.owner_id != 0 else Color(0.8, 0.85, 1.0)
	_ring_color.a = 0.55
	_deco.queue_redraw()
	for l in [_title, _subtitle, _details]:
		l.modulate.a = a
	_title.size = Vector2(br * 2.0, 24)
	_title.position = bubble + Vector2(-br, -20)
	_subtitle.size = Vector2(br * 2.0, 18)
	_subtitle.position = bubble + Vector2(-br, 6)
	# The spice bar hangs under the bubble (see _draw_deco), so the details
	# have to clear it: a wide gap when they sit beside the bubble, and a
	# start below it when they sit underneath.
	_details.size = Vector2(340, 0)
	_details.position = Vector2(bubble.x - br - SPICE_BAR_GAP - 340.0, bubble.y - 10)
	if _details.position.x < 8:
		# No room on the left: float the details under the bubble, clear of
		# the bar and its figure.
		_details.position = Vector2(maxf(8.0, bubble.x - 170), bubble.y + br + SPICE_BAR_H + 12.0)
		_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Where the spice bar can go. A label's drawn width is not its box width
	# (a long line overruns it), so rather than trust the gap, the two rects
	# are compared and the bar is dropped below the text if they touch.
	var bar := Rect2(bubble + Vector2(-br - 2.0, br + SPICE_BAR_TOP - 2.0), Vector2(br * 2.0 + 4.0, SPICE_BAR_H))
	var text := Rect2(_details.position, Vector2(maxf(_details.size.x, _details.get_combined_minimum_size().x),
		maxf(_details.size.y, _details.get_combined_minimum_size().y))).grow(6.0)
	if bar.intersects(text):
		bar.position.y = text.position.y + text.size.y + 6.0
	_ring["spice_y"] = bar.position.y + 2.0

## The spice reserve bar under the name bubble: how far below the bubble it
## starts, how much room it takes (bar plus its figure), and the gap anything
## beside the bubble keeps from it.
const SPICE_BAR_TOP := 10.0
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

## Ring around the planet, a leader line out to a small name bubble.
func _draw_deco() -> void:
	if _ring.is_empty():
		return
	var c: Color = _ring_color
	c.a *= _ring["alpha"]
	_deco.draw_arc(_ring["center"], _ring["r"], 0.0, TAU, 128, c, 1.5, true)
	_deco.draw_line(_ring["from"], _ring["to"], c, 1.5, true)
	_deco.draw_circle(_ring["bubble"], _ring["br"], Color(0.02, 0.03, 0.08, 0.55 * _ring["alpha"]))
	_deco.draw_arc(_ring["bubble"], _ring["br"], 0.0, TAU, 64, c, 1.5, true)
	# Spice reserve bar under the name bubble, in the spice color.
	if is_instance_valid(planet) and planet.max_spice_reserve > 0.0:
		var sc: Color = Defs.RESOURCE_COLORS["spice"]
		var w: float = _ring["br"] * 2.0
		var tl := Vector2(_ring["bubble"].x - _ring["br"], _ring.get("spice_y", _ring["bubble"].y + _ring["br"] + SPICE_BAR_TOP))
		var frac := clampf(planet.spice_reserve / planet.max_spice_reserve, 0.0, 1.0)
		_deco.draw_rect(Rect2(tl - Vector2(2, 2), Vector2(w + 4, 12)), Color(0, 0, 0, 0.7 * _ring["alpha"]))
		_deco.draw_rect(Rect2(tl, Vector2(w * frac, 8)), Color(sc, _ring["alpha"]))
		_deco.draw_rect(Rect2(tl - Vector2(2, 2), Vector2(w + 4, 12)), Color(sc, 0.8 * _ring["alpha"]), false, 1.0)
		_deco.draw_string(get_theme_default_font(), tl + Vector2(0, 24), "Spice %d / %d" % [int(planet.spice_reserve), int(planet.max_spice_reserve)], HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(sc, _ring["alpha"]))

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
	_subtitle.text = ("%s · Size %d
%d/%d built" % [t["label"], planet.fields, used0, planet.fields]) if planet.fields > 0 else t["label"]
	var owner_text := "Unclaimed" if planet.owner_id == 0 else ("Your world" if mine else "Enemy world")
	var s := owner_text
	for tr in Defs.planet_traits(planet.kind):
		s += "\n" + tr
	if not planet.is_habitable():
		s = "Uninhabitable. No regions to build on; cannot be colonized."
		if planet.depleted_timer > 0.0:
			var left := int(planet.depleted_timer)
			s += "\nDEPLETED: reserve refills in %d:%02d" % [left / 60, left % 60]
		else:
			s += "\nMineral reserve: %d" % planet.amount
		s += "\nMine it with Gas Skimmers (research Gas Skimming)."
		s += "\nSkimmers haul what they mine back to a starbase."
	elif planet.owner_id != 0:
		s += "\nPopulation %d / %d  (+%d/min)" % [int(planet.pop), int(planet.max_pop()), int(planet.growth_per_min)]
		s += "\nPlanetary shield %d / %d" % [int(planet.shield), int(planet.max_shield())]
		if planet.type_def().has("spice_reserve"):
			s += "\nSpice reserve: %d%s" % [int(planet.spice_reserve), "  (exhausted)" if planet.spice_reserve <= 0.0 else ""]
		if planet.under_siege():
			s += "\nUNDER BOMBARDMENT: growth halted, %d%% of pops left" % int(ceil(100.0 * planet.pop / maxf(planet.siege_start_pop, 1.0)))
		# Population is the whole reason to grow a world now: it multiplies
		# what every building on it produces.
		s += "\nPopulation bonus: x%.2f on every building here" % planet.pop_output_mult()
		s += "\nFood grown %.1f/min, eaten %.1f/min" % [planet.food_made_per_min, planet.food_eaten_per_min]
		s += "\nEnergy %.0f/min" % planet.energy_out
		if planet.spice_out > 0.0:
			s += "   Spice %.1f/min" % planet.spice_out
		if planet.starving:
			s += "\nSTARVING: shrinking %d/min until food recovers" % int(-planet.growth_per_min)
	else:
		s += "\nPop cap %d\nSend a Colony Ship to settle it." % int(planet.max_pop())
		if planet.type_def().has("spice_reserve"):
			s += "\nSpice reserve: %d (extract with Spice Extractors)" % int(planet.spice_reserve)
		if planet.colonizing_owner != 0:
			s += "\nBeing colonized: %d%%" % int(100.0 * planet.colonize_progress / Planet.COLONIZE_TIME)
	if mine and planet.fields > 0:
		if planet.construction.is_empty():
			s += "\nNo construction. Click an empty field to build." if planet.free_fields() > 0 else "\nAll fields in use."
		else:
			var cd: Dictionary = Defs.BUILDINGS[planet.construction["id"]]
			s += "\nBuilding %s: %d%%%s. %d more queued." % [cd["name"], int(100.0 * planet.construction["progress"] / cd["time"]), " (STALLED: insufficient funds)" if planet.construction_stalled else "", planet.construction_queue.size()]
	stats = s
	_details.text = s
	for i in _field_buttons.size():
		var b := _field_buttons[i]
		var built: String = planet.buildings[i]
		var job := planet.field_job(i)
		if built != "":
			(b.get_node("Art") as TextureRect).texture = Defs.tex("bld_" + built)
			# A finished building always runs; only an extractor whose reserve
			# is gone goes dark.
			var dry: bool = planet.is_dry(i)
			b.text = "DRY" if dry else ""
			b.modulate = Color(1, 1, 1, 0.4) if dry else Color.WHITE
			(b.get_node("Art") as TextureRect).modulate = Color.WHITE
			_progress_text(b, Color("ffd46b") if dry else Color.WHITE, 13)
			b.tooltip_text = "%s%s\n%s%s" % [Defs.BUILDINGS[built]["name"], " (dry: the reserve is gone)" if dry else "", Defs.BUILDINGS[built]["desc"], "\nClick to demolish." if mine else ""]
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
