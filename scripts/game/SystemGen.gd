class_name SystemGen
## Seeded, two-player-symmetric star system generator.
##
## generate(seed, params) builds player 1's half of the system and mirrors
## it through the star (p -> -p) for player 2, so both sides get the same
## planets, belts and distances. The same seed + params always give the same
## system (names included), which is what lets saves rebuild it.
##
## Result: {"planets": [{name, kind, size, pos, owner}], "asteroids": [{name,
## variant, pos}], "starbases": [{owner, pos}], "ships": [{type, owner, pos,
## rot}]}. Game builds nodes from it (see Game._build_system).

## Picked systems. "orion_reach" is the hand-made classic in Main.tscn; the
## rest are generated from a fixed seed and their own flavor of params.
const SYSTEMS := [
	{"id": "orion_reach", "name": "Orion Reach", "desc": "The classic hand-built system.", "star": "yellow", "star_name": "Orion",
		"bg": "violet", "nebula": "flanks", "arrival": "You arrive in Orion Reach. Twin deserts flank a quiet yellow sun."},
	{"id": "vega_drift", "name": "Vega Drift", "seed": 1101, "desc": "Balanced worlds around twin suns.", "star": "white", "star_name": "Vega",
		"bg": "teal", "names": "cold", "feature": "binary", "nebula": "bands", "arrival": "You arrive in Vega Drift. Twin white suns wheel around a shifting safe lane.",
		"params": {"planets": 4, "belts": 2, "spice": 0.12}},
	{"id": "kharon_expanse", "name": "Kharon Expanse", "seed": 2207, "desc": "Sparse and spice-rich.", "star": "red_dwarf", "star_name": "Kharon",
		"bg": "rust", "names": "dust", "feature": "spice_nebula", "arrival": "You arrive in the Kharon Expanse. Spice lies thick in the dim red dust.",
		"params": {"planets": 3, "belts": 1, "spice": 0.28}},
	{"id": "tethys_cluster", "name": "Tethys Cluster", "seed": 3313, "desc": "Crowded worlds behind a debris ring.", "star": "orange", "star_name": "Tethys",
		"bg": "verdant", "names": "myth", "feature": "rings", "nebula": "pockets", "arrival": "You arrive in the Tethys Cluster. A wall of rubble rings the inner worlds; find the gaps.",
		"params": {"planets": 5, "belts": 3, "spice": 0.1}},
	{"id": "sable_verge", "name": "Sable Verge", "seed": 4419, "desc": "Heavy belts, swept by ion storms.", "star": "blue_giant", "star_name": "Sable",
		"bg": "ash", "names": "stone", "feature": "storms", "nebula": "drifts", "arrival": "You arrive at the Sable Verge. Ion storms drift around a blue giant; mind where they roam.",
		"params": {"planets": 3, "belts": 3, "spice": 0.05}},
	{"id": "random", "name": "Random", "desc": "A new system every match.", "arrival": "You arrive in uncharted space."},
]

## Background palettes: base color and a tint for the nebula layer.
const BACKGROUNDS := {
	"violet": {"base": Color(0.027, 0.024, 0.059), "nebula": Vector3(1.0, 1.0, 1.0)},
	"teal": {"base": Color(0.018, 0.03, 0.055), "nebula": Vector3(0.55, 0.95, 1.25)},
	"rust": {"base": Color(0.05, 0.022, 0.028), "nebula": Vector3(1.35, 0.7, 0.5)},
	"verdant": {"base": Color(0.022, 0.04, 0.034), "nebula": Vector3(0.8, 1.25, 0.8)},
	"ash": {"base": Color(0.03, 0.03, 0.038), "nebula": Vector3(0.75, 0.8, 0.95)},
}

