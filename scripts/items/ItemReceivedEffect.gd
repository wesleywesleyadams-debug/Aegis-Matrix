extends RefCounted
class_name ItemReceivedEffect
## Brief "you just received this item" visual for a unit/building that just
## caught a thrown item (see RTSController._on_thrown_item_landed) -- a
## glowing, non-interactive copy of the item's equipped visual (not the
## pickup scene, since this has no collision/selection of its own) floats
## above the target for HOLD_DURATION seconds, then shrinks down into the
## target and is freed.

## How high above the target the effect floats while holding.
const FLOAT_HEIGHT: float = 2.2
## How much brighter than its own albedo the effect glows -- brighter than a
## map pickup's WorldItem.GLOW_ENERGY since this is meant to catch the eye.
const GLOW_ENERGY: float = 5.0
## How long the effect holds at full size above the target before shrinking.
const HOLD_DURATION: float = 2.0
## How long the shrink-into-target animation takes.
const SHRINK_DURATION: float = 0.35

## Instantiates `item_type`'s visual scene under `parent`, floats it above
## `target`, holds it there glowing for HOLD_DURATION seconds, then shrinks
## it down into `target` and frees it. No-op (returns null) for an unknown
## item_type.
static func spawn(item_type: String, target: Node3D, parent: Node) -> Node3D:
	var scene: PackedScene = ItemDefs.get_visual_scene(item_type)
	if scene == null:
		return null

	var effect := Node3D.new()
	parent.add_child(effect)
	var visual: Node3D = scene.instantiate()
	effect.add_child(visual)

	var float_position := target.global_position + Vector3(0, FLOAT_HEIGHT, 0)
	effect.global_position = float_position
	WorldItem.apply_glow(visual, GLOW_ENERGY)

	var tween := effect.create_tween()
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(effect, "scale", Vector3.ZERO, SHRINK_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(effect, "global_position", target.global_position, SHRINK_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(effect.queue_free)

	return effect
