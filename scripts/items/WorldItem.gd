extends Area3D
class_name WorldItem
## A pickup sitting on the map -- collected only by an explicit right-click
## pickup order (see RTSController._issue_pickup_order / Unit.pick_up_item),
## never by a unit merely wandering or pathing near it for some other
## reason. Raycast-targetable via ITEM_MASK (see collision_layer in
## SwordPickup.tscn/CrossbowPickup.tscn) so it can be clicked; no overlap
## detection needed since collection is order-driven, not proximity-driven.
## Not an Entity (no health/selection/etc.) -- just a trigger-free volume
## around whatever visual scene is instanced as its child (e.g.
## SwordPickup.tscn wraps Sword.tscn).

## Collision layer items sit on so a dedicated raycast (see
## RTSController._raycast_item) can find them; separate from
## GROUND_MASK(1)/UNIT_MASK(2)/SIGHT_OBSTACLE_MASK(8) in
## RTSController.gd/Entity.gd.
const ITEM_MASK: int = 16

## How much brighter than its own albedo the item glows while sitting on
## the map -- see _apply_glow(). Equipped weapons (Unit.equip_weapon
## instantiates a fresh, separate copy of the same visual scene) never go
## through this, so they stay their plain, unlit material.
const GLOW_ENERGY: float = 3.0

## How far above the ground a dropped item floats once it lands -- same
## offset the map's pre-placed pickups use (see Main.tscn), so a dropped
## item looks the same as one that was always sitting there.
const DROPPED_ITEM_HEIGHT: float = 0.5
## One grid tile -- matches DebugGrid's cell_size shader parameter and
## RTSController.FORMATION_SPACING. A dropped item lands one full tile
## behind whichever unit dropped it.
const TILE_SIZE: float = 2.6
## How high a dropped item pops up before settling into place.
const EJECT_HEIGHT: float = 1.2
## How long the eject-and-land animation takes, start to finish.
const EJECT_DURATION: float = 0.45

## Half-extent of the square selection frame -- items are small, so this is
## much tighter than Building's (2.6) equivalent.
const SELECTION_FRAME_SIZE: float = 0.7

@export var item_type: String = ""

## Clicking an item shows a square frame around it, same green-frame visual
## language as a Building's selection box -- see RTSController._select_item.
## Purely a "yes, this is what you clicked" indicator; items can't be
## commanded themselves (see Unit.pick_up_item for the actual order).
var selected: bool = false:
	set(value):
		selected = value
		if _selection_frame != null:
			_selection_frame.visible = value

var _selection_frame: Node3D = null

## How long each on/off phase of blink_selection() lasts.
const BLINK_INTERVAL: float = 0.15

## Flashes the selection frame on/off twice -- the feedback for "you just
## right-clicked this item" (see RTSController._issue_pickup_order), as
## opposed to selected's steady on/off for "this is what's clicked right
## now". Restores the frame to whatever `selected` actually is once done,
## so a blink on an already-selected item doesn't leave it stuck hidden.
func blink_selection(times: int = 2) -> void:
	if _selection_frame == null:
		return
	for i in times:
		_selection_frame.visible = true
		await get_tree().create_timer(BLINK_INTERVAL).timeout
		# The unit could easily reach and collect this item (freeing it)
		# mid-blink for a short trip -- bail out rather than touching a
		# freed node once the await resumes.
		if not is_instance_valid(self):
			return
		_selection_frame.visible = false
		await get_tree().create_timer(BLINK_INTERVAL).timeout
		if not is_instance_valid(self):
			return
	_selection_frame.visible = selected

func _ready() -> void:
	_apply_glow(self)
	_selection_frame = _build_selection_frame()
	add_child(_selection_frame)

