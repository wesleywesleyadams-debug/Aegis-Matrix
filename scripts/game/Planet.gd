@tool
class_name Planet
extends Node2D
## A colonizable world. Owned planets pay energy every second. A planet
## flips to whoever has warships in orbit with no enemy warships present,
## after CLAIM_TIME seconds of uncontested presence.

const CLAIM_TIME := 12.0

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
## Energy multiplier (gas giants and terran worlds pay more).
@export var yield_mult: float = 1.0

var radius: float = 24.0
var claim_owner: int = 0
var claim_progress: float = 0.0
var _check_timer: float = 0.0

func _ready() -> void:
	$Sprite.texture = Defs.tex(kind)
	radius = $Sprite.texture.get_width() / 2.0
	if Engine.is_editor_hint():
		return
	add_to_group("planets")

func orbit_radius() -> float:
	return radius + 70.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if owner_id != 0:
		Game.instance.add_resources(owner_id, {"energy": Defs.PLANET_ENERGY_PER_SEC * yield_mult * delta})

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.5
	var present := {}
	for s in Game.instance.ships_near(global_position, orbit_radius()):
		if not s.is_miner():
			present[s.owner_id] = true
	var prev_progress := claim_progress
	if present.size() == 1:
		var who: int = present.keys()[0]
		if who == owner_id:
			claim_progress = 0.0
		else:
			if who != claim_owner:
				claim_owner = who
				claim_progress = 0.0
			claim_progress += 0.5
			if claim_progress >= CLAIM_TIME:
				var old := owner_id
				owner_id = who
				claim_progress = 0.0
				Game.instance.planet_claimed(self, old)
	elif present.is_empty():
		claim_progress = maxf(0.0, claim_progress - 0.5)
	if prev_progress != claim_progress:
		queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	var r := radius + 5.0
	if owner_id != 0:
		# Owner ring: dotted pixel circle.
		var col := Defs.team_color(owner_id)
		var n := int(r * 1.2)
		for i in n:
			if i % 3 != 2:
				var a := TAU * i / n
				draw_rect(Rect2(Vector2.from_angle(a) * r - Vector2(0.5, 0.5), Vector2(1, 1)), col)
	if claim_progress > 0.0:
		var col2 := Defs.team_color(claim_owner)
		draw_arc(Vector2.ZERO, r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * claim_progress / CLAIM_TIME, 48, col2, 2.0)
