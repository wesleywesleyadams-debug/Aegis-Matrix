class_name SystemPreview
extends Control
## Lobby thumbnail of a star system: the star and its radiation zone, planets
## (colored by type, sized by size), both home worlds in team colors, and
## asteroids as resource-colored specks, over the system's background color.
## Generated systems are laid out from their seed; Orion Reach is read from
## Main.tscn. `facts` holds a one-line summary for a label under it.

const KIND_COLORS := {"planet_terran": Color("3d8fc8"), "planet_desert": Color("e0a85a"), "planet_ice": Color("9ec3e0"),
	"planet_lava": Color("ff6a2b"), "planet_gas": Color("9a5e7e"), "planet_moon": Color("8a8a98")}
const MAP_SIZE := Vector2(3500, 3500)   # Game.MAP_RECT (a disc's bounding square)

var facts: String = ""
var _layout: Dictionary = {}
var _settings: Dictionary = {}
var _random := false
static var _orion_cache: Dictionary = {}

func _ready() -> void:
	# Storm arms and the like reach past the edge: keep them in the box.
	clip_contents = true

func show_system(id: String) -> void:
	_random = id == "random"
	var sys := SystemGen.find(id)
	_settings = SystemGen.settings(id, int(sys.get("seed", 0)))
	if _random:
		_layout = {}
		facts = "A different system every match."
	else:
		# Laid out for the players filled in the lobby (SL_LAYOUT_PLAYERS=n
		# overrides, for dev shots).
		var n_pl := GameState.player_slots.filter(func(s): return not s["slot_type"] in ["open", "closed"]).size()
		if OS.get_environment("SL_LAYOUT_PLAYERS") != "":
			n_pl = int(OS.get_environment("SL_LAYOUT_PLAYERS"))
		n_pl = clampi(n_pl, 2, 8)
		_layout = _orion_layout() if id == "orion_reach" and n_pl == 2 else SystemGen.generate(int(sys.get("seed", 0)), _settings, n_pl)
		var worlds := 0
		for p in _layout["planets"]:
			if p["owner"] == 0:
				worlds += 1
		var spice := 0
		for a in _layout["asteroids"]:
			if str(a["variant"]).begins_with("spice"):
				spice += 1
		facts = "%s\n%d worlds · %d rocks (%d spice)" % [Defs.STAR_TYPES[_settings.get("star", "yellow")]["label"], worlds, _layout["asteroids"].size(), spice]
		if _settings.get("feature", "") == "binary":
			facts = facts.replace(Defs.STAR_TYPES[_settings.get("star", "yellow")]["label"], "Binary " + Defs.STAR_TYPES[_settings.get("star", "yellow")]["label"] + "s")
			facts += "\nTwin suns orbit the center; the lane between them moves."
		if _settings.get("feature", "") == "rings":
			facts += "\nDebris ring: four narrow gaps funnel every fleet."
		if _settings.get("feature", "") == "spice_nebula":
			facts += "\nSpice Nebula: rich spice, but constant low Radiation inside."
		if _settings.get("feature", "") == "storms":
			facts += "\nIon storms: sweeping arms slow ships to 40%."
		facts += {"flanks": "\nSpice clouds on both flanks, equally far from each base.",
			"bands": "\nSpice bands arc across the lane between the bases.",
			"pockets": "\nSmall spice pockets scattered outside the ring.",
			"drifts": "\nA great spice drift on each base's flank."}.get(_settings.get("nebula", ""), "")
	queue_redraw()

## Orion Reach is hand-placed in Main.tscn: read its planets, rocks and
## starbases straight from the scene (without running it).
static func _orion_layout() -> Dictionary:
	if not _orion_cache.is_empty():
		return _orion_cache
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	var out := {"planets": [], "asteroids": [], "starbases": [], "ships": []}
	for p in main.get_node("World/Planets").get_children():
		out["planets"].append({"name": p.planet_name, "kind": p.kind, "size": p.size_variant, "pos": p.position, "owner": p.owner_id})
	for a in main.get_node("World/Asteroids").get_children():
		out["asteroids"].append({"name": a.name, "variant": a.variant, "pos": a.position})
	for s in main.get_node("World/Starbases").get_children():
		out["starbases"].append({"owner": s.owner_id, "pos": s.position})
	main.free()
	# Its nebulae are laid out at match start against the player 1 base.
	var p1: Array = out["starbases"].filter(func(b): return b["owner"] == 1)
	out["features"] = SystemGen.nebulae("flanks", p1[0]["pos"], 0) if not p1.is_empty() else []
	_orion_cache = out
	return out

