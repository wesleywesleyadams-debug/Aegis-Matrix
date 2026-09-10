extends Node2D
## Draws a live blip for every unit/building at its ground-plane position,
## projected into the same isometric diamond shape the terrain itself
## forms under this game's camera (see Main.tscn's CameraRig/Camera3D
## transforms, and MinimapPanel/Frame's own git history for the
## derivation) -- world (x, z) -> local (x - z) * 0.7071068 on the
## diamond's horizontal axis, (x + z) * 0.4060 on its vertical axis.
## GROUND_HALF_EXTENT matches Main.tscn's Ground BoxMesh (60x60, centered
## on the origin); FILL_HALF_DIAGONAL matches Frame/Fill's own polygon
## points, so a unit at the very edge of the map lands exactly on the
## diamond's own edge, not outside or short of it. This node's own
## position should be set to the same center Border/Fill use (their
## Polygon2D position), so local (0, 0) here lines up with world (0, 0).

const GROUND_HALF_EXTENT: float = 30.0
const FILL_HALF_DIAGONAL: Vector2 = Vector2(199.0, 109.0)
## Blips are small squares, not circles -- reads as a cleaner, more
## "map icon" look at this size than a circle does, and matches
## strategy-game minimap convention (a dot per unit/building).
const BLIP_SIZE: float = 5.0

## The largest |raw projected offset| a point at the very edge of the
## ground plane reaches, before scaling into FILL_HALF_DIAGONAL -- see
## the class doc comment's projection formula.
const MAX_RAW: Vector2 = Vector2(2.0 * GROUND_HALF_EXTENT * 0.7071068, 2.0 * GROUND_HALF_EXTENT * 0.4060)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for group in ["units", "buildings"]:
		for entity in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(entity):
				continue
			var color: Color = Entity.PLAYER_COLORS.get(entity.player_id, Color.WHITE)
			var center := _project(entity.global_position)
			draw_rect(Rect2(center - Vector2.ONE * BLIP_SIZE / 2.0, Vector2.ONE * BLIP_SIZE), color)

func _project(world_pos: Vector3) -> Vector2:
	var raw := Vector2((world_pos.x - world_pos.z) * 0.7071068, (world_pos.x + world_pos.z) * 0.4060)
	return raw / MAX_RAW * FILL_HALF_DIAGONAL
