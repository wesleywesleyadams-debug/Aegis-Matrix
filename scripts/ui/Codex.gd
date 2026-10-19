extends Control
## In-game Codex: the manual, built from the game's own data (Defs.SHIPS,
## VARIANTS, JOBS, TECHS, BUILDINGS, PLANET_TYPES, SystemGen.SYSTEMS), so it
## always matches the current balance instead of repeating it in prose.
## Reached from the title menu's Codex button; docs/SHIP_VARIANTS.md is the
## same material outside the game.

const BG := Color("0a0c1a")
const PANEL := Color("141833")
const EDGE := Color("2b3a6b")
const EDGE_LIT := Color("4fb4ff")
const TEXT := Color("ffffff")
const DIM := Color("e8eefc")
const BACK_RED := Color("ff6b6b")

const SECTIONS := [
	["overview", "Overview"],
	["controls", "Controls"],
	["combat", "Combat"],
	["ships", "Ships"],
	["research", "Research"],
	["economy", "Economy"],
	["systems", "Systems"],
	["terms", "Terminology"],
]

const COL_GAP := 32.0

var _body: VBoxContainer          ## staging: pages build here, then _flow()
var _rows: VBoxContainer          ## the laid-out page (see _flow)
var _nav_buttons := {}
var _current := "overview"
## Opened over a running match (from the pause menu) instead of from the
## title screen: Back closes the overlay and leaves the match alone.
var overlay := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_top = 28
	root.offset_right = -40
	root.offset_bottom = -28
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var title := _label("CODEX", TEXT, 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(260, 0)
	nav.add_theme_constant_override("separation", 8)
	cols.add_child(nav)
	for s in SECTIONS:
		var b := Button.new()
		b.text = s[1]
		b.custom_minimum_size = Vector2(0, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func(): _show(s[0]))
		nav.add_child(b)
		_nav_buttons[s[0]] = b
	# Leaving sits at the bottom of the same column, in red.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var back := Button.new()
	back.text = "Back to Match" if overlay else "Back to Title"
	back.custom_minimum_size = Vector2(0, 52)
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 22)
	back.add_theme_color_override("font_color", BACK_RED)
	back.add_theme_color_override("font_hover_color", Color("ff9a9a"))
	back.pressed.connect(_back)
	nav.add_child(back)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style())
	cols.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	# Two columns so no line runs the full width of the screen. Pages are
	# still written as one flow; _flow() lays them out (see _show).
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 16)
	scroll.add_child(_rows)
	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 12)
	add_child(_body)

	_show("overview")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()

func _back() -> void:
	if overlay:
		get_parent().queue_free()
		return
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")

# ---------------------------------------------------------------- widgets

