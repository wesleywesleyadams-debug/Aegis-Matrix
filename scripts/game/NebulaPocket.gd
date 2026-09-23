class_name NebulaPocket
extends Node2D
## A spot inside a spice nebula where Gas Skimmers harvest spice gas (right-
## click in a nebula with skimmers selected). Behaves like an asteroid for
## mining (resource / amount / radius / extract) but never runs dry.

var resource: String = "spice"
var amount: int = 1_000_000
var radius: float = 18.0
## Nebula spice never runs out, so it comes slowly: harvesters gather at
## Defs.HARVEST_NEBULA_MULT of their normal rate here.

func _ready() -> void:
	add_to_group("nebula_pockets")
	z_index = -1

func extract(n: int) -> int:
	return n

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# A slow amber swirl marking the harvest spot.
	var t := Time.get_ticks_msec() / 1000.0
	for k in 3:
		var a := t * 0.8 + TAU * k / 3.0
		draw_arc(Vector2.ZERO, radius - k * 4.0, a, a + 2.0, 12, Color(1.0, 0.6, 0.2, 0.45 - k * 0.1), 1.5)
