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

## Lays the page out in two columns. A block is a heading and everything
## under it, so a section is never split down the middle. Blocks that are
## too wide for half the panel (wide tables, ship cards) keep the full
## width to themselves instead of being clipped; the rest are paired up.
func _flow() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var half := _half_width()
	var blocks: Array = []
	for child in _body.get_children():
		if blocks.is_empty() or child.has_meta("block"):
			blocks.append([child])
		else:
			blocks[-1].append(child)
	var pending: Array = []      # narrow blocks waiting for a partner
	for b in blocks:
		if _block_width(b) > half:
			_flush(pending, half)
			pending = []
			var full := _text_column(0.0)
			_move(b, full)
			_rows.add_child(full)
		else:
			pending.append(b)
			if pending.size() == 2:
				_flush(pending, half)
				pending = []
	_flush(pending, half)

## Puts one or two narrow blocks side by side in a row.
func _flush(pending: Array, half: float) -> void:
	if pending.is_empty():
		return
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(COL_GAP))
	for b in pending:
		var col := _text_column(half)
		_move(b, col)
		row.add_child(col)
	if pending.size() == 1:
		row.add_child(_text_column(half))   # keep the left column at half width
	_rows.add_child(row)

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
func _text_width() -> float:
	return minf(_half_width() - 16.0, 720.0)

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
## shape, a trim or a world looks like instead of only describing it.
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
		"economy": _page_economy()
		"systems": _page_systems()
		"terms": _page_terms()
	_flow()

func _page_overview() -> void:
	_heading("Star Lords")
	_para("A match is won by destroying every enemy starbase. Starbases build ships and receive the cargo your miners haul in; lose your last one and the match is over.")
	_plate([["starbase", "Starbase", EDGE_LIT], ["planet_terran_s", "Worlds"], ["ship_miner", "Harvesters"],
		["ship_corvette", "Warships"], ["asteroid_0", "Belts"]], 68.0, true,
		"Lose your last starbase and the match is over, so everything else exists to protect one or take one.")
	_heading("The loop", EDGE_LIT)
	_para("Mine the belts and gas giants, settle free worlds, build farms and power plants so your population and fleet can grow, research what your strategy needs, and take the fight to the enemy before their economy outgrows yours.")
	_heading("What you can see", EDGE_LIT)
	_para("Sensors give fog of war. Unexplored space is black; explored space you can't currently see is dimmed and shows only terrain and the last owner you saw on a planet. Enemy ships and shots appear only inside your sensor range, and an enemy starbase stays on your map once you have seen it. Ships in a spice nebula are hidden unless something of yours is close, a Scout is close, or one of its beacons is watching; ion storms halve sensor range. The AI plays under exactly the same rules.")
	_heading("Resources", EDGE_LIT)
	_table(["Resource", "Comes from", "Pays for"], [
		[["Food", Color("8fe060")], "Farms only", "%.2f per pop per minute (spice covers a shortfall); an unfed world shrinks as fast as it would grow" % Defs.FOOD_PER_POP_PER_MIN],
		[["Minerals", Color("3fd6b0")], "Mining barges, gas skimmers, mining complexes, starbase refineries", "Ships, buildings, starbases"],
		[["Energy", Color("ffd84a")], "Power plants, starbase reactors", "Research, fleet and starbase upkeep, shield regeneration"],
		[["Spice", Color("ff9a2e")], "Spice asteroids, spice extractors, nebula harvesting", "Advanced hulls and techs; covers any other shortfall 1:1"],
	])

