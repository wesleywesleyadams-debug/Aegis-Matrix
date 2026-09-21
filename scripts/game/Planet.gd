@tool
class_name Planet
extends Node2D
## A world. Colonized planets hold population that eats food, grows, and
## produces food, energy and (some types) spice. Growth: 1 pop per minute
## per pair of pop, while fed (spice covers food deficits 1:1), up to the
## type's ceiling. Neutral planets need a Colony Ship; enemy planets flip
## after CONQUER_TIME seconds of your warships in orbit with no defenders
## present, keeping half their population.

const CONQUER_TIME := 15.0
const ECON_TICK := 0.25

@export_enum("planet_terran", "planet_desert", "planet_ice", "planet_lava", "planet_gas", "planet_moon") var kind: String = "planet_terran":
	set(v):
		kind = v
		if has_node("Sprite"):
			$Sprite.texture = Defs.tex(kind)
@export var planet_name: String = "Unnamed"
@export var owner_id: int = 0:
	set(v):
		owner_id = v
		queue_redraw()
## Starting population if owned at match start (0 = Defs.START_POP).
@export var start_pop: float = 0.0
## Buildings already standing at match start (filled into the first fields).
@export var start_buildings: PackedStringArray = []

var radius: float = 24.0
var pop: float = 0.0
var starving: bool = false
var claim_owner: int = 0
var claim_progress: float = 0.0
var focused: bool = false:
	set(v):
		focused = v
		queue_redraw()
## Pops currently going unfed, and how long they have been hungry.
var hungry: float = 0.0
var starve_timer: float = 0.0
## Last computed per-minute food figures and per-second outputs, for the HUD.
var food_made_per_min: float = 0.0
var food_eaten_per_min: float = 0.0
var energy_out: float = 0.0
var spice_out: float = 0.0
var growth_per_min: float = 0.0

## Buildable fields (count set by planet size) and what occupies each ("" = empty).
var fields: int = 3
var buildings: Array[String] = []
## Construction: the active job and the queue behind it, each {"field": int, "id": String}.
var construction: Dictionary = {}
var construction_queue: Array = []
var construction_stalled: bool = false
## Whether each field's building has enough pop to run, and pop left unassigned.
var operating: Array[bool] = []
var idle_pop: float = 0.0

var _check_timer: float = 0.0
var _econ_timer: float = 0.0

func _ready() -> void:
	$Sprite.texture = Defs.tex(kind)
	radius = $Sprite.texture.get_width() / 2.0
	if Engine.is_editor_hint():
		return
	add_to_group("planets")
	fields = Defs.field_count($Sprite.texture.get_width())
	buildings.resize(fields)
	buildings.fill("")
	operating.resize(fields)
	operating.fill(false)
	for i in mini(start_buildings.size(), fields):
		buildings[i] = start_buildings[i]
	# A starting world always has at least one Farm.
	if owner_id != 0 and not buildings.has("farm"):
		var slot := buildings.find("")
		if slot >= 0:
			buildings[slot] = "farm"
	if owner_id != 0:
		pop = start_pop if start_pop > 0.0 else Defs.START_POP
	_econ_timer = randf() * ECON_TICK

func type_def() -> Dictionary:
	return Defs.PLANET_TYPES[kind]

func max_pop() -> float:
	var extra := 0.0
	for b in buildings:
		if b != "":
			extra += Defs.BUILDINGS[b].get("max_pop", 0)
	if owner_id == 0:
		return type_def()["max_pop"] + extra
	return (type_def()["max_pop"] + extra) * Game.instance.mod(owner_id, "max_pop")

func orbit_radius() -> float:
	return radius + 70.0

func colonize(pid: int) -> void:
	var old := owner_id
	owner_id = pid
	construction = {}
	construction_queue.clear()
	pop = Defs.START_POP
	claim_progress = 0.0
	Game.instance.planet_claimed(self, old)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_econ_timer += delta
	if _econ_timer >= ECON_TICK:
		_economy(_econ_timer)
		_econ_timer = 0.0
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.5
		_check_conquest()

