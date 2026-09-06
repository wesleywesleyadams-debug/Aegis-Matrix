extends SubViewport
## Off-screen render target for capturing a still icon of any unit on
## demand -- shared by the selection tray so each slot shows that unit's
## real appearance (3D model or sprite) instead of a generic shape.
## Reuses the same render-layer-2 trick as PortraitCamera (see Unit.tscn
## and ParentUnit.tscn's Body/FacingNose/UnitSprite `layers` values) so it
## sees units' visuals independently of the main game camera, and frames
## them the same "facing the front" way PortraitCamera does.

const DISTANCE := 2.4
const HEIGHT := 1.3
const LOOK_AT_HEIGHT := 0.9

@onready var camera: Camera3D = $IconCamera

## Positions the shared camera at `unit`, waits for the render to
## actually land, and returns a still snapshot as an ImageTexture. Always
## await this -- capturing takes a couple of frames since the viewport
## has to actually render after the camera moves.
func capture_icon(unit: Node3D) -> ImageTexture:
	if unit == null or not is_instance_valid(unit):
		return null
	var model_root: Node3D = unit.get_node_or_null("ModelRoot")
	var facing_y: float = model_root.rotation.y if model_root != null else 0.0
	var forward := Vector3(0, 0, 1).rotated(Vector3.UP, facing_y)
	camera.global_position = unit.global_position + forward * DISTANCE + Vector3(0, HEIGHT, 0)
	camera.look_at(unit.global_position + Vector3(0, LOOK_AT_HEIGHT, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(unit):
		return null
	var img := get_texture().get_image()
	return ImageTexture.create_from_image(img)
