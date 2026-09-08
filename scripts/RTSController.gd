extends Node3D
## Click-select / drag-select / right-click-to-move RTS input handling.
## Ground = collision layer 1, units = collision layer 2.

const GROUND_MASK: int = 1
const UNIT_MASK: int = 2
const CLICK_DRAG_THRESHOLD: float = 6.0
## Spacing between spread-out unit destinations in a group move order --
## see _spread_offset.
const UNIT_SPREAD_SPACING: float = 2.6
## How far above a building's own origin its gather-point flag sits when
## the gather point is set directly onto that building (itself or another)
## -- buildings' global_position is at ground level, so without this the
## flag would plant at the building's base instead of visibly on top of it.
const GATHER_FLAG_BUILDING_HEIGHT: float = 2.0
## How often fog-of-war visibility is recomputed. It's an O(friendly x
## enemy) sweep with a line-of-sight raycast per pair (see
## _update_fog_of_war/_is_seen_by_any) -- units and vision don't change
## fast enough to need that every single frame at 60fps, so this throttles
## it to a still-responsive but far cheaper rate instead.
const FOG_UPDATE_INTERVAL: float = 0.15

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var selection_box: Control = $UI/SelectionBox
@onready var selection_panel: Control = $UI/SelectionPanel
@onready var portrait_panel: Control = $UI/PortraitPanel
@onready var equipment_panel: Control = $UI/EquipmentPanel/Background
@onready var storage_panel: Control = $UI/BuildingStoragePanel/Background
@onready var debug_grid: MeshInstance3D = $DebugGrid

var _selected_units: Array[Node] = []
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _fog_update_elapsed: float = 0.0

## Waypoint queues currently in progress, one entry per group of units
## that has outstanding shift-clicked waypoints:
## {"units": Array[Node], "waypoints": Array[Vector3],
##  "flags": Array[Node3D], "items": Array[WorldItem], "current_flag":
##  Node3D, "current_item": WorldItem}. "flags" holds one flag marker per
## pending (not yet dispatched) entry in "waypoints", in the same order;
## "items" parallels "waypoints" the same way -- null for an ordinary move
## waypoint, or the WorldItem to collect once the group actually reaches
## that leg, for a shift-queued pickup order (see _issue_pickup_order).
## "current_flag"/"current_item" mark whichever destination/item (if any)
## the group is actively traveling to and collecting right now. Keyed by
## group rather than a single global queue, so giving a different group
## its own order doesn't silently cancel another group's still-pending
## waypoints.
var _move_queues: Array[Dictionary] = []
## The one WorldItem currently showing its selection frame, or null. Kept
## separate from _selected_units (Units/Buildings only) since an item can't
## be commanded itself -- clicking one is purely a "here's what you clicked"
## indicator, not a selection you can issue orders from.
var _selected_item: WorldItem = null

func _ready() -> void:
	Music.play_track(Music.IN_GAME_TRACK)
	debug_grid.visible = GameState.show_debug_grid
	if GameState.load_on_start:
		GameState.load_on_start = false
		_load_save()
	else:
		_apply_starting_unit_count()
	_assign_players()

	equipment_panel.item_right_clicked.connect(_on_equipment_item_right_clicked)
	_refresh_equipment_panel()
	storage_panel.item_right_clicked.connect(_on_storage_item_right_clicked)
	_refresh_storage_panel()

	# So a pickup landing directly in a unit's weapon slot (see WorldItem.gd)
	# updates the equipment panel immediately if that unit happens to be
	# selected, without the panel needing to poll every frame.
	for unit in get_tree().get_nodes_in_group("units"):
		unit.weapon_changed.connect(_on_unit_weapon_changed)
		unit.item_thrown.connect(_on_unit_item_thrown)
	# Same idea for a building's storage panel -- a drag-drop landing an
	# item in storage updates the panel live if that building is selected.
	for building in get_tree().get_nodes_in_group("buildings"):
		building.storage_changed.connect(_on_building_storage_changed)

## Splits whatever roster remains (after trimming/loading) evenly between
## the two players -- first half Player 1, second half Player 2 (Player 1
## gets the extra unit on an odd count). Recomputed fresh each match rather
## than persisted through saves, since save files don't carry player_id yet.
func _assign_players() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var player1_count: int = int(ceil(units.size() / 2.0))
	for i in units.size():
		units[i].player_id = 1 if i < player1_count else 2

