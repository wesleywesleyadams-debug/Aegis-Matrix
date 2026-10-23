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
	["worlds", "Worlds"],
	["constructs", "Constructs"],
	["systems", "Systems"],
	["terms", "Terminology"],
]

## Long sections split into sub-pages, listed under them in the nav while
## the section is open. The first sub-page is the section's landing page.
## The research tabs in the research screen's order (HUD._build_research);
## Research gets one sub-page per tab that has techs (see _subpages).
const RESEARCH_TABS := [["warships", "Warships"], ["weapons", "Weapons"], ["mods", "Mods"], ["defense", "Defense"],
	["constructs", "Constructs"], ["worlds", "Worlds"], ["logistics", "Logistics"], ["general", "General"]]

static var SUBPAGES: Dictionary = _subpages()
const _SUBPAGES_FIXED := {
	"combat": [["layers", "Defense layers"], ["classes", "Classes"], ["variants", "Variants"],
		["mods", "Weapon Mods"], ["matchups", "Matchups"], ["jobs", "Ship jobs"], ["engagement", "Stance & Engagement"]],
	"ships": [["overview", "Overview"], ["marks", "Marks"], ["colors", "Variant colors"], ["every", "Every ship"]],
}

static func _subpages() -> Dictionary:
	var d: Dictionary = _SUBPAGES_FIXED.duplicate()
	var r: Array = [["overview", "Overview"]]
	for tab in RESEARCH_TABS:
		for id in Defs.TECHS:
			if Defs.TECHS[id].get("group", "general") == tab[0]:
				r.append(tab)
				break
	d["research"] = r
	return d

const COL_GAP := 32.0
## Width of a research card and its caption on a Research tab page.
const CAPTION_W := 380.0

var _body: VBoxContainer          ## staging: pages build here, then _flow()
var _rows: VBoxContainer          ## the laid-out page (see _flow)
var _nav_buttons := {}
var _sub_buttons := {}
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
	nav.add_theme_constant_override("separation", 6)
	cols.add_child(nav)
	for s in SECTIONS:
		var b := Button.new()
		b.text = s[1]
		b.custom_minimum_size = Vector2(0, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func(): _show(s[0]))
		nav.add_child(b)
		_nav_buttons[s[0]] = b
		for sp in SUBPAGES.get(s[0], []):
			var sb := Button.new()
			sb.text = sp[1]
			sb.custom_minimum_size = Vector2(0, 24)
			sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			sb.focus_mode = Control.FOCUS_NONE
			sb.flat = true
			sb.add_theme_font_size_override("font_size", 17)
			var pad := StyleBoxEmpty.new()
			pad.content_margin_left = 20
			for st in ["normal", "hover", "pressed", "focus"]:
				sb.add_theme_stylebox_override(st, pad)
			sb.pressed.connect(func(): _show(s[0] + "/" + sp[0]))
			sb.visible = false
			nav.add_child(sb)
			_sub_buttons[s[0] + "/" + sp[0]] = sb
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
## `striped` (default): every other row gets a lighter band, so a table reads
## left to right.
func _table(cols: Array, rows: Array, striped: bool = true) -> void:
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.columns = cols.size()
	grid.add_theme_constant_override("h_separation", 0 if striped else 22)
	grid.add_theme_constant_override("v_separation", 0 if striped else 4)
	for c in cols:
		grid.add_child(_striped(_label(str(c), EDGE_LIT, 16), -1) if striped else _label(str(c), EDGE_LIT, 16))
	var ri := 0
	for row in rows:
		for cell in row:
			var l: Label = _cell(str(cell[0]), cell[1]) if cell is Array else _cell(str(cell), TEXT)
			grid.add_child(_striped(l, ri) if striped else l)
		ri += 1
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.add_theme_stylebox_override("panel", _table_style())
	frame.add_child(grid)
	_body.add_child(frame)

## A striped table's cell: padded, with a band behind odd rows.
func _striped(c: Control, row: int) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.55, 0.9, 0.12) if row >= 0 and row % 2 == 1 else Color(0, 0, 0, 0)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(c)
	return pc

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
	if SUBPAGES.has(id):
		id += "/" + SUBPAGES[id][0][0]
	_current = id
	var top := id.get_slice("/", 0)
	for k in _nav_buttons:
		_nav_buttons[k].add_theme_color_override("font_color", EDGE_LIT if k == top else TEXT)
	for k in _sub_buttons:
		_sub_buttons[k].visible = k.begins_with(top + "/")
		_sub_buttons[k].add_theme_color_override("font_color", EDGE_LIT if k == id else DIM)
	for c in _body.get_children():
		c.queue_free()
	match id:
		"overview": _page_overview()
		"controls": _page_controls()
		"combat/layers": _page_layers()
		"combat/classes": _page_classes()
		"combat/variants": _page_variants()
		"combat/mods": _page_mods()
		"combat/matchups": _section_matchups()
		"combat/jobs": _page_jobs()
		"combat/engagement": _page_engagement()
		"ships/overview": _page_ships()
		"ships/marks": _page_marks()
		"ships/colors": _page_colors()
		"ships/every": _page_every()
		"research/overview": _page_research()
		_ when id.begins_with("research/"): _page_research_tab(id.get_slice("/", 1))
		"economy": _page_economy()
		"worlds": _page_worlds()
		"constructs": _page_constructs()
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
		[["Minerals", Color("3fd6b0")], "Mining barges, gas skimmers, mining complexes - all finite", "Ships, buildings, starbases, Power Plant fuel"],
		[["Energy", Color("ffd84a")], "Power plants (burning 1 mineral per 10 energy), Radiation Sail Arrays. Starbases make none", "Fleet and starbase upkeep, building upkeep, shield regeneration"],
		[["Spice", Color("ff9a2e")], "Spice asteroids, spice extractors, nebula harvesting", "All research; covers shortfalls of food, minerals and energy (1 spice covers 2; not Power Plant fuel)"],
	])
	_heading("A finite galaxy", EDGE_LIT)
	_para("Nothing refills. Rocks, gas giants, worlds' crusts and spice nebulae all run out, so a long match becomes a fight over what is left. Gas giants and mined-out worlds glow when nearly empty and blow up 10 seconds after they run out - see Economy.")

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

func _page_layers() -> void:
	_heading("Defense layers")
	_pic("layers", "Damage drains shields, then armor, then hull.", Vector2(460, 150))
	_table(["Layer", "Regenerates", "Notes"], [
		[["Shields", Defs.LAYER_COLORS["shield"]], "Yes, for a little energy", "Paused while taking damage, Radiation included"],
		[["Armor", Defs.LAYER_COLORS["armor"]], "No", "Only a Repair Tender restores it"],
		[["Hull", Defs.LAYER_COLORS["hull"]], "No", "A Repair Tender heals hull first, then armor"],
	])
	_pic("shield_regen", "Spread fire lets unhit ships recover; focused fire keeps their shields down.", Vector2(460, 150))
	_para("Research can raise every layer, and add screens that cut a share of each hit: see Research > Defense.")

func _page_classes() -> void:
	_heading("Generalists")
	_para("Each class leans on a different layer: corvettes on hull, destroyers on armor, cruisers on shields, carriers on shields and armor. That gives specialists a target.")
	var rows: Array = []
	for t in Defs.MARK_LINES + ["starbase"]:
		var d: Dictionary = Defs.STARBASE if t == "starbase" else Defs.SHIPS[t]
		rows.append([d["name"], [str(int(d["shield"])), Defs.LAYER_COLORS["shield"]], [str(int(d.get("armor", 0))), Defs.LAYER_COLORS["armor"]],
			[str(int(d["hp"])), Defs.LAYER_COLORS["hull"]], _lean_cell(d)])
	_table(["Ship", "Shield", "Armor", "Hull", "Leans on"], rows)
	var wrows: Array = []
	for t in Defs.MARK_LINES:
		var d: Dictionary = Defs.SHIPS[t]
		wrows.append([d["name"], "%s every %s s" % [String.num(float(d["damage"]), 1), String.num(float(d["cooldown"]), 1)], "%d" % int(d["range"]), "%d" % int(d.get("guns", 1)), "%d" % int(d["speed"])])
	_table(["Ship", "Laser damage", "Range", "Guns", "Speed"], wrows)

func _page_variants() -> void:
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
	_para("Base damage needed to destroy a target, compared with a generalist: 1.00 is equal, lower kills faster. Worked out from each hull's shield, armor and hull and each variant's damage against them - layer math, not battle results. Real fights also turn on range, speed, accuracy, marks and Mods, so treat it as a guide; Combat > Matchups has measured duel results for classes and Mods (not variants).")
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
	_heading("When to use each variant")
	var vgrid := GridContainer.new()
	vgrid.columns = 3
	vgrid.add_theme_constant_override("h_separation", 16)
	vgrid.add_theme_constant_override("v_separation", 12)
	for vu in [["generalist", "Generalist", "No weak matchup: the safe pick when you don't know the enemy. Against starbases every variant is about even."],
			["plasma", "Plasma", "Cruiser- and carrier-heavy fleets of uncertain mix: by the layer math it gives up less than Slip or Disruptor when the guess is wrong."],
			["breacher", "Breacher", "Destroyers: the best pick against them by the layer math."],
			["reaver", "Ravager", "Corvette swarms, and bombarding worlds (it hits population hardest)."],
			["slip", "Slip", "Cruisers, then carriers. Weak against corvettes and destroyers, which need clearly more damage to kill."],
			["disruptor", "Disruptor", "Carriers and cruisers. Weakest of all against corvettes, and poor against destroyers."]]:
		var cell := VBoxContainer.new()
		var vn := _label(vu[1], Defs.GENERALIST_SHOT if vu[0] == "generalist" else Defs.VARIANTS[vu[0]]["color"], 16)
		cell.add_child(vn)
		cell.add_child(CodexArt.new("use_" + vu[0], Vector2(300, 150)))
		var vc := _wrap(vu[2], DIM, 14)
		vc.custom_minimum_size.x = 300
		cell.add_child(vc)
		vgrid.add_child(cell)
	_body.add_child(vgrid)
	_para("A variant comes from a Weapons Depot and stacks with the ship's mark (Ships > Marks).")

