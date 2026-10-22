class_name NebulaPocket
extends Node2D
## A spot inside a spice nebula where Gas Skimmers harvest spice gas (right-
## click in a nebula with skimmers selected). Behaves like an asteroid for
## mining (resource / amount / radius / extract). It drains the nebula cell it
## sits in (SpiceNebula.CELL); when that cell is empty it moves on to the
## nearest cell still holding gas, and the skimmers on it follow. `amount` is
## what the whole nebula has left: at 0 the skimmers find other work.

var resource: String = "spice"
var amount: int = 1
var radius: float = 18.0
## The nebula this spot drains (found on first use).
var nebula: SpiceNebula
## Nebula spice comes slowly: harvesters gather at Defs.HARVEST_NEBULA_MULT of
## their normal rate here (1.0: full rate).

func _ready() -> void:
	add_to_group("nebula_pockets")
	z_index = -1
	_attach()

## Finds the nebula with gas nearest this spot and moves onto that gas.
func _attach() -> void:
	var best_d := INF
	for n in get_tree().get_nodes_in_group("nebulae"):
		if n.depleted():
			continue
		var k = n.nearest_live_cell(global_position)
		if k == null:
			continue
		var d: float = n.cell_center(k).distance_to(global_position)
		if d < best_d:
			best_d = d
			nebula = n
	_settle()

## Onto a live cell: stay if this one still has gas, else move to the nearest
## one that does (the frontier of what has been harvested), and send the
## skimmers working here after it.
func _settle() -> void:
	if not is_instance_valid(nebula) or nebula.depleted():
		amount = 0
		return
	amount = maxi(1, int(ceil(nebula.remaining())))
	if float(nebula.cells.get(nebula.cell_of(global_position), 0.0)) > 0.0:
		return
	var k = nebula.nearest_live_cell(global_position)
	if k == null:
		amount = 0
		return
	global_position = nebula.cell_center(k)
	for s in get_tree().get_nodes_in_group("ships"):
		if s.get("mine_target") == self and s.state == Ship.State.MINING:
			s.state = Ship.State.MINE_GO

func extract(n: int) -> int:
	if not is_instance_valid(nebula):
		_attach()
		if not is_instance_valid(nebula):
			amount = 0
			return 0
	var got := int(round(nebula.drain_at(global_position, float(n))))
	_settle()
	if got <= 0 and amount > 0:
		got = int(round(nebula.drain_at(global_position, float(n))))
		_settle()
	if amount <= 0:
		queue_free()
	return got

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# A slow amber swirl marking the harvest spot.
	var t := Time.get_ticks_msec() / 1000.0
	for k in 3:
		var a := t * 0.8 + TAU * k / 3.0
		draw_arc(Vector2.ZERO, radius - k * 4.0, a, a + 2.0, 12, Color(1.0, 0.6, 0.2, 0.45 - k * 0.1), 1.5)