func _text_column(width: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(width, 0)
	c.add_theme_constant_override("separation", 12)
	return c

## Half the room the content panel has, which is what one text column gets.
func _half_width() -> float:
	var avail: float = get_viewport_rect().size.x - 80.0 - 260.0 - 16.0 - 36.0
	return maxf((avail - COL_GAP) * 0.5, 260.0)

## Lays the page out as a single column of sections, in the order the page
## built them. Two columns read faster per screen but paired sections of
## unequal height left heading-sized holes down the page, and a reader had to
## guess whether the next section was below or across; one column just reads
## top to bottom. Paragraphs keep their own measure (see _text_width), so the
## text never runs the full width of the panel.
func _flow() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var sections: Array = []
	for child in _body.get_children():
		if sections.is_empty() or child.has_meta("section"):
			sections.append([child])
		else:
			sections[-1].append(child)
	for n in sections.size():
		# A hairline between sections, so the eye finds the next heading.
		if n > 0:
			var sep := ColorRect.new()
			sep.color = EDGE
			sep.custom_minimum_size = Vector2(0, 2)
			_rows.add_child(sep)
		var col := _text_column(0.0)
		_move(sections[n], col)
		_rows.add_child(col)

func _move(block: Array, into: VBoxContainer) -> void:
	for child in block:
		_body.remove_child(child)
		into.add_child(child)

## How wide a block insists on being.
func _block_width(block: Array) -> float:
	var w := 0.0
	for child in block:
		if child is Control:
			w = maxf(w, (child as Control).get_combined_minimum_size().x)
	return w

func _label(text: String, color: Color = TEXT, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l

## Wrapped body text. It is pinned to one column's width even inside a
## full-width row, so no line ever runs the width of the screen.
func _wrap(text: String, color: Color = TEXT, size: int = 17) -> Label:
	var l := _label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size = Vector2(_text_width(), 0)
	return l

## Text inside a card: narrower than a plain paragraph, so the card itself
## still fits in one column beside the sprite.
func _card_text(text: String, color: Color) -> Label:
	var l := _wrap(text, color, 16)
	l.custom_minimum_size = Vector2(maxf(_text_width() - 150.0, 260.0), 0)
	return l

## How wide a paragraph is allowed to get.
## A readable measure, not the width of the panel: long lines are the fastest
## way to make a wall of text unreadable.
func _text_width() -> float:
	return minf(_half_width() * 2.0 - 16.0, 900.0)

func _panel_style(border: Color = EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	return sb

func _heading(text: String, color: Color = TEXT) -> void:
	var l := _label(text, color, 26)
	l.set_meta("block", true)
	# A heading owns everything under it until the next one: the flow keeps a
	# section together in one column, so a heading can never end up stranded
	# at the top of an empty column with its table in the next one.
	l.set_meta("section", true)
	_body.add_child(l)

func _para(text: String) -> void:
	_body.add_child(_wrap(text, DIM))

## A table: `cols` are header strings, `rows` are arrays of [text, color]
## pairs or plain strings.
func _table(cols: Array, rows: Array) -> void:
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.columns = cols.size()
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	for c in cols:
		grid.add_child(_label(str(c), EDGE_LIT, 16))
	for row in rows:
		for cell in row:
			if cell is Array:
				grid.add_child(_cell(str(cell[0]), cell[1]))
			else:
				grid.add_child(_cell(str(cell), TEXT))
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.add_theme_stylebox_override("panel", _table_style())
	frame.add_child(grid)
	_body.add_child(frame)

## Tables get a thin border so a grid of numbers reads as a table.
func _table_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.12, 0.55)
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	return sb

## One table cell. A long one (a building's effect, say) wraps rather than
## stretching its column across the page.
func _cell(text: String, color: Color) -> Label:
	var l := _label(text, color, 17)
	if text.length() > 56:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(minf(460.0, _text_width()), 0)
	return l

## A small pixel sprite (ships, icons) at `scale_px`.
func _sprite(name: String, scale_px: int, team: bool = false) -> Control:
	var stack := Control.new()
	var base := TextureRect.new()
	base.texture = Defs.tex(name)
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var art_div: float = Defs.art_div(name)
	base.custom_minimum_size = base.texture.get_size() * scale_px / art_div
	stack.custom_minimum_size = base.custom_minimum_size
	stack.add_child(base)
	if team:
		var tm := TextureRect.new()
		tm.texture = Defs.tex(name + "_team")
		tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tm.custom_minimum_size = base.custom_minimum_size
		tm.modulate = Defs.team_color(1)
		stack.add_child(tm)
	return stack

## An illustration plate: a labelled strip of sprites, so a page SHOWS what a
## shape, a ship or a world looks like instead of only describing it.
## items: [[sprite_name, caption, caption_color (optional)], ...]
func _plate(items: Array, box: float = 72.0, team: bool = true, note: String = "") -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style())
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for it in items:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var art := _fit_sprite(it[0], box, team)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(art)
		var cap := _label(it[1], it[2] if it.size() > 2 else DIM, 15)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(cap)
		row.add_child(cell)
	if note != "":
		col.add_child(_card_text(note, DIM))
	card.set_meta("block", true)
	_body.add_child(card)

## A sprite sized to fit `box` pixels on its longest side: small art is
## scaled up by a whole number so it stays crisp, oversized art (a planet or
## a star next to a corvette) is scaled down to fit.
func _fit_sprite(name: String, box: float, team: bool = false) -> Control:
	var tex := Defs.tex(name)
	if tex == null:
		return Control.new()
	var art := Vector2(tex.get_size()) / Defs.art_div(name)
	var k: float = box / maxf(art.x, art.y)
	if k >= 1.0:
		k = floorf(k)
	var stack := Control.new()
	var base := TextureRect.new()
	base.texture = tex
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	base.custom_minimum_size = Vector2(box, art.y * k)
	stack.custom_minimum_size = base.custom_minimum_size
	stack.add_child(base)
	if team and Defs.tex(name + "_team") != null:
		var tm := TextureRect.new()
		tm.texture = Defs.tex(name + "_team")
		tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tm.custom_minimum_size = base.custom_minimum_size
		tm.modulate = Defs.team_color(1)
		stack.add_child(tm)
	return stack

func _rule() -> void:
	var r := ColorRect.new()
	r.color = EDGE
	r.custom_minimum_size = Vector2(0, 2)
	_body.add_child(r)

# ---------------------------------------------------------------- sections

func _show(id: String) -> void:
	_current = id
	for k in _nav_buttons:
		_nav_buttons[k].add_theme_color_override("font_color", EDGE_LIT if k == id else TEXT)
	for c in _body.get_children():
		c.queue_free()
	match id:
		"overview": _page_overview()
		"controls": _page_controls()
		"combat": _page_combat()
		"ships": _page_ships()
		"research": _page_research()
		"economy": _page_economy()
		"systems": _page_systems()
		"terms": _page_terms()
	_flow()

## A CodexArt picture with a one-line caption under it.
func _pic(kind: String, caption: String, size: Vector2) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(CodexArt.new(kind, size))
	var cap := _wrap(caption, DIM, 14)
	cap.custom_minimum_size.x = size.x
	col.add_child(cap)
	_body.add_child(col)

func _page_overview() -> void:
	_heading("Stardust Dominion")
	_pic("lose", "Starbases build your ships and take in what harvesters haul; worlds feed and power everything.", Vector2(460, 150))
	_plate([["starbase", "Starbase", EDGE_LIT], ["planet_terran_s", "Worlds"], ["ship_miner", "Harvesters"],
		["ship_corvette", "Warships"], ["asteroid_0", "Belts"]], 68.0, true)

	_heading("The loop", EDGE_LIT)
	_pic("loop", "Research what your strategy needs, and strike before the enemy outgrows you.", Vector2(460, 150))
	_heading("What you can see", EDGE_LIT)
	_pic("fog", "Ships inside a spice nebula stay hidden unless an enemy is close; a seen enemy starbase stays on your map.", Vector2(460, 150))
	_heading("Resources", EDGE_LIT)
	_table(["Resource", "Comes from", "Pays for"], [
		[["Food", Color("8fe060")], "Farms only", "%.2f per pop per minute (spice covers a shortfall); an unfed world shrinks as fast as it would grow" % Defs.FOOD_PER_POP_PER_MIN],
		[["Minerals", Color("3fd6b0")], "Mining barges, gas skimmers, mining complexes, starbase refineries", "Ships, buildings, starbases"],
		[["Energy", Color("ffd84a")], "Power plants, starbase reactors", "Research, fleet and starbase upkeep, shield regeneration"],
		[["Spice", Color("ff9a2e")], "Spice asteroids, spice extractors, nebula harvesting", "Advanced hulls and techs; covers any other shortfall 1:1"],
	])

## The layer(s) a hull leans on: the biggest, two tied, or "even".
func _lean_cell(d: Dictionary) -> Variant:
	var top: float = maxf(d["shield"], maxf(d.get("armor", 0.0), d["hp"]))
	var leans: Array = []
	for l in [["shields", "shield", d["shield"]], ["armor", "armor", d.get("armor", 0.0)], ["hull", "hull", d["hp"]]]:
		if float(l[2]) >= top * 0.97:
			leans.append(l)
	if leans.size() == 3:
		return "even"
	if leans.size() == 1:
		return [leans[0][0], Defs.LAYER_COLORS[leans[0][1]]]
	return " + ".join(leans.map(func(l): return l[0]))

func _page_combat() -> void:
	_heading("Defense layers")
	_pic("layers", "Damage drains shields, then armor, then hull.", Vector2(460, 150))
	_table(["Layer", "Regenerates", "Notes"], [
		[["Shields", Defs.LAYER_COLORS["shield"]], "Yes, for a little energy", "Paused while taking damage, Radiation included"],
		[["Armor", Defs.LAYER_COLORS["armor"]], "No", "Only a Repair Tender restores it"],
		[["Hull", Defs.LAYER_COLORS["hull"]], "No", "A Repair Tender heals hull first, then armor"],
	])
	_pic("shield_regen", "Spread fire lets unhit ships recover; focused fire keeps their shields down.", Vector2(460, 150))
	_heading("Generalists")
	_para("Each class leans on a different layer: corvettes on hull, destroyers on armor, cruisers on shields, carriers on shields and armor. That gives specialists a target.")
	var rows: Array = []
	for t in Defs.MARK_LINES + ["starbase"]:
		var d: Dictionary = Defs.STARBASE if t == "starbase" else Defs.SHIPS[t]
		rows.append([d["name"], [str(int(d["shield"])), Defs.LAYER_COLORS["shield"]], [str(int(d.get("armor", 0))), Defs.LAYER_COLORS["armor"]],
			[str(int(d["hp"])), Defs.LAYER_COLORS["hull"]], _lean_cell(d)])
	_table(["Ship", "Shield", "Armor", "Hull", "Leans on"], rows)
	_heading("Specialist variants")
	_pic("variants", "Every variant costs the same as its generalist; its chevrons and shots share its color.", Vector2(460, 160))
	var vrows: Array = [["Generalist", "-", "100%", ["yellow laser", Defs.GENERALIST_SHOT], ["^ ^ ^", Defs.GENERALIST_COLOR]]]
	var shots := {"plasma": "light blue laser", "breacher": "red laser", "reaver": "green laser",
		"slip": "orange V-shot", "disruptor": "purple V-shot"}
	for v in Defs.VARIANTS:
		var vd: Dictionary = Defs.VARIANTS[v]
		var effect := ""
		if vd["pierce"] >= 2:
			effect = "ignores shields and armor"
		elif vd["pierce"] == 1:
			effect = "ignores shields"
		else:
			for layer in vd["vs"]:
				effect = "x%.1f vs %s" % [vd["vs"][layer], layer]
		vrows.append([[vd["label"], vd["color"]], effect, "%d%%" % int(vd["damage"] * 100.0), [shots[v], vd["color"]], ["^ ^ ^", vd["color"]]])
	_table(["Variant", "Effect", "Base damage", "Shots", "Chevrons"], vrows)
	_heading("Which variant against what")
	_para("Base damage needed to destroy a target, compared with a generalist: 1.00 is equal, lower kills faster. Worked out from each hull's layers - and confirmed by equal-cost fleet duels, which picked the same best variant for every class.")
	var head: Array = ["Target"]
	for v in Defs.VARIANTS:
		head.append(Defs.VARIANTS[v]["label"])
	var mrows: Array = []
	for t in Defs.MARK_LINES:
		var row: Array = [Defs.SHIPS[t]["name"]]
		for v in Defs.VARIANTS:
			var r := Defs.kill_ratio(Defs.SHIPS[t], v)
			row.append(["%.2f" % r, Defs.LAYER_COLORS["hull"] if r < 0.98 else (Defs.LAYER_COLORS["armor"] if r > 1.05 else TEXT)])
		mrows.append(row)
	var sbrow: Array = ["Starbase"]
	for v in Defs.VARIANTS:
		var r2 := Defs.kill_ratio(Defs.STARBASE, v)
		sbrow.append(["%.2f" % r2, Defs.LAYER_COLORS["hull"] if r2 < 0.98 else (Defs.LAYER_COLORS["armor"] if r2 > 1.05 else TEXT)])
	mrows.append(sbrow)
	_table(head, mrows)
	_heading("Hull marks", EDGE_LIT)
	_para("A mark is rank. It comes from the Warships research tab and raises damage and every defense layer. A variant comes from a Weapons Depot and sets what the ship is good against. They stack. The Ships page compares class, mark and variant.")
	_heading("Weapons Depots")
	var wd: Dictionary = Defs.WEAPONS_DEPOT
	_pic("depot", "Starbases build generalists only; a depot refits them into one variant.", Vector2(460, 150))
	_para("Build depots with a Constructor (%s, %ds each). %d ships fit at a time; each refit costs:" % [Defs.cost_text(wd["cost"]), int(wd["build_time"]), int(wd["capacity"])])
	var rrows: Array = []
	for t in Defs.VARIANTS_OF:
		var r: Dictionary = Defs.SHIPS[t]["refit"]
		rrows.append([Defs.SHIPS[t]["name"], "%d minerals" % int(r["minerals"]), "%ds" % int(r["time"])])
	_table(["Hull", "Refit cost", "Refit time"], rrows)
	_para("No minerals: the refit waits. Cancel to eject it unchanged. A specialist can't refit again. A destroyed depot throws its ships clear at -60%.")
	_heading("Weapon Mods")
	_para("Mods change what a ship class fires: one per class at a time. Researching another replaces it (the old one keeps working until the new one is done).")
	_pic("mod_toggle", "Click a Mod's card (or its name under the clock) to switch it off and on.", Vector2(460, 150))
	_para("A Mod sets the weapon's shape; a depot variant still sets its damage (a Plasma torpedo hits shields x2.5).")
	_pic("hit_run", "Bombs, torpedoes and missiles attack hit-and-run.", Vector2(460, 150))
	# The Mods tab as it appears on the research screen.
	_tech_tree("mods", _research_rows("mods"))
	var coming: Array = []
	for id in Defs.TECHS:
		if Defs.TECHS[id].has("mod") and not Defs.MOD_WEAPONS.has(id):
			coming.append(Defs.TECHS[id]["name"])
	if not coming.is_empty():
		_para("Still being built: " + ", ".join(coming) + ".")
	_heading("When to use each Mod")
	var sgrid := GridContainer.new()
	sgrid.columns = 3   # one row per class: corvette, destroyer, cruiser, carrier
	sgrid.add_theme_constant_override("h_separation", 16)
	sgrid.add_theme_constant_override("v_separation", 14)
	for id in Defs.TECHS:
		if not Defs.TECHS[id].has("mod"):
			continue
		var cell := VBoxContainer.new()
		var nm := Label.new()
		nm.text = Defs.TECHS[id]["name"] + ("" if Defs.MOD_WEAPONS.has(id) else "  (coming)")
		nm.add_theme_color_override("font_color", TEXT)
		cell.add_child(nm)
		cell.add_child(ModScene.new(id))
		var cap := _wrap(ModScene.caption(id), DIM, 14)
		cap.custom_minimum_size.x = ModScene.W
		cell.add_child(cap)
		sgrid.add_child(cell)
	_body.add_child(sgrid)
	_pic("blasts", "Each blast hits every enemy inside it for full damage: spread out against them. Drawn to scale.", Vector2(460, 150))
	var vs: Dictionary = Defs.MOD_WEAPONS["mod_proton_torpedoes"]["vs_class"]
	_para("Interceptor Drones: the carrier launches one drone every %d s from its turret doors, up to %d. Drones have %d hull, fight on their own within %d of the carrier, and die with it. Point-Defense Lattice shoots them for x%d damage." % [int(Ship.DRONE_BUILD), int(Defs.MOD_WEAPONS["mod_interceptor_drones"]["drones"][0]), int(Drone.HULL), int(Defs.MOD_WEAPONS["mod_interceptor_drones"]["drones"][1]), int(Ship.PD_DRONE_MULT)])
	var trb: Array = Defs.MOD_WEAPONS["mod_tractor_beams"]["tractor"]
	_para("Tractor Beams: each turret's beam reaches %dx weapon range and slows its target by %d%% far out to %d%% up close, reeling it in. Slows from several beams multiply (two 50%% beams: 75%%). Missile Barrage: a %d-missile salvo every %d s at +%d%% range." % [int(trb[2]), int(trb[0] * 100), int(trb[1] * 100), 4 * int(Defs.MOD_WEAPONS["mod_missile_barrage"]["count"]), int(Defs.MOD_WEAPONS["mod_missile_barrage"]["cd"]), int((Defs.MOD_WEAPONS["mod_missile_barrage"]["range"] - 1.0) * 100)])
	_para("Proton Torpedoes are built to hunt big hulls: x%.2f damage to destroyers, x%.2f to cruisers and x%.2f to carriers, and weaker than lasers against corvettes. They steer gently, so a ship that turns hard can shake one off." % [vs["destroyer"], vs["cruiser"], vs["carrier"]])

	_heading("Defense research")
	_para("Four lines on the Defense tab: shields, armor and hull below, plus screens, which cut a share of every hit (all three: -52%). They are expensive on purpose: committing to a layer is a strategic choice. Only one project runs at a time, so every tech costs time as well as energy.")
	_para("The shield line also raises a Radiation Sail Array's solar shield (and a merged mega shield). It refills just as fast, since each energy harvested recharges 10% of the maximum.")
	var lines := {"shields": "shield", "armor": "armor", "hull": "hull"}
	for line in lines:
		var lrows: Array = []
		for id in Defs.TECHS:
			var t: Dictionary = Defs.TECHS[id]
			if t.get("line", "") == line:
				lrows.append([[t["name"], Defs.LAYER_COLORS[lines[line]]], "Tier %d" % t["tier"], Defs.cost_text(t["cost"]), "%ds" % int(t["time"]), t["desc"]])
		_table([line.to_upper(), "", "Cost", "Time", "Effect"], lrows)
	_heading("Ship jobs")
	_para("Jobs are what a ship does besides shooting. Passive jobs always work. Use an active one with Q or its ship panel button.")
	var jrows: Array = []
	for j in Defs.JOBS:
		var jd: Dictionary = Defs.JOBS[j]
		var owners: Array = []
		for s in Defs.SHIPS:
			if Defs.SHIPS[s].get("job", "") == j and not Defs.SHIPS[s].has("variant"):
				owners.append(Defs.SHIPS[s]["name"])
		jrows.append([[jd["name"], jd["color"]], ", ".join(owners), "Q, %ds" % int(jd.get("cooldown", 0)) if jd.get("active", false) else "passive"])
	_table(["Job", "Ships", "Use"], jrows)
	for j in Defs.JOBS:
		_body.add_child(_wrap("%s: %s" % [Defs.JOBS[j]["name"], Defs.JOBS[j]["desc"]], DIM, 16))

func _page_ships() -> void:
	# Three independent systems decide what a warship is, and players keep
	# conflating them, so they are laid out side by side here before the
	# stat cards: what it IS, how GOOD it is, and what it is FOR.
	_heading("Class, Mark and Variant")
	_para("Every warship has three separate traits. Its CLASS is the hull it was built as and never changes. Its MARK is how refined that hull is, bought on the Warships research tab. Its VARIANT is its specialty, from a Weapons Depot refit. A Mk IV Reaver Corvette is all three: a corvette, at the top mark, fitted to hunt hull.")
	_table(["System", "Comes from", "Changes", "You can tell by"], [
		[["Class", TEXT], "What you build it as", "Never", "The hull's silhouette"],
		[["Mark", EDGE_LIT], "Warships research", "Every ship of that class, at once", "How many chevrons beside it"],
		[["Variant", Defs.VARIANTS["reaver"]["color"]], "Refit at a Weapons Depot", "Once, permanently", "The color of its chevrons"],
	])
	_heading("Class — the shape")
	var cls_plate: Array = []
	for cls in Defs.MARK_LINES:
		cls_plate.append(["ship_" + cls, Defs.SHIPS[cls]["name"], TEXT])
	_plate(cls_plate, 104.0, true, "One shape per class, for life: corvette A, destroyer Y, cruiser X, carrier H.")
	_para("Shape says what a ship is, not how good it is. A corvette is a braced delta with its apex at the bow. A destroyer is a tail boom forking into two prongs. A cruiser is four wings crossed at a hub. A carrier is two nacelles either side of a central spine. Silhouettes show a fleet's makeup.")
	_heading("Mark — the rank")
	_para("Each mark adds to damage, hull, armor and shields alike. Later marks are worth more, and bigger classes gain more from each. Bonus over Mk I:")
	var mrows0: Array = []
	for cls in Defs.MARK_LINES:
		var row0: Array = [[Defs.SHIPS[cls]["name"], TEXT]]
		for i in range(1, Defs.HULL_MARKS.size()):
			row0.append("+%d%%" % int(round(Defs.MARK_BONUS[cls][i] * 100.0)))
		mrows0.append(row0)
	_table(["Class", Defs.HULL_MARKS[1], Defs.HULL_MARKS[2], Defs.HULL_MARKS[3]], mrows0)
	_para("Every warship has small chevrons beside it, one per mark: one at Mk I, four at Mk IV. Each class researches its own marks, so each class is a separate investment. A mark applies to every ship of that class the moment research finishes, existing ships included.")
	_heading("Variant — the color")
	_para("A variant keeps its class's hull; only its chevrons change color. Generalists wear yellow chevrons. Each variant has its own color, the same as its shots:")
	var crows: Array = [[["Generalist", Defs.GENERALIST_COLOR], ["^ ^ ^", Defs.GENERALIST_COLOR]]]
	for tv in Defs.VARIANTS:
		crows.append([[Defs.VARIANTS[tv]["label"], Defs.VARIANTS[tv]["color"]], ["^ ^ ^", Defs.VARIANTS[tv]["color"]]])
	_table(["Variant", "Chevrons"], crows)
	_para("Chevron count shows rank; color shows variant. The Combat page covers what each variant does to damage.")
	_heading("Every ship")
	_para("Stats as built, before research. Specialist variants share their generalist's hull and cost; only their damage profile changes (see Combat).")
	for t in Defs.BUILD_ORDER:
		var d: Dictionary = Defs.SHIPS[t]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _panel_style())
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		row.add_child(_sprite("ship_" + Defs.SHIPS[t].get("base", t), 3, true))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 12)
		name_row.add_child(_label(d["name"], TEXT, 20))
		if d.has("requires"):
			name_row.add_child(_label("needs %s" % Defs.TECHS[d["requires"]]["name"], Color("ffd84a"), 14))
		col.add_child(name_row)
		var stats := "%s  ·  %s shield / %s armor / %s hull\n%d speed  ·  %d sensors" % [
			str(d.get("subclass", d["role"])).capitalize(), int(d["shield"]), int(d.get("armor", 0)), int(d["hp"]), int(d["speed"]), int(d.get("sensor", 260))]
		if d["weapon"] != "":
			stats += "  ·  %s %d dmg / %.1fs, range %d" % [d["weapon"], int(d["damage"]), d["cooldown"], int(d["range"])]
			if int(d.get("guns", 1)) > 1:
				stats += "  ·  %d guns" % int(d["guns"])
		var fittings: Array = []
		if d.has("turrets"):
			fittings.append("%d turrets, traversing %d°/s" % [d["turrets"].size(), int(rad_to_deg(float(d.get("turret_rate", 1.0))))])
		if not fittings.is_empty():
			stats += "