func _page_mods() -> void:
	_heading("Weapon Mods")
	_para("Mods change what a ship class fires: one per class at a time. Researching another replaces it (the old one keeps working until the new one is done).")
	_pic("mod_toggle", "Click a Mod's card (or its name under the clock) to switch it off and on.", Vector2(460, 150))
	_para("A Mod sets the weapon's shape; a depot variant still sets its damage (a Plasma torpedo hits shields x3.0).")
	_para("What each Mod costs and does, in numbers: see Research > Mods.")
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
	var pdm: Dictionary = Defs.MOD_WEAPONS["mod_point_defense_lattice"]
	_para("Point-Defense Lattice fires sliver-thin needle lasers, at the normal reload whatever the target. Each ready turret first fires at an enemy missile, torpedo or bomb within %d (never two turrets on one): the needle destroys it, then bends and bounces on to up to %d more enemy missiles, torpedoes, bombs or drones, each within %d of the last. Next come enemy drones in range (x%d damage), and only then ships, constructs and worlds, at %d%% damage." % [int(pdm["pd"]), Game.PD_BOUNCES, int(Game.PD_BOUNCE_R), int(Ship.PD_DRONE_MULT), int(round(float(pdm["dmg"]) * 100.0))])
	var ilb: Array = Defs.MOD_WEAPONS["mod_ion_lance"]["beam"]
	var ild: float = float(Defs.MOD_WEAPONS["mod_ion_lance"]["dmg"])
	_para("Ion Lance: each turret holds a continuous beam on its target once aimed (within 8 degrees), with no reload. Damage ramps the longer it stays on one target, from %d%% to %d%% of a laser's damage rate over %d s, and starts over on a new target: strong on one big hull, weak against swarms." % [int(round(ilb[0] * ild * 100.0)), int(round(ilb[1] * ild * 100.0)), int(ilb[2])])
	_para("Tractor Beams: the carrier's turrets fire no lasers. Each holds a beam on an enemy ship or drone up to %dx weapon range away, which burns it harder the closer it is: x%.2f a laser's damage rate at the beam's full reach, rising to x%.2f once dragged in to where the pull stops (it doesn't ramp over time like the Ion Lance), and drags it toward the carrier at %d per second (x4 drones, x3 corvettes, x2 destroyers, x0.5 carriers) until it is at 52%% of the guns' range. The beam doesn't slow its target. Missile Barrage: a %d-missile salvo every %d s at +%d%% range." % [int(trb[1]), float(trb[2]) * float(Defs.MOD_WEAPONS["mod_tractor_beams"]["dmg"]), float(trb[3]) * float(Defs.MOD_WEAPONS["mod_tractor_beams"]["dmg"]), int(trb[0]), 4 * int(Defs.MOD_WEAPONS["mod_missile_barrage"]["count"]), int(Defs.MOD_WEAPONS["mod_missile_barrage"]["cd"]), int((Defs.MOD_WEAPONS["mod_missile_barrage"]["range"] - 1.0) * 100)])
	var tb: float = float(Defs.MOD_WEAPONS["mod_proton_torpedoes"]["dmg"])
	var tcd: float = float(Defs.MOD_WEAPONS["mod_proton_torpedoes"]["cd"])
	_para("Proton Torpedoes are built to hunt big hulls. Each torpedo hits for %d%% of a laser shot, times the bonus below, and reloads %dx slower than a laser. They steer gently, so a ship that turns hard can shake one off." % [int(round(tb * 100.0)), int(tcd)])
	var trows: Array = []
	for k in [["Corvette", "corvette"], ["Destroyer", "destroyer"], ["Cruiser", "cruiser"], ["Carrier", "carrier"], ["Starbase", "starbase"], ["World", "world"], ["Other constructs", "construct"]]:
		var m: float = float(vs.get(k[1], 1.0))
		trows.append([k[0], "x%s" % String.num(m, 2), "%d%%" % int(round(tb * m * 100.0)), "%d%%" % int(round(tb * m / tcd * 100.0))])
	_table(["Target", "Bonus", "Per torpedo (vs a laser shot)", "Damage over time (vs lasers)"], trows)


func _page_engagement() -> void:
	_heading("Stance")
	_para("Each warship also has a Stance, set with the three buttons under Engagement (one or many warships at once; a mixed selection shows Mixed). Stance decides whether, and how far, the ship goes after enemies on its own; Engagement then shapes the fight within what the Stance allows. Orders you give are always followed. A tiny colored square beside the Engagement dot marks a non-Aggressive stance.")
	_table(["Stance", "What it does"], [
		["Aggressive", "Takes on any enemy that comes within about its weapon range (plus a little) and chases it as long as it can see it, then flies back to where it picked the fight. Every new ship, and every AI ship, uses it, and the game's balance is tuned for it."],
		[["Defensive", Color("ffd24a")], "Takes on enemies the same way, but on a fight it picked itself it never goes more than about 1.5x its weapon range from its anchor (where it was last parked). A target it cannot shoot from inside that ring is let go, and the ship returns to its anchor."],
		[["Stand Ground", Color("e070ff")], "Never moves on its own: it only turns (hull and turrets) and fires at enemies within weapon range, and Engagement movement (closing in, falling back, dodging) is switched off. A move order still moves it; an attack order on a target out of range flies in to about 80% of range, as Default does. Once the target is dead it holds the new spot."],
	])
	_para("Combined: a Defensive ship with Aggressive Engagement closes to 40% of range, but never past its 1.5x leash; a Defensive one with Evasive Engagement still dodges, inside the leash. Attack and attack-move orders are orders: the leash does not apply to them, and a Stand Ground ship on an attack-move chases what it meets (with no Engagement movement).")
	_heading("Engagement")
	_para("Each warship has an Engagement setting, chosen with the four buttons in its panel (one or many warships at once; a mixed selection shows Mixed). It shapes how the ship fights once it engages, automatically or on an attack order. A move order still goes exactly where it is sent; the ship takes up its Engagement again on arrival. A small colored dot under a warship's chevrons marks a non-Default setting.")
	_table(["Engagement", "What it does"], [
		["Default", "Closes to about 80% of weapon range and holds there. New ships start here, and the game's balance is tuned for it."],
		[["Aggressive", Color("ff5a4a")], "Closes to about 40% of weapon range and sticks to its target, following it if it runs."],
		[["Defensive", Color("5aa8ff")], "Fights from about 90% of weapon range. An enemy closing inside 75% makes it fall back until the range is open again: backing off while firing with Reverse Thrusters, otherwise turning away, flying out and coming back about."],
		[["Evasive", Color("6cf08a")], "Fights as Default but dodges. Bomblets: it sidesteps (Strafing Thrusters) and/or backs off (Reverse Thrusters) as they come. Torpedoes: it waits, then jukes square across the shot's path just before impact, so the torpedo cannot turn tightly enough and overshoots; Proton Torpedoes lose their lock. A dodge or juke is a burst at %d%% speed on every axis; afterwards the engines run at %d%% for %s as long, and no new dodge starts until they recover. Lasers and Flak (and Rail from long range): with Strafing Thrusters it weaves side to side at normal thrust, nose still on its target, so shots aimed where it was or was heading go wide; weaving shakes its own aim a little. In tests it cut bomblet hits about 80%%, Proton Torpedo hits about half and laser hits about a third, for about 8%% less damage dealt. Homing Missiles are too fast and keep their lock, and Kinetic slugs and close-range Rail arrive too quickly, so it does not try against those. Without either thruster it can only burn straight ahead, and only when its nose already points roughly across the shot's path, so it seldom dodges at all." % [int(round((1.0 + Ship.EVADE_BOOST) * 100.0)), int(round((1.0 - Ship.EVADE_PENALTY) * 100.0)), "twice" if is_equal_approx(Ship.EVADE_PENALTY_TIME_MULT, 2.0) else "%.1fx" % Ship.EVADE_PENALTY_TIME_MULT]],
	])

func _page_jobs() -> void:
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
	_para("Every warship has three separate traits. Its CLASS is the hull it was built as and never changes. Its MARK is how refined that hull is, bought on the Warships research tab. Its VARIANT is its specialty, from a Weapons Depot refit. A Mk IV Ravager Corvette is all three: a corvette, at the top mark, fitted to hunt hull.")
	_table(["System", "Comes from", "Changes", "You can tell by"], [
		[["Class", TEXT], "What you build it as", "Never", "The hull's silhouette"],
		[["Mark", EDGE_LIT], "Warships research", "Every ship of that class, at once", "How many chevrons beside it"],
		[["Variant", Defs.VARIANTS["reaver"]["color"]], "Refit at a Weapons Depot", "Once, permanently", "The color of its chevrons"],
	])
	_heading("Class — the shape")
	var cls_plate: Array = []
	for cls in Defs.MARK_LINES:
		cls_plate.append(["ship_" + cls, Defs.SHIPS[cls]["name"], TEXT])
	_plate(cls_plate, 104.0, true, "One shape per class, for life: corvette A, destroyer Y, cruiser X, carrier a winged arrowhead.")
	_para("Shape says what a ship is, not how good it is. A corvette is a braced delta with its apex at the bow. A destroyer is a tail boom forking into two prongs. A cruiser is four wings crossed at a hub. A carrier is an arrowhead core with hangar wings, whose wingtips carry two outrigger nacelles with its turrets. Silhouettes show a fleet's makeup.")

func _page_marks() -> void:
	_heading("Mark — the rank")
	_para("Each mark adds to damage, hull, armor and shields alike. Later marks are worth more, and bigger classes gain more from each. What each mark adds, as a share of Mk I stats:")
	var mrows0: Array = []
	for cls in Defs.MARK_LINES:
		var row0: Array = [[Defs.SHIPS[cls]["name"], TEXT]]
		for i in range(1, Defs.HULL_MARKS.size()):
			row0.append("+%d%%" % int(round((Defs.MARK_BONUS[cls][i] - Defs.MARK_BONUS[cls][i - 1]) * 100.0)))
		mrows0.append(row0)
	_table(["Class", Defs.HULL_MARKS[1], Defs.HULL_MARKS[2], Defs.HULL_MARKS[3]], mrows0)
	_para("Every warship has small chevrons beside it, one per mark: one at Mk I, four at Mk IV. Each class researches its own marks, so each class is a separate investment. A mark applies to every ship of that class the moment research finishes, existing ships included.")
	_para("Costs and times for every mark: see Research > Warships.")

