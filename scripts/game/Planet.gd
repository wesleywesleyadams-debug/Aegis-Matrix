@tool
class_name Planet
extends Node2D
## A world. Colonized planets hold population that eats food, grows, and
## produces food, energy and (some types) spice. Growth: 1 pop per minute
## per pair of pop, while fed (spice covers food deficits 1:1), up to the
## type's ceiling. Neutral planets are settled by a Colony Ship over
## COLONIZE_TIME seconds. Enemy planets are taken by bombarding them: a
## corvette shot kills 1 pop, and every shot scales with its damage (twice a
## corvette's damage = 2 pops). Bombardment also halts growth; at 0
## pop every building is destroyed and the planet turns neutral, ready for
## anyone to colonize.

## Planetary shields: bombardment must knock these down before pops die.
## Recharge after SHIELD_REGEN_DELAY seconds without hits (costs a little
## energy, like ship shields). Boosted by shield research.
const PLANET_SHIELD := 1000.0
const PLANET_SHIELD_REGEN := 20.0
const SHIELD_REGEN_DELAY := 5.0

## Pops killed per point of damage, pegged so one base corvette shot = 1 pop.
static var POP_PER_DAMAGE: float = 1.0 / float(Defs.SHIPS["corvette"]["damage"])
const COLONIZE_TIME := 60.0
## A planet counts as under siege for this long after its last hit.
const SIEGE_TIME := 3.0
## The siege bar resets if the bombardment stops for this long.
const SIEGE_MEMORY := 10.0
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
## Bombardment: pop at the start of the current siege and time of last hit.
var siege_start_pop: float = 0.0
var shield: float = 0.0
var last_hit_time: float = -1000.0
## Colonization in progress: whose, how far, and the ship doing it.
var colonizing_owner: int = 0
var colonize_progress: float = 0.0
var colonizer: Node2D
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

## Gas giants: mined by Gas Skimmers (duck-types like an Asteroid).
var resource: String = ""
var amount: int = 0
## Seconds (game time) until a depleted gas giant refills its reserve.
const REPLENISH_SECONDS := 600.0
var depleted_timer: float = 0.0

var _check_timer: float = 0.0
var _econ_timer: float = 0.0

func _ready() -> void:
	$Sprite.texture = Defs.tex(kind)
	radius = $Sprite.texture.get_width() / 2.0
	if Engine.is_editor_hint():
		return
	add_to_group("planets")
	fields = Defs.field_count($Sprite.texture.get_width()) if is_habitable() else 0
	if not is_habitable():
		resource = "minerals"
		amount = int(type_def().get("gas_reserve", 0))
	buildings.resize(fields)
	buildings.fill("")
	operating.resize(fields)
	operating.fill(false)
	for i in mini(start_buildings.size(), fields):
		buildings[i] = start_buildings[i]
	# A starting world always has at least one Farm and one Power Plant.
	if owner_id != 0:
		for must in ["farm", "generator"]:
			if not buildings.has(must):
				var slot := buildings.find("")
				if slot >= 0:
					buildings[slot] = must
	if owner_id != 0:
		pop = start_pop if start_pop > 0.0 else Defs.HOME_START_POP
		shield = PLANET_SHIELD
	_econ_timer = randf() * ECON_TICK

func type_def() -> Dictionary:
	return Defs.PLANET_TYPES[kind]

func is_habitable() -> bool:
	return type_def().get("habitable", true)

## Gas giant skimming; returns how much was actually taken.
func extract(n: int) -> int:
	var got := mini(n, amount)
	amount -= got
	if amount <= 0 and depleted_timer <= 0.0:
		depleted_timer = REPLENISH_SECONDS
		$Sprite.modulate = Color(0.45, 0.45, 0.5)
		queue_redraw()
	return got

func max_pop() -> float:
	var extra := 0.0
	for b in buildings:
		if b != "":
			extra += Defs.BUILDINGS[b].get("max_pop", 0)
	var base := float(fields * Defs.POP_PER_SIZE)
	if owner_id == 0:
		return base + extra
	return (base + extra) * Game.instance.mod(owner_id, "max_pop")

func orbit_radius() -> float:
	return radius + 70.0

func colonize(pid: int) -> void:
	if not is_habitable():
		return
	var old := owner_id
	owner_id = pid
	construction = {}
	construction_queue.clear()
	pop = Defs.START_POP
	colonizing_owner = 0
	shield = max_shield()
	colonize_progress = 0.0
	colonizer = null
	Game.instance.planet_claimed(self, old)
	queue_redraw()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if depleted_timer > 0.0:
		depleted_timer -= delta
		if depleted_timer <= 0.0:
			depleted_timer = 0.0
			amount = int(type_def().get("gas_reserve", 0))
			$Sprite.modulate = Color.WHITE
			queue_redraw()
	_econ_timer += delta
	if _econ_timer >= ECON_TICK:
		_economy(_econ_timer)
		_econ_timer = 0.0
	# A colonization attempt ends if its ship is lost.
	if colonizing_owner != 0 and not is_instance_valid(colonizer):
		colonizing_owner = 0
		colonize_progress = 0.0
		queue_redraw()
	if owner_id != 0 and Game.now() - last_hit_time < SIEGE_MEMORY:
		queue_redraw()
	# Shield recharge once the bombardment has paused.
	var ms := max_shield() if owner_id != 0 else 0.0
	if shield < ms and Game.now() - last_hit_time > SHIELD_REGEN_DELAY:
		var gain := minf(ms - shield, PLANET_SHIELD_REGEN * delta)
		var paid := Game.instance.pay_over_time(owner_id, {"energy": gain * Defs.SHIELD_ENERGY_PER_POINT}, 1.0)
		shield += gain * paid
		queue_redraw()

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
	energy_out = 0.0 # only Power Plants add energy (see _run_buildings)
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
				g.alert("%d pops starved on %s." % [int(died), planet_name], "alert_starved")
	else:
		# Fed again within the window: nobody dies.
		hungry = 0.0
		starve_timer = 0.0
	var cap := max_pop()
	if not starving and pop < cap and not under_siege():
		var pairs := floorf(pop / 2.0)
		growth_per_min = pairs * Defs.GROWTH_PER_PAIR_PER_MIN * g.mod(owner_id, "growth")
		pop = minf(cap, pop + growth_per_min / 60.0 * dt)
	else:
		growth_per_min = 0.0
		pop = minf(pop, cap)