func _page_combat() -> void:
	_heading("Defense layers")
	_para("Damage drains shields, then armor, then hull. A ship dies when its hull reaches 0.")
	_table(["Layer", "Regenerates", "Notes"], [
		[["Shields", Defs.LAYER_COLORS["shield"]], "Yes, for a little energy", "Drained inside spice nebulae"],
		[["Armor", Defs.LAYER_COLORS["armor"]], "No", "Only a Repair Tender restores it"],
		[["Hull", Defs.LAYER_COLORS["hull"]], "No", "A Repair Tender heals hull first, then armor"],
	])
	_rule()
	_heading("Generalists")
	_para("Each generalist carries the same total toughness split differently, which is what gives specialists something to specialize against.")
	var rows: Array = []
	for t in ["corvette", "destroyer", "cruiser"]:
		var d: Dictionary = Defs.SHIPS[t]
		var lean := "hull"
		if d["shield"] >= d["armor"] and d["shield"] >= d["hp"]:
			lean = "shields"
		elif d["armor"] >= d["shield"] and d["armor"] >= d["hp"]:
			lean = "armor"
		rows.append([d["name"], [str(int(d["shield"])), Defs.LAYER_COLORS["shield"]], [str(int(d.get("armor", 0))), Defs.LAYER_COLORS["armor"]],
			[str(int(d["hp"])), Defs.LAYER_COLORS["hull"]], [lean, Defs.LAYER_COLORS[lean.trim_suffix("s")]]])
	var sb: Dictionary = Defs.STARBASE
	rows.append(["Starbase", [str(int(sb["shield"])), Defs.LAYER_COLORS["shield"]], [str(int(sb.get("armor", 0))), Defs.LAYER_COLORS["armor"]],
		[str(int(sb["hp"])), Defs.LAYER_COLORS["hull"]], "hull"])
	_table(["Ship", "Shield", "Armor", "Hull", "Leans on"], rows)
	_rule()
	_heading("Specialist variants")
	_para("Generalists deal full damage to every layer. A specialist either hits one layer harder for less base damage, or skips layers entirely for much less. Every variant costs the same as its generalist. A variant is cut into the hull as a TRIM style along its edges, in your player color, so the silhouette names the variant and the shot color names the layer it hits.")
	var trim_plate: Array = [["ship_corvette", "Generalist", TEXT]]
	for tv in Defs.VARIANTS:
		trim_plate.append(["ship_%s_corvette" % tv, Defs.VARIANTS[tv]["label"], Defs.VARIANTS[tv]["color"]])
	_plate(trim_plate, 96.0, true, "The same corvette in all six trims: blocky, rounded, ribbed, toothed, swept and serrated.")
	var vrows: Array = [["Generalist", "-", "100%", ["yellow laser", Defs.GENERALIST_SHOT], "blocky, as built"]]
	var marks := {"plasma": "rounded edges", "breacher": "ribbed plates", "reaver": "toothed saw edge",
		"slip": "swept fins", "disruptor": "serrated notches"}
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
		vrows.append([[vd["label"], vd["color"]], effect, "%d%%" % int(vd["damage"] * 100.0), [shots[v], vd["color"]], marks[v]])
	_table(["Variant", "Effect", "Base damage", "Shots", "Trim"], vrows)
	_rule()
	_heading("Which variant against what")
	_para("Base damage needed to destroy a target, compared with a generalist: 1.00 is the same, lower kills faster. Figures come straight from the ships' current stats.")
	var head: Array = ["Target"]
	for v in Defs.VARIANTS:
		head.append(Defs.VARIANTS[v]["label"])
	var mrows: Array = []
	for t in ["corvette", "destroyer", "cruiser"]:
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
	_rule()
	_rule()
	_heading("Hull marks", EDGE_LIT)
	_para("Every warship has two independent axes. Its MARK is raw power and comes from the War Ships research line; its VARIANT is purpose and comes from a Weapons Depot. An A-class Reaver Corvette is both: the toughest corvette mark, fitted to hunt hull.")
	var krows: Array = []
	for i in Defs.HULL_MARKS.size():
		krows.append([Defs.HULL_MARKS[i], "start" if i == 0 else "research", "+%d%% damage, +%d%% shields, armor and hull" % [
			int(i * Defs.MARK_STEP["damage"] * 100.0), int(i * Defs.MARK_STEP["hull"] * 100.0)]])
	_table(["Mark", "From", "Over an H-class"], krows)
	for cls in Defs.MARK_LINES:
		var mplate: Array = []
		for mi in Defs.HULL_MARKS.size():
			mplate.append(["ship_%s%s" % [cls, Defs.mark_suffix(mi)], Defs.HULL_MARKS[mi], TEXT if mi == 0 else EDGE_LIT])
		_plate(mplate, 96.0, true, "%s, mark by mark." % Defs.SHIPS[cls]["name"])
	_para("A mark is the shape of the ship, not a badge on it: an H-class is two nacelles either side of a central body, a Y-class is a tail boom forking into two bow prongs, an X-class crosses four wings at a hub, and an A-class is a braced delta with its apex at the bow. Refitting to a variant keeps the shape and only changes the markings on it.")
	_para("Each class researches its own marks, so a corvette fleet and a cruiser fleet are separate investments. Marks apply to every ship of that class you already own the moment the research lands.")
	_heading("Weapons Depots")
	var wd: Dictionary = Defs.WEAPONS_DEPOT
	_para("Starbases build generalists only. Once the Depots tech is researched, a Constructor builds a depot (E) for %s over %ds, and every depot is built for ONE variant: a Plasma Depot makes Plasma ships, a Slip Depot Slip ships, and so on — the depot wears your color and its variant's marking." % [
		Defs.cost_text(wd["cost"]), int(wd["build_time"])])
	_para("Send generalists in by right-clicking the depot (or with the refit buttons in their panel). They fly in and dock — %d at a time, hidden and safe inside — and are refitted automatically as minerals allow. Each hull has its own cost and time:" % int(wd["capacity"]))
	var rrows: Array = []
	for t in Defs.VARIANTS_OF:
		var r: Dictionary = Defs.SHIPS[t]["refit"]
		rrows.append([Defs.SHIPS[t]["name"], "%d minerals" % int(r["minerals"]), "%ds" % int(r["time"])])
	_table(["Hull", "Refit cost", "Refit time"], rrows)
	_para("A refit with no minerals to pay for it simply waits, and the ship stays inside until you cancel it — cancelling ejects it unchanged, still a generalist. A refitted specialist can never be refitted again. If a depot is destroyed with ships inside, they are thrown clear and lose 60% of their shields, armor and hull in the blast.")
	_rule()
	_heading("Defense research")
	_para("Three lines on the research screen's Defense tab, expensive on purpose: committing to a layer is a strategic choice. Only one project runs at a time, so every tech is time as well as energy.")
	var lines := {"shields": "shield", "armor": "armor", "hull": "hull"}
	for line in lines:
		var lrows: Array = []
		for id in Defs.TECHS:
			var t: Dictionary = Defs.TECHS[id]
			if t.get("line", "") == line:
				lrows.append([[t["name"], Defs.LAYER_COLORS[lines[line]]], "Tier %d" % t["tier"], Defs.cost_text(t["cost"]), "%ds" % int(t["time"]), t["desc"]])
		_table([line.to_upper(), "", "Cost", "Time", "Effect"], lrows)
	_rule()
	_heading("Ship jobs")
	_para("Jobs are what a ship is for beyond its guns. Passive jobs always work; an active one is used with Q or its button in the ship panel.")
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
		row.add_child(_sprite("ship_" + t, 3, true))
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
			d["role"].capitalize(), int(d["shield"]), int(d.get("armor", 0)), int(d["hp"]), int(d["speed"]), int(d.get("sensor", 260))]
		if d["weapon"] != "":
			stats += "  ·  %s %d dmg / %.1fs, range %d" % [d["weapon"], int(d["damage"]), d["cooldown"], int(d["range"])]
		col.add_child(_label(stats, DIM, 16))
		col.add_child(_label("%s over %ds  ·  upkeep %.0f energy/min" % [Defs.cost_text(d["cost"]), int(d["build_time"]), d["upkeep"]], DIM, 16))
		if d.has("job"):
			col.add_child(_card_text("Job — %s: %s" % [Defs.JOBS[d["job"]]["name"], Defs.JOBS[d["job"]]["desc"]], Defs.JOBS[d["job"]]["color"]))
		if SHIP_NOTES.has(t):
			col.add_child(_card_text(SHIP_NOTES[t], DIM))
		card.set_meta("block", true)
		_body.add_child(card)