func _draw() -> void:
	var bg: Dictionary = SystemGen.BACKGROUNDS.get(_settings.get("bg", "violet"), SystemGen.BACKGROUNDS["violet"])
	var base: Color = bg["base"]
	# The system is a disc (Game.MAP_RADIUS): just the disc, no box round it.
	var sc := minf(size.x / MAP_SIZE.x, size.y / MAP_SIZE.y)
	var center := size / 2.0
	draw_circle(center, Game.MAP_RADIUS * sc, base.lightened(0.04))
	draw_arc(center, Game.MAP_RADIUS * sc, 0, TAU, 96, Color(0.55, 0.65, 0.95, 0.55), 1.0)
	if _random:
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, center.y + 10), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, Color(0.7, 0.75, 0.9, 0.8))
		return
	for ft in _layout.get("features", []):
		if ft["type"] == "storms":
			for arm in 2:
				var mid: float = ft["phase"] + PI * arm
				# Out to the edge of the round system, not past it.
				var reach: float = Game.MAP_RADIUS * sc
				var wedge := PackedVector2Array([center + Vector2.from_angle(mid - IonStorm.HALF_WIDTH) * ft["inner"] * sc])
				for s in 9:
					wedge.append(center + Vector2.from_angle(mid - IonStorm.HALF_WIDTH + IonStorm.HALF_WIDTH * 2.0 * s / 8.0) * reach)
				wedge.append(center + Vector2.from_angle(mid + IonStorm.HALF_WIDTH) * ft["inner"] * sc)
				draw_colored_polygon(wedge, Color(0.5, 0.75, 1.0, 0.14))
	for ft in _layout.get("features", []):
		if ft["type"] == "rings":
			for i in 96:
				var a0 := TAU * i / 96.0
				var mid := a0 + TAU / 192.0
				var open := false
				for gp in ft["gaps"]:
					if absf(angle_difference(mid, gp)) < ft["gap_half"]:
						open = true
				if not open:
					draw_arc(center, ft["radius"] * sc, a0, a0 + TAU / 96.0, 3, Color("6e5c4a"), maxf(2.0, ft["width"] * sc))
	for ft in _layout.get("features", []):
		if ft["type"] == "spice_nebula":
			SpiceNebula.draw_feature_on_map(self, func(p): return center + p * sc, sc, ft)
	var st: Dictionary = Defs.STAR_TYPES[_settings.get("star", "yellow")]
	# The star (or both binary stars, with their orbit): radiation zone as a
	# dashed ring, then the star itself.
	var suns: Array = [Vector2.ZERO]
	for ft in _layout.get("features", []):
		if ft["type"] == "binary":
			suns = [Vector2(-ft["orbit"], 0), Vector2(ft["orbit"], 0)]
			draw_arc(center, ft["orbit"] * sc, 0.0, TAU, 48, Color(st["tint"], 0.35), 1.0)
	var zr: float = st["zone"] * sc
	for sp in suns:
		var c: Vector2 = center + sp * sc
		for i in 32:
			var a0 := TAU * i / 32.0
			draw_arc(c, zr, a0, a0 + TAU / 64.0, 4, Color(1, 0.35, 0.3, 0.55), 1.0)
		draw_circle(c, maxf(3.0, st["core"] * sc * 2.2), st["tint"])
	for a in _layout["asteroids"]:
		var res := "spice" if str(a["variant"]).begins_with("spice") else "minerals"
		draw_rect(Rect2(center + a["pos"] * sc - Vector2(1, 1), Vector2(2, 2)), Defs.RESOURCE_COLORS[res])
	for p in _layout["planets"]:
		var w := float(Defs.tex(p["kind"] + p.get("size", "")).get_width())
		var r := maxf(2.5, w * 0.5 * sc * 2.2)
		var pos: Vector2 = center + p["pos"] * sc
		draw_circle(pos, r, KIND_COLORS.get(p["kind"], Color.GRAY))
		if p["owner"] != 0:
			draw_arc(pos, r + 2.5, 0.0, TAU, 20, Defs.team_color(p["owner"]), 1.5)
	for s in _layout["starbases"]:
		var q: Vector2 = center + s["pos"] * sc
		draw_rect(Rect2(q - Vector2(2.5, 2.5), Vector2(5, 5)), Defs.team_color(s["owner"]))