func _economy(dt: float) -> void:
	if owner_id == 0:
		food_made_per_min = 0.0
		food_eaten_per_min = 0.0
		hungry = 0.0
		energy_out = 0.0
		spice_out = 0.0
		growth_per_min = 0.0
		return
	var g := Game.instance
	var t := type_def()
	var k := pop / 1000.0
	food_made_per_min = 0.0 # farms add to this in _run_buildings
	food_eaten_per_min = pop * Defs.FOOD_PER_POP_PER_MIN
	energy_out = (t["energy"] + k * Defs.ENERGY_PER_1000_POP) * g.mod(owner_id, "energy")
	spice_out = t["spice"] * minf(1.0, pop / 1000.0 + 0.25)
	g.add_resources(owner_id, {"food": food_made_per_min / 60.0 * dt, "energy": energy_out * dt, "spice": spice_out * dt})
	_run_buildings(dt)
	# Every pop eats from the empire stockpile; spice covers any deficit.
	var fed := g.pay_over_time(owner_id, {"food": food_eaten_per_min / 60.0}, dt) if pop > 0.0 else 1.0
	starving = fed < 0.999
	if starving:
		# The unfed share starts (or keeps) a one-minute countdown.
		hungry = maxf(hungry, pop * (1.0 - fed))
		starve_timer += dt
		if starve_timer >= Defs.STARVE_SECONDS:
			var died := minf(hungry, pop)
			pop -= died
			hungry = 0.0
			starve_timer = 0.0
			if owner_id == g.player_id and died >= 1.0:
				g.message.emit("%d pops starved on %s." % [int(died), planet_name], Color("ff6a5a"))
	else:
		# Fed again within the window: nobody dies.
		hungry = 0.0
		starve_timer = 0.0
	var cap := max_pop()
	if not starving and pop < cap:
		var pairs := floorf(pop / 2.0)
		growth_per_min = pairs * Defs.GROWTH_PER_PAIR_PER_MIN * g.mod(owner_id, "growth")
		pop = minf(cap, pop + growth_per_min / 60.0 * dt)
	else:
		growth_per_min = 0.0
		pop = minf(pop, cap)

func _check_conquest() -> void:
	if owner_id == 0:
		claim_progress = 0.0
		return
	var present := {}
	for s in Game.instance.ships_near(global_position, orbit_radius()):
		if s.def["role"] == "warship":
			present[s.owner_id] = true
	var prev := claim_progress
	if present.size() == 1 and not present.has(owner_id):
		var who: int = present.keys()[0]
		if who != claim_owner:
			claim_owner = who
			claim_progress = 0.0
		claim_progress += 0.5
		if claim_progress >= CONQUER_TIME:
			var old := owner_id
			owner_id = who
			pop = maxf(1.0, pop * 0.5)
			construction = {}
			construction_queue.clear()
			claim_progress = 0.0
			Game.instance.planet_claimed(self, old)
	else:
		claim_progress = maxf(0.0, claim_progress - 0.5)
	if prev != claim_progress:
		queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	var r := radius + 5.0
	if owner_id != 0 or focused:
		# Owner ring: dotted pixel circle (white while focused).
		var col := Defs.team_color(owner_id) if owner_id != 0 else Color("9aa0b0")
		if focused:
			col = col.lightened(0.5)
		var n := int(r * 1.2)
		for i in n:
			if focused or i % 3 != 2:
				var a := TAU * i / n
				draw_rect(Rect2(Vector2.from_angle(a) * r - Vector2(0.5, 0.5), Vector2(1, 1)), col)
	if claim_progress > 0.0:
		var col2 := Defs.team_color(claim_owner)
		draw_arc(Vector2.ZERO, r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * claim_progress / CONQUER_TIME, 48, col2, 2.0)

# ---------------------------------------------------------------- fields & buildings

## "" if `id` may be ordered on `field` by the owner, else a reason.
func can_build(field: int, id: String) -> String:
	if field < 0 or field >= fields:
		return "No such field"
	if buildings[field] != "":
		return "Field is occupied"
	if field_job(field) != "":
		return "Field already has construction ordered"
	var only: Array = Defs.BUILDINGS[id]["only"]
	if not only.is_empty() and kind not in only:
		return "%s can't be built on a %s world" % [Defs.BUILDINGS[id]["name"], type_def()["label"]]
	return ""