" + "  ·  ".join(fittings)
		col.add_child(_label(stats, DIM, 16))
		col.add_child(_label("%s over %ds  ·  upkeep %.2f energy/min" % [Defs.cost_text(d["cost"]), int(d["build_time"]), d["upkeep"]], DIM, 16))
		if d.has("job"):
			col.add_child(_card_text("Job — %s: %s" % [Defs.JOBS[d["job"]]["name"], Defs.JOBS[d["job"]]["desc"]], Defs.JOBS[d["job"]]["color"]))
		if SHIP_NOTES.has(t):
			col.add_child(_card_text(SHIP_NOTES[t], DIM))
		card.set_meta("block", true)
		_body.add_child(card)

## Every tech, tab by tab: what it needs, costs and does.
func _page_research() -> void:
	_heading("Research")
	_para("Research spends energy (and spice for later tiers) over time. Only one project runs at a time. Picking another tech pauses the current one, and a paused tech resumes where it left off. Each tech needs only the tier below it in its row. A warship's Mk II needs the class unlocked first.")
	# Each tab as it appears on the research screen: named rows, three
	# columns, the same cards (icon, cost, effect, padlock for what it needs).
	for g in ["warships", "weapons", "mods", "defense", "constructs", "worlds", "logistics"]:
		_heading(g.capitalize(), TechIcons.GROUP_COLORS.get(g, EDGE_LIT))
		_para(Defs.TECH_GROUP_DESC.get(g, ""))
		_tech_tree(g, _research_rows(g))