## Trims the Units roster down to the lobby's chosen starting count,
## removing from the end (Unit8, Unit7, ...) so the frontmost/first units
## in the scene -- including the one peasant -- are always kept. Skipped
## entirely when loading a save, since a save already has its own exact
## roster to restore.
func _apply_starting_unit_count() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var keep: int = clampi(GameState.starting_unit_count, 1, units.size())
	for i in range(units.size() - 1, keep - 1, -1):
		units[i].queue_free()

## Restores each unit's position and health from the last save, matching
## saved entries to current units by index -- both this and MainMenu's
## save logic iterate get_tree().get_nodes_in_group("units") in the same
## (scene-tree) order, so this only works correctly against a freshly
## loaded scene with the same unit roster the save was taken from.
func _load_save() -> void:
	var path := GameState.load_save_path
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed.has("units"):
		return

	var units_data: Array = parsed["units"]
	var units := get_tree().get_nodes_in_group("units")
	var n: int = mini(units.size(), units_data.size())
	for i in n:
		var unit = units[i]
		var data: Dictionary = units_data[i]
		var pos: Array = data["position"]
		unit.global_position = Vector3(pos[0], pos[1], pos[2])
		unit.max_health = data["max_health"]
		unit.current_health = data["current_health"]
		unit.health_bar.set_health_fraction(unit.current_health / unit.max_health)

	if parsed.has("elapsed_time"):
		$UI/GameTimer.set_elapsed(parsed["elapsed_time"])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_grid"):
		GameState.show_debug_grid = not GameState.show_debug_grid
		debug_grid.visible = GameState.show_debug_grid
		return
	if event is InputEventKey and event.keycode == KEY_H and event.pressed and not event.echo:
		_halt_selected_units()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start = event.position
				selection_box.drag_start = event.position
				selection_box.drag_end = event.position
				selection_box.visible = true
				selection_box.queue_redraw()
			else:
				_finish_drag_select(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		selection_box.drag_end = event.position
		selection_box.queue_redraw()

func _process(delta: float) -> void:
	_fog_update_elapsed += delta
	if _fog_update_elapsed >= FOG_UPDATE_INTERVAL:
		_fog_update_elapsed = 0.0
		_update_fog_of_war()

	_prune_selected_units()

	for i in range(_move_queues.size() - 1, -1, -1):
		var q: Dictionary = _move_queues[i]
		var units: Array = q["units"]
		# Drop units that no longer exist (e.g. destroyed mid-route, once
		# combat exists) rather than letting them stall the queue forever.
		for j in range(units.size() - 1, -1, -1):
			if not is_instance_valid(units[j]):
				units.remove_at(j)
		if units.is_empty():
			_free_queue_flags(q)
			_move_queues.remove_at(i)
			continue

		var all_finished := true
		for unit in units:
			if not unit.nav_agent.is_navigation_finished():
				all_finished = false
				break
		if not all_finished:
			continue

		var waypoints: Array = q["waypoints"]
		if waypoints.is_empty():
			# Final destination reached with nothing queued after it --
			# the flag has done its job, and this queue entry is done.
			_free_flag(q["current_flag"])
			_move_queues.remove_at(i)
			continue

		# The whole group has finished its current leg -- move on to the
		# next queued waypoint. The flag marking it is already there from
		# when it was queued; just promote it to be the current-leg flag
		# instead of spawning a new one, and remove the one for the leg
		# that was just completed.
		_free_flag(q["current_flag"])
		var next_target: Vector3 = waypoints.pop_front()
		var flags: Array = q["flags"]
		q["current_flag"] = flags.pop_front()
		var items: Array = q["items"]
		var next_item: WorldItem = items.pop_front()
		q["current_item"] = next_item
		_renumber_flags(q)
		if next_item != null and is_instance_valid(next_item):
			for unit in units:
				unit.pick_up_item(next_item)
			next_item.blink_selection()
		else:
			_dispatch_move(next_target, units)

## Frees every flag (current and still-queued) belonging to one queue
## entry -- used when the whole queue is dropped (e.g. its units no
## longer exist) so no flags are left behind marking a route nobody is
## following anymore.
func _free_queue_flags(q: Dictionary) -> void:
	_free_flag(q["current_flag"])
	for flag in q["flags"]:
		_free_flag(flag)

func _free_flag(flag: Node3D) -> void:
	if flag != null and is_instance_valid(flag):
		flag.queue_free()

func _spawn_flag(world_position: Vector3) -> Node3D:
	return WaypointFlag.spawn(self, world_position)

## Keeps each flag's number matching its position in the route: 1 for the
## leg currently being traveled to, 2 for the next one queued after it,
## and so on. Called whenever a queue's flags change (appended to,
## advanced past one) so the numbers always reflect the current order.
func _renumber_flags(q: Dictionary) -> void:
	var current_flag: Node3D = q["current_flag"]
	if current_flag != null and is_instance_valid(current_flag):
		current_flag.set_number(1)
	var flags: Array = q["flags"]
	for i in flags.size():
		if is_instance_valid(flags[i]):
			flags[i].set_number(i + 2)

func _finish_drag_select(release_pos: Vector2) -> void:
	_dragging = false
	selection_box.visible = false
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	var drag_size := (release_pos - _drag_start).length()

	if drag_size < CLICK_DRAG_THRESHOLD:
		var clicked := _raycast_unit(release_pos)
		if clicked:
			if not shift_held:
				_clear_selection()
			_clear_item_selection()
			_select_unit(clicked)
		else:
			var clicked_item := _raycast_item(release_pos)
			if clicked_item != null:
				_select_item(clicked_item)
			else:
				if not shift_held:
					_clear_selection()
				_clear_item_selection()
	else:
		if not shift_held:
			_clear_selection()
		_clear_item_selection()
		var rect := Rect2(
			Vector2(min(_drag_start.x, release_pos.x), min(_drag_start.y, release_pos.y)),
			(release_pos - _drag_start).abs()
		)

		var units_in_box: Array = []
		for unit in get_tree().get_nodes_in_group("units"):
			if not camera.is_position_behind(unit.global_position):
				var screen_pos := camera.unproject_position(unit.global_position)
				if rect.has_point(screen_pos):
					units_in_box.append(unit)

		if not units_in_box.is_empty():
			# Units in the box always win outright -- any buildings also
			# caught in the same box are ignored entirely, not just
			# deprioritized.
			for unit in units_in_box:
				_select_unit(unit)
		else:
			# No units in the box -- fall back to buildings, but only ever
			# add ONE per drag (buildings aren't meant to swarm-select like
			# units). Repeatedly shift-dragging is how you build up a
			# multi-building selection, one at a time.
			for building in get_tree().get_nodes_in_group("buildings"):
				if not camera.is_position_behind(building.global_position):
					var screen_pos := camera.unproject_position(building.global_position)
					if rect.has_point(screen_pos):
						_select_unit(building)
						break

## The 'h' hotkey: cancels whatever order(s) each currently selected entity
## has outstanding -- only the current selection, nothing else on the map.
## Selected (mobile) units drop any queued waypoints and halt in place
## immediately; selected buildings have their gather point (their only
## standing order) cleared.
func _halt_selected_units() -> void:
	var movable: Array[Node] = []
	var buildings: Array[Node] = []
	for entity in _selected_units:
		if entity is Building:
			buildings.append(entity)
		else:
			movable.append(entity)
	if movable.is_empty() and buildings.is_empty():
		return

	# Pull halted units out of any queue they're part of -- rather than
	# dropping the whole queue -- so any other, still-going units that
	# happened to share that group order keep running their remaining legs.
	for i in range(_move_queues.size() - 1, -1, -1):
		var q: Dictionary = _move_queues[i]
		var units: Array = q["units"]
		for unit in movable:
			units.erase(unit)
		if units.is_empty():
			_free_queue_flags(q)
			_move_queues.remove_at(i)

	for unit in movable:
		unit.stop()
	for building in buildings:
		building.clear_gather_point()

## Routes a right-click to whichever of the two things it can mean,
## splitting the current selection by kind first so buildings (which have
## no move/attack interface at all -- see Building/Entity) never get
## handed to the unit-only order functions:
## - Any selected buildings get a gather point set/queued to wherever was
##   clicked -- plain click replaces their whole gather queue with this one
##   point, shift-click appends it, same as a unit's move-order queue.
##   Clicking directly on a building -- friendly or enemy, including one of
##   the buildings currently selected -- snaps the point exactly onto it
##   (flag shown floating above its roof) rather than the approximate
##   ground position underneath; clicking an enemy unit uses its position;
##   otherwise it's wherever the ground raycast landed.
## - Any selected (mobile) units get the usual move/attack order. Clicking
##   directly on a building sends them to a flag snapped onto it (same
##   top-center spot/height as the building-to-building case above) instead
##   of the ground position underneath.
func _handle_right_click(screen_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return

	var selected_movable: Array[Node] = []
	var selected_buildings: Array[Node] = []
	for entity in _selected_units:
		if entity is Building:
			selected_buildings.append(entity)
		else:
			selected_movable.append(entity)

	var enemy := _raycast_enemy_unit(screen_pos)

	if not selected_buildings.is_empty():
		var clicked_building := _raycast_building(screen_pos)
		var gather_target: Vector3 = Vector3.INF
		if clicked_building != null:
			gather_target = clicked_building.global_position + Vector3(0, GATHER_FLAG_BUILDING_HEIGHT, 0)
		elif enemy != null:
			gather_target = enemy.global_position
		else:
			var hit := _raycast(screen_pos, GROUND_MASK)
			if not hit.is_empty():
				gather_target = hit["position"]
		if gather_target != Vector3.INF:
			var append_gather := Input.is_key_pressed(KEY_SHIFT)
			for building in selected_buildings:
				if append_gather:
					building.queue_gather_point(gather_target)
				else:
					building.set_gather_point(gather_target)

	if selected_movable.is_empty():
		return
	if enemy != null:
		_issue_attack_order(selected_movable, enemy)
		return

	# Clicking directly on a world item sends the group to walk to and
	# collect it (see Unit.pick_up_item) -- an explicit order, not the mere
	# proximity-triggered pickup this used to be.
	var clicked_item := _raycast_item(screen_pos)
	if clicked_item != null:
		_issue_pickup_order(selected_movable, clicked_item, Input.is_key_pressed(KEY_SHIFT))
		return

	# Clicking directly on a building sends the group to a flag snapped onto
	# it (top-center, same as a building-to-building gather point) instead
	# of the approximate ground position underneath -- reuses the same
	# _raycast_building() lookup and height offset _handle_right_click
	# already uses for that building case above.
	var clicked_building := _raycast_building(screen_pos)
	var move_target: Vector3
	if clicked_building != null:
		move_target = clicked_building.global_position + Vector3(0, GATHER_FLAG_BUILDING_HEIGHT, 0)
	else:
		var hit := _raycast(screen_pos, GROUND_MASK)
		if hit.is_empty():
			return
		move_target = hit["position"]
	_issue_move_order(selected_movable, move_target, Input.is_key_pressed(KEY_SHIFT))

## Handles a right-click move order. Plain right-click cancels this
## group's queue (if any) and moves immediately; shift-right-click instead
## appends the clicked point as a waypoint to run after whatever this
## exact group of units is currently doing -- classic queued-order
## movement. A shift-click against a selection with no queue of its own
## yet has nothing to append to, so it starts a fresh order (and a fresh,
## empty queue ready to receive further shift-clicks) instead.
func _issue_move_order(units: Array[Node], target: Vector3, append_to_queue: bool) -> void:
	if units.is_empty():
		return

	var existing_index := _find_queue_index(units)
	if append_to_queue and existing_index != -1:
		var q: Dictionary = _move_queues[existing_index]
		(q["waypoints"] as Array).append(target)
		(q["flags"] as Array).append(_spawn_flag(target))
		(q["items"] as Array).append(null)
		_renumber_flags(q)
		return

	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var new_queue := {
		"units": units.duplicate(),
		"waypoints": [],
		"flags": [],
		"items": [],
		"current_flag": _spawn_flag(target),
		"current_item": null,
	}
	_move_queues.append(new_queue)
	_renumber_flags(new_queue)
	_dispatch_move(target, units)

## Index into _move_queues whose "units" exactly matches `units` (same
## members, any order), or -1 if this exact group has no queue going.
func _find_queue_index(units: Array[Node]) -> int:
	for i in _move_queues.size():
		if _same_units(_move_queues[i]["units"], units):
			return i
	return -1

func _same_units(a: Array, b: Array[Node]) -> bool:
	if a.size() != b.size():
		return false
	for unit in a:
		if not unit in b:
			return false
	return true

## The actual move-order logic. Takes `units` explicitly rather than
## reading _selected_units directly so a queued waypoint can be dispatched
## later to whichever units it was issued for, even if the player's
## current selection has since changed.
##
## Each unit gets its own destination, spread around `target` in a simple
## grid (see _spread_offset) rather than every unit in the group being
## sent to the exact same point. Without this, a multi-unit move order
## left every unit trying to stand on top of the same coordinate, so they
## piled up and jostled indefinitely with only avoidance keeping them
## apart. This intentionally doesn't do full formation-keeping (no rank
## ordering, no shared marching path, no orienting to the direction of
## travel) -- just enough that each unit has a distinct spot to actually
## reach, still using its own ordinary move_to() (nav agent + octile path
## + avoidance all still apply per unit).
func _dispatch_move(target: Vector3, units: Array[Node]) -> void:
	var count := units.size()
	for i in count:
		units[i].move_to(target + _spread_offset(i, count))

## A simple centered grid offset for spreading `count` units' destinations
## around a shared point, indexed 0..count-1. Spacing is wide enough that
## a unit's own collision radius (see ParentUnit.tscn) doesn't overlap its
## neighbors' slots, so units settle into place without needing to shove
## each other aside once they arrive.
func _spread_offset(index: int, count: int) -> Vector3:
	if count <= 1:
		return Vector3.ZERO
	var columns := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / columns))
	var row := index / columns
	var col := index % columns
	var x := (col - (columns - 1) / 2.0) * UNIT_SPREAD_SPACING
	var z := (row - (rows - 1) / 2.0) * UNIT_SPREAD_SPACING
	return Vector3(x, 0.0, z)