func _page_colors() -> void:
	_heading("Variant — the color")
	_para("A variant keeps its class's hull; only its chevrons change color. Generalists wear yellow chevrons. Each variant has its own color, the same as its shots:")
	var crows: Array = [[["Generalist", Defs.GENERALIST_COLOR], ["^ ^ ^", Defs.GENERALIST_COLOR]]]
	for tv in Defs.VARIANTS:
		crows.append([[Defs.VARIANTS[tv]["label"], Defs.VARIANTS[tv]["color"]], ["^ ^ ^", Defs.VARIANTS[tv]["color"]]])
	_table(["Variant", "Chevrons"], crows)
	_para("Chevron count shows rank; color shows variant. Combat > Variants covers what each variant does to damage.")

func _page_every() -> void:
	_heading("Every ship")
	_para("Stats as built, before research. Specialist variants share their generalist's hull and cost; only their damage profile changes (see Combat > Variants).")
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

## Research > Overview: how research works.
func _page_research() -> void:
	_heading("Research")
	_para("Research costs spice only, paid over time. Open the research screen with R. Only one project runs at a time: click a tech to start it. Picking another tech pauses the current one; a paused tech keeps its progress and resumes where it left off. Click the active one to pause it.")
	_para("The cost is paid gradually while the project runs, not up front. If you run out of spice, progress stalls until you have more.")
	_para("In single player the match waits while the research screen is open. It opens by itself at the start of a match (on Warships) and whenever a project finishes with nothing else running (on that tech's tab), so research never sits idle unnoticed.")
	_heading("Tiers and requirements", EDGE_LIT)
	_para("Each tab is a grid: one row per line of upgrades, one column per tier. A tech needs the one before it in its row (the padlock on a card names it); Spice Navigation needs either of two. Tier 1 costs energy only and takes under a minute; tier 2 adds spice and costs about twice as much; tier 3 costs around five times tier 2 and takes about four minutes, so a tier 3 project is a real commitment.")
	_para("Bonuses of the same kind add together: three damage techs of +20%, +25% and +30% give +75% (x1.75). Different kinds multiply: damage times rate of fire times a ship's mark.")
	var trows: Array = []
	for tab in SUBPAGES["research"]:
		if tab[0] == "overview":
			continue
		var n := 0
		for id in Defs.TECHS:
			if Defs.TECHS[id].get("group", "general") == tab[0]:
				n += 1
		trows.append([[tab[1], TechIcons.GROUP_COLORS.get(tab[0], EDGE_LIT)], str(n), Defs.TECH_GROUP_DESC.get(tab[0], "")])
	_table(["Tab", "Techs", "What it is for"], trows)
	_para("Each tab's page here shows its tree with a note under every tech: exact numbers, what it touches, how it stacks, and when it is worth the time.")

## Research > <tab>: the tab's tree, a caption under every card.
func _page_research_tab(g: String) -> void:
	var title := g.capitalize()
	for tab in RESEARCH_TABS:
		if tab[0] == g:
			title = tab[1]
	_heading(title, TechIcons.GROUP_COLORS.get(g, EDGE_LIT))
	_para(Defs.TECH_GROUP_DESC.get(g, ""))
	match g:
		"mods": _para("A row is one class. Its three Mods exclude each other: researching another replaces the one you have (the old one keeps working until the new one is done, and must be researched again to come back). Click an active Mod's card to switch it off and on for free. A Mod changes the weapon's shape; a depot variant still sets its damage profile, and marks and Weapons research apply as usual. Combat > Weapon Mods shows each one in action.")
		"warships": _para("A mark applies at once to every ship of that class, built or not yet built, and multiplies with Weapons and Defense research.")
		"defense": _para("The Shields, Armor and Hull lines each add a share of a ship's or construct's total base HP (hull + armor + shields, Mk I stats) to that one layer, so a small ship gains as much, in proportion, as a big one. The Deflectors line applies before the layers: with all three, a hit loses %d%% before shields see it." % int(round(_tot("damage_taken") * 100.0)))
	_tech_tree(g, _research_rows(g), true)

## ", +N% with the techs before it" for a tech deeper than tier 1 in a line.
func _cum_text(id: String, key: String) -> String:
	return ""
	var total := 0.0
	var cur := id
	while cur != "":
		total += float(Defs.TECHS[cur]["effects"].get(key, 0.0))
		var req: Array = Defs.TECHS[cur]["requires"]
		cur = req[0] if req.size() == 1 and Defs.TECHS[req[0]]["effects"].has(key) else ""
	if is_equal_approx(total, float(Defs.TECHS[id]["effects"].get(key, 0.0))):
		return ""
	return " (+%d%% with the techs before it)" % int(round(total * 100.0))

## Sum of one effect key over every tech: the most research can give.
func _tot(key: String) -> float:
	var t := 0.0
	for id in Defs.TECHS:
		t += float(Defs.TECHS[id]["effects"].get(key, 0.0))
	return t

func _ship_line(cls: String) -> String:
	var d: Dictionary = Defs.SHIPS[cls]
	var gun: String = (", range %d" % int(d["range"])) if str(d.get("weapon", "")) != "" else ", unarmed"
	return "%s (%s, %d s): %d shield / %d armor / %d hull%s, speed %d" % [d["name"], Defs.cost_text(d["cost"]), int(d["build_time"]), int(d["shield"]), int(d.get("armor", 0)), int(d["hp"]), gun, int(d["speed"])]