func _page_economy() -> void:
	_heading("Planets")
	_para("A planet's size is its number of fields, one building each, and its population cap is size x %d. Colonies start at %d pops. Pops eat %s food per minute; an unfed world shrinks instead of growing. Barren worlds hide the most spice, lush ones almost none." % [Defs.POP_PER_SIZE, int(Defs.START_POP), str(Defs.FOOD_PER_POP_PER_MIN)])
	var prows: Array = []
	for p in Defs.PLANET_TYPES:
		var pd: Dictionary = Defs.PLANET_TYPES[p]
		prows.append([pd["label"], "yes" if pd.get("habitable", true) else "no (gas giant)",
			"%.2f" % pd["fertility"], str(pd.get("spice_reserve", pd.get("gas_reserve", 0)))])
	_table(["Type", "Habitable", "Fertility", "Spice / gas reserve"], prows)
	var wplate: Array = []
	for p2 in Defs.PLANET_TYPES:
		wplate.append([p2 + "_s", Defs.PLANET_TYPES[p2]["label"]])
	_plate(wplate, 64.0, false)
	_rule()
	_heading("Harvesting")
	_plate([["ship_miner", "Mining Barge"], ["asteroid_big_0", "Mineral asteroid"], ["spice_0", "Spice asteroid"],
		["ship_skimmer", "Gas Skimmer"], ["planet_gas_s", "Gas giant"], ["starbase", "Starbase"]], 76.0, true,
		"A barge works rock, a skimmer works gas giants and spice nebulae; both haul their loads to a starbase or a Mining Station.")
	_para("A harvester parks on a node and fills its hold at a steady rate, then hauls the load to the nearest starbase and comes back. The gather rate never changes with distance — distance only adds flying time, so a forward starbase is worth building for a far belt.")
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
	_para("Asteroids run dry and vanish (a mineral rock holds about %s per 100 px of width, a spice rock %s), gas giants refill after a pause, and a spice nebula never runs out. The Logistics techs raise hold size, gather rate and speed." % [
		str(int(Defs.ASTEROID_MINERALS_PER_PX2 * 1000.0)), str(int(Defs.ASTEROID_SPICE_PER_PX2 * 1000.0))])
	_rule()
	_heading("Buildings")
	var bplate: Array = []
	for b in Defs.BUILDING_ORDER:
		bplate.append(["bld_" + b, Defs.BUILDINGS[b]["name"]])
	_plate(bplate, 56.0, false)
	var brows: Array = []
	for b in Defs.BUILDINGS:
		var bd: Dictionary = Defs.BUILDINGS[b]
		brows.append([bd["name"], Defs.cost_text(bd["cost"]), "%ds" % int(bd["time"]), str(bd["pop"]) + " pop", bd["desc"]])
	_table(["Building", "Cost", "Time", "Staff", "Effect"], brows)
	_rule()
	_heading("Food")
	_para("Food is on the same scale as every other resource, and like the rest it is counted per minute. One Farm feeds exactly %d pops; past that a world needs another Farm or it starves." % int(Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN))
	_table(["", "Rate"], [
		["A pop eats", "%.2f/min" % Defs.FOOD_PER_POP_PER_MIN],
		["A Farm grows", "%d/min" % int(Defs.BUILDINGS["farm"]["output"]["food"])],
		["1,000 pops eat", "%d/min" % int(1000.0 * Defs.FOOD_PER_POP_PER_MIN)],
		["A Farm supports", "%d pops" % int(Defs.BUILDINGS["farm"]["output"]["food"] / Defs.FOOD_PER_POP_PER_MIN)],
	])
	_para("Spice covers a food shortfall 1:1, and pops living on it keep growing. When neither food nor spice can feed a world it starves: growth runs backwards at the same rate it would have grown, and the shortage only lifts once the world has been fed for %d seconds straight." % int(Defs.REGROW_SECONDS))
	_rule()
	_heading("Defense Battery")
	_para("A world with a Defense Battery is no longer a free kill: each one adds %d to its planetary shield and fires on besieging ships (%d damage, %d px). Two batteries make a colony something a raiding party has to commit to." % [int(Defs.BATTERY_SHIELD), int(Defs.BATTERY["damage"]), int(Defs.BATTERY["range"])])
	_rule()
	_heading("Upkeep")
	_para("Every ship costs energy per minute, and the total is multiplied as the fleet grows (1 + (ships/%d)^2), so fleets plateau instead of growing forever. Starbases have their own steeper curve, which makes more than a handful expensive. With no energy in the stockpile, starbases stop producing and your ships move and fire at %d%% speed." % [int(Defs.UPKEEP_SCALE_SHIPS), int(Defs.ENERGY_STARVED_FACTOR * 100.0)])

