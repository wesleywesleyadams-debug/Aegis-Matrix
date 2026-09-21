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

var _check_timer: float = 0.0
var _econ_timer: float = 0.0

func _ready() -> void:
	$Sprite.texture = Defs.tex(kind)
	radius = $Sprite.texture.get_width() / 2.0
	if Engine.is_editor_hint():
		return
	add_to_group("planets")
	if owner_id != 0:
		pop = start_pop if start_pop > 0.0 else Defs.START_POP
	_econ_timer = randf() * ECON_TICK

func type_def() -> Dictionary:
	return Defs.PLANET_TYPES[kind]

func max_pop() -> float:
	if owner_id == 0:
		return type_def()["max_pop"]
	return type_def()["max_pop"] * Game.instance.mod(owner_id, "max_pop")

func orbit_radius() -> float:
	return radius + 70.0

func colonize(pid: int) -> void:
	var old := owner_id
	owner_id = pid
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
	food_made_per_min = t["fertility"] * (Defs.FOOD_BASE_PER_MIN + pop * Defs.FOOD_GROWN_PER_POP_PER_MIN) * g.mod(owner_id, "food")
	food_eaten_per_min = pop * Defs.FOOD_PER_POP_PER_MIN
	energy_out = (t["energy"] + k * Defs.ENERGY_PER_1000_POP) * g.mod(owner_id, "energy")
	spice_out = t["spice"] * minf(1.0, pop / 1000.0 + 0.25)
	g.add_resources(owner_id, {"food": food_made_per_min / 60.0 * dt, "energy": energy_out * dt, "spice": spice_out * dt})
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