## Player 1 is the only player the human controls right now -- Player 2's
## units exist (visually marked by a different belt color) but can't be
## selected or ordered yet, since there's no AI to give them anything to
## do against. World objects (trees, etc.) are excluded outright, on top of
## that ownership check -- they're Nature-owned incidentally, but the real
## reason is that they're static scenery, not a commandable unit/building,
## so selecting one and right-clicking should never be able to task it.
func _on_unit_weapon_changed(unit: Unit) -> void:
	if unit == _first_selected_unit():
		_refresh_equipment_panel()

func _first_selected_unit() -> Unit:
	for entity in _selected_units:
		if entity is Unit:
			return entity
	return null

func _first_selected_building() -> Building:
	for entity in _selected_units:
		if entity is Building:
			return entity
	return null

## Refreshes the equipment panel to show the first selected unit's equipped
## weapon (or empty, if no unit -- just a building/World object, or nothing
## at all -- is selected).
func _refresh_equipment_panel() -> void:
	equipment_panel.refresh(_first_selected_unit())

## Refreshes the storage panel to show the first selected building's stored
## items (or hides it entirely -- see BuildingStoragePanel.refresh -- if no
## building is selected).
func _refresh_storage_panel() -> void:
	storage_panel.refresh(_first_selected_building())

func _on_building_storage_changed(building: Building) -> void:
	if building == _first_selected_building():
		_refresh_storage_panel()