## A tab's rows, [name, [three tech ids]], in the research screen's layout.
func _research_rows(g: String) -> Array:
	match g:
		"warships":
			var rows: Array = [["UNLOCKS", ["destroyers", "cruisers", "carriers"]]]
			for c in ["corvette", "destroyer", "cruiser", "carrier"]:
				rows.append([c.to_upper(), ["%s_mk2" % c, "%s_mk3" % c, "%s_mk4" % c]])
			return rows
		"defense":
			var out: Array = []
			for line in ["shields", "armor", "hull", "screens"]:
				var ids: Array = ["", "", ""]
				for id in Defs.TECHS:
					if Defs.TECHS[id].get("line", "") == line:
						ids[Defs.TECHS[id]["tier"] - 1] = id
				out.append([line.to_upper(), ids])
			return out
	return HUD.TECH_ROWS.get(g, [])

func _tech_tree(g: String, rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(Control.new())
	for tier in [1, 2, 3]:
		grid.add_child(_label("" if g == "mods" else "TIER %d" % tier, DIM, 13))
	var col: Color = TechIcons.GROUP_COLORS.get(g, EDGE_LIT)
	for r in rows:
		var head := _label(r[0], col, 14)
		head.custom_minimum_size = Vector2(110, 0)
		head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(head)
		for id in r[1]:
			grid.add_child(_tech_card(id) if id != "" and Defs.TECHS.has(id) else Control.new())
	grid.set_meta("block", true)
	_body.add_child(grid)

func _tech_card(id: String) -> Control:
	var t: Dictionary = Defs.TECHS[id]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2550")
	sb.border_color = Color("3a4a85")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(330, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	var pic := TextureRect.new()
	pic.texture = TechIcons.icon(id)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(72, 72)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	v.add_child(_label(t["name"], TEXT, 14))
	v.add_child(CostRow.make(t["cost"], 13, t["time"]))
	var d := _label(t["desc"], DIM, 12)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(230, 0)
	v.add_child(d)
	if not t["requires"].is_empty():
		var req := HBoxContainer.new()
		req.add_theme_constant_override("separation", 5)
		var lock := TextureRect.new()
		lock.texture = HUD._padlock_tex()
		lock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.custom_minimum_size = Vector2(12, 14)
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.modulate = Color("8a96bd")
		req.add_child(lock)
		req.add_child(_label(", ".join(t["requires"].map(func(r): return Defs.TECHS[r]["name"] if Defs.TECHS.has(r) else str(r))), DIM, 12))
		v.add_child(req)
	return card

## A tech effect as a whole percent (Defs.TECHS), so text stays in step with balance.
func _pct(tech: String, effect: String) -> int:
	return int(round(float(Defs.TECHS[tech]["effects"].get(effect, 0.0)) * 100.0))

## The asteroid sizes side by side at their true relative size, each with
## what it holds (worked out exactly as Asteroid does, so it can't drift).
func _rock_sizes() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style())
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)
	const K := 3.0   # screen px per world px
	# Rarity: share of all rocks, measured over 24 generated maps (1,404 rocks).
	for it in [["asteroid_0", 1.0, "Small mineral", "minerals", "Common", "~60% of rocks"],
			["asteroid_big_0", 1.0, "Large mineral", "minerals", "Uncommon", "~25% of rocks"],
			["spice_0", 1.0, "Small spice", "spice", "Rare", "~13% of rocks"],
			["spice_0", SystemGen.BIG_SPICE, "Large spice", "spice", "Very rare", "~2% of rocks"]]:
		var tex := Defs.tex(it[0])
		var w: float = tex.get_width() * float(it[1]) / Defs.ART_SCALE
		var holds: int = Defs.ROCK_LARGE if Defs.rock_is_large(it[0], float(it[1])) else Defs.ROCK_SMALL
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.add_theme_constant_override("separation", 4)
		var art := TextureRect.new()
		art.texture = tex
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.custom_minimum_size = Vector2(w, w) * K
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(art)
		var cap := _label(it[2], TEXT, 15)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(cap)
		var amt := _label("%d %s" % [holds, it[3]], Defs.RESOURCE_COLORS[it[3]], 15)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(amt)
		for line in [it[4], it[5]]:
			var rar := _label(line, DIM, 13)
			rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(rar)
		row.add_child(cell)
	_body.add_child(card)