## Themed planet names per system (each list is long enough for any layout).
const NAME_SETS := {
	"cold": ["Rime", "Hoarfrost", "Selene", "Kaldr", "Isen", "Brumal", "Glace", "Nivel", "Frore", "Hiems", "Borea", "Skadi",
		"Tundris", "Pallor", "Frostmere", "Algor", "Vinter", "Crysta", "Norrin", "Coldharbor", "Sleet", "Ymir", "Halo", "Albedo"],
	"dust": ["Ashkar", "Qarsa", "Zahir", "Sirocco", "Harmat", "Duneholm", "Khamsin", "Oasra", "Tamrit", "Saffra", "Marrakai", "Emberlee",
		"Ghibli", "Rukh", "Sabakh", "Ochre", "Cinnabar", "Scorch", "Kiln", "Mirage", "Haboob", "Dustwane", "Tarim", "Qadir"],
	"myth": ["Nerites", "Phorcys", "Thaum", "Doris", "Eurybia", "Pontus", "Ceto", "Galene", "Metis", "Styx", "Clymene", "Perseis",
		"Oceanus", "Proteus", "Amphis", "Triton", "Nereid", "Thalassa", "Psamathe", "Halimede", "Sao", "Laomedeia", "Neso", "Glauce"],
	"stone": ["Basalt", "Obsidian", "Slate", "Gneiss", "Tuff", "Scoria", "Flint", "Chert", "Jasper", "Marl", "Gabbro", "Pumice",
		"Cairn", "Tor", "Scree", "Shale", "Granitor", "Umbra", "Anvil", "Crag", "Monolith", "Ferrox", "Cobble", "Quarry"],
}

## Layout lives on a circle inside the round system (Game.MAP_RADIUS): t = 1
## is LAYOUT_R from the star. Each player gets an equal wedge of it.
const LAYOUT_R := 1600.0
## How many players the layout being generated is for (set by generate).
static var players: int = 2
## Keep-out around the star: its radiation zone plus room to fly around it
## (set per system from its star type).
static var star_clear: float = 330.0
const EDGE_MARGIN := 90.0
const HOME_T := 0.9
## Binary systems: each star's distance from the center, and one orbit's
## length in game seconds.
const BINARY_ORBIT := 260.0
const BINARY_PERIOD := 480.0
## Ringed systems: the debris ring's radius and thickness, and each gap's
## angular half-width (about 150 px wide at the ring).
const RING_RADIUS := 640.0
const RING_WIDTH := 70.0
const RING_GAP_HALF := 0.12
## Set while generating a ringed system (0 = no ring).
static var ring_radius: float = 0.0

const NAMES := ["Aster", "Belen", "Calyx", "Draxis", "Eryth", "Fenra", "Galen", "Hesper", "Ilion", "Jarro",
	"Kalthe", "Lumen", "Marrow", "Nyx", "Ossary", "Pellan", "Quorra", "Rhaen", "Sorrel", "Tamber", "Ulthar",
	"Vesk", "Wynd", "Xantha", "Yarrow", "Zephon", "Ashfall", "Brine", "Cinder", "Dusk", "Ember", "Fallow",
	"Gloam", "Hollow", "Ironveil", "Juno", "Kestrel", "Lode", "Mire", "Nadir", "Onyx", "Pale", "Rime", "Scour",
	"Talus", "Umber", "Vantor", "Welk"]

## Everything that defines a system's build and look: layout params, star
## type, background, name set, star name and arrival line. Random draws its
## params from the seed.
static func settings(id: String, seed: int) -> Dictionary:
	var sys := find(id)
	var out: Dictionary = sys.get("params", {}).duplicate()
	if id == "random" or out.is_empty():
		out = random_params(seed)
	for k in ["star", "bg", "names", "star_name", "arrival", "feature", "nebula"]:
		if sys.has(k):
			out[k] = sys[k]
	if not out.has("star_name"):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed ^ 0x57a2
		out["star_name"] = NAMES[rng.randi() % NAMES.size()]
	return out

static func find(id: String) -> Dictionary:
	for s in SYSTEMS:
		if s["id"] == id:
			return s
	return SYSTEMS[0]