## Right-clicking the equipped item in the equipment panel: takes it off
## the unit and drops it on the ground at the unit's feet as a pickup again
## -- the opposite of walking onto one.
func _on_equipment_item_right_clicked(item_type: String) -> void:
	var unit := _first_selected_unit()
	if unit == null or unit.equipped_weapon != item_type:
		return
	unit.unequip_weapon()
	_refresh_equipment_panel()
	WorldItem.spawn_pickup(item_type, unit.global_position, unit.model_root.rotation.y, $World)

## Right-clicking a stored item in the storage panel: takes it out of the
## building and drops it on the ground at the building's feet, same
## "opposite of walking onto one" pattern as the equipment panel's version.
func _on_storage_item_right_clicked(item_type: String) -> void:
	var building := _first_selected_building()
	if building == null or not building.take_item(item_type):
		return
	_refresh_storage_panel()
	WorldItem.spawn_pickup(item_type, building.global_position, building.model_root.rotation.y, $World)

## Dragging an item out of the equipment panel or building storage panel
## (see ItemDropTarget/ItemSlotButton) and releasing it at `screen_pos`.
## Exactly one of source_unit/source_building is set (whichever panel it
## came from). A unit source issues a throw order (see
## Unit.throw_item/_on_unit_item_thrown) -- the unit has to actually walk
## within throwing range before the item leaves its hand, rather than it
## teleporting there instantly. A building can't walk anywhere, so a
## building source throws immediately instead, but that throw is capped to
## the same one-tile range a unit has to close in to (see
## _throw_from_building) -- a building can eject an item to its own
## doorstep, not fling it anywhere on the map.
func handle_item_drag_drop(item_type: String, source_unit: Unit, source_building: Building, screen_pos: Vector2) -> void:
	if is_instance_valid(source_unit):
		if source_unit.equipped_weapon != item_type:
			return
		var target := _resolve_drop_target(screen_pos, source_unit)
		source_unit.throw_item(item_type, target["position"], target["unit"], target["building"])
	elif is_instance_valid(source_building):
		if not source_building.take_item(item_type):
			return
		_refresh_storage_panel()
		var target := _resolve_drop_target(screen_pos, source_building)
		_throw_from_building(item_type, source_building, target)