## What a tech does in practice. Numbers come from Defs so they follow balance.
func _tech_caption(id: String) -> String:
	var t: Dictionary = Defs.TECHS[id]
	var e: Dictionary = t["effects"]
	if t.has("mod"):
		return _mod_caption(id)
	if t.has("class"):
		var cls: String = t["class"]
		var lvl: int = ["mk2", "mk3", "mk4"].find(id.get_slice("_", 1)) + 1
		var b: Array = Defs.MARK_BONUS[cls]
		var s := "Every %s you own, existing ships included, gains +%d%% of its Mk I damage, hull, armor and shields on top of the mark before" % [str(Defs.SHIPS[cls]["name"]).to_lower(), int(round((b[lvl] - b[lvl - 1]) * 100.0))]
		s += ". It multiplies with Weapons damage techs rather than adding to them. "
		match lvl:
			1: s += "Cheap and quick: worth it as soon as this class is the backbone of your fleet."
			2: s += "Good value: buy it for the class you build most."
			3: s += "The biggest single jump, at a tier-3 price: commit only to the class you will still be building at the end."
		return s
	match id:
		"destroyers": return _ship_line("destroyer") + ". Destroyers lean on armor and outrange corvettes. Also opens destroyer marks and Mods, and leads to Cruisers. Cheap: the usual first tech unless you are rushing with corvettes."
		"cruisers": return _ship_line("cruiser") + ", %d turreted guns. Cruisers lean on shields, which regenerate between fights. Opens cruiser marks and Mods, and leads to Carriers." % int(Defs.SHIPS["cruiser"]["guns"])
		"carriers": return _ship_line("carrier") + ". The heaviest hull, shields and armor in equal measure, slow, and the dearest upkeep after a starbase. Opens carrier marks and Mods. A late-game investment."
		# --- Weapons
		"ion_cannons", "particle_lances", "lance_batteries":
			var why: String = {"ion_cannons": "The cheapest raw combat upgrade in the game: almost always worth it early.", "particle_lances": "A strong mid-game pick once you fight regularly.", "lance_batteries": "The heavy-gun end of the tier-3 choice; pairs best with slow, heavy weapons (Rail Cannons, Proton Torpedoes)."}[id]
			var mid := " It applies to every shot you fire: warships, drones, starbases, outposts, mining stations and world batteries, against ships, constructs and worlds alike (so bombardment kills pops faster too), on top of marks, variants and Mods." if int(t["tier"]) == 1 else ""
			return "+%d%% weapon damage%s.%s %s" % [_pct(id, "damage"), _cum_text(id, "damage"), mid, why]
		"targeting_arrays", "beam_focusing", "capital_batteries":
			var why2: String = {"targeting_arrays": "Cheap; best for fleets that stand off (cruisers, Rail Cannons).", "beam_focusing": "Also lets starbases cover more of the space around them.", "capital_batteries": "Late game: with Citadel Protocols a starbase outranges most fleets."}[id]
			var mid2 := " It reaches every ship, starbase and Frontier Outpost (Mining Stations keep theirs), and multiplies a Mod's own range: with the whole line Rail Cannons' x1.4 becomes x%.2f. Longer reach gives you the first volley and lets you kite slower fleets." % (1.4 * (1.0 + _tot("range"))) if int(t["tier"]) == 1 else ""
			return "+%d%% weapon range%s.%s %s" % [_pct(id, "range"), _cum_text(id, "range"), mid2, why2]
		"autoloaders", "heavy_mounts", "scatter_arrays":
			var why3: String = {"autoloaders": "Worth about as much as a damage tech; take whichever is cheaper first.", "heavy_mounts": "Best with many small guns: corvette swarms, Kinetic Repeaters, Flak.", "scatter_arrays": "The fast-gun end of the tier-3 choice (Lance Batteries is the heavy-gun end)."}[id]
			var mid3 := " It speeds the reload of ships, drones and starbases (outposts and Mining Stations keep theirs); more shots also means more Point-Defense needles." if int(t["tier"]) == 1 else ""
			return "+%d%% rate of fire%s.%s %s" % [_pct(id, "fire_rate"), _cum_text(id, "fire_rate"), mid3, why3]
		"overcharged_coils": return "%d%% of each hit ignores enemy shields and goes straight on to armor. Strongest against cruisers, carriers and starbases (shield-heavy); no help once a target's shields are down. Plasma, Slip and Disruptor variants already pass shields, so it adds nothing to them." % _pct(id, "shield_pierce")
		"burst_cyclers": return "%d%% of what reaches the armor skips it and hits the hull. Best against destroyers and carriers, which carry the most armor. With Overcharged Coils a laser shot gets a quarter past each of the first two layers." % _pct(id, "armor_pierce")
		"hullbreaker_rounds": return "Damage that reaches the hull is x%.2f. Every kill ends on the hull, so it helps against everything, most against hull-heavy corvettes and anything already stripped. Pairs with the two piercing techs, which push more of each shot onto the hull." % (1.0 + float(e["hull_damage"]))
		"target_prediction": return "Unguided shots aim where a moving target will be, not where it is. Without it fast ships (corvettes, speed %d) dodge much of the fire aimed at them at range. Homing weapons don't need it. Cheap: worth it whenever you fight anything fast." % int(Defs.SHIPS["corvette"]["speed"])
		"gyro_stabilizers": return "No accuracy loss on the move. Without it a ship firing at full speed lands only about %d%% of its shots (less loss the slower it goes). Essential for kiting, chasing and fighting while retreating." % int(round(Ship.MOVING_ACCURACY * 100.0))
		"overkill_awareness": return "Your side keeps count of the damage already in flight at each enemy. When those shots will finish it, the other guns (turrets, corvettes' fixed guns, starbases, outposts and Mining Stations) pick the nearest enemy that is not already doomed instead of adding more; if every enemy in reach is doomed they fire anyway, and a target whose doomed shots miss is taken up again. Ships hunting for a target pass over doomed ones too. Area shots (bombs, blasts) are not counted. Worth it in big fights with many guns on many small targets (corvette swarms, mixed fleets), where piled-on volleys waste the most; little help against a few large hulls."
		# --- Defense
		"phase_shields", "crystal_prisms", "aegis_matrix":
			var w4: String = {"phase_shields": "Shields are the layer that comes back: they regenerate, for a little energy, once a ship stops taking hits, so this pays off over many fights. Shield-heavy classes gain the least, in proportion, since they already carry the most.", "crystal_prisms": "Also thickens planetary shields and a Radiation Sail Array's solar shield, which refills just as fast (each energy harvested charges a share of the maximum).", "aegis_matrix": "The biggest step; commit to it when most of your fleet's toughness is shields (cruisers, carriers, starbases)."}[id]
			return "Every ship and construct gains shields equal to %d%% of its total base HP (hull + armor + shields). Worlds' planetary shields gain +%d%% of themselves. %s" % [_pct(id, "shield_total"), _pct(id, "world_shield"), w4]
		"composite_plating", "reactive_armor", "neutronium_armor":
			var w5: String = {"composite_plating": "Armor never regenerates; only a Repair Tender restores it, so it suits fleets that fight decisively or bring tenders. Worlds have none.", "reactive_armor": "Breachers and Burst Cyclers are the enemy's answer to it.", "neutronium_armor": "The biggest step; armor never comes back, so pair it with Repair Tenders."}[id]
			return "Every ship and construct gains armor equal to %d%% of its total base HP (hull + armor + shields). %s" % [_pct(id, "armor_total"), w5]
		"reinforced_frames", "living_metals", "adaptive_hulls":
			var w6: String = {"reinforced_frames": "Hull is the last layer, the one Ravagers and Rupture Charges hit hardest, so this blunts both. Since the bonus is a share of all three layers, it helps every class equally.", "living_metals": "Harvesters gain too, and with Convoy Protocols a harvester's extra shields and armor grow with its hull.", "adaptive_hulls": "The biggest step; hull is the layer Ravagers hit hardest."}[id]
			return "Every ship and construct gains hull equal to %d%% of its total base HP (hull + armor + shields). %s" % [_pct(id, "hull_total"), w6]
		"glance_plates", "steel_canopy", "iron_umbrella":
			var why4: String = "Cheap: the best defense for the price." if int(t["tier"]) == 1 else ("Worth it once the fleet is most of your spending." if int(t["tier"]) == 2 else "Expensive, but no layer tech gives as much in one step.")
			return "-%d%% damage taken by every ship and construct, before shields. Deflectors add together: all three cut %d%% of every hit, radiation included. Worlds are not covered. %s" % [_pct(id, "damage_taken"), int(round(_tot("damage_taken") * 100.0)), why4]
		# --- Constructs
		"garrison_guns": return "Construct guns hit +%d%%: starbases, Mining Stations and Frontier Outposts (world batteries are on the Worlds tab). It multiplies with Weapons damage: with all of both, a starbase shot is x%.2f. Worth it if raiders keep reaching your base or stations." % [_pct(id, "structure_damage"), (1.0 + float(e["structure_damage"])) * (1.0 + _tot("damage"))]
		"reinforced_docks": return "+%d%% hull and armor on every construct: starbases, depots, stations, outposts and gates. Also multiplies the Defense hull and armor lines' added amounts. Buy it when your starbase is what the enemy is aiming for." % _pct(id, "structure")
		"citadel_protocols": return "+%d%% construct shields (also applied to the Defense shield line's added amount) and +%d%% range for starbase and outpost guns (multiplied with Weapons range). A turtling pick: a starbase that outranges besiegers and refills its shields between waves." % [_pct(id, "structure_shield"), _pct(id, "structure_range")]
		"depots": return "Unlocks the Weapons Depot (%s), which refits generalist warships into a specialist variant: Plasma, Breacher, Ravager, Slip or Disruptor. Needed for any variant at all. Leads to Outposts." % Defs.cost_text(Defs.WEAPONS_DEPOT["cost"])
		"outposts": return "Unlocks the Frontier Outpost (%s): half a starbase's shields, armor, hull and gun. It builds nothing and takes no cargo, but holds ground; construct gun research applies to it. Upkeep weighs as a cruiser. Use it to claim a belt or a choke point." % Defs.cost_text(Defs.FRONTIER_OUTPOST["cost"])
		"warp_gates": return "Unlocks the Warp Gate (%s, no gun): garrison any number of ships inside, then fling them all %d-%d px at %dx speed, fog or not, every %d s. Ships inside still cost upkeep and die with the gate, which weighs as a starbase in the upkeep multiplier. Late-game reach for surprise strikes." % [Defs.cost_text(Defs.WARP_GATE["cost"]), int(Defs.WARP_GATE["warp_min"]), int(Defs.WARP_GATE["warp_max"]), int(Defs.WARP_GATE["warp_speed_mult"]), int(Defs.WARP_GATE["warp_cooldown"])]
		"orbital_yards", "shipyard_networks":
			return "Starbases build ships +%d%% faster; the cost is paid faster too, so a ship costs the same. Worth it when the build queue, not resources, is the bottleneck." % _pct(id, "build_speed")
		"forward_bases": return "Ships +%d%% faster at starbases, and constructs +%d%% faster. Adds to Orbital Yards and to the Construction row. A bridge to Shipyard Networks." % [_pct(id, "build_speed"), _pct(id, "construct_speed")]
		"modular_frames": return "Constructors raise constructs +%d%% faster: starbases, depots, stations, outposts and gates. The less time a half-built construct stands, the less chance a raider kills it. With every construction tech, x%.2f speed." % [_pct(id, "construct_speed"), 1.0 + _tot("construct_speed")]
		"rapid_assembly": return "New constructs start %d%% built, with %d%% hull instead of 10%%: that first part of the build is free and instant, so every starbase, depot, station, outpost and gate finishes sooner and costs less, and a site under fire survives its first seconds. Best when you expand into contested space." % [int(round(float(e["construct_progress"]) * 100.0)), int(round(0.1 * (1.0 + float(e["construct_start"])) * 100.0))]
		"orbital_elevators": return "Constructs build +%d%% faster, and the empire upkeep multiplier shrinks by %d%% (with Jump Drives, %d%%). Every unit you own gets cheaper to keep, so it pays back most for a large empire." % [_pct(id, "construct_speed"), -_pct(id, "upkeep"), -int(round(_tot("upkeep") * 100.0))]
		# --- Worlds
		"hydroponics", "orbital_farms":
			var farm: float = Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN
			return "Farms grow +%d%% food. Fewer fields spent on Farms leaves more for Power Plants and Mining Complexes." % _pct(id, "food")
		"terraforming": return "+%d%% food and +%d%% population cap on every world. The cap bonus adds to the Population row's. A capstone for when your worlds are near their caps." % [_pct(id, "food"), _pct(id, "max_pop")]
		"rationing", "gene_clinics":
			var w7: String = {"rationing": "A fed world gains %s pop a minute for every 2 pops, so growth snowballs: the bigger a world, the faster it grows. Cheap: get it early if you plan to grow worlds." % str(Defs.GROWTH_PER_PAIR_PER_MIN), "gene_clinics": "The step that matters: worlds reach the output bonus much sooner and refill faster after bombardment or a famine."}[id]
			return "+%d%% population growth%s. %s" % [_pct(id, "growth"), _cum_text(id, "growth"), w7]
		"gene_forges": return "+%d%% growth and +%d%% population cap. The biggest growth step: worlds refill fast after bombardment or starvation." % [_pct(id, "growth"), _pct(id, "max_pop")]
		"habitat_modules", "arcologies", "deep_vaults":
			var extra := (", +%d%% growth" % _pct(id, "growth")) if e.has("growth") else ""
			var w8: String = {"habitat_modules": "Pops multiply every Farm, Power Plant, Mining Complex and Spice Extractor on their world; that bonus levels off toward x%.2f, and the three cap techs together lift the ceiling to x%.2f (a Habitat on the world adds 0.1 more). Cheap, but it only pays once worlds fill: pair with growth." % [1.0 + Defs.OUTPUT_POP_BONUS, 1.0 + Defs.OUTPUT_POP_BONUS + _tot("pop_bonus")], "arcologies": "Bigger worlds produce more twice over: more pops, and a higher ceiling on what each pop adds. Worth it once your core worlds are near their caps.", "deep_vaults": "The largest cap step, with some growth built in so the new room fills; the end-game economy tech for wide empires."}[id]
			return "+%d%% population cap on every world%s, and population's output bonus can rise %.2fx higher. %s" % [_pct(id, "max_pop"), extra, float(e["pop_bonus"]), w8]
		"colony_pods": return "New colonies start with %d pops instead of %d. Growth counts pairs of pops, so a new colony also grows twice as fast at first. Worth it if you plan several colonies." % [int(Defs.START_POP * (1.0 + float(e["colony_pop"]))), int(Defs.START_POP)]
		"planetary_shields", "planetary_citadels":
			var s2 := "+%d%% planetary shield (%d base, +%d per Defense Battery), multiplied with the Defense shield line. Bombardment must break the shield before it kills pops, and the shield refills after %d s without hits." % [_pct(id, "planet_shield"), int(Planet.PLANET_SHIELD), int(Defs.BATTERY_SHIELD), int(Defs.SHIELD_REGEN_DELAY)]
			if e.has("planet_damage"):
				s2 += " Batteries also hit +%d%%." % _pct(id, "planet_damage")
			return s2 + " Worth it when the enemy raids your worlds."
		"solar_collectors", "plasma_reactors", "dark_matter":
			var why5: String = {"solar_collectors": "Cheap fuel savings from the first Power Plant on.", "plasma_reactors": "Worth it once ship and building upkeep start eating your energy.", "dark_matter": "The big one: with all three, each mineral of fuel buys about 1.9x the energy."}[id]
			var mid5 := " Energy pays for ship, construct and building upkeep and shield regeneration." if int(t["tier"]) == 1 else ""
			return "+%d%% energy from Power Plants and Radiation Sail Arrays%s ; the extra energy burns no fuel, so each mineral of fuel goes further.%s %s" % [_pct(id, "energy"), _cum_text(id, "energy"), mid5, why5]
		# --- Logistics
		"deep_drills", "bulk_holds":
			return "Harvesters (Mining Barges and Gas Skimmers) carry +%d%% per load. Fewer trips per load hauled: worth most when belts are far from your drop-off." % _pct(id, "cargo")
		"logistics_command": return "Harvesters gather +%d%% faster and carry +%d%% more. Adds to both the Cargo and Harvest rows." % [_pct(id, "harvest"), _pct(id, "cargo")]
		"cutting_lasers", "resonance_drills", "mass_drivers":
			return "Harvesters gather +%d%% faster while parked on a rock, gas giant or nebula. Worth most when belts are close and trips short, so time spent gathering dominates." % _pct(id, "harvest")
		"ion_thrusters", "fusion_drives":
			return "+%d%% speed for every ship, harvesters and Constructors included. Faster harvest trips, faster reinforcements, easier kiting." % _pct(id, "speed")
		"vectored_thrusters": return "+%d%% turn rate for every ship, its turrets and drones. Ships fly nose-first and must turn to change course (bigger hulls turn slower), so this gets fleets onto a new heading, and fixed guns onto a new target, sooner. Worth it for corvettes and any fleet that fights on the move." % _pct(id, "turn_rate")
		"strafing_thrusters": return "Ships can also thrust sideways at up to %d%% of their speed, on top of full forward thrust. Used automatically: a ship slides toward its destination while still turning, and in a fight it keeps its nose on its target while sidestepping. Helps fixed-gun corvettes most." % int(round(Ship.LATERAL_THRUST * 100.0))
		"reverse_thrusters": return "Ships can also thrust backward at up to %d%% of their speed. Used automatically: a ship ordered away from a fight backs off still facing and firing, and one being dragged by Tractor Beams backs against the pull. Without it, a ship must turn its back to retreat." % int(round(Ship.REVERSE_THRUST * 100.0))
		"jump_drives": return "+%d%% speed for every ship, and the empire upkeep multiplier shrinks by %d%% (with Orbital Elevators, %d%%)." % [_pct(id, "speed"), -_pct(id, "upkeep"), -int(round(_tot("upkeep") * 100.0))]
		"gas_skimming": return "Unlocks the " + _ship_line("skimmer") + ". It works gas giants (finite: they explode when drained) and spice nebulae (finite spice, low Radiation inside). Worth it on maps with gas near your base."
		"convoy_protocols": return "Every harvester gains extra shields and extra armor, each equal to its hull, so it takes about three times the damage to kill. Get it when the enemy hunts your harvesters."
		"spice_navigation": return "Your ships take %d%% less radiation inside a spice nebula (not from a star). Needs Gas Skimming or Convoy Protocols. Worth it if skimmers or fleets spend time in nebulae." % int(round((1.0 - Abilities.SPICE_NAV_RADIATION) * 100.0))
	return t["desc"]

