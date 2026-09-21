class_name PlanetView
extends PanelContainer
## Pop-up close-up of a selected planet: a big pixel render of the world,
## its population/economy, and its grid of building fields. On your own
## planets, click an empty field to order a building, click a building to
## demolish it, or click one under construction to cancel it. The game
## keeps running while it's open.

const FIELD_PX := 64
const COLS := 6

var game: Game
var planet: Planet

var _art: TextureRect
var _title: Label
var _stats: Label
var _fields_title: Label
var _grid: GridContainer
var _status: Label
var _picker: PopupPanel
var _picker_list: VBoxContainer
var _menu_field: int = -1
var _field_buttons: Array[Button] = []

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HUD.BG, 0.96)
	sb.border_color = HUD.EDGE_LIT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var head := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = " X "
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(func(): game.clear_planet_focus())
	head.add_child(close)
	root.add_child(head)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(240, 240)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	left.add_child(_art)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.custom_minimum_size = Vector2(270, 0)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_stats)
	body.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	_fields_title = Label.new()
	_fields_title.add_theme_font_size_override("font_size", 16)
	right.add_child(_fields_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLS * (FIELD_PX + 6), 5 * (FIELD_PX + 6))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	right.add_child(scroll)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(COLS * (FIELD_PX + 6), 0)
	right.add_child(_status)
	body.add_child(right)

	_picker = PopupPanel.new()
	_picker_list = VBoxContainer.new()
	_picker_list.add_theme_constant_override("separation", 4)
	_picker.add_child(_picker_list)
	add_child(_picker)

func show_planet(p: Planet) -> void:
	planet = p
	visible = p != null
	if p == null:
		_picker.hide()
		return
	# Big version of the planet: same pixel art, scaled up crisply.
	_art.texture = Defs.tex(p.kind)
	var scale_px := maxi(1, int(240.0 / (p.get_node("Sprite") as Sprite2D).texture.get_width()))
	_art.custom_minimum_size = Vector2.ONE * (p.get_node("Sprite") as Sprite2D).texture.get_width() * scale_px
	for c in _grid.get_children():
		c.queue_free()
	_field_buttons.clear()
	for i in p.fields:
		var b := Button.new()
		b.custom_minimum_size = Vector2(FIELD_PX, FIELD_PX)
		b.focus_mode = Control.FOCUS_NONE
		# Building art as a crisp 3x child image; the button text shows progress.
		var art := TextureRect.new()
		art.name = "Art"
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 8
		art.offset_top = 8
		art.offset_right = -8
		art.offset_bottom = -8
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_field_pressed.bind(i))
		_grid.add_child(b)
		_field_buttons.append(b)
	refresh()

func refresh() -> void:
	if planet == null or not visible:
		return
	if not is_instance_valid(planet):
		game.clear_planet_focus()
		return
	var t := planet.type_def()
	var mine := planet.owner_id == game.player_id
	_title.text = ("%s  ·  %s  ·  Size %d" % [planet.planet_name, t["label"], planet.fields]) if planet.fields > 0 else "%s  ·  %s" % [planet.planet_name, t["label"]]
	_title.add_theme_color_override("font_color", Defs.team_color(planet.owner_id))
	var owner_text := "Unclaimed" if planet.owner_id == 0 else ("Your world" if mine else "Enemy world")
	var s := owner_text
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
		s += "\nBuildings need %d pop (%d unassigned)" % [planet.pop_required(), int(planet.idle_pop)]
		var idle := 0
		for k in planet.fields:
			if planet.buildings[k] != "" and not planet.operating[k]:
				idle += 1
		if idle > 0:
			s += "\n%d building%s IDLE: not enough pop" % [idle, "" if idle == 1 else "s"]
		s += "\nFood grown %d/min, eaten %d/min" % [int(planet.food_made_per_min), int(planet.food_eaten_per_min)]
		s += "\nEnergy %.1f/s" % planet.energy_out
		if planet.spice_out > 0.0:
			s += "   Spice %.2f/s" % planet.spice_out
		if planet.starving:
			s += "\nSTARVING: %d pops die in %ds unless fed" % [int(planet.hungry), int(Defs.STARVE_SECONDS - planet.starve_timer)]
	else:
		s += "\nPop cap %d\nSend a Colony Ship to settle it." % int(planet.max_pop())
	_stats.text = s
	var used := planet.fields - planet.buildings.count("")
	_fields_title.text = ("Fields: %d / %d built" % [used, planet.fields]) if planet.fields > 0 else "No habitable regions"
	for i in _field_buttons.size():
		var b := _field_buttons[i]
		var built: String = planet.buildings[i]
		var job := planet.field_job(i)
		if built != "":
			(b.get_node("Art") as TextureRect).texture = Defs.tex("bld_" + built)
			var running: bool = planet.operating[i] if i < planet.operating.size() else true
			b.text = "" if running else "IDLE"
			b.modulate = Color.WHITE if running else Color(1, 1, 1, 0.4)
			b.tooltip_text = "%s%s\n%s%s" % [Defs.BUILDINGS[built]["name"], "" if running else " (idle: not enough pop)", Defs.BUILDINGS[built]["desc"], "\nClick to demolish." if mine else ""]
		elif job != "":
			(b.get_node("Art") as TextureRect).texture = Defs.tex("bld_" + job)
			var active: bool = planet.construction.get("field", -1) == i
			if active:
				b.text = "%d%%" % int(100.0 * planet.construction["progress"] / Defs.BUILDINGS[job]["time"])
				b.modulate = Color(1, 0.6, 0.55, 0.8) if planet.construction_stalled else Color(1, 1, 1, 0.6)
			else:
				b.text = "queued"
				b.modulate = Color(1, 1, 1, 0.35)
			b.tooltip_text = "%s under construction.\nClick to cancel (paid share refunded)." % Defs.BUILDINGS[job]["name"]
		else:
			(b.get_node("Art") as TextureRect).texture = null
			b.text = "+" if mine else ""
			b.modulate = Color.WHITE if mine else Color(1, 1, 1, 0.4)
			b.tooltip_text = "Empty field. Click to build." if mine else "Empty field."
		b.disabled = not mine
	if not mine:
		_status.text = ""
	elif planet.construction.is_empty():
		_status.text = "No construction. Click an empty field to build." if planet.free_fields() > 0 else "All fields in use."
	else:
		var d: Dictionary = Defs.BUILDINGS[planet.construction["id"]]
		_status.text = "Building %s: %d%%%s. %d more queued." % [d["name"], int(100.0 * planet.construction["progress"] / d["time"]), " (STALLED: waiting for resources)" if planet.construction_stalled else "", planet.construction_queue.size()]

func _on_field_pressed(i: int) -> void:
	if planet == null or planet.owner_id != game.player_id:
		return
	_menu_field = i
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

## One row in the build picker: building art, name, and its cost with
## resource icons. Disabled rows show why in their tooltip.
func _add_pick(title: String, art: String, cost: Dictionary, seconds: float, action: int, why: String, desc: String = "") -> void:
	var b := Button.new()
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