## Resolves what's at `screen_pos` in the world for a drag-drop -- a
## unit/building to hand the item to, or bare ground otherwise. Shared by
## the unit-source (throw order) and building-source (instant placement)
## cases. exclude_node keeps dragging an item onto its own source (e.g. a
## unit dragging its weapon onto itself) from being treated as a valid
## target, falling through to the ground instead, same as the
## pre-drag-and-drop right-click-to-drop behavior would. Same fallback for
## anything not player-controlled -- items can't be handed to another
## player's (or Nature/Mob's) units/buildings, only placed on the ground
## near them.
func _resolve_drop_target(screen_pos: Vector2, exclude_node: Node3D) -> Dictionary:
	var target_node := _raycast_unit(screen_pos)
	if target_node is Unit and target_node != exclude_node and target_node.is_player_controlled():
		return {"position": target_node.global_position, "unit": target_node, "building": null}
	if target_node is Building and target_node != exclude_node and target_node.is_player_controlled():
		return {"position": target_node.global_position, "unit": null, "building": target_node}
	var ground_hit := _raycast(screen_pos, GROUND_MASK)
	var position: Vector3 = ground_hit["position"] if not ground_hit.is_empty() else exclude_node.global_position
	return {"position": position, "unit": null, "building": null}

## The building-storage drag source's counterpart to a unit's throw_item()
## order -- a stationary building can't walk closer first, so it throws
## right away, but the throw is capped to Unit.THROW_RANGE (one tile) from
## the building itself. A target beyond that range is unreachable: the
## hand-off to whatever was aimed at is dropped, and the throw lands short,
## at the building's max range in that direction, as a plain ground pickup
## instead -- the same "can't reach it" outcome a unit would have if it
## simply couldn't move any closer.
func _throw_from_building(item_type: String, building: Building, target: Dictionary) -> void:
	var target_unit: Unit = target["unit"]
	var target_building: Building = target["building"]
	var target_position: Vector3 = target["position"]

	var offset := target_position - building.global_position
	offset.y = 0.0
	if offset.length() > Unit.THROW_RANGE:
		target_unit = null
		target_building = null
		target_position = building.global_position + offset.normalized() * Unit.THROW_RANGE

	WorldItem.spawn_thrown(
		item_type, building.global_position, target_position, $World,
		_on_thrown_item_landed.bind(target_unit, target_building)
	)