## A Mod's caption, from Defs.MOD_WEAPONS.
func _mod_caption(id: String) -> String:
	var m: Dictionary = Defs.MOD_WEAPONS.get(id, {})
	var dm := int(round(float(m.get("dmg", 1.0)) * 100.0))
	match id:
		"mod_proton_torpedoes":
			var vs: Dictionary = m["vs_class"]
			return "Slow, steerable torpedoes: each hits for %d%% of a laser shot and reloads %.1fx slower, but deals x%s vs destroyers, x%s vs cruisers and x%s vs carriers, starbases and worlds. Loses slightly to laser corvettes. The corvette answer to big hulls and sieges." % [dm, float(m["cd"]), String.num(vs["destroyer"]), String.num(vs["cruiser"]), String.num(vs["carrier"])]
		"mod_kinetic_repeaters": return "%.1fx the fire rate at %d%% damage per slug, %d%% of a laser's damage over time, at %d%% range. Rate-of-fire research multiplies it. For brawling corvettes against other light hulls." % [1.0 / float(m["cd"]), dm, int(round(float(m["dmg"]) / float(m["cd"]) * 100.0)), int(round(float(m["range"]) * 100.0))]
		"mod_arc_emitters": return "Each shot hits its target for %d%%, then jumps to up to 2 more enemies within %d for %d%% each. Strong against tight swarms; no gain on a lone big hull." % [int(round(m["chain"][0] * 100.0)), int(m["jump"]), int(round(m["chain"][1] * 100.0))]
		"mod_flak_cannons": return "Shells burst, hitting every enemy within %d of the blast for %d%% of a laser shot. Weak against one target, strong against corvette clumps and drones." % [int(Defs.AOE_RADIUS["flak"]), dm]
		"mod_cluster_bombs": return "Every %.1fx reload each gun throws %d unguided bomblets in a %d-%d degree fan, each %d%% of a laser shot with a %d-wide blast. About a laser's damage on a lone ship, far more on a group or a world." % [float(m["cd"]), int(m["count"]), int(m["fan"][0]), int(m["fan"][1]), dm, int(Defs.AOE_RADIUS["bomblet"])]
		"mod_homing_missiles": return "Volleys of homing missiles at +%d%% range, each %d%% of a laser shot with a small blast. They steer onto their target, so Target Prediction and Gyro-Stabilizers don't matter; Point-Defense can shoot them down." % [int(round((float(m["range"]) - 1.0) * 100.0)), dm]
		"mod_ion_lance": return "A continuous beam per turret, no reload: it ramps from %d%% to %d%% of a laser's damage rate over %d s on one target and restarts on a new one. Melts single big hulls; weak against swarms." % [int(round(m["beam"][0] * float(m["dmg"]) * 100.0)), int(round(m["beam"][1] * float(m["dmg"]) * 100.0)), int(m["beam"][2])]
		"mod_rail_cannons": return "A heavy slug every %.0fx the reload for %d%% of a laser shot: about %d%% of a laser's damage over time, at %d%% range. Best against big hulls from beyond their reach." % [float(m["cd"]), dm, int(round(float(m["dmg"]) / float(m["cd"]) * 100.0)), int(round(float(m["range"]) * 100.0))]
		"mod_point_defense_lattice": return "Needle lasers: each turret first shoots down enemy ordnance within %d (bouncing on to %d more), then drones (x%d damage), and only then ships at %d%% damage. The hard counter to missiles, torpedoes, bombs and drones." % [int(m["pd"]), Game.PD_BOUNCES, int(Ship.PD_DRONE_MULT), dm]
		"mod_interceptor_drones": return "The turrets stand down; the carrier launches up to %d drones (%d hull each) that fight within %d of it and die with it. Weaker against heavy hulls (x%s vs carriers). Flak and Point-Defense counter them." % [int(m["drones"][0]), int(Drone.HULL), int(m["drones"][1]), String.num(m["vs_class"]["carrier"])]
		"mod_tractor_beams": return "No lasers: each turret holds a beam on an enemy ship or drone up to %dx weapon range away, drags it toward the carrier at %d per second (x4 drones, x3 corvettes, x2 destroyers, x0.5 carriers) and burns it, harder the closer it is (x%.2f a laser's damage rate at full reach, x%.2f once pulled in to 52%% of range; no ramp over time). Beams never miss and all four hold at once. Pulls kiters and runners into your fleet." % [int(m["tractor"][1]), int(m["tractor"][0]), float(m["tractor"][2]) * float(m["dmg"]), float(m["tractor"][3]) * float(m["dmg"])]
		"mod_missile_barrage": return "A %d-missile salvo every %d s at +%d%% range, each missile %d%% of a laser shot: the longest reach a carrier has. A strong opener; Point-Defense thins it." % [4 * int(m["count"]), int(m["cd"]), int(round((float(m["range"]) - 1.0) * 100.0)), dm]
	return Defs.TECHS[id]["desc"]

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
			for line in ["shields", "armor", "hull", "deflectors"]:
				var ids: Array = ["", "", ""]
				for id in Defs.TECHS:
					if Defs.TECHS[id].get("line", "") == line:
						ids[Defs.TECHS[id]["tier"] - 1] = id
				out.append([line.to_upper(), ids])
			return out
	return HUD.TECH_ROWS.get(g, [])

