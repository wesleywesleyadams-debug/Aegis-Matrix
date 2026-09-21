extends MeshInstance3D
## Procedural lat/long wireframe capsule (PRIMITIVE_LINES), for debug hitbox
## visualization -- e.g. HurtboxMesh in ParentUnit.tscn -- in place of a
## solid translucent mesh. StandardMaterial3D has no built-in wireframe
## rendering mode in Godot 4, so this builds actual line geometry instead:
## a few latitude rings plus several longitude meridians tracing the
## capsule's silhouette, matching a classic hitbox-gizmo grid look.

@export var radius: float = 0.19
@export var height: float = 1.37
@export var longitude_count: int = 12
@export var latitude_rings_per_hemisphere: int = 2
@export var ring_segments: int = 24
@export var color: Color = Color(1, 1, 0, 1)

func _ready() -> void:
	mesh = _build_wireframe_capsule()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	material_override = mat

func _build_wireframe_capsule() -> ArrayMesh:
	var half_h := height * 0.5
	var cyl_half: float = maxf(half_h - radius, 0.0)
	var points := PackedVector3Array()

	# Longitude meridians -- each one traces the full silhouette profile
	# (bottom pole -> bottom hemisphere -> cylinder side -> top hemisphere
	# -> top pole) at a fixed azimuth, same idea as a sphere's meridian
	# lines but with a straight cylindrical section spliced into the middle.
	var profile_steps := 8
	for li in range(longitude_count):
		var theta: float = (float(li) / longitude_count) * TAU
		var cos_t: float = cos(theta)
		var sin_t: float = sin(theta)
		var profile: Array[Vector3] = []
		profile.append(Vector3(0, -half_h, 0))
		for s in range(1, profile_steps + 1):
			var phi: float = (float(s) / profile_steps) * (PI * 0.5)
			var r: float = radius * sin(phi)
			var y: float = -cyl_half - radius * cos(phi)
			profile.append(Vector3(r * cos_t, y, r * sin_t))
		profile.append(Vector3(radius * cos_t, cyl_half, radius * sin_t))
		for s in range(1, profile_steps + 1):
			var phi2: float = PI * 0.5 - (float(s) / profile_steps) * (PI * 0.5)
			var r2: float = radius * sin(phi2)
			var y2: float = cyl_half + radius * cos(phi2)
			profile.append(Vector3(r2 * cos_t, y2, r2 * sin_t))
		profile.append(Vector3(0, half_h, 0))
		for i in range(profile.size() - 1):
			points.append(profile[i])
			points.append(profile[i + 1])

	# Latitude rings -- the two hemisphere equators (top/bottom of the
	# cylinder) plus a couple of smaller rings climbing each hemisphere
	# toward its pole.
	var ring_ys: Array[float] = [-cyl_half, cyl_half]
	var ring_radii: Array[float] = [radius, radius]
	for hemi in [-1.0, 1.0]:
		for ri in range(1, latitude_rings_per_hemisphere + 1):
			var phi: float = (float(ri) / (latitude_rings_per_hemisphere + 1)) * (PI * 0.5)
			ring_radii.append(radius * sin(phi))
			ring_ys.append(hemi * cyl_half + hemi * radius * cos(phi))
	for idx in range(ring_ys.size()):
		var y: float = ring_ys[idx]
		var r: float = ring_radii[idx]
		for s in range(ring_segments):
			var a0: float = (float(s) / ring_segments) * TAU
			var a1: float = (float(s + 1) / ring_segments) * TAU
			points.append(Vector3(r * cos(a0), y, r * sin(a0)))
			points.append(Vector3(r * cos(a1), y, r * sin(a1)))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return array_mesh