## A unit's throw_item() order actually landing (see Unit.item_thrown) --
## spawns the visible thrown item traveling from the unit to the target
## point, and hands it off to whatever the throw was aimed at once the
## animation finishes (see _on_thrown_item_landed), same end states
## _throw_from_building reaches, just with walking time first.
func _on_unit_item_thrown(unit: Unit, item_type: String, target_position: Vector3, target_unit: Unit, target_building: Building) -> void:
	_refresh_equipment_panel()
	WorldItem.spawn_thrown(
		item_type, unit.global_position, target_position, $World,
		_on_thrown_item_landed.bind(target_unit, target_building)
	)

## Re-checks target_unit/target_building are still valid (and still
## player-controlled -- see _resolve_drop_target) at landing time, in case
## either died/was destroyed during the throw's travel time, before handing
## the item over -- otherwise it just stays a normal ground pickup where it
## landed, same as aiming at bare ground in the first place.
func _on_thrown_item_landed(pickup: Node3D, target_unit: Unit, target_building: Building) -> void:
	if not is_instance_valid(pickup):
		return
	var item_type: String = pickup.item_type
	if is_instance_valid(target_unit) and target_unit.is_player_controlled():
		if not target_unit.equipped_weapon.is_empty():
			var displaced: String = target_unit.unequip_weapon()
			WorldItem.spawn_pickup(displaced, target_unit.global_position, target_unit.model_root.rotation.y, $World)
		target_unit.equip_weapon(item_type)
		pickup.queue_free()
		_refresh_equipment_panel()
		ItemReceivedEffect.spawn(item_type, target_unit)
	elif is_instance_valid(target_building) and target_building.is_player_controlled():
		target_building.store_item(item_type)
		pickup.queue_free()
		ItemReceivedEffect.spawn(item_type, target_building)
		_refresh_storage_panel()