func _tech_tree(g: String, rows: Array, captions: bool = false) -> void:
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
		if captions:
			head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			head.custom_minimum_size.y = 72
		grid.add_child(head)
		for id in r[1]:
			if id == "" or not Defs.TECHS.has(id):
				grid.add_child(Control.new())
			elif captions:
				var cell := VBoxContainer.new()
				cell.add_theme_constant_override("separation", 4)
				var card := _tech_card(id)
				card.custom_minimum_size.x = CAPTION_W
				cell.add_child(card)
				var cap := _label(_tech_caption(id), DIM, 14)
				cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				cap.custom_minimum_size = Vector2(CAPTION_W, 0)
				cell.add_child(cap)
				grid.add_child(cell)
			else:
				grid.add_child(_tech_card(id))
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
		req.add_child(_label(Game.requires_text(id, true), DIM, 12))
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
	_para("Rates are at base. Logistics techs speed up every harvester, Mining Barges and Gas Skimmers alike: Cutting Lasers, Resonance Drills and Mass Drivers add +%d%%, +%d%% and +%d%% gather rate, Deep-Core Drills and Bulk Holds +%d%% and +%d%% hold, and Logistics Command +%d%% of each. Convoy Protocols gives every harvester extra shields and extra armor, each equal to its hull. A Radiation Sail Array also gathers %d energy a minute while in Radiation (a star's zone or a spice nebula)." % [
		_pct("cutting_lasers", "harvest"), _pct("resonance_drills", "harvest"), _pct("mass_drivers", "harvest"),
		_pct("deep_drills", "cargo"), _pct("bulk_holds", "cargo"), _pct("logistics_command", "harvest"), int(Defs.SHIPS["heatshield"]["solar_sail"])])
	_heading("Asteroid sizes")
	_para("A small rock holds the same amount whether it is minerals or spice, and so does a large one, on every map. Spice is rare instead: about one rock in seven. Belts differ in their mix: a rich belt has more big rocks, a poor one mostly small. Rocks run dry and vanish. Nothing refills.")
	_heading("Gas giants")
	_para("Each gas giant holds %s minerals and never refills. It shrinks as it is drained (down to %d%% of its size) and below %s it turns unstable: it glows and pulses orange-red - there is no alert, so watch for it. Empty, it starts a %d-second countdown that nothing can stop (the glow turns red and pulses faster; its panel and tooltip show the seconds left), then EXPLODES and is gone: %s damage at its centre, falling evenly to 0 at %d px, to every ship, construct and world nearby, whoever owns them (planetary shields soak it first). Pull your skimmers and keep your stations clear - or drain one beside the enemy." % [
		Defs.short_num(Defs.GAS_RESERVE), int(Defs.GAS_MIN_SCALE * 100.0), Defs.short_num(Defs.UNSTABLE_RESERVE), int(Defs.DOOM_SECONDS), Defs.short_num(Defs.BLAST_DAMAGE), int(Defs.BLAST_RADIUS)])
	_heading("Spice nebulae")
	_para("A spice nebula is finite too: its gas is an invisible grid of %d px cells, %d spice each. A Gas Skimmer drains the cell its harvest spot is in; the cloud thins there, and an empty cell fades away for good - that patch no longer hides ships, irradiates them or counts as nebula at all. The skimmer then moves on to the nearest cell with gas left, until the whole nebula is gone." % [int(SpiceNebula.CELL), int(SpiceNebula.CELL_SPICE)])
	_heading("Power Plant fuel")
	_para("Power Plants burn minerals: 1 mineral for every 10 energy they make, counted after every bonus (population, research, a Molten world). Fuel comes only from the mineral stockpile - spice never pays it - and it is all or nothing: with no minerals to burn a plant makes no energy at all. Plants need no energy upkeep, so they keep running through a Blackout. Starbases make no energy and no minerals. The world panel and the resource bar tooltips show fuel per minute.")
	_rock_sizes()
	_heading("Upkeep")
	_para("Every ship and construct costs energy per minute, and ALL of it is multiplied by one empire-wide factor (shown on the resource bar): each unit you own multiplies it - starbase x%.2f, carrier x%.2f, cruiser x%.2f, destroyer x%.2f, anything else x%.2f - so the more you own, the dearer every unit gets. Orbital Elevators and Jump Drives each shrink the multiplier by 10%%. With no energy in stock, starbases stop producing and your ships move and fire at %d%% speed." % [
		Defs.UPKEEP_WEIGHT["starbase"], Defs.UPKEEP_WEIGHT["carrier"], Defs.UPKEEP_WEIGHT["cruiser"], Defs.UPKEEP_WEIGHT["destroyer"], Defs.UPKEEP_WEIGHT_SMALL, int(Defs.ENERGY_STARVED_FACTOR * 100.0)])
	_heading("Building upkeep and Blackout")
	var urows: Array = []
	for b in Defs.BUILDING_ORDER:
		urows.append([Defs.BUILDINGS[b]["name"], "%d/min" % int(Defs.BUILDINGS[b].get("energy_upkeep", 0))])
	_table(["Building", "Energy upkeep"], urows)
	_para("Every finished building also draws a flat amount of energy per minute. The empire upkeep multiplier does NOT apply to it. Buildings under construction, paused Mining Complexes and dry Spice Extractors draw nothing; Habitats and Power Plants draw nothing (Plants burn minerals instead). Ship and construct upkeep is paid first, then building upkeep, from the same energy stock, with spice covering shortfalls (%d per spice)." % int(Defs.SPICE_COVER_RATIO))
	_para("If energy and spice both run out and building upkeep can't be paid, your empire goes into BLACKOUT: every building that draws energy drops to LOW POWER at once and runs at %d%% - the same fraction as ships out of energy. Farms, Mining Complexes and Spice Extractors produce %d%% of their output; Defense Batteries add %d%% of their shield and fire at %d%% of their rate (full damage per shot). Habitats and Power Plants draw no energy and are not affected. Low-power buildings draw no upkeep while it lasts (the stockpile is at 0 anyway), so a Blackout cannot spiral. Ships are slowed to %d%% and ship production halts, as when out of energy; the world panel marks low-power buildings '25%%'. Power returns once the energy stockpile has stayed above 0 for %d seconds in a row; dropping back to 0 restarts the count (the panels show 'Restoring power: N s')." % [int(Defs.ENERGY_STARVED_FACTOR * 100.0), int(Defs.ENERGY_STARVED_FACTOR * 100.0), int(Defs.ENERGY_STARVED_FACTOR * 100.0), int(Defs.ENERGY_STARVED_FACTOR * 100.0), int(Defs.ENERGY_STARVED_FACTOR * 100.0), int(Defs.BLACKOUT_RESUME_SECS)])
	_heading("Spice cover")
	_para("While spice cover is ON (the default), spice automatically pays any food, mineral or energy shortfall: 1 spice covers %d of the missing resource - never Power Plant fuel. Whenever it does, the spice counter on the resource bar flashes orange with '▼N' (N = spice per minute spent covering; the tooltip lists what for), and an alert sounds once per shortfall. The small ON/OFF button beside the counter switches it: with cover OFF your spice is kept, but shortfalls go unpaid - pops go hungry and starve, unpaid energy upkeep brings a Blackout, and construction stalls for want of minerals. The setting is kept in save games." % int(Defs.SPICE_COVER_RATIO))
	_heading("Net per minute")
	_para("The resource bar shows each stockpile followed by its NET change per minute (green rising, red falling): everything that came in minus everything paid out - upkeep, building upkeep, Power Plant fuel, food eaten, research, construction and ships - measured over the last minute. A world's panel shows that world's own net per resource: its buildings' output minus the food it eats, its Power Plant fuel and its building upkeep (construction not included); hover it for the breakdown.")
	_para("Recovery: harvesters need no energy, so deliver minerals - Power Plants restart as soon as there are minerals to burn, energy builds up, and the lights come back on. Pausing mining or demolishing buildings cuts the drain.")

## The population output multiplier at this many pops (see Planet.pop_output_mult).
func _popm(p: float) -> float:
	return 1.0 + Defs.OUTPUT_POP_BONUS * (1.0 - exp(-p / Defs.OUTPUT_POP_SCALE))