## The building being built or queued on a field, or "".
func field_job(field: int) -> String:
	if construction.get("field", -1) == field:
		return construction["id"]
	for j in construction_queue:
		if j["field"] == field:
			return j["id"]
	return ""

func order_build(field: int, id: String) -> String:
	var why := can_build(field, id)
	if why == "":
		construction_queue.append({"field": field, "id": id})
	return why

## Cancels construction on a field; the paid share of an active job is refunded.
func cancel_build(field: int) -> void:
	if construction.get("field", -1) == field:
		var d: Dictionary = Defs.BUILDINGS[construction["id"]]
		var frac: float = construction["progress"] / d["time"]
		var refund := {}
		for k in d["cost"]:
			refund[k] = d["cost"][k] * frac
		Game.instance.add_resources(owner_id, refund)
		construction = {}
	construction_queue = construction_queue.filter(func(j): return j["field"] != field)

func demolish(field: int) -> void:
	buildings[field] = ""

func count_building(id: String) -> int:
	return buildings.count(id)

func free_fields() -> int:
	var n := 0
	for i in fields:
		if buildings[i] == "" and field_job(i) == "":
			n += 1
	return n

## Per-tick building output and construction payments (called from _economy).
func _run_buildings(dt: float) -> void:
	var g := Game.instance
	var t := type_def()
	var out := {}
	_staff()
	for i in fields:
		var b: String = buildings[i]
		if b == "" or not operating[i]:
			continue
		for k in Defs.BUILDINGS[b]["output"]:
			var v: float = Defs.BUILDINGS[b]["output"][k]
			if k == "food":
				# Farms: per-minute figure, scaled by fertility and Hydroponics.
				v = v * (0.5 + 0.5 * t["fertility"]) * g.mod(owner_id, "food") / 60.0
				food_made_per_min += v * 60.0
			elif k == "energy":
				v *= g.mod(owner_id, "energy")
				energy_out += v
			elif k == "spice":
				spice_out += v
			out[k] = out.get(k, 0.0) + v * dt
	if not out.is_empty():
		g.add_resources(owner_id, out)

	construction_stalled = false
	if construction.is_empty():
		if construction_queue.is_empty():
			return
		var j: Dictionary = construction_queue.pop_front()
		construction = {"field": j["field"], "id": j["id"], "progress": 0.0}
	var d: Dictionary = Defs.BUILDINGS[construction["id"]]
	var per_sec := {}
	for k in d["cost"]:
		per_sec[k] = d["cost"][k] / d["time"]
	var f := g.pay_over_time(owner_id, per_sec, dt)
	construction_stalled = f < 0.999
	construction["progress"] += dt * f
	if construction["progress"] >= d["time"]:
		buildings[construction["field"]] = construction["id"]
		if owner_id == g.player_id:
			g.message.emit("%s completed on %s." % [d["name"], planet_name], Color("7fd8ff"))
			g.sfx.play_ui("build")
		construction = {}

## Assigns pop to buildings: food first, then energy, minerals, spice.
## A building runs only if its full "pop" requirement can be met.
func _staff() -> void:
	var left := pop
	operating.fill(false)
	for i in fields:
		var b: String = buildings[i]
		if b != "" and Defs.BUILDINGS[b].get("pop", 0) == 0:
			operating[i] = true
	for res in Defs.STAFFING_PRIORITY:
		for i in fields:
			var b: String = buildings[i]
			if b == "" or operating[i] or not Defs.BUILDINGS[b]["output"].has(res):
				continue
			var need: float = Defs.BUILDINGS[b]["pop"]
			if left >= need:
				operating[i] = true
				left -= need
	idle_pop = left

## Pop needed to run every building on this planet.
func pop_required() -> int:
	var n := 0
	for b in buildings:
		if b != "":
			n += Defs.BUILDINGS[b].get("pop", 0)
	return n
