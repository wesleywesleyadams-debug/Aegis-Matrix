extends Node3D
class_name StorageFlag
## A small pole-and-pennant marker at a building's back top corner,
## shown only while Building.stored_items has at least one item in it
## (see Building._update_storage_flag) -- a passive "there's something
## in here" indicator visible from a distance, without having to select
## the building and open BuildingStoragePanel just to check. Pennant is
## tinted to the owning building's own player color (see
## Entity.PLAYER_COLORS) rather than a fixed color, so it reads as
## "this player's building has stored items" at a glance.

const SCENE: PackedScene = preload("res://scenes/StorageFlag.tscn")

@onready var pennant: MeshInstance3D = $Pennant

func set_color(color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	pennant.set_surface_override_material(0, material)

## Instantiates, parents, positions, and colors a flag in one call.
static func spawn(parent: Node3D, local_position: Vector3, color: Color) -> StorageFlag:
	var flag: StorageFlag = SCENE.instantiate()
	parent.add_child(flag)
	flag.position = local_position
	flag.set_color(color)
	return flag