func _page_worlds() -> void:
	_heading("Planets")
	_para("A planet's size is its number of fields, one building each. Its population cap is size x %d. Colonies start at %d pops. Pops eat %s food per minute; an unfed world shrinks instead of growing. Barren worlds hide the most spice, lush ones almost none." % [Defs.POP_PER_SIZE, int(Defs.START_POP), str(Defs.FOOD_PER_POP_PER_MIN)])
	var prows: Array = []
	for p in Defs.PLANET_TYPES:
		var pd: Dictionary = Defs.PLANET_TYPES[p]
		prows.append([pd["label"], "yes" if pd.get("habitable", true) else "no (gas giant)",
			", ".join(Defs.planet_traits(p)) if not Defs.planet_traits(p).is_empty() else "-", (("%d per size" % int(pd["spice_reserve"])) if pd.has("spice_reserve") else ("%s minerals" % Defs.short_num(Defs.GAS_RESERVE) if not pd.get("habitable", true) else "0"))])
	_table(["Type", "Habitable", "Effects", "Spice / gas reserve"], prows)
	_heading("Mineral crust")
	_para("Every world holds %s minerals per size in its crust (a size-30 world: %s), and its Mining Complexes dig it out. Below %s the world turns unstable and glows (no alert: watch for it). At 0 a %d-second countdown starts that nothing can stop - the glow turns red and pulses faster, and its panel shows the seconds left - then it IMPLODES: the world, its pops and its buildings are gone, it counts as a world lost, and the blast hits everything around it - scaled by size: a size-%d world matches a gas giant (%s damage, %d px), a size-20 world %s damage over %d px, a size-10 world %s over %d px. Pause mining (the button in the world's panel) stops its Mining Complexes: they produce nothing and dig nothing until resumed. Pause power (beside it) does the same for its Power Plants: they make no energy and burn no minerals until resumed." % [
		Defs.short_num(Defs.WORLD_RESERVE_PER_SIZE), Defs.short_num(Defs.WORLD_RESERVE_PER_SIZE * 30.0), Defs.short_num(Defs.UNSTABLE_RESERVE), int(Defs.DOOM_SECONDS), int(Defs.BLAST_REF_SIZE),
		Defs.short_num(Defs.BLAST_DAMAGE), int(Defs.BLAST_RADIUS), Defs.short_num(Defs.BLAST_DAMAGE * 20.0 / Defs.BLAST_REF_SIZE), int(Defs.BLAST_RADIUS * 20.0 / Defs.BLAST_REF_SIZE),
		Defs.short_num(Defs.BLAST_DAMAGE * 10.0 / Defs.BLAST_REF_SIZE), int(Defs.BLAST_RADIUS * 10.0 / Defs.BLAST_REF_SIZE)])
	var wplate: Array = []
	for p2 in Defs.PLANET_TYPES:
		wplate.append([p2 + "_s", Defs.PLANET_TYPES[p2]["label"]])
	_plate(wplate, 64.0, false)
	_heading("Colonizing")
	_para("A Colony Ship settles a free, habitable world and is used up doing it: it orbits for %d s, then the world is yours with %d pops. Colony Pods (Worlds research) start colonies with more." % [int(Planet.COLONIZE_TIME), int(Defs.START_POP)])
	_heading("Population")
	_para("Pops grow while a world is fed, up to its cap (Habitats and Worlds research raise it). They are the reason to grow a world: every pop raises the output of every building on it, so a full world makes several times what a fresh colony does. A world's panel shows its bonus as 'x' on every building here.")
	_heading("Buildings")
	var bplate: Array = []
	for b in Defs.BUILDING_ORDER:
		bplate.append(["bld_" + b, Defs.BUILDINGS[b]["name"]])
	_plate(bplate, 56.0, false)
	var brows: Array = []
	for b in Defs.BUILDINGS:
		var bd: Dictionary = Defs.BUILDINGS[b]
		brows.append([bd["name"], Defs.cost_text(bd["cost"]), "%ds" % int(bd["time"]), "%d/min" % int(bd.get("energy_upkeep", 0)), bd["desc"]])
	_table(["Building", "Cost", "Time", "Energy upkeep", "Effect"], brows)
	_para("A finished building runs as long as it has power; no staffing needed (see Economy > Building upkeep and Blackout). Population sets how MUCH a world produces: its pops multiply the output of every Farm, Power Plant, Mining Complex and Spice Extractor on it, with diminishing returns: the first pops count most, and the bonus levels off (x%.2f at 5,000 pops, x%.2f at 10,000, x%.2f at 20,000, x%.2f at 30,000). That bonus levels off toward x%.2f, but each population cap tech raises the ceiling (Habitat Modules +0.15, Arcologies +0.20, Deep Vaults +0.25), and so does each Habitat on the world (+0.1). A Molten world's Power Plants make a further x%.2f, the one thing that barren rock is good for." % [_popm(5000.0), _popm(10000.0), _popm(20000.0), _popm(30000.0), 1.0 + Defs.OUTPUT_POP_BONUS, Defs.PLANET_TYPES["planet_lava"]["energy_mult"]])
	_heading("Food")
	_para("Food is counted per minute, like every other resource. One Farm feeds exactly %d pops on a fully fertile world, and only a fraction of that on a poor one, since output scales with fertility. Past that, a world needs another Farm or it starves." % int(Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN))
	_table(["", "Rate"], [
		["A pop eats", "%.2f/min" % Defs.FOOD_PER_POP_PER_MIN],
		["A Farm grows", "%d/min" % int(Defs.BUILDINGS["farm"]["output"]["food"])],
		["1,000 pops eat", "%d/min" % int(1000.0 * Defs.FOOD_PER_POP_PER_MIN)],
		["A Farm supports", "%d pops" % int(Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN)],
	])
	_para("Spice covers a food shortfall (1 spice feeds as much as %d food), and pops living on it keep growing. If neither food nor spice can feed a world, it starves: growth runs backwards at the rate it would have grown. The shortage lifts only after the world has been fed for %d seconds straight." % [int(Defs.SPICE_COVER_RATIO), int(Defs.REGROW_SECONDS)])
	_heading("Defense Battery")
	_para("A world with a Defense Battery is no free kill. Each battery adds %d to its planetary shield and fires on besieging ships (%d damage, %d px). Two batteries force a raiding party to commit." % [int(Defs.BATTERY_SHIELD), int(Defs.BATTERY["damage"]), int(Defs.BATTERY["range"])])
	_heading("Siege")
	_para("Enemy worlds are taken by bombardment, not invasion. Warships ordered onto a world fire at it: its planetary shield soaks the damage first and recharges after %d s without hits; then every point of damage kills pops (one base corvette shot kills about three pops). While shots are reaching the pops, growth stops (until %d s after the last such hit); fire the shield absorbs doesn't stop it. At 0 pops every building is destroyed and the world turns neutral, ready for anyone to colonize." % [int(Defs.SHIELD_REGEN_DELAY), int(Planet.SIEGE_TIME)])
	_para("Food, growth, population cap, colony and energy techs: see Research > Worlds.")

func _page_constructs() -> void:
	_heading("Constructs")
	_para("Constructs are the stations you build rather than fly. A Constructor (%s, %d s at a starbase) flies to the site and is used up building it. The cost is paid gradually while it builds; a construct starts at %d%% hull and fills in as it goes (Rapid Assembly: %d%%). Sites need room: clear of planets, the star, other constructs, debris and the map edge." % [Defs.cost_text(Defs.SHIPS["constructor"]["cost"]), int(Defs.SHIPS["constructor"]["build_time"]), 10, 50])
	_plate([["starbase", "Starbase"], ["ship_depot_plasma", "Weapons Depot"], ["ship_mining_station", "Mining Station"], ["ship_frontier_outpost", "Frontier Outpost"], ["ship_warp_gate", "Warp Gate"], ["ship_constructor", "Constructor"]], 76.0, true)
	var crows: Array = []
	for c in [Defs.STARBASE, Defs.WEAPONS_DEPOT, Defs.MINING_STATION, Defs.FRONTIER_OUTPOST, Defs.WARP_GATE]:
		var gun: String = ("%d dmg / %.1fs, range %d" % [int(c["damage"]), float(c["cooldown"]), int(c["range"])]) if c.has("weapon") else "-"
		crows.append([c["name"], Defs.cost_text(c["cost"]), "%ds" % int(c["build_time"]), "%d / %d / %d" % [int(c["shield"]), int(c["armor"]), int(c["hp"])], gun, "%.1f/min" % float(c["upkeep"])])
	_table(["Construct", "Cost", "Build", "Shield / armor / hull", "Gun", "Upkeep"], crows)
	_heading("Starbase")
	_para("Your production station: it builds every ship, takes in harvesters' cargo, and defends itself. It generates nothing itself - no energy, no minerals: those come from your worlds and harvesters. Lose every starbase and Constructor and you lose the match. Starbases cost the most upkeep of anything (x%.2f to the empire multiplier each). Keep them clear of nearly drained gas giants: their explosion wrecks anything close." % Defs.UPKEEP_WEIGHT["starbase"])
	_heading("Mining Station")
	_para("A forward drop-off: harvesters unload here instead of flying home, so a station beside a far belt or nebula shortens every trip. It has a light gun for raiders.")
	_heading("Frontier Outpost")
	_para("Half a starbase: half its shields, armor, hull and gun, on a cheaper site (Outposts research). It builds nothing and takes no cargo; it only holds the space around it, and enemy ships attack it on sight like a starbase. Construct weapon research (damage, starbase range) applies to its laser. Upkeep weight x%.2f, as a cruiser." % Defs.UPKEEP_WEIGHT["cruiser"])
	_heading("Warp Gate")
	var wg: Dictionary = Defs.WARP_GATE
	_para("No gun (Warp Gates research). Right-click your gate with ships selected to garrison them inside, any number; they still cost upkeep, and if the gate is destroyed every ship inside is lost with it. Its panel ejects one ship or all of them. Warp (Q) flings the whole garrison at a point %s-%s px away, fog or not: they fly there in a straight line at %dx speed, holding fire and ignoring orders until they arrive, and can be shot on the way. The gate then recharges for %d s. Upkeep weight x%.2f, as a starbase." % [
		str(int(wg["warp_min"])), str(int(wg["warp_max"])), int(wg["warp_speed_mult"]), int(wg["warp_cooldown"]), Defs.UPKEEP_WEIGHT["starbase"]])
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
	_para("Construct guns, toughness, build speed and the Depot / Outpost / Warp Gate unlocks: see Research > Constructs.")