func _page_economy() -> void:
	_heading("Planets")
	_para("A planet's size is its number of fields, one building each. Its population cap is size x %d. Colonies start at %d pops. Pops eat %s food per minute; an unfed world shrinks instead of growing. Barren worlds hide the most spice, lush ones almost none." % [Defs.POP_PER_SIZE, int(Defs.START_POP), str(Defs.FOOD_PER_POP_PER_MIN)])
	var prows: Array = []
	for p in Defs.PLANET_TYPES:
		var pd: Dictionary = Defs.PLANET_TYPES[p]
		prows.append([pd["label"], "yes" if pd.get("habitable", true) else "no (gas giant)",
			", ".join(Defs.planet_traits(p)) if not Defs.planet_traits(p).is_empty() else "-", str(pd.get("spice_reserve", pd.get("gas_reserve", 0)))])
	_table(["Type", "Habitable", "Effects", "Spice / gas reserve"], prows)
	var wplate: Array = []
	for p2 in Defs.PLANET_TYPES:
		wplate.append([p2 + "_s", Defs.PLANET_TYPES[p2]["label"]])
	_plate(wplate, 64.0, false)
	_heading("Harvesting")
	_plate([["ship_miner", "Mining Barge"], ["asteroid_big_0", "Mineral asteroid"], ["spice_0", "Spice asteroid"],
		["ship_skimmer", "Gas Skimmer"], ["planet_gas_s", "Gas giant"], ["starbase", "Starbase"]], 76.0, true,
		"Barges work rock; skimmers work gas giants and spice nebulae. Both haul to a starbase or Mining Station.")
	_pic("harvest", "Every harvester runs this loop on its own once given a target.", Vector2(460, 150))
	var hrows: Array = []
	for row in [
		["Mining Barge", "miner", "Mineral asteroid", "minerals", 1.0],
		["Mining Barge", "miner", "Spice asteroid", "spice", Defs.HARVEST_SPICE_MULT],
		["Gas Skimmer", "skimmer", "Gas giant", "minerals", 1.0],
		["Gas Skimmer", "skimmer", "Spice nebula", "spice", Defs.HARVEST_NEBULA_MULT],
	]:
		var d: Dictionary = Defs.SHIPS[row[1]]
		var rate: float = float(d["harvest"]) * float(row[4])
		hrows.append([row[0], row[2], [row[3].capitalize(), Defs.RESOURCE_COLORS[row[3]]],
			"%.0f/min" % rate, "%d" % int(d["cargo"]), "%ds" % int(float(d["cargo"]) / rate * Defs.PER_MIN)])
	_table(["Ship", "Source", "Yields", "Gather", "Hold", "Fill time"], hrows)
	_para("Rates are at base. Logistics techs speed up every harvester, Mining Barges and Gas Skimmers alike: Cutting Lasers, Resonance Drills and Mass Drivers add +%d%%, +%d%% and +%d%% gather rate, Deep-Core Drills and Bulk Holds +%d%% and +%d%% hold, and Logistics Command +%d%% of each. A Radiation Sail Array also gathers %d energy a minute while in Radiation (a star's zone or a spice nebula)." % [
		_pct("cutting_lasers", "harvest"), _pct("resonance_drills", "harvest"), _pct("mass_drivers", "harvest"),
		_pct("deep_drills", "cargo"), _pct("bulk_holds", "cargo"), _pct("logistics_command", "harvest"), int(Defs.SHIPS["heatshield"]["solar_sail"])])
	_heading("Asteroid sizes")
	_para("A small rock holds the same amount whether it is minerals or spice, and so does a large one, on every map. Spice is rare instead: about one rock in seven. Belts differ in their mix: a rich belt has more big rocks, a poor one mostly small. Rocks run dry and vanish; gas giants refill after a pause, and a spice nebula never runs out.")
	_rock_sizes()
	_heading("Buildings")
	var bplate: Array = []
	for b in Defs.BUILDING_ORDER:
		bplate.append(["bld_" + b, Defs.BUILDINGS[b]["name"]])
	_plate(bplate, 56.0, false)
	var brows: Array = []
	for b in Defs.BUILDINGS:
		var bd: Dictionary = Defs.BUILDINGS[b]
		brows.append([bd["name"], Defs.cost_text(bd["cost"]), "%ds" % int(bd["time"]), bd["desc"]])
	_table(["Building", "Cost", "Time", "Effect"], brows)
	_para("A finished building always runs; no staffing needed. Population sets how MUCH a world produces: every pop adds %s%% to the output of every Farm, Power Plant, Mining Complex and Spice Extractor on it, so a world of 30,000 makes four times what the same buildings make on a bare colony. A Molten world's Power Plants make a further x%.2f, the one thing that barren rock is good for." % [str(Defs.OUTPUT_PER_POP * 100.0), Defs.PLANET_TYPES["planet_lava"]["energy_mult"]])
	_heading("Food")
	_para("Food is counted per minute, like every other resource. One Farm feeds exactly %d pops on a fully fertile world, and only a fraction of that on a poor one, since output scales with fertility. Past that, a world needs another Farm or it starves." % int(Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN))
	_table(["", "Rate"], [
		["A pop eats", "%.2f/min" % Defs.FOOD_PER_POP_PER_MIN],
		["A Farm grows", "%d/min" % int(Defs.BUILDINGS["farm"]["output"]["food"])],
		["1,000 pops eat", "%d/min" % int(1000.0 * Defs.FOOD_PER_POP_PER_MIN)],
		["A Farm supports", "%d pops" % int(Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN)],
	])
	_para("Spice covers a food shortfall 1:1, and pops living on it keep growing. If neither food nor spice can feed a world, it starves: growth runs backwards at the rate it would have grown. The shortage lifts only after the world has been fed for %d seconds straight." % int(Defs.REGROW_SECONDS))
	_heading("Defense Battery")
	_para("A world with a Defense Battery is no free kill. Each battery adds %d to its planetary shield and fires on besieging ships (%d damage, %d px). Two batteries force a raiding party to commit." % [int(Defs.BATTERY_SHIELD), int(Defs.BATTERY["damage"]), int(Defs.BATTERY["range"])])
	_heading("Upkeep")
	_para("Every ship costs energy per minute, and the total is multiplied as the fleet grows (1 + (ships/%d)^2), so fleets plateau. Starbases have their own steeper curve, so more than a handful is expensive. With no energy in stock, starbases stop producing and your ships move and fire at %d%% speed." % [int(Defs.UPKEEP_SCALE_SHIPS), int(Defs.ENERGY_STARVED_FACTOR * 100.0)])

