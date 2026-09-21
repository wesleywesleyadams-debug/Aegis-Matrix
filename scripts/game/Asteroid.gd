@tool
class_name Asteroid
extends Node2D
## Mineral-bearing rock. Mining barges extract from it until it's empty,
## then it crumbles.

@export_enum("asteroid_0", "asteroid_1", "asteroid_2", "asteroid_3", "asteroid_big_0", "asteroid_big_1") var variant: String = "asteroid_0":
	set(v):
		variant = v
		if has_node("Sprite"):
			$Sprite.texture = Defs.tex(variant)
@export var minerals: int = 400

var radius: float = 8.0
var _spin: float

func _ready() -> void:
	$Sprite.texture = Defs.tex(variant)
	radius = $Sprite.texture.get_width() / 2.0
	if Engine.is_editor_hint():
		return
	add_to_group("asteroids")
	_spin = randf_range(-0.25, 0.25)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		$Sprite.rotation += _spin * delta

func extract(amount: int) -> int:
	var got := mini(amount, minerals)
	minerals -= got
	if minerals <= 0:
		Game.instance.spawn_explosion(global_position, 0.5)
		queue_free()
	return got