## Shows `item`'s selection frame, clearing any unit/building selection
## first -- items and units/buildings are never selected at the same time,
## since an item selection can't be given orders anyway.
func _select_item(item: WorldItem) -> void:
	if _selected_item == item:
		return
	_clear_item_selection()
	_clear_selection()
	_selected_item = item
	item.selected = true

func _clear_item_selection() -> void:
	if _selected_item != null and is_instance_valid(_selected_item):
		_selected_item.selected = false
	_selected_item = null

func _select_unit(unit: Node) -> void:
	if unit is World:
		return
	if not unit.is_player_controlled():
		return
	if unit in _selected_units:
		return
	_selected_units.append(unit)
	unit.selected = true
	selection_panel.set_selected_units(_selected_units)
	portrait_panel.set_subject(_selected_units[0])
	_refresh_equipment_panel()
	_refresh_storage_panel()

## Removes any selected unit that's since been freed (a unit only
## queue_free()s once its death animation actually finishes -- see
## Entity._die() -- not the instant its health hits 0) from
## _selected_units, and pushes the cleaned list to every panel that reads
## it. Run every frame, not just in response to explicit selection
## changes, since a selected unit can die mid-fight without the player
## touching selection at all -- without this, SelectionPanel's _draw()
## (which redraws periodically on its own timer, independent of selection
## changes) would try to read a property off an already-freed node and
## error every single frame from then on, which is exactly what caused a
## crash: a unit died while selected, its stale reference sat in
## _selected_units, and SelectionPanel kept hitting it on every redraw.
func _prune_selected_units() -> void:
	var had_invalid := false
	for i in range(_selected_units.size() - 1, -1, -1):
		if not is_instance_valid(_selected_units[i]):
			_selected_units.remove_at(i)
			had_invalid = true
	if not had_invalid:
		return
	selection_panel.set_selected_units(_selected_units)
	portrait_panel.set_subject(_selected_units[0] if not _selected_units.is_empty() else null)
	_refresh_equipment_panel()
	_refresh_storage_panel()

func _clear_selection() -> void:
	for unit in _selected_units:
		if is_instance_valid(unit):
			unit.selected = false
	_selected_units.clear()
	selection_panel.set_selected_units(_selected_units)
	portrait_panel.set_subject(null)
	_refresh_equipment_panel()
	_refresh_storage_panel()

func _raycast_unit(screen_pos: Vector2) -> Node3D:
	var hit := _raycast(screen_pos, UNIT_MASK)
	if not hit.is_empty():
		var collider: Node3D = hit["collider"]
		# Fog of war hides this entity (see _update_fog_of_war) -- an entity
		# you can't see shouldn't be clickable either.
		if collider.visible:
			return collider
	return _find_nearest_unit_to_ray(screen_pos)

## Widens the effective click target for units/buildings beyond their
## exact collision capsule (radius 0.38 for a Unit -- see
## CollisionShape3D/NavigationAgent3D in ParentUnit.tscn -- noticeably
## narrower than the visible armor at its shoulders/edges), only used once
## a direct raycast against that capsule has already missed. Finds
## whichever visible entity's world position passes closest to the click
## ray (not the capsule's own surface), within UNIT_CLICK_TOLERANCE,
## measured at roughly chest height (SIGHT_RAY_HEIGHT-ish) rather than at
## the feet, since that's where most of a standing entity's visible bulk
## actually is.
const UNIT_CLICK_TOLERANCE: float = 0.5
const UNIT_CLICK_HEIGHT: float = 0.9

func _find_nearest_unit_to_ray(screen_pos: Vector2) -> Node3D:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best: Node3D = null
	var best_dist := UNIT_CLICK_TOLERANCE
	var candidates: Array = get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("buildings")
	for entity in candidates:
		if not is_instance_valid(entity) or not entity.visible:
			continue
		var target_point: Vector3 = entity.global_position + Vector3(0, UNIT_CLICK_HEIGHT, 0)
		var t := (target_point - origin).dot(dir)
		if t <= 0.0:
			continue
		var closest_point_on_ray := origin + dir * t
		var dist := closest_point_on_ray.distance_to(target_point)
		if dist < best_dist:
			best_dist = dist
			best = entity
	return best