func _page_systems() -> void:
	_heading("Systems")
	_para("A match is fought in one star system, chosen in the lobby. Every system is symmetric: each player starts with the same worlds, rocks and distances, arranged evenly around the star. Every system but the Silent Void has spice nebulae: endless spice for Gas Skimmers, at the price of constant low Radiation inside. Systems differ in star, signature feature and gas placement, and these decide how the match is fought.")
	_heading("Belts")
	_para("Every player starts with three belts of their own:")
	_table(["Belt", "Where", "Holds"], [
		[["Safe", TEXT], "Beside your home world, a short haul from the starbase", "Minerals only"],
		[["Forward", TEXT], "Past your starbase, toward the star - where enemies come through", "Mostly minerals, a little spice"],
		[["Back", TEXT], "Behind your home world, by the map edge", "A few spice rocks"],
	])
	_para("Neutral belts lie anywhere from just outside the star's Radiation to near the map edge. Each is either a large mineral belt (a long arc) or a small spice belt (a tight cluster). Spice is about one rock in seven, but a spice rock holds as much as a mineral rock of its size. Richer belts have more big rocks.")
	_heading("Every match is different")
	_para("A system keeps its star, signature feature and character, but its seed reshuffles the details. Pick the same system and seed to replay a map exactly; both players always get the same layout.")
	_table(["What varies", "How much"], [
		["Worlds and belts", "One more or fewer than the system's usual count"],
		["Distance between bases", "Bases sit 80-95% of the way to the edge"],
		["Belt shape", "Spread, density, arc length and thickness; where the home belts sit"],
		["Belt richness", "How many big rocks each belt has"],
		["Planet positions and moons", "Where every world sits; 0-2 moons per gas giant"],
		["Spice nebulae", "Size, distance, angle, and sometimes how many clouds"],
		["Debris ring", "Size, thickness, and 1-3 gaps on each side"],
		["Twin suns", "Orbit size and speed (the safe lane moves differently)"],
		["Ion storms", "Size, drift speed and path"],
	])
	for s in SystemGen.SYSTEMS:
		_system_card(s)
	_star_section()

## Everything a player needs to know about one system: its map, star, worlds
## and rocks, signature feature, nebulae, and how it tends to play.
func _system_card(s: Dictionary) -> void:
	var id: String = s["id"]
	var random := id == "random"
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var map := SystemPreview.new()
	map.custom_minimum_size = Vector2(260, 166)
	map.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	map.show_system(id)
	row.add_child(map)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var star: Dictionary = Defs.STAR_TYPES.get(s.get("star", "yellow"), {})
	col.add_child(_label(s["name"], star.get("tint", TEXT), 22))
	col.add_child(_label(s["desc"], DIM, 16))
	if random:
		col.add_child(_card_text("Everything is drawn fresh each match from the match's seed, and the same seed always gives the same system:", TEXT))
		col.add_child(_card_text("- Star: any type, from a Red Dwarf (smallest, gentlest radiation) to a Blue Giant (widest, deadliest).\n- Worlds: 3 to 6 per side, of mixed types.\n- Belts: safe, forward and back home belts, plus 1 to 4 neutral belts per side; about one rock in seven is spice.\n- Spice nebulae: one of the four layouts - flank clouds, bands, pockets or drifts.\n- No signature feature (no twin suns, debris ring or ion storms), and its own backdrop and world names.", DIM))
		col.add_child(_card_text("How it plays: scout first. Nothing about the map is known in advance, so an early Scout and a look at where the gas lies matter more here than anywhere.", EDGE_LIT))
		card.set_meta("block", true)
		_body.add_child(card)
		return
	# Star and radiation.
	var binary: bool = s.get("feature", "") == "binary"
	col.add_child(_card_text("Star: %s%s - radiation out to %d px, up to %d damage/s at the surface." % [
		"twin " if binary else "", star.get("label", ""), int(star.get("zone", 0)), int(star.get("dps", 0))], TEXT))
	# Worlds and rocks, counted from the layout itself.
	var lay: Dictionary = map._layout
	var kinds := {}
	var giants := 0
	for p in lay.get("planets", []):
		if p["owner"] == 0 and not Defs.PLANET_TYPES.get(p["kind"], {}).get("habitable", true):
			giants += 1
		elif p["owner"] == 0:
			var lbl: String = Defs.PLANET_TYPES.get(p["kind"], {}).get("label", p["kind"])
			kinds[lbl] = kinds.get(lbl, 0) + 1
	var worlds: Array = []
	for k in kinds:
		worlds.append("%d %s" % [kinds[k], k])
	var rocks: int = lay.get("asteroids", []).size()
	var spice := 0
	for a in lay.get("asteroids", []):
		if str(a["variant"]).begins_with("spice"):
			spice += 1
	col.add_child(_card_text("Worlds to claim: %s.  Gas giants: %d.  Asteroids: %d, %d of them spice." % [", ".join(worlds) if not worlds.is_empty() else "none", giants, rocks, spice], TEXT))
	var feature: String = s.get("feature", "")
	if feature != "":
		col.add_child(_card_text({
			"binary": "Twin suns: two radiation zones circle the center, and the safe lane between them keeps moving.",
			"spice_nebula": "Spice nebula: a full ring of gas around the star, seeded with extra spice rocks.",
			"rings": "Debris ring: an impassable wall of rubble with a few narrow gaps (how many varies by seed), which makes those gaps chokepoints.",
			"storms": "Ion storms: ragged clouds of charged gas drift around the system, crackling with lightning. Ships inside move at 40% speed and see half as far.",
		}.get(feature, feature), EDGE_LIT))
	var ntext: String = {
		"flanks": "Spice nebulae: one cloud on each flank, equally far from both bases - the contested middle.",
		"bands": "Spice nebulae: two arcs of gas across the lane between the bases, just outside the suns' orbit.",
		"pockets": "Spice nebulae: six small clouds scattered outside the debris ring, near the outer worlds.",
		"drifts": "Spice nebulae: a great cloud on each base's flank - your own to harvest, the enemy's to raid.",
	}.get(s.get("nebula", ""), "")
	if ntext != "":
		col.add_child(_card_text(ntext, Defs.RESOURCE_COLORS["spice"]))
	if SYSTEM_TIPS.has(id):
		col.add_child(_card_text("How it plays: " + SYSTEM_TIPS[id], DIM))
	card.set_meta("block", true)
	_body.add_child(card)