func _page_systems() -> void:
	_heading("Systems")
	_para("Every system is point-symmetric, so both players start with the same terrain. Each has its own star, look and signature feature.")
	for s in SystemGen.SYSTEMS:
		if s["id"] == "random":
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _panel_style())
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var star: Dictionary = Defs.STAR_TYPES.get(s.get("star", "yellow"), {})
		col.add_child(_label(s["name"], star.get("tint", TEXT), 20))
		col.add_child(_label("%s  ·  %s" % [s["desc"], star.get("label", "")], DIM, 16))
		col.add_child(_wrap(s.get("arrival", ""), TEXT, 15))
		var feature: String = s.get("feature", "")
		if feature != "":
			var ftext: String = {
				"binary": "Twin suns: two radiation zones circle the center, and the safe lane between them keeps moving.",
				"spice_nebula": "Spice nebula: shields drain inside it and won't recharge, ships hide in it, and Gas Skimmers can harvest spice there.",
				"rings": "Debris ring: an impassable wall of rubble with a few gaps, which makes those gaps chokepoints.",
				"storms": "Ion storms: sweeping arms slow ships to 40% and halve sensors while they pass.",
			}.get(feature, feature)
			col.add_child(_wrap(ftext, EDGE_LIT, 16))
		card.set_meta("block", true)
		_body.add_child(card)
	_rule()
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
	_para("Radiation damages anything inside the zone, worst at the surface. A Heat Shield Frigate protects ships around it, and its Surge blocks radiation completely for a few seconds.")