func _page_systems() -> void:
	_heading("Systems")
	_para("A match is fought in one star system, chosen in the lobby. Every system is symmetric: each player starts with the same worlds, rocks and distances, arranged evenly around the star. Every system but the Silent Void has spice nebulae: finite spice for Gas Skimmers, at the price of constant low Radiation inside. Systems differ in star, signature feature and gas placement, and these decide how the match is fought.")
	_heading("Belts")
	_para("Every player starts with three belts of their own:")
	_table(["Belt", "Where", "Holds"], [
		[["Safe", TEXT], "Beside your home world, a short haul from the starbase", "Minerals only"],
		[["Forward", TEXT], "Past your starbase, toward the star - where enemies come through", "Mostly minerals, a little spice"],
		[["Back", TEXT], "Behind your home world, by the map edge", "A few spice rocks"],
	])
	_para("Neutral belts lie anywhere from just outside the star's Radiation to near the map edge. Each is either a large mineral belt (a long arc) or a small spice belt (a tight cluster). Spice is about one rock in seven (one in three in the Kharon Expanse), but a spice rock holds as much as a mineral rock of its size. Richer belts have more big rocks.")
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
			"spice_nebula": "Spice nebula: a full ring of gas around the star, seeded with extra spice rocks - on top of a third of all rocks being spice.",
			"rings": "Debris ring: an impassable wall of rubble with a few narrow gaps (how many varies by seed), which makes those gaps chokepoints. Two large, fertile worlds per player lie inside it.",
			"storms": "Ion storms: ragged clouds of charged gas drift around the system, crackling with lightning. Ships inside move at 40% speed and see half as far.",
		}.get(feature, feature), EDGE_LIT))
	var ntext: String = {
		"flanks": "Spice nebulae: one cloud on each flank, equally far from both bases - the contested middle.",
		"bands": "Spice nebulae: two arcs of gas across the lane between the bases, just outside the suns' orbit.",
		"pockets": "Spice nebulae: a few small clouds scattered outside the debris ring, near the outer worlds.",
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
	"kharon_expanse": "Few worlds, but the most spice anywhere: about a third of its rocks are spice, plus a wide spice ring around the star. The gas carries low Radiation: shields stay down while you are inside, so expect drawn-out fights there.",
	"tethys_cluster": "The richest worlds - large and mostly fertile - sit behind the debris ring, reachable only through its gaps. Hold a gap and you hold the inner system; the outer pockets are easy, safe spice.",
	"silent_void": "Nothing in the way and nothing to hide in: no nebulae, storms or rings, only the star's own zone. With no nebulae, spice comes only from rocks and Spice Extractors. Fleets meet in the open.",
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
	_para("Spice Navigation (Logistics research) makes your ships take %d%% less radiation damage inside a spice nebula (not from a star), and anything inside a Radiation Sail Array's charged bubble takes none." % int(round((1.0 - Abilities.SPICE_NAV_RADIATION) * 100.0)))


func _page_terms() -> void:
	_heading("Terminology")
	var terms := [
		["System", "The map: one star (or two), its planets, belts and features. Called a system, not a map."],
		["Starbase", "Your production station. It builds ships, takes in cargo and defends itself. Losing every one with no Constructor left to build another loses the match (so does losing every world)."],
		["Weapons Depot", "Constructor-built station where a generalist warship is refitted into a specialist variant, permanently."],
		["Class", "The hull a warship was built as, and keeps for life: Corvette, Destroyer, Cruiser or Carrier. You read it off the silhouette."],
		["Mark", "How refined a class is, Mk I to Mk IV, bought on the Warships research tab. It applies to every ship of that class at once."],
		["Generalist", "Any warship as built, before a refit: full damage to every defense layer."],
		["Specialist / variant", "A refitted warship: Plasma, Breacher, Ravager, Slip or Disruptor. One refit only, and it is permanent."],
		["Layers", "Shields, armor and hull, in the order damage takes them."],
		["Radiation", "Environmental damage inside a star's radiation zone (worst near the star) or a spice nebula (low, constant). Hits shields, armor and hull in turn and stops shield regeneration."],
		["Pierce", "Skipping a layer entirely: Slip skips shields, Disruptor skips shields and armor."],
		["Job", "What a ship is for beyond shooting: Deep Sensors, Radiation Sail, Field Repair."],
		["Mod", "A research option that changes one ship class's weapon (Mods tab). One per class; another replaces it; click an active one to switch it off."],
		["Blast", "The area an exploding shot hits: every enemy inside takes its full damage, the target included."],
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
			# A heading (or paragraph) containing this text: scroll it to the top.
			for l in find_children("*", "Label", true, false):
				if ("text" in l) and (OS.get_environment("SL_CODEX_SCROLL") in str(l.text)):
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
		["Pause and resume", ["P, or the Pause button", EDGE_LIT]],
		["Game speed", ["-  /  =  (Backspace resets)", EDGE_LIT]],
		["Self-destruct one selected unit / all selected (starbases ask first)", ["Delete  /  Shift + Delete", EDGE_LIT]],
		["Clear the selection; with nothing selected, the menu", ["Esc", EDGE_LIT]],
	])

## What each ship is for, beyond its stats. Warship variants and the depot
## are covered in Combat, so they aren't repeated here.
const SHIP_NOTES := {
	"miner": "Hauls ore. Right-click an asteroid to mine it and it shuttles loads back to a starbase on its own; orange-flecked rocks carry spice. Asteroids run dry, so miners keep moving outward as a belt empties.",
	"skimmer": "Mines minerals from gas giants (3,000 each, no refill: they shrink, glow when nearly empty and explode when drained) and harvests spice gas inside a spice nebula: right-click a spot in the cloud and it drains the gas there cell by cell, moving on to the nearest gas left until the nebula is gone.",
	"colony": "Settles a free world, and is used up doing it. Colonizing takes a minute in orbit and the new colony starts small, so send it early and guard it: an unescorted colony ship is the cheapest kill on the map.",
	"constructor": "Builds stations and is used up doing it: a starbase to claim ground and produce ships, a Mining Station as a forward drop-off, or a Weapons Depot to refit warships. Starbase upkeep climbs steeply with each one, so the second and third are real economic decisions.",
	"scout": "Cheap, fast and unarmed: its only purpose is sight. It sees far, into spice nebulae and through ion storms, and its beacons keep watching a spot after it has moved on.",
	"tender": "Keeps a fleet alive between battles. Armor never comes back any other way, so a tender is what turns a worn-down fleet into a fresh one without going home.",
	"heatshield": "A support ship that lives where others can't: inside a star's radiation and spice nebulae. Its solar sail harvests 15 energy a minute there, charging a light-purple solar shield (100; each energy recharges 10% of it; full when built, charging even under fire) before any goes to your energy pool. The shield is a bubble nearly two carriers wide: one shared damage pillow that soaks enemy fire on every friendly ship, construct and world inside it, and while it is up nothing inside takes Radiation - friend or foe. Touching bubbles of your arrays merge into one mega shield that pools their points (three full arrays: 300); every hit is shared among the arrays in proportion to their charge, so the pool bursts for all of them at once when it hits 0. If they drift apart, each keeps its own share and becomes a separate bubble again. Shield techs on the Defense tab (Phase Shields, Crystal Prisms, Aegis Matrix) raise a solar shield's maximum like any other shield - all three: +90%, 190 points - and since each energy recharges 10% of the maximum, a bigger shield refills just as fast. Variant rules apply to solar shields as to any shield: Plasma hits them at x3.0, Slip and Disruptor shots pass straight through the bubble, and Overcharged Coils lets 25% of each hit through. The array itself is always immune to Radiation. A support ship with no weapon: it can't be refitted.",
	"corvette": "The cheap body of a fleet. Fast and short-ranged, it is bought in numbers.",
	"destroyer": "An armored boat with two light turrets that track a target without turning the hull, and the longest reach of the small hulls.",
	"cruiser": "Heavy shields and three laser turrets that outrange everything smaller. Slow to turn, so it is punished by anything that can stay off its nose, and it wants an escort of its own.",
	"carrier": "The heaviest hull, armored and shielded far more than its hull, with four turrets that traverse on their own, so the hull never has to come about to fire. Turrets fire on the move at reduced accuracy (Gyro-Stabilizers remove that). Its Mods trade the turrets for drones, add tractor beams, or fire long-range missile salvos.",
}

## Combat page: the class-vs-class and every-weapon matchup tables, from
## data/matchups.json (the latest merged balance round robin).
func _section_matchups() -> void:
	# Measured numbers come from data/matchups.json (tools/matchups_to_json.py
	# writes it from the latest merged balance round robin).
	var mu: Dictionary = {}
	var mf := FileAccess.open("res://data/matchups.json", FileAccess.READ)
	if mf != null:
		var parsed = JSON.parse_string(mf.get_as_text())
		if parsed is Dictionary:
			mu = parsed
	if mu.is_empty():
		_para("(No matchup data yet.)")
		return
	_heading("Matchups")
	_para("How each class fares against each other class at equal cost, from the latest balance round robin (%s): every class's plain lasers and all twelve Mods fought one another, %d times per pairing. Each figure is the row class's win rate against the column class, across all its sides (lasers and Mods). The aim is a gentle size ladder: corvettes 47%%, destroyers 49%%, cruisers 51%%, carriers 53%% overall." % [str(mu.get("label", "")), int(mu.get("per_pair", 0))])
	var mk := ["Corvette", "Destroyer", "Cruiser", "Carrier"]
	var mt: Array = mu["classes"]
	var mt_rows: Array = []
	for i in 4:
		var r: Array = [mk[i]]
		for j in 4:
			var v: int = int(mt[i][j])
			r.append(["%d%%" % v, Color("8fe060") if v >= 60 else (Color("ff6a4a") if v <= 40 else TEXT)])
		mt_rows.append(r)
	_table(["vs", "Corvettes", "Destroyers", "Cruisers", "Carriers"], mt_rows, true)
	_para("So every class has a prey and a predator: destroyers crush corvettes, corvettes swarm cruisers, cruisers outlast destroyers and carriers, and carriers grind down destroyers.")
	_heading("Every weapon against every weapon")
	_para("Each row is one side (a class's plain lasers, or one of its Mods); each figure is how hard it beats the column side at equal cost, averaged over %d duels: +1.00 means it destroys the other without taking any damage, -1.00 that it is destroyed without dealing any, 0 an even trade (a win scores the toughness the winner kept; a draw, the difference in toughness left). The codes are listed below the table." % int(mu.get("per_pair", 0)))
	var wcode := ["CL", "Kin", "Arc", "Trp", "DL", "Flk", "Clu", "Hom", "RL", "Ion", "Rail", "PD", "VL", "Drn", "Trc", "Brg"]
	var wname := ["Corvette lasers", "Kinetic Repeaters", "Arc Emitters", "Proton Torpedoes", "Destroyer lasers", "Flak Cannons", "Cluster Bombs", "Homing Missiles",
		"Cruiser lasers", "Ion Lance", "Rail Cannons", "Point-Defense Lattice", "Carrier lasers", "Interceptor Drones", "Tractor Beams", "Missile Barrage"]
	var wm: Array = mu.get("weights", [])
	var wrows2: Array = []
	for i in 16:
		var r: Array = [[wcode[i], TEXT]]
		for j in 16:
			var g = wm[i][j]
			if g == null:
				r.append(["-", DIM])
			else:
				var f := float(g)
				r.append(["%+.2f" % f, Color("8fe060") if f >= 0.2 else (Color("ff6a4a") if f <= -0.2 else TEXT)])
		wrows2.append(r)
	_para("Read it across: pick a weapon on the left, then follow its row (the shaded bands help); the codes are listed below. Green means that weapon beats the one at the top of the column, red means it loses to it. (Reading down a column shows the same fights from the other side.)")
	_table(["vs"] + wcode, wrows2, true)
	var legend := PackedStringArray()
	for i in 16:
		legend.append("%s = %s" % [wcode[i], wname[i]])
	_para(", ".join(legend) + ".")