## Builds a flat square frame (4 thin bars) the same way Building's does,
## just sized down to fit a small item instead of a building footprint.
## Raised to y=0.15 rather than sitting flush on the ground -- a frame at
## ground level renders underneath the ground plane's own top surface (see
## ParentBuilding.tscn's SelectionRing, which hit exactly this bug).
func _build_selection_frame() -> Node3D:
	var frame := Node3D.new()
	frame.position = Vector3(0, 0.15, 0)
	frame.visible = false

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3, 1, 0.4, 1)
	material.emission_enabled = true
	material.emission = Color(0.3, 1, 0.4, 1)
	material.emission_energy_multiplier = 1.5

	var s := SELECTION_FRAME_SIZE
	var bars := [
		{"position": Vector3(0, 0, -s), "size": Vector3(s * 2, 0.05, 0.06)},
		{"position": Vector3(0, 0, s), "size": Vector3(s * 2, 0.05, 0.06)},
		{"position": Vector3(-s, 0, 0), "size": Vector3(0.06, 0.05, s * 2)},
		{"position": Vector3(s, 0, 0), "size": Vector3(0.06, 0.05, s * 2)},
	]
	for bar in bars:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar["size"]
		mesh_instance.mesh = box
		mesh_instance.position = bar["position"]
		mesh_instance.material_override = material
		frame.add_child(mesh_instance)

	return frame

## Puts this item into `unit`'s weapon slot (swapping out and dropping
## whatever it already had equipped first, if anything) and removes this
## pickup from the world. Called once a unit's explicit pickup order (see
## Unit._update_pickup_target) actually gets it close enough.
func collect(unit: Unit) -> void:
	if not unit.equipped_weapon.is_empty():
		var old_item_type: String = unit.unequip_weapon()
		spawn_pickup(old_item_type, unit.global_position, unit.model_root.rotation.y, get_parent())
	unit.equip_weapon(item_type)
	queue_free()

## Instantiates `item_type`'s pickup scene under `parent` at `near_position`
## (the dropping unit's own position) and animates it popping up and
## landing one tile behind `facing_angle` (that unit's current facing --
## same snapped-angle convention as Entity._face_direction/model_root's own
## rotation.y) rather than just appearing there. No-op (returns null) for
## an unknown item_type.
static func spawn_pickup(item_type: String, near_position: Vector3, facing_angle: float, parent: Node) -> Node3D:
	var scene: PackedScene = ItemDefs.get_pickup_scene(item_type)
	if scene == null:
		return null
	var pickup: Node3D = scene.instantiate()
	parent.add_child(pickup)

	var behind := -Vector3(sin(facing_angle), 0.0, cos(facing_angle))
	var landing_position := near_position + behind * TILE_SIZE + Vector3(0, DROPPED_ITEM_HEIGHT, 0)
	pickup.global_position = near_position + Vector3(0, DROPPED_ITEM_HEIGHT, 0)

	var travel_tween := pickup.create_tween()
	travel_tween.set_parallel(true)
	travel_tween.tween_property(pickup, "global_position:x", landing_position.x, EJECT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	travel_tween.tween_property(pickup, "global_position:z", landing_position.z, EJECT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var hop_tween := pickup.create_tween()
	hop_tween.tween_property(pickup, "global_position:y", landing_position.y + EJECT_HEIGHT, EJECT_DURATION * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(pickup, "global_position:y", landing_position.y, EJECT_DURATION * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	return pickup

## Recursively duplicates and lights up every StandardMaterial3D under this
## pickup, so the shared material resource (also used by the equipped
## visual) is untouched -- only this specific pickup instance glows.
func _apply_glow(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var material: Material = node.get_surface_override_material(i)
			if material == null:
				material = node.mesh.surface_get_material(i)
			if material is StandardMaterial3D:
				var glow_material: StandardMaterial3D = material.duplicate()
				glow_material.emission_enabled = true
				glow_material.emission = glow_material.albedo_color
				glow_material.emission_energy_multiplier = GLOW_ENERGY
				node.set_surface_override_material(i, glow_material)
	for child in node.get_children():
		_apply_glow(child)