func _page_terms() -> void:
	_heading("Terminology")
	var terms := [
		["System", "The map: one star (or two), its planets, belts and features. Called a system, not a map."],
		["Starbase", "Your production station. It builds ships, takes in cargo, defends itself, and losing them all loses the match."],
		["Weapons Depot", "Constructor-built station where a generalist warship is refitted into a specialist variant, permanently."],
		["Generalist", "Corvette, Destroyer or Cruiser as built: full damage to every defense layer."],
		["Specialist / variant", "A refitted warship: Plasma, Breacher, Reaver, Slip or Disruptor."],
		["Layers", "Shields, armor and hull, in the order damage takes them."],
		["Pierce", "Skipping a layer entirely: Slip skips shields, Disruptor skips shields and armor."],
		["Job", "What a ship is for beyond shooting: Swarm, Escort, Deep Sensors, Heat Screen, Field Repair."],
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
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://codex.png")
		get_tree().quit()

func _page_controls() -> void:
	_heading("Panel grid")
	_para("The buttons in the bottom-left panel are wired to a grid of keys, in the order they appear, and each button shows its letter in the corner. The letters never move: whatever the selected ship, starbase or depot offers, the first button is Q, the fourth A, the seventh Z.")
	var pk := HUD.panel_keys()
	var krows: Array = []
	for r in 4:
		var ks: Array = []
		for c in 3:
			ks.append(OS.get_keycode_string(pk[r * 3 + c]))
		krows.append([["First row", "Second row", "Third row", "Overflow"][r], ["   ".join(ks), EDGE_LIT]])
	_table(["Row", "Keys"], krows)
	_para("The build picker on one of your worlds uses the same letters.")
	_para("Every key here can be rebound in Options > Hotkeys, with a Reset to defaults button; the letters drawn on the buttons follow your bindings.")
	_rule()
	_heading("Build grid")
	_para("With a starbase selected these letters build ships. With no starbase selected, the same letter selects every ship of that class you own, wherever it is.")
	var rows: Array = []
	for i in Defs.BUILD_ORDER.size():
		if i >= HUD.panel_keys().size():
			break
		var t: String = Defs.BUILD_ORDER[i]
		rows.append([[OS.get_keycode_string(HUD.panel_keys()[i]), EDGE_LIT], Defs.SHIPS[t]["name"], Defs.cost_text(Defs.SHIPS[t]["cost"])])
	_table(["Key", "Builds / selects", "Cost"], rows)
	_rule()
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
		["Go to your starbase, then cycle through the others", ["B", EDGE_LIT]],
		["Next world of yours", ["Space", EDGE_LIT]],
		["Build on the focused world", ["F", EDGE_LIT]],
		["Research", ["R", EDGE_LIT]],
		["Set / select control group", ["Ctrl + 1-9  /  1-9", EDGE_LIT]],
		["Centre on a control group", ["1-9 twice", EDGE_LIT]],
		["Pause and resume", ["Pause key, or the Pause button", EDGE_LIT]],
		["Game speed", ["-  /  =  (Backspace resets)", EDGE_LIT]],
		["Clear the selection; with nothing selected, the menu", ["Esc", EDGE_LIT]],
	])

## What each ship is for, beyond its stats. Warship variants and the depot
## are covered in Combat, so they aren't repeated here.
const SHIP_NOTES := {
	"miner": "Hauls ore. Right-click an asteroid to mine it and it shuttles loads back to a starbase on its own; orange-flecked rocks carry spice. Asteroids run dry, so miners keep moving outward as a belt empties.",
	"skimmer": "Mines minerals from gas giants, which never run out but refill slowly after being drained, and harvests spice gas inside a spice nebula: right-click a spot in the cloud and it works there, slowly and indefinitely.",
	"colony": "Settles a free world, and is used up doing it. Colonizing takes a minute in orbit and the new colony starts small, so send it early and guard it: an unescorted colony ship is the cheapest kill on the map.",
	"constructor": "Builds stations and is used up doing it: a starbase to claim ground and produce ships, or a Weapons Depot to refit warships. Starbase upkeep climbs steeply with each one, so the second and third are real economic decisions.",
	"scout": "Cheap, fast and unarmed: its only purpose is sight. It sees far, into spice nebulae and through ion storms, and its beacons keep watching a spot after it has moved on.",
	"tender": "Keeps a fleet alive between battles. Armor never comes back any other way, so a tender is what turns a worn-down fleet into a fresh one without going home.",
	"heatshield": "Lets a fleet fight where others can't: inside a star's radiation and inside a spice nebula, where shields normally drain away.",
}