## One line per system on what tends to decide a match there.
const SYSTEM_TIPS := {
	"orion_reach": "The even, open map. Both flank clouds are as close to the enemy as to you, so spice goes to whoever holds the middle - send skimmers with an escort.",
	"vega_drift": "The suns' radiation sweeps the center, so the lane between bases opens and closes. Time attacks for when it is clear, and harvest the bands when the enemy fleet is elsewhere.",
	"kharon_expanse": "Few worlds, but the most spice anywhere, all of it inside the ring. The gas is full of Radiation: don't linger, bring tough hulls, and expect fights inside it.",
	"tethys_cluster": "The richest worlds sit behind the debris ring, reachable only through its gaps. Hold a gap and you hold the inner system; the outer pockets are easy, safe spice.",
	"silent_void": "Nothing in the way and nothing to hide in: no nebulae, storms or rings, only the star's own zone. Spice comes from rocks and Spice Extractors, so it is scarce. Fleets meet in the open.",
	"sable_verge": "Heavy belts and sparse worlds: a mining race. Ion storms slow and blind anything they cross, and each side's spice drift is an inviting raid target.",
}

func _star_section() -> void:
	_heading("The star")
	var splate: Array = []
	for st in Defs.STAR_TYPES:
		splate.append([Defs.STAR_TYPES[st]["tex"], Defs.STAR_TYPES[st]["label"], Defs.STAR_TYPES[st]["tint"]])
	_plate(splate, 88.0, false)
	var srows: Array = []
	for st in Defs.STAR_TYPES:
		var sd: Dictionary = Defs.STAR_TYPES[st]
		srows.append([[sd["label"], sd["tint"]], "%d px" % int(sd["zone"]), "%d dps" % int(sd["dps"])])
	_table(["Star", "Radiation zone", "Damage at the surface"], srows)
	_heading("Radiation", Color("ffae4a"))
	_pic("radiation", "It takes shields, then armor, then hull - and counts as a hit, so shields stay down inside it.", Vector2(460, 150))
	_table(["Source", "Where", "Damage"], [
		[["A star", Color("ffb347")], "Its radiation zone (sizes above)", "Strongest at the surface, falling steeply toward the edge"],
		[["A spice nebula", Color("ff9a2e")], "Anywhere inside the gas", "%d per second, about a star's outer zone: low, but constant" % int(SpiceNebula.RADIATION_DPS)],
	])


func _page_terms() -> void:
	_heading("Terminology")
	var terms := [
		["System", "The map: one star (or two), its planets, belts and features. Called a system, not a map."],
		["Starbase", "Your production station. It builds ships, takes in cargo and defends itself. Losing every one with no Constructor left to build another loses the match (so does losing every world)."],
		["Weapons Depot", "Constructor-built station where a generalist warship is refitted into a specialist variant, permanently."],
		["Class", "The hull a warship was built as, and keeps for life: Corvette, Destroyer, Cruiser or Carrier. You read it off the silhouette."],
		["Mark", "How refined a class is, Mk I to Mk IV, bought on the Warships research tab. It applies to every ship of that class at once."],
		["Generalist", "Any warship as built, before a refit: full damage to every defense layer."],
		["Specialist / variant", "A refitted warship: Plasma, Breacher, Reaver, Slip or Disruptor. One refit only, and it is permanent."],
		["Layers", "Shields, armor and hull, in the order damage takes them."],
		["Radiation", "Environmental damage inside a star's radiation zone (worst near the star) or a spice nebula (low, constant). Hits shields, armor and hull in turn and stops shield regeneration."],
		["Pierce", "Skipping a layer entirely: Slip skips shields, Disruptor skips shields and armor."],
		["Job", "What a ship is for beyond shooting: Deep Sensors, Radiation Sail, Field Repair."],
		["Mod", "A research option that changes one ship class's weapon (Mods tab). One per class; another replaces it; click an active one to switch it off."],
		["Blast", "The area an exploding shot hits: every enemy inside takes part of its damage, the target included."],
		["Hit-and-run", "How bomb, torpedo and missile ships attack: close in, fire, peel away while reloading, come round again."],
		["Mega Shield", "Touching Radiation Sail Array bubbles of yours merged into one. Its points are their sum (three full arrays: 300), every hit is shared among them by charge, and it bursts for all of them at 0. If they drift apart, each keeps its share as its own bubble."],
		["Fog of war", "What your sensors can see. Unexplored is black, explored-but-unseen is dimmed and out of date."],
		["Beacon", "A Scout's dropped sensor buoy: watches a spot for 90 seconds."],
		["Upkeep", "Energy per minute for ships and starbases, rising as your fleet grows."],
		["Spice", "The rare resource. Buys advanced hulls and techs, and automatically covers a shortfall in anything else."],
		["Bombard", "Firing on an enemy planet to kill its population; at zero pops its buildings are destroyed and it goes neutral."],
		["Colonize", "Settling a free world with a Colony Ship, which is used up in the process."],
	]
	for t in terms:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.add_child(_label(t[0], EDGE_LIT, 19))
		row.add_child(_wrap(t[1], DIM, 17))
		row.set_meta("block", true)
		_body.add_child(row)

