@tool
class_name Asteroid
extends Node2D
## Resource-bearing rock: minerals (common) or spice (rare, orange glints).
## Mining barges extract from it until it's empty, then it crumbles.

@export_enum("asteroid_0", "asteroid_1", "asteroid_2", "asteroid_3", "asteroid_big_0", "asteroid_big_1", "spice_0", "spice_1") var variant: String = "asteroid_0":
	set(v):
		variant = v
		if has_node("Sprite"):
			$Sprite.texture = Defs.tex(variant)
@export var amount: int = 400

var resource: String = "minerals"
var radius: float = 8.0
var _spin: float

func _ready() -> void:
	$Sprite.texture = Defs.tex(variant)
	radius = $Sprite.texture.get_width() / 2.0
	resource = "spice" if variant.begins_with("spice") else "minerals"
	if Engine.is_editor_hint():
		return
	add_to_group("asteroids")
	_spin = randf_range(-0.25, 0.25)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		$Sprite.rotation += _spin * delta

func extract(n: int) -> int:
	var got := mini(n, amount)
	amount -= got
	if amount <= 0:
		Game.instance.spawn_explosion(global_position, 0.5)
		queue_free()
	return got