# ---------------------------------------------------------------- siege & colonization

func max_shield() -> float:
	if owner_id == 0:
		return 0.0
	return PLANET_SHIELD * Game.instance.mod(owner_id, "shield")

func is_alive() -> bool:
	return owner_id != 0 and pop > 0.0 and is_inside_tree()

func is_enemy_of(pid: int) -> bool:
	return owner_id != 0 and pid != 0 and owner_id != pid

func under_siege() -> bool:
	return owner_id != 0 and Game.now() - last_hit_time < SIEGE_TIME

## Weapon fire from bombarding ships: the planetary shield absorbs it first,
## then each point kills POP_PER_DAMAGE pops.
func take_damage(amount: float, from: Node2D = null) -> void:
	if owner_id == 0:
		return
	var g := Game.instance
	if g.now() - last_hit_time > SIEGE_MEMORY or siege_start_pop <= 0.0:
		siege_start_pop = maxf(pop, 1.0)
	last_hit_time = g.now()
	# The planetary shield soaks damage first.
	var absorbed := minf(shield, amount)
	shield -= absorbed
	amount -= absorbed
	if absorbed > 0.0:
		g.spawn_shield_hit(global_position, radius * 0.6, from.global_position if is_instance_valid(from) else global_position + Vector2.RIGHT)
	pop -= amount * POP_PER_DAMAGE
	if owner_id == g.player_id:
		g.alert("%s is being bombarded!" % planet_name, "alert_planet")
	if pop <= 0.0:
		var attacker: int = from.owner_id if is_instance_valid(from) and from.get("owner_id") != null else 0
		_depopulate(attacker)
	queue_redraw()

## 0 pop: every building and construction job is destroyed and the planet
## becomes neutral.
func _depopulate(attacker: int) -> void:
	var old := owner_id
	pop = 0.0
	buildings.fill("")
	operating.fill(false)
	construction = {}
	construction_queue.clear()
	hungry = 0.0
	starve_timer = 0.0
	shield = 0.0
	siege_start_pop = 0.0
	owner_id = 0
	Game.instance.planet_depopulated(self, old, attacker)

## Called every tick by a colony ship sitting in orbit. The first empire
## to start keeps the slot until its ship is lost.
func progress_colonize(ship: Node2D, dt: float) -> bool:
	if owner_id != 0 or not is_habitable():
		return false
	if colonizing_owner != 0 and colonizing_owner != ship.owner_id and is_instance_valid(colonizer):
		return false
	if colonizing_owner != ship.owner_id:
		colonize_progress = 0.0
	colonizing_owner = ship.owner_id
	colonizer = ship
	colonize_progress += dt
	queue_redraw()
	if colonize_progress >= COLONIZE_TIME:
		colonize(ship.owner_id)
		return true
	return false

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	if depleted_timer > 0.0:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(-radius, radius + 12.0), "DEPLETED", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 8, Color(1, 0.55, 0.45))
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
	var f2 := ThemeDB.fallback_font
	# Planetary shield: light-blue ring just outside the others while it's
	# not full (or under fire).
	if owner_id != 0:
		var ms2 := max_shield()
		if ms2 > 0.0 and (shield < ms2 - 0.5 or Game.now() - last_hit_time < SIEGE_MEMORY):
			draw_arc(Vector2.ZERO, r + 9.0, 0.0, TAU, 64, Color(0.5, 0.85, 1.0, 0.15), 2.0)
			draw_arc(Vector2.ZERO, r + 9.0, -PI / 2.0, -PI / 2.0 + TAU * shield / ms2, 64, Color("7fd8ff"), 2.0)
	# Siege: ring showing the share of pops left since bombardment began.
	if owner_id != 0 and Game.now() - last_hit_time < SIEGE_MEMORY and siege_start_pop > 0.0:
		var frac := clampf(pop / siege_start_pop, 0.0, 1.0)
		# In the owning player's color, draining as pops die.
		var oc := Defs.team_color(owner_id)
		draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 64, Color(oc, 0.2), 3.0)
		draw_arc(Vector2.ZERO, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 64, oc, 3.0)
		draw_string(f2, Vector2(-100.0, -r - 10.0), "%d%% pops left" % int(ceil(frac * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8, oc)
	# Colonization: ring filling up in the colonizer's color.
	if colonizing_owner != 0 and colonize_progress > 0.0:
		var col3 := Defs.team_color(colonizing_owner)
		draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 64, Color(col3, 0.2), 3.0)
		draw_arc(Vector2.ZERO, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * colonize_progress / COLONIZE_TIME, 64, col3, 3.0)
		draw_string(f2, Vector2(-100.0, -r - 10.0), "Colonizing %d%%" % int(100.0 * colonize_progress / COLONIZE_TIME), HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8, col3)

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
				# Farms: per-minute figure, boosted by Hydroponics.
				v = v * g.mod(owner_id, "food") / 60.0
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
			g.notify("%s completed on %s." % [d["name"], planet_name], "note_building")
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