## Dev aid: SL_CODEX_SHOT=<section> opens that page, saves
## user://codex.png and quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and OS.get_environment("SL_CODEX_SHOT") != "":
		await get_tree().create_timer(0.6).timeout
		_show(OS.get_environment("SL_CODEX_SHOT"))
		await get_tree().process_frame
		if OS.get_environment("SL_CODEX_SCROLL") != "":
			for f in 5:
				await get_tree().process_frame
			# A heading's text: scroll so that heading sits at the top.
			for l in _rows.find_children("*", "Label", true, false):
				if l.text == OS.get_environment("SL_CODEX_SCROLL"):
					for n in find_children("*", "ScrollContainer", true, false):
						(n as ScrollContainer).scroll_vertical = int(l.global_position.y - _rows.global_position.y)
					break
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://codex.png")
		get_tree().quit()

func _page_controls() -> void:
	_heading("Panel grid")
	_para("The bottom-left panel's buttons map to a grid of keys, in order, and each shows its letter in the corner. Letters never move: whatever is selected, the first button is Q, the fourth A, the seventh Z.")
	var pk := HUD.panel_keys()
	var krows: Array = []
	for r in 4:
		var ks: Array = []
		for c in 3:
			ks.append(OS.get_keycode_string(pk[r * 3 + c]))
		krows.append([["First row", "Second row", "Third row", "Overflow"][r], ["   ".join(ks), EDGE_LIT]])
	_table(["Row", "Keys"], krows)
	_para("The build picker on one of your worlds uses the same letters.")
	_para("Rebind any key in Options > Hotkeys, which has a Reset to defaults button. Button letters follow your bindings.")
	_heading("Build grid")
	_para("A starbase builds from two pages, Economy and Military, switched with the bottom-right button. With no starbase selected, a letter selects every ship of one class you own, anywhere on the map.")
	var war: Array = Defs.BUILD_ORDER.filter(func(t): return Defs.SHIPS[t]["role"] == "warship")
	var eco: Array = Defs.BUILD_ORDER.filter(func(t): return Defs.SHIPS[t]["role"] != "warship")
	var keys := HUD.panel_keys()
	var rows: Array = []
	for i in mini(keys.size(), Defs.BUILD_ORDER.size()):
		var e: String = Defs.SHIPS[eco[i]]["name"] if i < eco.size() else ""
		var w: String = Defs.SHIPS[war[i]]["name"] if i < war.size() else ""
		if i == HUD.PAGE_SWITCH_SLOT:
			e = "Military >"
			w = "< Economy"
		var sel: String = "" if Defs.BUILD_ORDER[i] == "corvette" else Defs.SHIPS[Defs.BUILD_ORDER[i]]["name"]
		rows.append([[OS.get_keycode_string(keys[i]), EDGE_LIT], e, w, sel])
	_table(["Key", "Economy page", "Military page", "Selects (no starbase)"], rows)
	_heading("Everything else")
	_table(["Action", "Key"], [
		["Select / box select", "Left click / drag"],
		["Select every ship of a class on screen", "Double-click"],
		["Move, attack, mine, colonize, refit", "Right click"],
		["Attack-move", "Ctrl + right click"],
		["Pan the camera", "Arrow keys, screen edge, middle-drag"],
		["Zoom", "Mouse wheel"],
		["Stop", ["T", EDGE_LIT]],
		["Select all warships", ["Tab", EDGE_LIT]],
		["Select all corvettes", [OS.get_keycode_string(Defs.key_for("corvettes")), EDGE_LIT]],
		["Go to your starbase, then cycle through the others", ["B", EDGE_LIT]],
		["Next world of yours", ["Space", EDGE_LIT]],
		["Build on the focused world", ["F", EDGE_LIT]],
		["Research", ["R", EDGE_LIT]],
		["Set / select control group", ["Ctrl + 1-9  /  1-9", EDGE_LIT]],
		["Center on a control group", ["1-9 twice", EDGE_LIT]],
		["Pause and resume", ["Pause key, or the Pause button", EDGE_LIT]],
		["Game speed", ["-  /  =  (Backspace resets)", EDGE_LIT]],
		["Self-destruct one selected unit / all selected (starbases ask first)", ["Delete  /  Shift + Delete", EDGE_LIT]],
		["Clear the selection; with nothing selected, the menu", ["Esc", EDGE_LIT]],
	])

## What each ship is for, beyond its stats. Warship variants and the depot
## are covered in Combat, so they aren't repeated here.
const SHIP_NOTES := {
	"miner": "Hauls ore. Right-click an asteroid to mine it and it shuttles loads back to a starbase on its own; orange-flecked rocks carry spice. Asteroids run dry, so miners keep moving outward as a belt empties.",
	"skimmer": "Mines minerals from gas giants, which never run out but refill slowly after being drained, and harvests spice gas inside a spice nebula: right-click a spot in the cloud and it works there, slowly and indefinitely.",
	"colony": "Settles a free world, and is used up doing it. Colonizing takes a minute in orbit and the new colony starts small, so send it early and guard it: an unescorted colony ship is the cheapest kill on the map.",
	"constructor": "Builds stations and is used up doing it: a starbase to claim ground and produce ships, a Mining Station as a forward drop-off, or a Weapons Depot to refit warships. Starbase upkeep climbs steeply with each one, so the second and third are real economic decisions.",
	"scout": "Cheap, fast and unarmed: its only purpose is sight. It sees far, into spice nebulae and through ion storms, and its beacons keep watching a spot after it has moved on.",
	"tender": "Keeps a fleet alive between battles. Armor never comes back any other way, so a tender is what turns a worn-down fleet into a fresh one without going home.",
	"heatshield": "A support ship that lives where others can't: inside a star's radiation and spice nebulae. Its solar sail harvests 15 energy a minute there, charging a light-purple solar shield (100; each energy recharges 10% of it; full when built, charging even under fire) before any goes to your energy pool. The shield is a bubble nearly two carriers wide: one shared damage pillow that soaks enemy fire on every friendly ship, construct and world inside it, and while it is up nothing inside takes Radiation - friend or foe. Touching bubbles of your arrays merge into one mega shield that pools their points (three full arrays: 300); every hit is shared among the arrays in proportion to their charge, so the pool bursts for all of them at once when it hits 0. If they drift apart, each keeps its own share and becomes a separate bubble again. Shield techs on the Defense tab (Deflector Arrays, Phase Shields, Aegis Matrix) raise a solar shield's maximum like any other shield - all three: +90%, 190 points - and since each energy recharges 10% of the maximum, a bigger shield refills just as fast. Variant rules apply to solar shields as to any shield: Plasma hits them at x2.2, Slip and Disruptor shots pass straight through the bubble, and Overcharged Coils lets 25% of each hit through. The array itself is always immune to Radiation. A support ship with no weapon: it can't be refitted.",
	"corvette": "The cheap body of a fleet. Fast and short-ranged, it is bought in numbers.",
	"destroyer": "An armored boat with two light turrets that track a target without turning the hull, and the longest reach of the small hulls.",
	"cruiser": "Heavy shields and three laser turrets that outrange everything smaller. Slow to turn, so it is punished by anything that can stay off its nose, and it wants an escort of its own.",
	"carrier": "The heaviest hull, armored and shielded far more than its hull, with four turrets that traverse on their own, so the hull never has to come about to fire. Turrets fire on the move at reduced accuracy (Gyro-Stabilizers remove that). Its Mods trade the turrets for drones, add tractor beams, or fire long-range missile salvos.",
}
