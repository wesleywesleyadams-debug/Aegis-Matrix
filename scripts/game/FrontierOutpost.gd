class_name FrontierOutpost
extends FortConstruct
## Frontier Outpost (Defs.FRONTIER_OUTPOST): half a starbase's guns (3 standard
## lasers) and most of its layers on a cheaper site, for holding a choke or a belt. It builds nothing,
## takes no deliveries and is not a starbase for winning or losing — it only
## shoots. Enemy ships auto-target it like a starbase (Game.fort_list).

var guns: ConstructGuns

func def() -> Dictionary:
	return Defs.FRONTIER_OUTPOST

func sprite_name() -> String:
	return "ship_frontier_outpost"

func _done_note() -> String:
	return "%s complete: it guards the space around it." % label()

## Construct weapon research (damage, range, fire rate) applies, as for a
## starbase's guns.
func weapon_range() -> float:
	return ConstructGuns.reach(owner_id, def())

func _operate(delta: float) -> void:
	if guns == null:
		guns = ConstructGuns.new(self, def()["guns"])
	guns.tick(def(), delta)
