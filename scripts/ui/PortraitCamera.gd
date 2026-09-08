extends Camera3D
## Lives inside a SubViewport with cull_mask limited to the unit-portrait
## render layer (layer 2 -- see Unit.tscn's Body/FacingNose meshes, which
## belong to both layer 1 and layer 2 so the main camera and this one can
## each see them independently). Tracks whichever unit is the current
## portrait subject every frame, so the portrait panel shows a live,
## always-current render of that unit -- not a one-time snapshot that
## goes stale as it walks, turns, or gets replaced by a new selection.
##
## Positioned out along the unit's own facing direction (where its nose
## points) rather than a fixed world-space offset, so the portrait always
## shows the unit's front -- whatever angle it currently faces -- instead
## of sometimes catching it from the side or back.

const DISTANCE := 2.4
const HEIGHT := 1.3
const LOOK_AT_HEIGHT := 0.9

var _target: Node3D = null
var _target_model_root: Node3D = null

func set_target(unit: Node3D) -> void:
	_target = unit
	_target_model_root = unit.get_node("ModelRoot") if unit != null else null

func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var facing_y := _target_model_root.rotation.y if _target_model_root != null else 0.0
	# ModelRoot's local +Z (see Unit.tscn's FacingNose offset) is the
	# direction the nose points -- rotate that by the model's current
	# yaw to get the unit's actual world-space facing this frame.
	var forward := Vector3(0, 0, 1).rotated(Vector3.UP, facing_y)
	global_position = _target.global_position + forward * DISTANCE + Vector3(0, HEIGHT, 0)
	look_at(_target.global_position + Vector3(0, LOOK_AT_HEIGHT, 0), Vector3.UP)
