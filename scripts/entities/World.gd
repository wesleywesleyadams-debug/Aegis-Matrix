extends Entity
class_name World
## A static world object (trees, rocks, resource nodes, ...) -- not a
## player-built Building and not a mobile Unit. Joins the "world" group
## instead of "units"/"buildings", so RTSController's fog-of-war pass
## leaves it alone entirely: unlike an enemy Building it's never hidden or
## "remembered" once seen, since it's just always there -- the same way the
## ground itself is never hidden, only lit or unlit by whoever's nearby.

## Sub-type for display only (e.g. "pine", "oak") -- "" for a World
## object with no species concept (a rock). Shown in the hover tooltip
## title as "Pine Tree" rather than just "Tree" (see get_tooltip_title).
@export var species: String = ""

## How much of this resource is left to gather -- 0 for a World object
## that doesn't yield one at all (a decorative rock), in which case no
## Wood row shows in the tooltip (see get_tooltip_extra_stats). No
## actual gathering gameplay reads/depletes this yet; it's tooltip
## display only for now.
@export var max_wood: float = 0.0
var current_wood: float

func _ready() -> void:
	super._ready()
	add_to_group("world")
	current_wood = max_wood

func get_tooltip_title() -> String:
	var base_name := Entity.display_name_for(self)
	return "%s %s" % [species.capitalize(), base_name] if not species.is_empty() else base_name

func get_tooltip_extra_stats() -> Dictionary:
	return {"Wood": "%d/%d" % [current_wood, max_wood]} if max_wood > 0.0 else {}

## World objects never fight -- overriding both means neither an order to
## attack it (attack(), from Unit.gd's chase-and-attack override) nor its
## own defend-when-approached default (Entity._update_attack_target, via
## can_attack() gating perform_attack()) can ever land a swing.
func attack(_target: Node3D) -> void:
	pass

func can_attack() -> bool:
	return false