## Reveals/hides every non-human-owned unit and building based on whether
## any human-owned entity currently has it within vision_range and a clear
## has_line_of_sight() to it. Enemy units vanish the instant they drop out
## of vision; enemy buildings, once seen, stay visible at their last-known
## position/state (Building.ever_seen) since they don't move -- unlike
## units, "remembering" a building costs nothing extra to get right.
func _update_fog_of_war() -> void:
	var friendly: Array = []
	for entity in get_tree().get_nodes_in_group("units"):
		if entity.is_player_controlled():
			friendly.append(entity)
	for entity in get_tree().get_nodes_in_group("buildings"):
		if entity.is_player_controlled():
			friendly.append(entity)

	for unit in get_tree().get_nodes_in_group("units"):
		if unit.is_player_controlled():
			continue
		unit.visible = _is_seen_by_any(unit, friendly)

	for building in get_tree().get_nodes_in_group("buildings"):
		if building.is_player_controlled():
			continue
		if _is_seen_by_any(building, friendly):
			building.ever_seen = true
		building.visible = building.ever_seen

func _is_seen_by_any(entity: Node3D, friendly: Array) -> bool:
	for watcher in friendly:
		if not is_instance_valid(watcher):
			continue
		if watcher.global_position.distance_to(entity.global_position) > watcher.vision_range:
			continue
		if watcher.has_line_of_sight(entity):
			return true
	return false

## Right-clicking any unit not owned by the human player counts as an
## attack target -- anything else is fair game regardless of an eventual
## real faction/ally system.
func _raycast_enemy_unit(screen_pos: Vector2) -> Node3D:
	var unit := _raycast_unit(screen_pos)
	if unit == null or unit.is_player_controlled():
		return null
	return unit

## Any building under the click, regardless of owner -- used for gather-
## point targeting, which cares about "is this a building" rather than
## "is this an enemy."
func _raycast_building(screen_pos: Vector2) -> Node3D:
	var unit := _raycast_unit(screen_pos)
	if unit == null or not (unit is Building):
		return null
	return unit

## Sends every currently selected unit to chase and swing at `target`,
## dropping whatever waypoint queue that exact group had going -- same as
## a plain (non-shift) move order -- so a stale queued leg doesn't yank the
## group away from the target once nav reports it "arrived" mid-chase.
func _issue_attack_order(units: Array[Node], target: Node3D) -> void:
	if units.is_empty():
		return
	var existing_index := _find_queue_index(units)
	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	for unit in units:
		unit.attack(target)
	if target is Entity:
		target.blink_attack_target()

## Sends every unit in the group to walk to and collect `item` (see
## Unit.pick_up_item). Same append_to_queue convention as
## _issue_move_order: plain right-click drops whatever queue the group had
## going and collects it now; shift-right-click appends it as another leg
## after whatever's already queued (a move waypoint, another pickup, or
## both mixed) instead.
func _issue_pickup_order(units: Array[Node], item: WorldItem, append_to_queue: bool) -> void:
	if units.is_empty():
		return
	var target := item.global_position

	var existing_index := _find_queue_index(units)
	if append_to_queue and existing_index != -1:
		var q: Dictionary = _move_queues[existing_index]
		(q["waypoints"] as Array).append(target)
		(q["flags"] as Array).append(_spawn_flag(target))
		(q["items"] as Array).append(item)
		_renumber_flags(q)
		item.blink_selection()
		return

	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var new_queue := {
		"units": units.duplicate(),
		"waypoints": [],
		"flags": [],
		"items": [],
		"current_flag": _spawn_flag(target),
		"current_item": item,
	}
	_move_queues.append(new_queue)
	_renumber_flags(new_queue)
	for unit in units:
		unit.pick_up_item(item)
	item.blink_selection()

## Raycasts for a WorldItem under the cursor -- items live on
## WorldItem.ITEM_MASK (an Area3D, not a body), so this needs its own query
## with collide_with_areas on, unlike the body-only lookups above.
func _raycast_item(screen_pos: Vector2) -> WorldItem:
	var hit := _raycast(screen_pos, WorldItem.ITEM_MASK, true, false)
	if hit.is_empty():
		return null
	var collider: Object = hit["collider"]
	return collider if collider is WorldItem else null

## Shared camera-ray builder for every screen-position raycast in this
## file. Items live on Area3D (see WorldItem.ITEM_MASK), everything else
## (ground/units/buildings) on ordinary PhysicsBody3D, hence the two
## collide_with_* flags -- default to the body-only case everyone else uses.
func _raycast(screen_pos: Vector2, mask: int, collide_with_areas: bool = false, collide_with_bodies: bool = true) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	return space_state.intersect_ray(query)