## Params for the Random entry, drawn from the seed.
static func random_params(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5eed
	var stars: Array = Defs.STAR_TYPES.keys()
	var bgs: Array = BACKGROUNDS.keys()
	var sets: Array = NAME_SETS.keys()
	return {"planets": rng.randi_range(3, 5), "belts": rng.randi_range(1, 3), "spice": rng.randf_range(0.06, 0.25),
		"star": stars[rng.randi() % stars.size()], "bg": bgs[rng.randi() % bgs.size()], "names": sets[rng.randi() % sets.size()],
		"nebula": NEBULA_STYLES[rng.randi() % NEBULA_STYLES.size()]}

## One wedge (TAU / n_players wide, centred on PI) is laid out for player 1
## and rotated round the star for every other player, so each start has the
## same worlds, rocks and distances.
static func generate(seed: int, params: Dictionary, n_players: int = 2) -> Dictionary:
	players = maxi(2, n_players)
	var wedge := PI / players   # half the wedge's angle
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	star_clear = float(Defs.STAR_TYPES.get(params.get("star", "yellow"), Defs.STAR_TYPES["yellow"])["zone"]) + 150.0
	if params.get("feature", "") == "binary":
		star_clear += BINARY_ORBIT
	ring_radius = RING_RADIUS if params.get("feature", "") == "rings" else 0.0
	var names: Array = NAME_SETS.get(params.get("names", ""), NAMES).duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	var placed: Array = []   # [pos, clearance] for every object in wedge 1 (_fits checks every copy)
	var half_planets: Array = []
	var half_rocks: Array = []

	# Home world in the middle of the wedge, give or take a little.
	var home_a := PI + rng.randf_range(-1.0, 1.0) * minf(0.35, wedge * 0.22)
	var home := _on_ellipse(home_a, HOME_T)
	half_planets.append({"kind": "planet_terran", "pos": home, "owner": 1, "home": true})
	_claim(placed, home, 90.0)
	# Starbase between home and the star; starting ships beside it.
	var to_star := (-home).normalized()
	var sb_pos := home + to_star * 170.0
	_claim(placed, sb_pos, 70.0)
	# Starter belt behind the home world (away from the star), plus one spice rock.
	var belt_center := home - to_star * 40.0 + to_star.orthogonal() * (240.0 if rng.randf() < 0.5 else -240.0)
	for i in rng.randi_range(8, 10):
		var p := _free_spot(rng, placed, belt_center, 110.0, 24.0)
		if p != Vector2.INF:
			half_rocks.append({"variant": "asteroid_%d" % rng.randi_range(0, 3) if rng.randf() < 0.8 else "asteroid_big_%d" % rng.randi_range(0, 1), "pos": p})
	var sp := _free_spot(rng, placed, belt_center, 140.0, 24.0)
	if sp != Vector2.INF:
		half_rocks.append({"variant": "spice_0", "pos": sp})

	# Other worlds: type by distance from the star (hot inside, cold outside).
	var n_planets: int = params.get("planets", 4)
	for i in n_planets:
		var ok := false
		for attempt in 200:
			var t := rng.randf_range(0.34, 0.95)
			var a := PI + rng.randf_range(-wedge + 0.12, wedge - 0.12)
			var pos := _on_ellipse(a, t)
			# Planets keep extra room from the edge (big sprites, orbit space).
			if pos.length() > Game.MAP_RADIUS - EDGE_MARGIN - 110.0:
				continue
			if not _fits(placed, pos, 260.0) or pos.distance_to(home) < 480.0:
				continue
			var kind := _kind_for(rng, t)
			var r := rng.randf()
			var size := "_s" if r < 0.3 else ("_l" if r > 0.75 else "")
			half_planets.append({"kind": kind, "size": size, "pos": pos, "owner": 0})
			_claim(placed, pos, 110.0)
			# Gas giants often have a barren moon.
			if kind == "planet_gas" and rng.randf() < 0.6:
				var mp := pos + Vector2.from_angle(rng.randf() * TAU) * 150.0
				if _fits(placed, mp, 70.0) and _inside(mp):
					half_planets.append({"kind": "planet_moon", "pos": mp, "owner": 0})
					_claim(placed, mp, 60.0)
			ok = true
			break
		if not ok:
			break

	# Asteroid belts: arcs along an orbit; spice more likely nearer the center.
	var spice_chance: float = params.get("spice", 0.12)
	for b in int(params.get("belts", 2)):
		var t := rng.randf_range(0.4, 0.85)
		var a0 := PI + rng.randf_range(-1.2, 1.2) * wedge / (PI / 2.0)
		var span := rng.randf_range(0.35, 0.7) * minf(1.0, wedge / (PI / 2.0))
		for k in rng.randi_range(10, 16):
			var a := a0 + span * (float(k) / 15.0 - 0.5) + rng.randf_range(-0.03, 0.03)
			var p := _on_ellipse(a, t + rng.randf_range(-0.03, 0.03))
			if not _in_wedge(p) or not _fits(placed, p, 26.0) or not _inside(p):
				continue
			var spice := rng.randf() < spice_chance * (1.4 - t)
			var variant := "spice_%d" % rng.randi_range(0, 1) if spice else ("asteroid_%d" % rng.randi_range(0, 3) if rng.randf() < 0.85 else "asteroid_big_%d" % rng.randi_range(0, 1))
			half_rocks.append({"variant": variant, "pos": p})
			_claim(placed, p, 12.0)

	# Signature feature: a spice nebula ring around the star, seeded with
	# extra spice rocks (the ring itself is symmetric; the rocks are mirrored).
	var features: Array = []
	if params.get("feature", "") == "storms":
		# Drifting storm clouds, spread evenly along their loops (one more
		# than there are players, at least three).
		var n_storms := maxi(3, players + 1)
		var ph0 := rng.randf() * TAU
		for k in n_storms:
			features.append({"type": "storms", "seed": seed + 101 * k, "radius": rng.randf_range(240.0, 330.0), "phase": ph0 + TAU * k / n_storms})
	if ring_radius > 0.0:
		# Two gaps per wedge, turned with it.
		var g1 := rng.randf_range(0.3, 1.1) * wedge / (PI / 2.0)
		var g2 := g1 + wedge + rng.randf_range(-0.35, 0.35) * wedge / (PI / 2.0)
		var gaps: Array = []
		for k in players:
			gaps.append(g1 + TAU * k / players)
			gaps.append(g2 + TAU * k / players)
		features.append({"type": "rings", "radius": RING_RADIUS, "width": RING_WIDTH, "gap_half": RING_GAP_HALF, "gaps": gaps})
	if params.get("feature", "") == "binary":
		features.append({"type": "binary", "orbit": BINARY_ORBIT, "period": BINARY_PERIOD})
	if params.get("feature", "") == "spice_nebula":
		var inner := star_clear + 20.0
		var outer := inner + 400.0
		features.append({"type": "spice_nebula", "inner": inner, "outer": outer})
		for k in 24:
			var a := PI + rng.randf_range(-wedge + 0.1, wedge - 0.1)
			var p := Vector2.from_angle(a) * rng.randf_range(inner + 40.0, outer - 40.0)
			if not _in_wedge(p) or not _fits(placed, p, 26.0):
				continue
			half_rocks.append({"variant": "spice_%d" % rng.randi_range(0, 1), "pos": p})
			_claim(placed, p, 12.0)
			if half_rocks.filter(func(r): return r["pos"].length() > inner and r["pos"].length() < outer and str(r["variant"]).begins_with("spice")).size() >= 7:
				break

	if params.has("nebula"):
		features.append_array(nebulae(str(params["nebula"]), sb_pos, seed))

	# Turn the wedge round the star once per player.
	var out := {"planets": [], "asteroids": [], "starbases": [], "ships": [], "features": features}
	var n := 0
	for side in players:
		var turn := TAU * side / players
		for pl in half_planets:
			out["planets"].append({"name": names[n % names.size()], "kind": pl["kind"], "size": pl.get("size", ""), "pos": pl["pos"].rotated(turn),
				"owner": (1 + side if pl["owner"] == 1 else 0)})
			n += 1
		for r in half_rocks:
			out["asteroids"].append({"name": "Rock%d" % out["asteroids"].size(), "variant": r["variant"], "pos": r["pos"].rotated(turn)})
		var pid := 1 + side
		var sb: Vector2 = sb_pos.rotated(turn)
		out["starbases"].append({"owner": pid, "pos": sb})
		var face := (-sb).angle()
		var side_dir := Vector2.from_angle(face).orthogonal()
		for i in 3:
			out["ships"].append({"type": "miner", "owner": pid, "pos": sb + side_dir * (60.0 + i * 22.0), "rot": face})
			out["ships"].append({"type": "corvette", "owner": pid, "pos": sb - side_dir * (60.0 + i * 22.0) + Vector2.from_angle(face) * 30.0, "rot": face})
	return out

## Nebula layouts other than Kharon's full ring, one per system so each map
## is fought over differently. Everything is mirrored through the star, so
## both players get the same gas at the same distances.
##   flanks  - one cloud on each flank, equally far from both bases: the
##             contested middle (Orion Reach).
##   bands   - two arcs of a ring outside the twin suns' orbit, across the
##             lane between the bases (Vega Drift).
##   pockets - small clouds scattered outside the debris ring (Tethys).
##   drifts  - one big cloud on each base's flank, out toward the edge: a home nebula
##             that the other side has to come and take (Sable Verge).
const NEBULA_STYLES := ["flanks", "bands", "pockets", "drifts"]
## How close gas may come to a starbase: a base parked in a nebula would
## lose its shields, which no layout should do to a player.
const NEBULA_BASE_CLEAR := 200.0

## The nebula features for `style`, given player 1's starbase position.
static func nebulae(style: String, base: Vector2, seed: int) -> Array:
	var half: Array = []
	var axis := base.normalized()
	var ang := axis.angle()
	match style:
		"flanks":
			half.append({"shape": "cloud", "pos": axis.orthogonal() * 720.0, "radius": 250.0})
		"bands":
			var r0 := star_clear + 110.0
			half.append({"shape": "ring", "pos": Vector2.ZERO, "inner": r0, "outer": r0 + 150.0, "arc_mid": ang + PI / 2.0, "arc_half": 0.55})
		"pockets":
			var r := (ring_radius if ring_radius > 0.0 else RING_RADIUS) + 250.0
			for da in [-0.8, 0.75, 1.75]:
				half.append({"shape": "cloud", "pos": Vector2.from_angle(ang + da) * r, "radius": 130.0})
		"drifts":
			half.append({"shape": "cloud", "pos": Vector2.from_angle(ang + 0.7) * 1200.0, "radius": 300.0})
	var out: Array = []
	var k := 0
	var bases: Array = []
	for side in players:
		bases.append(base.rotated(TAU * side / players))
	for side in players:
		var turn := TAU * side / players
		for h in half:
			var f: Dictionary = h.duplicate()
			f["type"] = "spice_nebula"
			f["seed"] = seed + 31 * k
			k += 1
			f["pos"] = h["pos"].rotated(turn)
			if f.has("arc_mid"):
				f["arc_mid"] = float(h["arc_mid"]) + turn
			if f["shape"] == "cloud":
				# Inside the map, and never over a starbase.
				f["pos"] = f["pos"].limit_length(Game.MAP_RADIUS - EDGE_MARGIN - float(f["radius"]))
				for b in bases:
					var room: float = f["pos"].distance_to(b) - NEBULA_BASE_CLEAR
					f["radius"] = maxf(minf(float(f["radius"]), room), 60.0)
			out.append(f)
	return out

static func _on_ellipse(a: float, t: float) -> Vector2:
	return Vector2.from_angle(a) * LAYOUT_R * t

static func _inside(p: Vector2) -> bool:
	return p.length() < Game.MAP_RADIUS - EDGE_MARGIN

## Inside player 1's wedge (centred on PI), with a little room at its sides.
static func _in_wedge(p: Vector2) -> bool:
	return absf(angle_difference(p.angle(), PI)) < PI / players - 0.02

## Room for something of `clearance` at p: off the star, inside the map,
## and clear of everything placed so far in every player's copy of it.
static func _fits(placed: Array, p: Vector2, clearance: float) -> bool:
	if p.length() < star_clear or not _inside(p):
		return false
	if ring_radius > 0.0 and absf(p.length() - ring_radius) < RING_WIDTH / 2.0 + minf(clearance, 60.0) + 30.0:
		return false
	for k in range(1, players):
		if p.distance_to(p.rotated(TAU * k / players)) < clearance:
			return false  # too close to its own copy in the next wedge
	for q in placed:
		var min_d: float = clearance + q[1]
		for k in players:
			if p.distance_to(q[0].rotated(TAU * k / players)) < min_d:
				return false
	return true

static func _claim(placed: Array, p: Vector2, clearance: float) -> void:
	placed.append([p, clearance])

static func _free_spot(rng: RandomNumberGenerator, placed: Array, center: Vector2, spread: float, clearance: float) -> Vector2:
	for attempt in 40:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, spread)
		if _fits(placed, p, clearance * 0.5):
			_claim(placed, p, clearance * 0.5)
			return p
	return Vector2.INF

static func _kind_for(rng: RandomNumberGenerator, t: float) -> String:
	var r := rng.randf()
	if t < 0.5:
		return "planet_lava" if r < 0.45 else ("planet_desert" if r < 0.8 else "planet_moon")
	if t < 0.72:
		return "planet_desert" if r < 0.4 else ("planet_moon" if r < 0.65 else ("planet_terran" if r < 0.85 else "planet_gas"))
	return "planet_ice" if r < 0.35 else ("planet_gas" if r < 0.65 else ("planet_terran" if r < 0.85 else "planet_desert"))
