class_name Minimap
extends Control
## Whole-map overview: planets, asteroid fields, ships and stations as
## pixel dots, plus the camera frustum. Click or drag to move the camera,
## right-click to issue a move order to the current selection (Ctrl for
## attack-move, Shift to queue it behind the current orders).

var game: Game
var _dragging := false

func _ready() -> void:
	custom_minimum_size = Vector2(HUD.MINIMAP_D, HUD.MINIMAP_D)
	clip_contents = true   # the corner mask and view frame stay inside
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _map_to_ui(p: Vector2) -> Vector2:
	var r := Game.MAP_RECT
	return (p - r.position) / r.size * size

func _ui_to_map(p: Vector2) -> Vector2:
	var r := Game.MAP_RECT
	return r.position + p / size * r.size

## Only the disc is map: clicks in the corners go to the game underneath.
func _has_point(p: Vector2) -> bool:
	return p.distance_to(size / 2.0) <= size.x / 2.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				game.center_on(_ui_to_map(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			game._issue_command(_ui_to_map(event.position), event.ctrl_pressed, event.shift_pressed)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		game.center_on(_ui_to_map(event.position))
		accept_event()

func _draw() -> void:
	draw_circle(size / 2.0, size.x / 2.0, Color("05050c"))
	var tree := game.get_tree()
	# Ion storms: active arms as blue wedges, a faint outline while building.
	for storm in tree.get_nodes_in_group("storms"):
		var sg: String = storm.stage(Game.now())
		if sg == "calm":
			continue
		var sc0 := _map_to_ui(storm.global_position)
		var ms := size.x / Game.MAP_RECT.size.x
		for arm in 2:
			var mid: float = storm.arm_angle(Game.now()) + PI * arm
			var pts := PackedVector2Array([sc0 + Vector2.from_angle(mid - IonStorm.HALF_WIDTH) * storm.inner * ms, sc0 + Vector2.from_angle(mid - IonStorm.HALF_WIDTH) * IonStorm.REACH * ms,
				sc0 + Vector2.from_angle(mid + IonStorm.HALF_WIDTH) * IonStorm.REACH * ms, sc0 + Vector2.from_angle(mid + IonStorm.HALF_WIDTH) * storm.inner * ms])
			draw_colored_polygon(pts, Color(0.5, 0.75, 1.0, 0.22 if sg == "active" else 0.07))
	# Debris rings: solid grey-brown band, gaps left open.
	for ring in tree.get_nodes_in_group("debris_rings"):
		var rc := _map_to_ui(ring.global_position)
		var rw: float = maxf(2.0, ring.width * size.x / Game.MAP_RECT.size.x)
		for i in 96:
			var a0 := TAU * i / 96.0
			if not ring.in_gap(a0 + TAU / 192.0):
				draw_arc(rc, ring.radius * size.x / Game.MAP_RECT.size.x, a0, a0 + TAU / 96.0, 3, Color("6e5c4a"), rw)
	# Spice nebulae as faint amber gas, whatever their shape.
	var msc := size.x / Game.MAP_RECT.size.x
	for neb in tree.get_nodes_in_group("nebulae"):
		neb.draw_on_map(self, _map_to_ui, msc)
	for star in tree.get_nodes_in_group("stars"):
		draw_circle(_map_to_ui(star.global_position), 3.0 + star.core_radius / 10.0, star.tint)
	# Asteroids as small blips in their resource's color (minerals teal,
	# spice orange).
	for a in tree.get_nodes_in_group("asteroids"):
		draw_rect(Rect2(_map_to_ui(a.global_position) - Vector2(1, 1), Vector2(2, 2)), Defs.RESOURCE_COLORS[a.resource])
	for p in tree.get_nodes_in_group("planets"):
		var c := Defs.team_color(p.shown_owner()) if p.shown_owner() != 0 else Color("7a809a")
		# Gas giants are mineral sources, so they get the minerals color.
		if not p.is_habitable():
			c = Defs.RESOURCE_COLORS["minerals"]
		var pos := _map_to_ui(p.global_position)
		draw_circle(pos, 4.0, Color("2a2e44"))
		draw_arc(pos, 5.0, 0, TAU, 16, c, 1.5)
	# Fog of war over the terrain (see Vision).
	if game.vision and game.vision.enabled:
		game.vision.draw_fog(self, Rect2(Vector2.ZERO, size), Vision.FOG_TINT_MAP)
	for sb in tree.get_nodes_in_group("starbases"):
		if not sb.visible:
			continue
		var pos := _map_to_ui(sb.global_position)
		draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), Defs.team_color(sb.owner_id))
		draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), Color.WHITE, false, 1.0)
	# Weapons Depots: a small hollow diamond in the owner's color.
	for dp in tree.get_nodes_in_group("depots"):
		if dp.visible:
			var dpos := _map_to_ui(dp.global_position)
			var dc := Defs.team_color(dp.owner_id)
			draw_polyline(PackedVector2Array([dpos + Vector2(0, -4), dpos + Vector2(4, 0), dpos + Vector2(0, 4), dpos + Vector2(-4, 0), dpos + Vector2(0, -4)]), dc, 1.5)
	for s in tree.get_nodes_in_group("ships"):
		if not s.visible:
			continue
		var c := Defs.team_color(s.owner_id)
		if s.selected:
			c = Color.WHITE
		draw_rect(Rect2(_map_to_ui(s.global_position) - Vector2(1, 1), Vector2(2, 2) if s.radius < 12 else Vector2(3, 3)), c)
	# Event flares (see Game.add_flare): red for alerts, light blue for
	# notifications. A bright dot plus rings pulsing outward, fading over
	# the flare's life. Real time, so they fade even while paused.
	var now_ms := Time.get_ticks_msec()
	for f in game.flares:
		var age := float(now_ms - f["ms"]) / Game.FLARE_MS
		if age >= 1.0:
			continue
		var p := _map_to_ui(f["pos"])
		var col: Color = f["color"]
		var fade := clampf(1.0 - age, 0.0, 1.0)
		fade = 0.45 + 0.55 * fade
		for k in 2:
			var ph := fmod(age * 4.0 + k * 0.5, 1.0)
			var c := col.lightened(0.15)
			c.a = fade * (1.0 - ph * 0.8)
			draw_arc(p, 4.0 + ph * 16.0, 0.0, TAU, 28, c, 2.5)
		var dot := col.lightened(0.3)
		dot.a = fade
		draw_circle(p, 3.5, dot)
	# Camera view rectangle.
	# The system is round (the HUD clips the minimap to its disc): ring the edge.
	var mid := size / 2.0
	draw_arc(mid, size.x * 0.5 - 0.5, 0, TAU, 96, Color(0.55, 0.65, 0.95, 0.5), 1.0)
	var cam := game.camera
	var view_size := game.get_viewport().get_visible_rect().size / cam.zoom
	var tl := _map_to_ui(cam.get_screen_center_position() - view_size / 2.0)
	var br := _map_to_ui(cam.get_screen_center_position() + view_size / 2.0)
	draw_rect(Rect2(tl, br - tl), Color(1, 1, 1, 0.8), false, 1.0)
