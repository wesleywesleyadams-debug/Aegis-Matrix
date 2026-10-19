@tool
class_name Asteroid
extends Node2D
## Resource-bearing rock: minerals (common) or spice (rare, orange glints).
## Its reserve is set by its size (see Defs.ASTEROID_*_PER_PX2): bigger
## rocks hold more. Mining barges extract from it until it's empty, then it
## crumbles. Click one to inspect it (it shows a ring and a reserve bar).

@export_enum("asteroid_0", "asteroid_1", "asteroid_2", "asteroid_3", "asteroid_big_0", "asteroid_big_1", "spice_0", "spice_1") var variant: String = "asteroid_0":
	set(v):
		variant = v
		if has_node("Sprite"):
			$Sprite.texture = Defs.tex(variant)

var resource: String = "minerals"
var radius: float = 8.0
## Reserve left, and the full reserve for this rock's size.
var amount: int = 0
## How rich this rock is for its size (set by its belt, see SystemGen).
var richness: float = 1.0
var max_amount: int = 0
var focused: bool = false:
	set(v):
		focused = v
		queue_redraw()
var _spin: float

func _ready() -> void:
	$Sprite.texture = Defs.tex(variant)
	# Rock art is drawn at Defs.ART_SCALE, so its world size (and the reserve
	# that size implies) comes from the texture divided by that.
	$Sprite.scale = Vector2.ONE / Defs.ART_SCALE
	radius = $Sprite.texture.get_width() / Defs.ART_SCALE / 2.0
	resource = "spice" if variant.begins_with("spice") else "minerals"
	var w: float = $Sprite.texture.get_width() / Defs.ART_SCALE
	var per_px2: float = Defs.ASTEROID_SPICE_PER_PX2 if resource == "spice" else Defs.ASTEROID_MINERALS_PER_PX2
	max_amount = int(round(w * w * per_px2 * richness / 10.0)) * 10
	amount = max_amount
	if Engine.is_editor_hint():
		return
	add_to_group("asteroids")
	_spin = randf_range(-0.25, 0.25)

func size_label() -> String:
	return "Large" if radius >= 12.0 else "Small"

func display_name() -> String:
	return "%s %s Asteroid" % [size_label(), "Spice" if resource == "spice" else "Mineral"]

## How many of `pid`'s barges are working this rock right now.
func miners_on(pid: int) -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid and s.is_miner() and s.mine_target == self:
			n += 1
	return n

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	$Sprite.rotation += _spin * delta
	if focused:
		queue_redraw()

func extract(n: int) -> int:
	var got := mini(n, amount)
	amount -= got
	if amount <= 0:
		if focused and is_instance_valid(Game.instance):
			Game.instance.clear_planet_focus()
		Game.instance.spawn_explosion(global_position, 0.5)
		queue_free()
	return got

func _draw() -> void:
	if Engine.is_editor_hint() or not focused:
		return
	# Selection ring plus a reserve bar under the rock.
	var col: Color = Defs.RESOURCE_COLORS[resource]
	var r := radius + 4.0
	var n := int(r * 1.6)
	for i in n:
		var a := TAU * i / n
		draw_rect(Rect2(Vector2.from_angle(a) * r - Vector2(0.5, 0.5), Vector2(1, 1)), col)
	var w := r * 2.0
	var y := r + 3.0
	draw_rect(Rect2(-r, y, w, 2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-r, y, w * float(amount) / maxf(max_amount, 1), 2), col)
