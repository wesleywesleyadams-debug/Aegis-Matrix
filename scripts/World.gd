extends Entity
class_name World
## A static world object (trees, rocks, resource nodes, ...) -- not a
## player-built Building and not a mobile Unit. Joins the "world" group
## instead of "units"/"buildings", so RTSController's fog-of-war pass
## leaves it alone entirely: unlike an enemy Building it's never hidden or
## "remembered" once seen, since it's just always there -- the same way the
## ground itself is never hidden, only lit or unlit by whoever's nearby.

func _ready() -> void:
	super._ready()
	add_to_group("world")

## World objects never fight -- overriding both means neither an order to
## attack it (attack(), from Unit.gd's chase-and-attack override) nor its
## own defend-when-approached default (Entity._update_attack_target, via
## can_attack() gating perform_attack()) can ever land a swing.
func attack(_target: Node3D) -> void:
	pass

func can_attack() -> bool:
	return false
