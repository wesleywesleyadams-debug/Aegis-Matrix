class_name FrontierOutpost
extends FortConstruct
## Frontier Outpost (Defs.FRONTIER_OUTPOST): half a starbase's layers and
## gun on a cheaper site, for holding a choke or a belt. It builds nothing,
## takes no deliveries and is not a starbase for winning or losing — it only
## shoots. Enemy ships auto-target it like a starbase (Game.fort_list).

var _cooldown: float = 0.0

func def() -> Dictionary:
	return Defs.FRONTIER_OUTPOST

func sprite_name() -> String:
	return "ship_frontier_outpost"

func _done_note() -> String:
	return "%s complete: it guards the space around it." % label()

## Construct weapon research (damage, starbase range) applies, as for a
## starbase's gun.
func weapon_range() -> float:
	var g := Game.instance
	return def()["range"] * g.mod(owner_id, "range") * g.mod(owner_id, "structure_range")

func _operate(delta: float) -> void:
	var g := Game.instance
	_cooldown -= delta * g.ship_speed_factor(owner_id)
	if _cooldown > 0.0:
		return
	var e := g.nearest_enemy(self, weapon_range() + radius)
	if e == null:
		return
	_cooldown = def()["cooldown"]
	g.fire(self, e, def()["weapon"], def()["damage"] * g.mod(owner_id, "structure_damage"))
