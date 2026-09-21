@tool
extends MeshInstance3D
## Small RGB axis-direction gizmo (X=red, Y=green, Z=blue, arrowheads
## pointing toward the positive/"tip" direction) drawn at a grip point so
## weapon authoring can see exactly which local axis points which way once
## attached, and which end is the base (origin) vs. the tip (arrowhead).
## Lives as a child of the existing GripMarker sphere, so it inherits that
## node's visibility -- toggled by the same "Grip Points" debug flag (see
## Unit.gd's _on_grip_points_visibility_changed), no extra wiring needed.

@export var axis_length: float = 0.12

func _ready() -> void:
	mesh = _build_gizmo_mesh(axis_length)
	material_override = _build_material()

func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	return mat

func _build_gizmo_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	_add_axis(st, Vector3.RIGHT * length, Color(1.0, 0.2, 0.2))
	_add_axis(st, Vector3.UP * length, Color(0.2, 1.0, 0.2))
	_add_axis(st, Vector3.FORWARD * length, Color(0.3, 0.5, 1.0))
	return st.commit()

func _add_axis(st: SurfaceTool, tip: Vector3, color: Color) -> void:
	var dir: Vector3 = tip.normalized()
	var side: Vector3 = dir.cross(_any_perpendicular(dir)) * tip.length() * 0.18
	var back: Vector3 = tip - dir * (tip.length() * 0.3)
	for seg in [[Vector3.ZERO, tip], [tip, back + side], [tip, back - side]]:
		st.set_color(color)
		st.add_vertex(seg[0])
		st.set_color(color)
		st.add_vertex(seg[1])

func _any_perpendicular(dir: Vector3) -> Vector3:
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.9:
		up = Vector3.RIGHT
	return up
