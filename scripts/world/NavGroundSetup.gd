extends NavigationRegion3D
## Builds a simple walkable navmesh covering the whole ground plane.
## Good enough until real obstacles (buildings, terrain) need proper baking.

@export var ground_size: Vector2 = Vector2(60.0, 60.0)

func _ready() -> void:
	var navmesh := NavigationMesh.new()
	var half := ground_size * 0.5
	var vertices := PackedVector3Array([
		Vector3(-half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, half.y),
		Vector3(-half.x, 0.0, half.y),
	])
	navmesh.vertices = vertices
	navmesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation_mesh = navmesh
