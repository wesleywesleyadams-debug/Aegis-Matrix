extends NavigationRegion3D
## Bakes the walkable navmesh from the actual static geometry in the scene
## -- the ground plane plus solid obstacles standing on it (buildings, the
## wall, trees; see NAV_SOURCE_GROUP) -- rather than one bare open
## rectangle. Recast voxelizes that geometry and carves out navmesh
## wherever an obstacle rises above the floor, so a unit's own
## path-following (see NavigationAgent3D.get_next_path_position(), used in
## Unit._current_desired_direction) actually routes around them instead of
## walking straight through.
##
## Parses each tagged node's own MeshInstance3D geometry (visual meshes,
## not collision shapes) rather than PARSED_GEOMETRY_STATIC_COLLIDERS --
## buildings/trees are CharacterBody3D (kinematic, not the "static" physics
## mode that collider-based parsing requires), so a collider-based bake
## silently skips them entirely and only picks up genuinely-static bodies
## like the Wall (confirmed headlessly: with collider-based parsing, a
## straight-line order across a building's own footprint sailed right
## through it -- the baked navmesh was a single unbroken open rectangle).
##
## Units themselves are never in this group, so they're never baked in as
## holes -- those are dynamic and handled by NavigationAgent3D's own RVO
## avoidance instead.
const NAV_SOURCE_GROUP: String = "nav_source"

## How tall a unit is treated as for clearance purposes -- an obstacle
## shorter than this wouldn't block a unit from walking under/over it, but
## every real obstacle here (buildings: 2m, the wall: 3m) is taller, so
## this only needs to clear a walking unit's own height.
const AGENT_HEIGHT: float = 1.8
## Matches NavigationAgent3D.radius on ParentUnit.tscn plus a small margin,
## so the baked walkable area is already inset far enough that a unit's own
## collision radius can't clip into an obstacle's edge.
const AGENT_RADIUS: float = 0.36

## Recast voxel size, deliberately finer than the navigation map's own
## 0.25 default -- see the bake-height bug this fixed, where the coarser
## default voxel height baked the walkable surface far enough above true
## ground level that a unit's real Y position never came within
## NavigationAgent3D's 3D arrival threshold of its first path corner,
## permanently stalling movement. The navigation MAP itself (not just this
## one region's mesh) must be told to use the same values, or the engine
## rasterizes obstacle edges against a mismatched grid -- confirmed
## headlessly via Godot's own "cell_size mismatch" warning, and units
## visibly failing to converge cleanly on a crowded target as a result.
const CELL_SIZE: float = 0.1
const CELL_HEIGHT: float = 0.05

func _ready() -> void:
	bake()

## Bakes (or re-bakes) the navmesh from whatever "nav_source"-tagged
## geometry currently exists in the tree -- pulled out of _ready() into
## its own callable method so a caller that dynamically adds/removes
## obstacles AFTER this node's own _ready() already ran (e.g.
## RTSController populating a custom map-editor-authored map, whose
## buildings/trees didn't exist yet when this node first baked) can
## call this again to pick them up. Synchronous (no callback) -- both
## calls block until done, which is fine for a one-time bake of a
## handful of static shapes.
func bake() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)

	var navmesh := NavigationMesh.new()
	navmesh.agent_height = AGENT_HEIGHT
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.cell_size = CELL_SIZE
	navmesh.cell_height = CELL_HEIGHT
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = NAV_SOURCE_GROUP

	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source_geometry, get_tree().root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source_geometry)

	navigation_mesh = navmesh
