class_name SystemPreview
extends Control
## Lobby thumbnail of a star system: the star and its radiation zone, planets
## (colored by type, sized by size), both home worlds in team colors, and
## asteroids as resource-colored specks, over the system's background color.
## Generated systems are laid out from their seed; Orion Reach is read from
## Main.tscn. `facts` holds a one-line summary for a label under it.

const KIND_COLORS := {"planet_terran": Color("3d8fc8"), "planet_desert": Color("e0a85a"), "planet_ice": Color("9ec3e0"),
	"planet_lava": Color("ff6a2b"), "planet_gas": Color("9a5e7e"), "planet_moon": Color("8a8a98")}
const MAP_SIZE := Vector2(3600, 2300)

var facts: String = ""
var _layout: Dictionary = {}
var _settings: Dictionary = {}
var _random := false
static var _orion_cache: Dictionary = {}

func show_system(id: String) -> void:
	_random = id == "random"
	var sys := SystemGen.find(id)
	_settings = SystemGen.settings(id, int(sys.get("seed", 0)))
	if _random:
		_layout = {}
		facts = "A different system every match."
	else:
		_layout = _orion_layout() if id == "orion_reach" else SystemGen.generate(int(sys["seed"]), _settings)
		var worlds := 0
		for p in _layout["planets"]:
			if p["owner"] == 0:
				worlds += 1
		var spice := 0
		for a in _layout["asteroids"]:
			if str(a["variant"]).begins_with("spice"):
				spice += 1
		facts = "%s · %d worlds · %d rocks (%d spice)" % [Defs.STAR_TYPES[_settings.get("star", "yellow")]["label"], worlds, _layout["asteroids"].size(), spice]
		if _settings.get("feature", "") == "spice_nebula":
			facts += "
Spice Nebula: rich spice, but shields drain inside."
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
	_orion_cache = out
	return out

func _draw() -> void:
	var bg: Dictionary = SystemGen.BACKGROUNDS.get(_settings.get("bg", "violet"), SystemGen.BACKGROUNDS["violet"])
	var base: Color = bg["base"]
	draw_rect(Rect2(Vector2.ZERO, size), base.lightened(0.04))
	draw_rect(Rect2(Vector2.ZERO, size), Color("2e3a66"), false, 1.0)
	var sc := minf(size.x / MAP_SIZE.x, size.y / MAP_SIZE.y)
	var center := size / 2.0
	if _random:
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, center.y + 10), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, Color(0.7, 0.75, 0.9, 0.8))
		return
	for ft in _layout.get("features", []):
		if ft["type"] == "spice_nebula":
			draw_arc(center, (ft["inner"] + ft["outer"]) / 2.0 * sc, 0.0, TAU, 64, Color(1.0, 0.6, 0.2, 0.16), (ft["outer"] - ft["inner"]) * sc)
	var st: Dictionary = Defs.STAR_TYPES[_settings.get("star", "yellow")]
	# Radiation zone as a dashed ring, then the star.
	var zr: float = st["zone"] * sc
	for i in 32:
		var a0 := TAU * i / 32.0
		draw_arc(center, zr, a0, a0 + TAU / 64.0, 4, Color(1, 0.35, 0.3, 0.55), 1.0)
	draw_circle(center, maxf(3.0, st["core"] * sc * 2.2), st["tint"])
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
