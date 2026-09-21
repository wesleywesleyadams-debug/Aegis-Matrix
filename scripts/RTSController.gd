extends Node3D
## Click-select / drag-select / right-click-to-move RTS input handling.
## Ground = collision layer 1, units = collision layer 2.

const GROUND_MASK: int = 1
const UNIT_MASK: int = 2
const CLICK_DRAG_THRESHOLD: float = 6.0
## Keycode -> control-group number (1-9), for Ctrl+<number> to assign the
## current selection to that group and plain <number> to recall it -- see
## _assign_control_group/_recall_control_group. 0 is deliberately excluded,
## same "1 through 9, no 0" convention AoE2's own control groups use.
const CONTROL_GROUP_KEYS: Dictionary = {
	KEY_1: 1, KEY_2: 2, KEY_3: 3, KEY_4: 4, KEY_5: 5,
	KEY_6: 6, KEY_7: 7, KEY_8: 8, KEY_9: 9,
}
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

## World-space size of one grid cell -- matches DebugGrid's own cell_size
## shader parameter (see Main.tscn) exactly, so a snapped building's edges
## land right on the drawn grid lines rather than off by some unrelated
## amount. Also equal to WorldItem.TILE_SIZE/UNIT_SPREAD_SPACING; all three
## are conceptually the same "one tile" and have historically been kept in
## sync by hand -- if this project ever gets a single shared tile-size
## constant, this should read from it instead of repeating the number.
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var selection_box: Control = $UI/SelectionBox
@onready var portrait_panel: Control = $UI/PortraitPanel
@onready var task_panel: Control = $UI/PortraitPanel/TaskPanel
@onready var item_tooltip_panel: Control = $UI/PortraitPanel/ItemTooltipPanel
@onready var resource_hud: ResourceHUD = $UI/ResourceHUD
@onready var control_group_bar: Control = $UI/ControlGroupBar
@onready var debug_grid: MeshInstance3D = $DebugGrid

## Every screen-position raycast/click-target-resolution helper this
## script uses now actually lives in RaycastService.gd -- see its own
## doc comment for why. Built once `camera` is ready (see _ready()); the
## functions below with the same names as its methods are thin
## forwarding wrappers, kept so every call site elsewhere in this file
## didn't need to change.
var _raycast_service: RaycastService

## Building placement (arming, ghost preview, snap-to-grid, confirming)
## now lives in BuildPlacementController.gd -- see its own doc comment
## for why (it was already a self-contained cluster with its own state,
## touched by nothing else). Built in _ready() once _raycast_service is
## ready.
var _build_placement: BuildPlacementController

var _selected_units: Array[Node] = []
var _dragging: bool = false
## True for exactly the one mouse-up that matches a double-click's own
## mouse-down (see that branch's own comment in _unhandled_input) -- skips
## that one _finish_drag_select call so it doesn't immediately undo the
## multi-select _handle_double_click just made.
var _suppress_release_select: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _fog_update_elapsed: float = 0.0
## True while the player has armed attack-move (Tab, with movable units
## selected) and is about to click a destination for it -- see
## _unhandled_input's KEY_TAB/MOUSE_BUTTON_LEFT handling. The cursor swaps
## to a sword (_attack_move_cursor) for the duration so the armed state is
## visible, same as any other pending-targeted-command cursor convention.
var _attack_move_pending: bool = false
var _attack_move_cursor: ImageTexture

## True while the player has armed Repair (TaskPanel's Repair icon) and is
## about to click a building to send the current selection to go heal --
## same "pending targeted command" family as _attack_move_pending/
## _build_placement.pending, mutually exclusive with both. Setters (not a
## plain var) so every one of the many existing "= false"/"= has_movable"
## assignment sites automatically keeps TaskPanel's armed-button highlight
## in sync -- without this, arming a pending order was invisible, and a
## player unsure whether their click registered would naturally click the
## command button again, silently disarming it right before their real
## target click landed as a plain select/move instead of the order they
## meant to give (this is exactly what "Garrison doesn't seem to work"
## turned out to be, confirmed via debug prints -- the double-click, not
## a wiring bug).
var _repair_pending: bool = false:
	set(value):
		_repair_pending = value
		_refresh_armed_command_visual()
## Same family/exclusivity as _repair_pending, but for Garrison (click a
## building to send the selection inside it) -- see
## _on_command_card_garrison_pressed/_issue_garrison_click. Seek Shelter
## (TaskPanel's other garrison-flavored icon) has no pending state of its
## own: it's instant, auto-picking each unit's own nearest building rather
## than waiting for a click -- see _on_command_card_seek_shelter_pressed.
var _garrison_pending: bool = false:
	set(value):
		_garrison_pending = value
		_refresh_armed_command_visual()
## Same family/exclusivity as _repair_pending, but for Plant Oak/Plant
## Apple (click a ground spot to plant a seedling there -- see
## _on_command_card_plant_oak_pressed/_issue_plant_click). Holds "oak",
## "apple", or "" (not armed) rather than a bool since the two plant
## commands share one pending state -- arming one always disarms the
## other, same as any other pending command would.
var _plant_pending: String = "":
	set(value):
		_plant_pending = value
		_refresh_armed_command_visual()

## Mirrors whichever of _repair_pending/_garrison_pending/_plant_pending
## (if any) is currently true onto TaskPanel's own button highlight -- see
## TaskPanel.set_armed_command's own doc comment. Called by every
## property's setter above rather than at each individual call site.
func _refresh_armed_command_visual() -> void:
	if task_panel == null:
		return
	if _repair_pending:
		task_panel.set_armed_command("repair_pressed")
	elif _garrison_pending:
		task_panel.set_armed_command("garrison_pressed")
	elif _plant_pending == "oak":
		task_panel.set_armed_command("plant_oak_pressed")
	elif _plant_pending == "apple":
		task_panel.set_armed_command("plant_apple_pressed")
	else:
		task_panel.set_armed_command("")

## Task queues currently in progress, one entry per group of units that
## has outstanding shift-clicked orders:
## {"units": Array[Node], "waypoints": Array[Vector3],
##  "flags": Array[Node3D], "tasks": Array[Dictionary], "current_flag":
##  Node3D, "current_task": Dictionary}. "flags" holds one flag marker per
## pending (not yet dispatched) entry in "waypoints", in the same order;
## "tasks" parallels "waypoints" the same way -- each entry a
## {"kind": "move"|"pickup"|"gather"|"attack"|"build", "target": Node}
## descriptor of what to actually do once the group reaches that leg
## (target is null for a plain "move" waypoint). This is the "integrate
## every order type into one shift-queue" the user asked for: a single
## right-click order (move, gather, attack, construct/repair, pickup) all
## become one more leg on the same queue when shift is held, rather than
## move being the only order type that could ever be queued. "current_flag"/
## "current_task" mark whichever destination/task (if any) the group is
## actively traveling to and working right now -- see _is_task_complete
## for why a working task (gather/attack/build) holds the queue here for
## as long as it takes, not just until the group merely arrives. Keyed by
## group rather than a single global queue, so giving a different group
## its own order doesn't silently cancel another group's still-pending
## queue.
var _move_queues: Array[Dictionary] = []
## The one WorldItem currently showing its selection frame, or null. Kept
## separate from _selected_units (Units/Buildings only) since an item can't
## be commanded itself -- clicking one is purely a "here's what you clicked"
## indicator, not a selection you can issue orders from.
var _selected_item: WorldItem = null
## Any World node, or Unit/Building NOT owned by the player, selected for
## read-only inspection -- see _inspect_foreign()/_inspect_foreign_multi().
## Also kept separate from _selected_units for the same reason
## _selected_item is: nothing in it can be commanded, so it must never
## reach any order-issuing code path (right-click move/attack, equipment/
## storage drag-and-drop) that reads _selected_units directly. Usually one
## entry (a single click), but a drag-box or double-click ("select every
## X on screen", see _handle_double_click) over several foreign/World
## objects fills this with all of them -- portrait_panel.set_selection
## already handles either size the same way it does for _selected_units.
var _inspected_foreign: Array[Node] = []

## Control-group number (1-9) -> the Array of entities assigned to it (see
## _assign_control_group) -- whatever _current_selection() held at the
## moment of assignment, either every entry straight out of
## _selected_units or, for a foreign/World selection, out of
## _inspected_foreign. A number with no entry here has never been
## assigned and plain-pressing it is a no-op (see _recall_control_group).
var _control_groups: Dictionary = {}

func _ready() -> void:
	# Fresh Paths progress every match -- GameState.human_path_state
	# persists across matches otherwise (it's on an autoload), unlike
	# ResourceHUD's own per-match economy dict, which is scene-owned and
	# naturally starts fresh.
	GameState.human_path_state = PathState.new()
	_raycast_service = RaycastService.new(camera)
	_build_placement = BuildPlacementController.new(self, _raycast_service, _on_building_placed)
	control_group_bar.group_clicked.connect(_recall_control_group)
	resource_hud.idle_villagers_clicked.connect(_select_nearest_idle_worker)
	Music.play_track(Music.IN_GAME_TRACK)
	debug_grid.visible = GameState.show_debug_grid
	_attack_move_cursor = _build_attack_move_cursor()
	if GameState.load_map_on_start:
		GameState.load_map_on_start = false
		_load_custom_map(GameState.load_map_path)
	elif GameState.load_on_start:
		GameState.load_on_start = false
		_load_save()
		_assign_players()
	else:
		_assign_players()

	task_panel.resource_hud = resource_hud
	task_panel.build_type_selected.connect(_on_build_type_selected)
	task_panel.stop_pressed.connect(_on_command_card_stop_pressed)
	task_panel.attack_move_pressed.connect(_on_command_card_attack_move_pressed)
	task_panel.repair_pressed.connect(_on_command_card_repair_pressed)
	task_panel.seek_shelter_pressed.connect(_on_command_card_seek_shelter_pressed)
	task_panel.garrison_pressed.connect(_on_command_card_garrison_pressed)
	task_panel.plant_oak_pressed.connect(_on_command_card_plant_oak_pressed)
	task_panel.plant_apple_pressed.connect(_on_command_card_plant_apple_pressed)
	_refresh_task_panel()

	# So a pickup landing directly in a unit's backpack (see WorldItem.gd)
	# updates the equipment/backpack panels immediately if that unit happens
	# to be selected, without the panels needing to poll every frame.
	for unit in get_tree().get_nodes_in_group("units"):
		unit.backpack_changed.connect(_on_unit_backpack_changed)
		unit.item_thrown.connect(_on_unit_item_thrown)

## Splits whatever roster remains (after trimming/loading) evenly between
## the two players -- first half Player 1, second half Player 2 (Player 1
## gets the extra unit on an odd count). Recomputed fresh each match rather
## than persisted through saves, since save files don't carry player_id yet.
func _assign_players() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var player1_count: int = int(ceil(units.size() / 2.0))
	for i in units.size():
		units[i].player_id = 1 if i < player1_count else 2

## Live-computed, not accumulated -- 1 point per currently-owned unit, 1
## per currently-owned building, plus 1 per 100 of that player's own
## currently-banked resources (summed across Acorns/Apples/Crystal/Mist,
## floored, see ResourceHUD.get_resource/RESOURCE_ORDER), all read fresh
## each call rather than tracked as a running total. This is what makes
## the score go back DOWN when something is lost (a unit dies, a
## building falls, resources get spent) -- there's no separate "lost
## points" bookkeeping to get out of sync, the number just reflects
## whatever's true right now.
func get_player_score(player_id: int) -> int:
	var unit_count := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.player_id == player_id:
			unit_count += 1
	var building_count := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.player_id == player_id:
			building_count += 1
	var resource_total := 0
	if resource_hud != null:
		for resource_name in ResourceHUD.RESOURCE_ORDER:
			resource_total += resource_hud.get_resource(player_id, resource_name)
	var resource_points: int = int(floor(resource_total / 100.0))
	return unit_count + building_count + resource_points

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

## Replaces the scene's hand-placed starting roster entirely with a
## map-editor-authored map (see scripts/MapEditorController.gd, which
## writes this same JSON shape) -- unlike _load_save()'s index-matched
## restore onto an already-existing roster, a custom map has no
## pre-existing Units/Buildings/World children to match against, so this
## clears them first. Every entry resolves through EditorPalette
## (find_entry/instantiate) so the palette and this loader can never
## disagree about what a category+type_id pair means; "Item" entries go
## through WorldItem.spawn_dropped instead, since ItemDefs' pickup scenes
## are Area3D pickups with their own spawn helper rather than a plain
## instance-and-place. Re-bakes the navmesh afterward since
## NavGroundSetup already ran its own bake() in _ready() before any of
## this map's obstacles existed.
func _load_custom_map(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed.has("objects"):
		return

	for unit in get_tree().get_nodes_in_group("units"):
		unit.queue_free()
	for building in get_tree().get_nodes_in_group("buildings"):
		building.queue_free()
	for child in $World.get_children():
		child.queue_free()

	for entry in parsed["objects"]:
		var category: String = entry["category"]
		var pos: Array = entry["position"]
		var position := Vector3(pos[0], pos[1], pos[2])
		var player_id: int = entry.get("player_id", 1)
		if category == "Item":
			WorldItem.spawn_dropped(entry["type_id"], position, $World)
			continue
		var instance := EditorPalette.instantiate(category, entry["type_id"])
		if instance == null:
			continue
		var parent := $Units if category == "Unit" else ($Buildings if category == "Building" else $World)
		# force_readable_name=true -- see BuildPlacementController.confirm_placement's
		# identical fix for why.
		parent.add_child(instance, true)
		instance.global_position = position
		if "rotation_y" in entry and instance is Node3D:
			instance.rotation.y = entry["rotation_y"]
		if "player_id" in instance:
			instance.player_id = player_id

	$NavigationRegion3D.bake()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_grid"):
		GameState.show_debug_grid = not GameState.show_debug_grid
		debug_grid.visible = GameState.show_debug_grid
		return
	if event is InputEventKey and event.keycode == KEY_H and event.pressed and not event.echo:
		_set_attack_move_pending(false)
		_set_build_pending(false)
		_repair_pending = false
		_garrison_pending = false
		_plant_pending = ""
		_halt_selected_units()
		return
	if event is InputEventKey and event.keycode == KEY_PERIOD and event.pressed and not event.echo:
		_select_nearest_idle_worker()
		return
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed and not event.echo:
		_set_build_pending(false)
		_repair_pending = false
		_garrison_pending = false
		_plant_pending = ""
		_toggle_attack_move_pending()
		return
	if event is InputEventKey and event.keycode == KEY_B and event.pressed and not event.echo:
		_set_attack_move_pending(false)
		_repair_pending = false
		_garrison_pending = false
		_plant_pending = ""
		# Always the plain generic building, regardless of whatever type a
		# previous TaskPanel build-submenu pick left armed -- the hotkey's
		# whole point is a fast, predictable default, not "whatever was
		# last selected".
		_build_placement.set_building_type("building")
		_set_build_pending(not _build_placement.pending)
		return
	if event is InputEventKey and event.pressed and not event.echo and CONTROL_GROUP_KEYS.has(event.keycode):
		var group_number: int = CONTROL_GROUP_KEYS[event.keycode]
		if event.ctrl_pressed:
			_assign_control_group(group_number)
		else:
			_recall_control_group(group_number)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_0 and event.ctrl_pressed:
		_auto_designate_control_groups()
		return
	if _attack_move_pending and event.is_action_pressed("ui_cancel"):
		_set_attack_move_pending(false)
		return
	if _build_placement.pending and event.is_action_pressed("ui_cancel"):
		_set_build_pending(false)
		return
	if _repair_pending and event.is_action_pressed("ui_cancel"):
		_repair_pending = false
		return
	if _garrison_pending and event.is_action_pressed("ui_cancel"):
		_garrison_pending = false
		_plant_pending = ""
		return
	if not _plant_pending.is_empty() and event.is_action_pressed("ui_cancel"):
		_plant_pending = ""
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _attack_move_pending:
					_issue_attack_move_click(event.position)
					return
				if _build_placement.pending:
					_build_placement.confirm_placement()
					return
				if _repair_pending:
					_issue_repair_click(event.position)
					return
				if _garrison_pending:
					_issue_garrison_click(event.position)
					return
				if not _plant_pending.is_empty():
					_issue_plant_click(event.position)
					return
				if event.double_click:
					_handle_double_click(event.position)
					# The button-release half of this same double-click still
					# arrives as its own event right after this -- without
					# this flag it falls straight through to the `else`
					# branch below and calls _finish_drag_select, which (a
					# plain click, not a drag: _drag_start is stale from
					# whatever the last real drag was) re-resolves the
					# release position as an ordinary single-unit click and
					# immediately collapses the multi-select this just made
					# back down to one. Godot only sets double_click on the
					# PRESS event, never the matching release, so the
					# release can't detect this on its own.
					_suppress_release_select = true
					return
				_suppress_release_select = false
				_dragging = true
				_drag_start = event.position
				selection_box.drag_start = event.position
				selection_box.drag_end = event.position
				selection_box.visible = true
				selection_box.queue_redraw()
			else:
				if _suppress_release_select:
					_suppress_release_select = false
					return
				_finish_drag_select(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _attack_move_pending:
				_set_attack_move_pending(false)
				return
			if _build_placement.pending:
				_set_build_pending(false)
				return
			if _repair_pending:
				_repair_pending = false
				return
			if _garrison_pending:
				_garrison_pending = false
				_plant_pending = ""
				return
			if not _plant_pending.is_empty():
				_plant_pending = ""
				return
			_handle_right_click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		selection_box.drag_end = event.position
		selection_box.queue_redraw()

## Toggles attack-move arming (Tab) -- only if at least one currently
## selected entity is a movable Unit (Buildings can't attack-move). Pressing
## Tab again while already armed disarms it without issuing anything, same
## as right-click/Escape.
func _toggle_attack_move_pending() -> void:
	if _attack_move_pending:
		_set_attack_move_pending(false)
		return
	var has_movable := false
	for entity in _selected_units:
		if not (entity is Building):
			has_movable = true
			break
	if has_movable:
		_set_attack_move_pending(true)

func _set_attack_move_pending(pending: bool) -> void:
	_attack_move_pending = pending
	if pending:
		Input.set_custom_mouse_cursor(_attack_move_cursor, Input.CURSOR_ARROW, Vector2(15, 2))
	else:
		Input.set_custom_mouse_cursor(null)

## The left-click that fires once attack-move is armed -- resolves a
## destination the same way an ordinary move order does (building clicked
## directly -> its gather-point flag position, otherwise the ground point
## under the cursor) and dispatches _issue_attack_move_order with it, then
## disarms back to normal click behavior.
func _issue_attack_move_click(screen_pos: Vector2) -> void:
	_set_attack_move_pending(false)
	var selected_movable: Array[Node] = []
	for entity in _selected_units:
		if not (entity is Building):
			selected_movable.append(entity)
	if selected_movable.is_empty():
		return

	var clicked_building := _raycast_building(screen_pos)
	var move_target: Vector3
	if clicked_building != null:
		move_target = clicked_building.global_position + Vector3(0, GATHER_FLAG_BUILDING_HEIGHT, 0)
	else:
		var hit := _raycast(screen_pos, GROUND_MASK)
		if hit.is_empty():
			return
		move_target = hit["position"]
	_issue_attack_move_order(selected_movable, move_target)

## Issues an attack-move order (see Unit.attack_move_to) to `units`, each
## still spread onto its own destination like an ordinary group move (see
## _dispatch_move/_spread_offset) rather than all converging on the exact
## same point -- just engaging anything hostile encountered along the way
## instead of ignoring it until arrival. Drops any queued waypoints this
## exact group had going, same as a plain (non-shift) move order.
func _issue_attack_move_order(units: Array[Node], target: Vector3) -> void:
	if units.is_empty():
		return
	var existing_index := _find_queue_index(units)
	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var count := units.size()
	for i in count:
		units[i].attack_move_to(target + _spread_offset(i, count))

## Builds a small sword icon (blade + crossguard + hilt) for the attack-move
## cursor -- procedural since there's no dedicated 2D icon asset to reuse
## (Sword.tscn/SwordPickup.tscn are 3D world models, not a UI texture).
func _build_attack_move_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var blade_color := Color(0.85, 0.87, 0.92, 1.0)
	for y in range(2, 20):
		var half_width := 1 if y < 7 else 2
		for x in range(16 - half_width, 16 + half_width):
			img.set_pixel(x, y, blade_color)

	var brass_color := Color(0.58, 0.45, 0.14, 1.0)
	for x in range(9, 24):
		for y in range(20, 23):
			img.set_pixel(x, y, brass_color)

	var hilt_color := Color(0.32, 0.18, 0.08, 1.0)
	for y in range(23, 29):
		for x in range(14, 19):
			img.set_pixel(x, y, hilt_color)

	for x in range(13, 20):
		for y in range(29, 31):
			img.set_pixel(x, y, brass_color)

	return ImageTexture.create_from_image(img)

## Thin wrapper so every _unhandled_input call site above didn't need to
## change -- the actual arming/ghost-preview logic now lives in
## BuildPlacementController.gd (see its own doc comment).
func _set_build_pending(pending: bool) -> void:
	_build_placement.set_pending(pending, get_viewport().get_mouse_position(), GROUND_MASK)

## Passed to BuildPlacementController as the callback it invokes with a
## newly-placed building.
## Every newly placed building starts as an unfinished foundation (see
## Building.is_under_construction) -- "has hp and a collision box" and
## nothing else until a peasant actually builds it. Whichever peasants
## are currently selected (the ones the player most likely just placed
## this with) are sent to start construction immediately, same "the
## worker who placed it starts building it" convention real RTS games
## use; a placement with no peasant selected just leaves the foundation
## sitting there until one is sent via Repair (see
## RTSController._issue_repair_click, which also doubles as "help
## construct" for an unfinished foundation).
func _on_building_placed(building: Building) -> void:
	building.is_under_construction = true
	for entity in _selected_units:
		if entity is Unit and entity.unit_type_id == "peasant":
			entity.construct_building(building)

func _process(delta: float) -> void:
	_fog_update_elapsed += delta
	if _fog_update_elapsed >= FOG_UPDATE_INTERVAL:
		_fog_update_elapsed = 0.0
		_update_fog_of_war()

	_prune_selected_units()

	if _build_placement.pending:
		_build_placement.update_ghost(get_viewport().get_mouse_position(), GROUND_MASK)

	_update_map_item_hover()

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

		# A working task (gather/attack/build) already dispatched onto
		# these units keeps running on its own -- Unit._physics_process's
		# own gather_target/attack_target/construct_target machinery -- for
		# as long as it needs to, which is usually far longer than the
		# nav_agent's own "arrived" moment (nav finishes the instant a
		# peasant reaches an Oak Tree; the tree can still take minutes to
		# actually deplete). Hold this queue entry here, untouched, until
		# the task itself is actually done, rather than letting the
		# nav-finished check below advance to the next queued leg the
		# moment the group merely arrives.
		var current_task: Dictionary = q.get("current_task", {})
		if not current_task.is_empty() and not _is_task_complete(current_task):
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
		var tasks: Array = q["tasks"]
		var next_task: Dictionary = tasks.pop_front()
		q["current_task"] = next_task
		_renumber_flags(q)
		_dispatch_task(units, next_task, next_target)

## True once a dispatched task no longer needs to hold its queue entry --
## i.e. it's either a plain move/pickup (whose own completion IS the
## nav-finished check the _process loop already runs right after this),
## or a working task (gather/attack/build) whose target has become
## invalid or has actually finished. Kept as one shared predicate so every
## order type advances the same shift-queue the same way.
func _is_task_complete(task: Dictionary) -> bool:
	var target = task.get("target")
	match task.get("kind", "move"):
		"gather":
			return target == null or not is_instance_valid(target) or not target.can_gather()
		"attack":
			return target == null or not is_instance_valid(target) or not (target is Entity) or target.current_health <= 0.0
		"build":
			if target == null or not is_instance_valid(target):
				return true
			if target.is_under_construction:
				return false
			return target.current_health >= target.max_health
		_:
			return true

## Carries out one already-arrived-at queue leg according to its "kind" --
## the single place every order type (move/pickup/gather/attack/build)
## funnels through once the group reaches that leg's waypoint, so shift-
## queueing a mixed sequence of order types just works without each order
## type needing its own copy of the advancement logic.
func _dispatch_task(units: Array, task: Dictionary, position: Vector3) -> void:
	var target = task.get("target")
	match task.get("kind", "move"):
		"pickup":
			for unit in units:
				unit.pick_up_item(target)
			if target != null and is_instance_valid(target):
				target.blink_selection()
		"gather":
			for unit in units:
				if unit is Unit and unit.unit_type_id == "peasant":
					unit.gather_resource(target)
				else:
					unit.move_to(position)
			if target != null and is_instance_valid(target):
				target.blink_attack_target(2, Entity.GATHER_TARGET_BLINK_COLOR)
		"attack":
			for unit in units:
				unit.order_attack(target)
			if target is Entity:
				target.blink_attack_target()
		"build":
			for unit in units:
				if unit is Unit and unit.unit_type_id == "peasant":
					unit.construct_building(target)
				else:
					unit.move_to(position)
		_:
			_dispatch_move(position, units)

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

## The "type" a double-click (see _handle_double_click) groups entities
## by -- unit_type_id for a Unit/Building (Peasant, Castle, ...), or, for
## a World node, its resource_type ("acorns"/"apples"/"crystal"/"mist") so
## an Oak Tree and Apple Tree don't get swept up together, falling back to
## species (e.g. "pine") for a decorative, non-gatherable World object
## with no resource_type at all. "" (never matches anything) for a node
## with neither.
func _type_key_for(entity: Node) -> String:
	if entity is World:
		return entity.resource_type if not entity.resource_type.is_empty() else entity.species
	if "unit_type_id" in entity:
		return entity.unit_type_id
	return ""

## Whether `entity` is currently inside the camera's own view -- same
## on-screen check the minimap/fog systems don't need but "select every X
## on screen" (see _handle_double_click) does, since that command is
## explicitly scoped to what's visible right now rather than the whole map.
func _entity_on_screen(entity: Node3D) -> bool:
	if camera.is_position_behind(entity.global_position):
		return false
	return get_viewport().get_visible_rect().has_point(camera.unproject_position(entity.global_position))

## Double-clicking any Unit/Building/World node selects every on-screen
## object of that same exact type (see _type_key_for) at once -- the
## standard RTS "select all of this" shortcut. An owned Unit/Building goes
## through the normal commandable _select_unit path (same as a drag-box);
## a World node or a foreign (enemy/Gaia) Unit/Building goes through the
## read-only _inspect_foreign_multi instead, same split single-click
## already has between the two.
func _handle_double_click(screen_pos: Vector2) -> void:
	var clicked := _raycast_unit(screen_pos)
	if clicked == null:
		return
	var type_key := _type_key_for(clicked)
	if type_key.is_empty():
		return
	var group := "world" if clicked is World else ("buildings" if clicked is Building else "units")
	var matches: Array = []
	for entity in get_tree().get_nodes_in_group(group):
		if is_instance_valid(entity) and entity.visible and _type_key_for(entity) == type_key and _entity_on_screen(entity):
			matches.append(entity)
	if matches.is_empty():
		return
	if clicked is World or not clicked.is_player_controlled():
		_inspect_foreign_multi(matches)
		return
	_clear_selection()
	_clear_item_selection()
	for entity in matches:
		_select_unit(entity)

func _finish_drag_select(release_pos: Vector2) -> void:
	_dragging = false
	selection_box.visible = false
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	var drag_size := (release_pos - _drag_start).length()

	if drag_size < CLICK_DRAG_THRESHOLD:
		var clicked := _raycast_unit(release_pos)
		if clicked:
			if clicked is World:
				# A Gaia resource node (Oak Tree, Crystal Cave, Mist
				# Fissure, ...) can't be given orders -- same "nothing to
				# command, but still worth showing stats for" reasoning
				# _inspect_foreign already has for an enemy unit/building,
				# just never wired up for World until now.
				_inspect_foreign(clicked)
			elif clicked.is_player_controlled():
				if not shift_held:
					_clear_selection()
				_clear_item_selection()
				_select_unit(clicked)
			else:
				_inspect_foreign(clicked)
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
			# Units in the box always win outright -- any buildings/World
			# nodes also caught in the same box are ignored entirely, not
			# just deprioritized.
			for unit in units_in_box:
				_select_unit(unit)
			return

		# No units in the box -- fall back to buildings, but only ever
		# add ONE per drag (buildings aren't meant to swarm-select like
		# units). Repeatedly shift-dragging is how you build up a
		# multi-building selection, one at a time. Skips a foreign
		# (non-player-controlled) building rather than stopping the scan
		# on it -- otherwise a single enemy/Gaia building caught in the
		# same box as gatherable World nodes would silently swallow the
		# whole drag with nothing selected, never reaching the World
		# fallback below.
		for building in get_tree().get_nodes_in_group("buildings"):
			if not building.is_player_controlled():
				continue
			if not camera.is_position_behind(building.global_position):
				var screen_pos := camera.unproject_position(building.global_position)
				if rect.has_point(screen_pos):
					_select_unit(building)
					return

		# No units or buildings either -- fall back to World nodes (Oak/
		# Apple Tree, Crystal Cave, Mist Fissure, a decorative Tree, ...).
		# These aren't commandable (see _select_unit's own guard), so they
		# go through the same read-only multi-inspect a "select every X on
		# screen" double-click uses (see _inspect_foreign_multi) rather than
		# _selected_units, but a drag-box can still gather more than one at
		# once -- unlike a building, there's no "swarm-select" concern here
		# since nothing about a World node can be commanded either way.
		var world_in_box: Array = []
		for world_node in get_tree().get_nodes_in_group("world"):
			if is_instance_valid(world_node) and world_node.visible and not camera.is_position_behind(world_node.global_position):
				var screen_pos := camera.unproject_position(world_node.global_position)
				if rect.has_point(screen_pos):
					world_in_box.append(world_node)
		if not world_in_box.is_empty():
			_inspect_foreign_multi(world_in_box)

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

	var shift_queue := Input.is_key_pressed(KEY_SHIFT)
	var enemy := _raycast_enemy_unit(screen_pos)
	# A World resource node (Oak Tree, Crystal Cave, ...) is owned by
	# Gaia (player_id 9, never the human's own), so raycast_enemy_unit's
	# plain "not player-controlled" check picks it up as if it were an
	# attackable enemy unit -- it isn't; right-clicking one should always
	# mean "gather from this", never "attack this" (see the gather check
	# below, which handles it instead).
	if enemy is World:
		enemy = null

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
		_issue_attack_order(selected_movable, enemy, shift_queue)
		return

	# Clicking a gatherable World resource node (an Oak Tree, Apple Tree,
	# Crystal Cave, Mist Fissure, ...) sends every selected peasant to
	# gather from it (see Unit.gather_resource -- a no-op guard on
	# anything else, but only bother calling it on peasants here so a
	# non-peasant in the group doesn't stand there uselessly instead of
	# joining the group's own move); any other selected unit just moves
	# to it like it would a building, so the whole group visually
	# converges on the node together.
	var clicked_node := _raycast_unit(screen_pos)
	if clicked_node is World and clicked_node.can_gather():
		_issue_gather_order(selected_movable, clicked_node, shift_queue)
		return

	# Clicking directly on an unfinished foundation sends every selected
	# peasant to (re)join constructing it -- same auto-detect shape as the
	# gather case just above, so resuming a foundation nobody's currently
	# working never needs the Repair command armed first; any non-peasant
	# in the group just walks over instead, exactly like a non-peasant
	# clicking a gatherable node above. Building.construction_workers (see
	# Unit.construct_target's own setter) is what makes the foundation's
	# selection ring start blinking the instant this actually lands.
	if clicked_node is Building and clicked_node.is_under_construction:
		_issue_build_order(selected_movable, clicked_node, shift_queue)
		return

	# Clicking directly on a world item sends the group to walk to and
	# collect it (see Unit.pick_up_item) -- an explicit order, not the mere
	# proximity-triggered pickup this used to be.
	var clicked_item := _raycast_item(screen_pos)
	if clicked_item != null:
		_issue_pickup_order(selected_movable, clicked_item, shift_queue)
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
	_issue_move_order(selected_movable, move_target, shift_queue)

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
		(q["tasks"] as Array).append({"kind": "move", "target": null})
		_renumber_flags(q)
		return

	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var new_queue := {
		"units": units.duplicate(),
		"waypoints": [],
		"flags": [],
		"tasks": [],
		"current_flag": _spawn_flag(target),
		"current_task": {"kind": "move", "target": null},
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
## that ownership check -- they're Gaia-owned incidentally, but the real
## reason is that they're static scenery, not a commandable unit/building,
## so selecting one and right-clicking should never be able to task it.
func _on_unit_backpack_changed(unit: Unit) -> void:
	if unit == _first_selected_unit():
		_refresh_task_panel()

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

## Refreshes TaskPanel with whichever of the first selected unit/building
## actually applies -- see TaskPanel.refresh's own doc comment for how it
## picks between its unit (backpack + command icons) and building
## (train/upgrades) content; the two are mutually exclusive by
## construction (a selection is never simultaneously a Unit and a
## Building).
func _refresh_task_panel() -> void:
	task_panel.refresh(_first_selected_unit(), _first_selected_building())

## TaskPanel's own build-type submenu (see its _show_build_menu) fires
## this once a specific building icon is picked -- arms placement for
## exactly that type. The B hotkey (see _unhandled_input's KEY_B branch)
## still arms the plain generic building immediately and unchanged; this
## is purely an additional, richer path through the same
## BuildPlacementController.
func _on_build_type_selected(type_id: String) -> void:
	_set_attack_move_pending(false)
	_repair_pending = false
	_garrison_pending = false
	_plant_pending = ""
	_build_placement.set_building_type(type_id)
	_set_build_pending(true)

func _on_command_card_stop_pressed() -> void:
	_set_attack_move_pending(false)
	_set_build_pending(false)
	_repair_pending = false
	_garrison_pending = false
	_plant_pending = ""
	_halt_selected_units()

func _on_command_card_attack_move_pressed() -> void:
	_set_build_pending(false)
	_repair_pending = false
	_garrison_pending = false
	_plant_pending = ""
	_toggle_attack_move_pending()

## Arms Repair (TaskPanel's Repair icon) -- only if at least one currently
## selected entity is a peasant (the only unit type allowed to construct
## or repair a building). Same on/off toggle convention as
## _toggle_attack_move_pending: pressing again while already armed
## disarms without issuing anything.
func _on_command_card_repair_pressed() -> void:
	_set_attack_move_pending(false)
	_set_build_pending(false)
	_garrison_pending = false
	_plant_pending = ""
	if _repair_pending:
		_repair_pending = false
		return
	var has_peasant := false
	for entity in _selected_units:
		if entity is Unit and entity.unit_type_id == "peasant":
			has_peasant = true
			break
	_repair_pending = has_peasant

## The left-click that fires once Repair is armed -- if a building is
## directly under the cursor, sends every selected peasant to either help
## finish it (still a foundation, see Unit.construct_building) or heal it
## (already built, see Unit.repair_building); clicking empty ground/a unit
## just disarms without issuing anything, same "no-op on a bad target"
## convention _issue_attack_move_click doesn't have but pickup/attack
## clicks do.
func _issue_repair_click(screen_pos: Vector2) -> void:
	_repair_pending = false
	var building := _raycast_building(screen_pos)
	if building == null:
		return
	var selected_peasants: Array[Node] = []
	for entity in _selected_units:
		if entity is Unit and entity.unit_type_id == "peasant":
			selected_peasants.append(entity)
	for unit in selected_peasants:
		if building.is_under_construction:
			unit.construct_building(building)
		else:
			unit.repair_building(building)

## Arms Garrison (TaskPanel's Garrison icon) -- click a building to send
## every selected non-Building unit inside it. Same toggle-arm/mutual-
## exclusion shape as _on_command_card_repair_pressed.
func _on_command_card_garrison_pressed() -> void:
	_set_attack_move_pending(false)
	_set_build_pending(false)
	_repair_pending = false
	if _garrison_pending:
		_garrison_pending = false
		_plant_pending = ""
		return
	var has_movable := false
	for entity in _selected_units:
		if not (entity is Building):
			has_movable = true
			break
	_garrison_pending = has_movable

## The left-click that fires once Garrison is armed -- mirrors
## _issue_repair_click exactly, but sends units to walk into the building
## and enter it (Unit.seek_garrison) rather than heal it.
func _issue_garrison_click(screen_pos: Vector2) -> void:
	_garrison_pending = false
	_plant_pending = ""
	var building := _raycast_building(screen_pos)
	if building == null:
		return
	var selected_movable: Array[Node] = []
	for entity in _selected_units:
		if not (entity is Building):
			selected_movable.append(entity)
	for unit in selected_movable:
		unit.seek_garrison(building)

## Seek Shelter -- instant, non-pending: each selected non-Building unit
## picks its own nearest building (owned by that unit's player, with
## garrison room left) and heads inside it. Unlike Garrison, there's no
## click-a-target step, so nothing here touches the pending/mutual-
## exclusion state at all.
func _on_command_card_seek_shelter_pressed() -> void:
	for entity in _selected_units:
		if entity is Building:
			continue
		var unit: Unit = entity
		var nearest: Building = null
		var nearest_dist := INF
		for candidate in get_tree().get_nodes_in_group("buildings"):
			if not (candidate is Building):
				continue
			var building: Building = candidate
			if building.player_id != unit.player_id or not building.can_garrison():
				continue
			var dist := unit.global_position.distance_to(building.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = building
		if nearest != null:
			unit.seek_garrison(nearest)

const OAK_TREE_SCENE: PackedScene = preload("res://scenes/OakTree.tscn")
const APPLE_TREE_SCENE: PackedScene = preload("res://scenes/AppleTree.tscn")
## Plant costs -- 1 Acorn per Oak Tree, 1 Apple per Apple Tree, matching
## what each tree itself yields a full unit of once grown.
const PLANT_COSTS: Dictionary = {
	"oak": {"acorns": 1},
	"apple": {"apples": 1},
}

## Arms Plant Oak (TaskPanel's Plant Oak icon) -- only if at least one
## currently selected entity is a peasant (the only unit type allowed to
## plant a tree, same restriction Repair/construction has). Same
## toggle-arm/mutual-exclusion shape as _on_command_card_repair_pressed.
func _on_command_card_plant_oak_pressed() -> void:
	_set_attack_move_pending(false)
	_set_build_pending(false)
	_repair_pending = false
	_garrison_pending = false
	if _plant_pending == "oak":
		_plant_pending = ""
		return
	_plant_pending = "oak" if _has_selected_peasant() else ""

func _on_command_card_plant_apple_pressed() -> void:
	_set_attack_move_pending(false)
	_set_build_pending(false)
	_repair_pending = false
	_garrison_pending = false
	if _plant_pending == "apple":
		_plant_pending = ""
		return
	_plant_pending = "apple" if _has_selected_peasant() else ""

func _has_selected_peasant() -> bool:
	return _first_selected_peasant() != null

func _first_selected_peasant() -> Unit:
	for entity in _selected_units:
		if entity is Unit and entity.unit_type_id == "peasant":
			return entity
	return null

## The left-click that fires once Plant Oak/Plant Apple is armed -- spends
## 1 Acorn/1 Apple up front (refusing, same as an unaffordable building, if
## the human player can't afford it -- an order that's refused outright
## never costs anything, unlike one that starts and is later interrupted,
## see Unit.order_plant's own doc comment) and sends the first selected
## peasant to walk there and spend Unit.PLANT_TIME seconds actually
## planting it -- see Unit.order_plant/_update_plant_target for the rest
## of that order's lifecycle, including the sapling itself only getting
## created once that timer completes.
func _issue_plant_click(screen_pos: Vector2) -> void:
	var tree_type := _plant_pending
	_plant_pending = ""
	var peasant := _first_selected_peasant()
	if peasant == null:
		return
	var hit := _raycast(screen_pos, GROUND_MASK)
	if hit.is_empty():
		return
	var cost: Dictionary = PLANT_COSTS.get(tree_type, {})
	if not resource_hud.spend_resources(GameState.human_player_id, cost):
		return
	var scene: PackedScene = OAK_TREE_SCENE if tree_type == "oak" else APPLE_TREE_SCENE
	# Snapped to the center of its tile -- same "every resource node sits
	# on a tile center" rule the map's own hand-placed Oak/Apple/Crystal/
	# Fissure nodes and the map editor's placement (EditorPlacementController.
	# update_ghost, which snaps every category unconditionally) already
	# follow; a planted tree is the one resource node that used to land
	# wherever the player's raycast happened to hit instead.
	var planted_position := _build_placement.snap_to_grid(hit["position"])
	peasant.order_plant(scene, planted_position)

## Dragging an item out of the equipment/backpack panel or building
## storage panel (see ItemDropTarget/ItemSlotButton) and releasing it at
## `screen_pos`. Exactly one of source_unit/source_building is set
## (whichever panel it came from); source_slot only matters for the
## former (see Unit.throw_item). A unit source issues a throw order (see
## Unit.throw_item/_on_unit_item_thrown) -- the unit has to actually walk
## within throwing range before the item leaves its hand, rather than it
## teleporting there instantly. A building can't walk anywhere, so a
## building source throws immediately instead, but that throw is capped to
## the same one-tile range a unit has to close in to (see
## _throw_from_building) -- a building can eject an item to its own
## doorstep, not fling it anywhere on the map.
func handle_item_drag_drop(item_type: String, source_slot: String, source_unit: Unit, source_building: Building, screen_pos: Vector2) -> void:
	if is_instance_valid(source_unit):
		if source_unit.backpack.get(source_slot, "") != item_type:
			return
		var target := _resolve_drop_target(screen_pos, source_unit)
		source_unit.throw_item(item_type, source_slot, target["position"], target["unit"], target["building"])
	elif is_instance_valid(source_building):
		if not source_building.take_item(item_type):
			return
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
## player's (or Gaia/Mob's) units/buildings, only placed on the ground
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
	_refresh_task_panel()
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
		var displaced := target_unit.equip_item(item_type)
		var angle_step := PI / 2.0
		for i in displaced.size():
			var angle_offset := (i - (displaced.size() - 1) / 2.0) * angle_step
			WorldItem.spawn_pickup(displaced[i], target_unit.global_position, target_unit.model_root.rotation.y, $World, angle_offset)
		pickup.queue_free()
		_refresh_task_panel()
		ItemReceivedEffect.spawn(item_type, target_unit)
	elif is_instance_valid(target_building) and target_building.is_player_controlled():
		# Storage might already be full (see Building.MAX_STORAGE_SLOTS) --
		# if so, just leave it sitting where it landed as a normal ground
		# pickup rather than losing it.
		if not target_building.store_item(item_type):
			return
		pickup.queue_free()
		ItemReceivedEffect.spawn(item_type, target_building)

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

## The "." hotkey / clicking ResourceHUD's own idle-villagers icon (see its
## own idle_villagers_clicked signal) -- selects whichever of the human
## player's own idle peasants (see Unit.is_idle(), now correctly excluding
## a peasant that's mid-gather/repair/construct/plant/garrison -- see that
## function's own doc comment) is nearest to wherever the camera is
## currently centered, and recenters the camera on it. "Nearest to the
## current view" rather than "nearest to the last selection" or some
## fixed cycling order, since there's no single obviously-right anchor
## point otherwise, and this at least means repeated presses sweep toward
## whatever's actually on screen right now. A no-op (camera/selection left
## alone) if no idle peasant exists at all.
func _select_nearest_idle_worker() -> void:
	var current_center := _ground_point(get_viewport().get_visible_rect().size / 2.0)
	var best: Node = null
	var best_dist: float = INF
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or unit.player_id != GameState.human_player_id:
			continue
		if unit.unit_type_id != "peasant" or not unit.is_idle() or unit.attack_target != null:
			continue
		var dist := current_center.distance_to(unit.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best == null:
		return
	_clear_selection()
	_clear_item_selection()
	_select_unit(best)
	_center_camera_on(best.global_position)

## Shifts camera_rig so `target` becomes the new center of the view --
## same delta-from-current-center math Minimap._gui_input's own "click to
## recenter here" uses, reimplemented here rather than reached through the
## minimap node since this needs to fire from a hotkey/HUD click with no
## minimap click involved at all.
func _center_camera_on(target: Vector3) -> void:
	var current_center := _ground_point(get_viewport().get_visible_rect().size / 2.0)
	var delta := target - current_center
	delta.y = 0.0
	camera_rig.global_position += delta

## Where the camera ray through `screen_pos` crosses the Y=0 ground plane
## -- same math Minimap._ground_point uses, for the same "fixed downward-
## angled camera, never level with or above the horizon" reason.
func _ground_point(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var t := -origin.y / direction.y
	return origin + direction * t

func _select_unit(unit: Node) -> void:
	if unit is World:
		return
	if not unit.is_player_controlled():
		return
	if unit in _selected_units:
		return
	_selected_units.append(unit)
	unit.selected = true
	portrait_panel.set_selection(_selected_units)
	_refresh_task_panel()

## Left-clicking a World node or a unit/building NOT owned by the player
## selects it for read-only inspection -- shows its stats (portrait,
## health/type tray) the same way an owned selection would, but it's never
## addable to _selected_units (which every order-issuing path -- right-click
## move/attack, equipment/storage drag-and-drop -- reads from), so there's
## no way to actually command it. Mutually exclusive with an owned
## selection and with a selected item -- _clear_selection() (called first
## here) already drops both.
func _inspect_foreign(entity: Node) -> void:
	_inspect_foreign_multi([entity])

## Same as _inspect_foreign, for more than one foreign/World object at
## once -- a drag-box that only caught World nodes (see
## _finish_drag_select), or "select every X on screen" (see
## _handle_double_click).
func _inspect_foreign_multi(entities: Array) -> void:
	_clear_selection()
	_clear_item_selection()
	_inspected_foreign = []
	for entity in entities:
		_inspected_foreign.append(entity)
		entity.selected = true
	portrait_panel.set_selection(_inspected_foreign)

## Whatever is currently selected, regardless of which of the two mutually
## exclusive selection arrays (see _inspected_foreign's own doc comment)
## holds it -- Ctrl+<number> (see _assign_control_group) doesn't care
## which kind it's snapshotting.
func _current_selection() -> Array:
	return _selected_units if not _selected_units.is_empty() else _inspected_foreign

## Ctrl+<number>: snapshots whatever's currently selected into control
## group `number` (1-9), overwriting anything previously assigned to it.
## A no-op with nothing selected -- there's nothing to remember.
func _assign_control_group(number: int) -> void:
	var current := _current_selection()
	if current.is_empty():
		return
	_control_groups[number] = current.duplicate()
	_refresh_control_group_bar()

## Ctrl+0: splits whatever's currently selected across up to 9 control
## groups at once, one entity per number -- the user's own worked example:
## 4 selected get groups 1-4 (one each); 9 selected fill 1-9 one each; 10
## or more fill 1-8 one each and dump every remaining entity into group 9
## together (not spread further -- 9 is the last slot there is). Replaces
## groups 1-9 outright, including any not touched by this selection (a
## smaller selection than 9 leaves the untouched high numbers empty
## afterward, not holding whatever they had before) -- "auto-designate for
## every currently selected object" is a fresh full re-mapping, not a
## merge with whatever groups already existed.
func _auto_designate_control_groups() -> void:
	var current := _current_selection()
	if current.is_empty():
		return
	for number in range(1, 10):
		_control_groups.erase(number)
	for i in range(current.size()):
		var group_number: int = mini(i + 1, 9)
		if not _control_groups.has(group_number):
			_control_groups[group_number] = []
		_control_groups[group_number].append(current[i])
	_refresh_control_group_bar()

## Rebuilds control_group_bar from _control_groups -- called after any
## assignment (Ctrl+<number>, Ctrl+0) and from _prune_selected_units so a
## group that's lost members (or emptied out) to death stays live-accurate
## without needing its own number pressed first.
func _refresh_control_group_bar() -> void:
	var entries: Array = []
	var numbers := _control_groups.keys()
	numbers.sort()
	for number in numbers:
		var members: Array = _control_groups[number]
		if members.is_empty():
			continue
		var sample: Node = members[0]
		entries.append({
			"number": number,
			"label": _majority_type_label(members),
			"player_id": sample.player_id if "player_id" in sample else GameState.human_player_id,
		})
	control_group_bar.refresh(entries)

## Which object type (see _type_key_for) most of `members` share, as
## display text (e.g. "Peasant", "Crystal") for a control-group button's
## own label -- an exact tie just keeps whichever type _type_key_for
## happened to count first, since there's no meaningful "correct" winner
## for one.
func _majority_type_label(members: Array) -> String:
	var counts: Dictionary = {}
	var best_key := ""
	var best_count := 0
	for entity in members:
		var key := _type_key_for(entity)
		var count: int = counts.get(key, 0) + 1
		counts[key] = count
		if count > best_count:
			best_count = count
			best_key = key
	return best_key.capitalize()

## Plain <number>: re-selects whatever's still alive in control group
## `number`, exactly the way that same selection would have been made
## fresh -- the normal commandable path (_select_unit) for a group of the
## player's own units/buildings, or the read-only multi-inspect path
## (_inspect_foreign_multi) for a group of foreign units/buildings or
## World nodes, matching whichever kind _assign_control_group captured.
## A no-op for a number that's never been assigned, or whose entire group
## has since died/been freed (which also forgets the empty group, rather
## than leaving a dead entry a later assign to the same number would need
## to silently overwrite anyway).
func _recall_control_group(number: int) -> void:
	if not _control_groups.has(number):
		return
	var group: Array = _control_groups[number]
	for i in range(group.size() - 1, -1, -1):
		if not is_instance_valid(group[i]):
			group.remove_at(i)
	if group.is_empty():
		_control_groups.erase(number)
		return
	var first: Node = group[0]
	if first is World or not first.is_player_controlled():
		_inspect_foreign_multi(group)
		return
	_clear_selection()
	_clear_item_selection()
	for entity in group:
		_select_unit(entity)

## Removes any selected unit that's since been freed (a unit only
## queue_free()s once its death animation actually finishes -- see
## Entity._die() -- not the instant its health hits 0) from
## _selected_units, and pushes the cleaned list to every panel that reads
## it. Run every frame, not just in response to explicit selection
## changes, since a selected unit can die mid-fight without the player
## touching selection at all -- without this, MultiSelectIcons' _draw()
## (which redraws periodically on its own timer, independent of selection
## changes) would try to read a property off an already-freed node and
## error every single frame from then on, which is exactly what caused a
## crash: a unit died while selected, its stale reference sat in
## _selected_units, and it kept hitting it on every redraw.
func _prune_selected_units() -> void:
	var had_invalid := false
	for i in range(_selected_units.size() - 1, -1, -1):
		if not is_instance_valid(_selected_units[i]):
			_selected_units.remove_at(i)
			had_invalid = true
	if had_invalid:
		portrait_panel.set_selection(_selected_units)
		_refresh_task_panel()

	# _inspected_foreign lives outside _selected_units entirely (see
	# _inspect_foreign), so it needs its own validity check here -- same
	# "died while selected, stale reference sat around" hazard the loop
	# above guards against.
	var had_invalid_foreign := false
	for i in range(_inspected_foreign.size() - 1, -1, -1):
		if not is_instance_valid(_inspected_foreign[i]):
			_inspected_foreign.remove_at(i)
			had_invalid_foreign = true
	if had_invalid_foreign:
		portrait_panel.set_selection(_inspected_foreign)

	# Same "died while assigned, stale reference sat around" hazard as
	# both loops above, for every control group -- keeps control_group_bar
	# (and a later recall of that same number) accurate without needing
	# that number actually pressed first.
	var had_invalid_group := false
	for number in _control_groups.keys():
		var group: Array = _control_groups[number]
		for i in range(group.size() - 1, -1, -1):
			if not is_instance_valid(group[i]):
				group.remove_at(i)
				had_invalid_group = true
		if group.is_empty():
			_control_groups.erase(number)
			had_invalid_group = true
	if had_invalid_group:
		_refresh_control_group_bar()

func _clear_selection() -> void:
	for unit in _selected_units:
		if is_instance_valid(unit):
			unit.selected = false
	_selected_units.clear()
	for entity in _inspected_foreign:
		if is_instance_valid(entity):
			entity.selected = false
	_inspected_foreign.clear()
	portrait_panel.set_selection(_selected_units)
	_refresh_task_panel()

func _raycast_unit(screen_pos: Vector2) -> Node3D:
	return _raycast_service.raycast_unit(screen_pos, UNIT_MASK)

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

func _raycast_enemy_unit(screen_pos: Vector2) -> Node3D:
	return _raycast_service.raycast_enemy_unit(screen_pos, UNIT_MASK)

func _raycast_building(screen_pos: Vector2) -> Node3D:
	return _raycast_service.raycast_building(screen_pos, UNIT_MASK)

## Sends every currently selected unit to chase and swing at `target`.
## Same append_to_queue convention as _issue_move_order: plain right-click
## drops whatever queue the group had going and attacks now; shift-right-
## click appends it as another leg after whatever's already queued instead,
## held until the target is actually dead (see _is_task_complete) before
## the group moves on to its next queued leg.
func _issue_attack_order(units: Array[Node], target: Node3D, append_to_queue: bool = false) -> void:
	if units.is_empty():
		return
	var existing_index := _find_queue_index(units)
	if append_to_queue and existing_index != -1:
		var q: Dictionary = _move_queues[existing_index]
		(q["waypoints"] as Array).append(target.global_position)
		(q["flags"] as Array).append(_spawn_flag(target.global_position))
		(q["tasks"] as Array).append({"kind": "attack", "target": target})
		_renumber_flags(q)
		return

	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var new_queue := {
		"units": units.duplicate(),
		"waypoints": [],
		"flags": [],
		"tasks": [],
		"current_flag": _spawn_flag(target.global_position),
		"current_task": {"kind": "attack", "target": target},
	}
	_move_queues.append(new_queue)
	_renumber_flags(new_queue)
	for unit in units:
		unit.order_attack(target)
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
		(q["tasks"] as Array).append({"kind": "pickup", "target": item})
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
		"tasks": [],
		"current_flag": _spawn_flag(target),
		"current_task": {"kind": "pickup", "target": item},
	}
	_move_queues.append(new_queue)
	_renumber_flags(new_queue)
	for unit in units:
		unit.pick_up_item(item)
	item.blink_selection()

## Sends every peasant in the group to gather from `node` (non-peasants
## just walk to it, same auto-detect shape _handle_right_click already used
## inline before this became queue-aware). Same append_to_queue convention
## as every other _issue_*_order: shift-right-click appends it as another
## leg, held until the node is actually depleted (see _is_task_complete)
## before the group advances to its next queued leg.
func _issue_gather_order(units: Array[Node], node: World, append_to_queue: bool) -> void:
	if units.is_empty():
		return
	var target := node.global_position

	var existing_index := _find_queue_index(units)
	if append_to_queue and existing_index != -1:
		var q: Dictionary = _move_queues[existing_index]
		(q["waypoints"] as Array).append(target)
		(q["flags"] as Array).append(_spawn_flag(target))
		(q["tasks"] as Array).append({"kind": "gather", "target": node})
		_renumber_flags(q)
		node.blink_attack_target(2, Entity.GATHER_TARGET_BLINK_COLOR)
		return

	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var new_queue := {
		"units": units.duplicate(),
		"waypoints": [],
		"flags": [],
		"tasks": [],
		"current_flag": _spawn_flag(target),
		"current_task": {"kind": "gather", "target": node},
	}
	_move_queues.append(new_queue)
	_renumber_flags(new_queue)
	_dispatch_task(units, new_queue["current_task"], target)

## Sends every peasant in the group to (re)join constructing/repairing
## `building` (non-peasants just walk to it). Same append_to_queue
## convention as every other _issue_*_order: shift-right-click appends it
## as another leg, held until the building is fully built and at full
## health (see _is_task_complete) before the group advances.
func _issue_build_order(units: Array[Node], building: Building, append_to_queue: bool) -> void:
	if units.is_empty():
		return
	var target := building.global_position

	var existing_index := _find_queue_index(units)
	if append_to_queue and existing_index != -1:
		var q: Dictionary = _move_queues[existing_index]
		(q["waypoints"] as Array).append(target)
		(q["flags"] as Array).append(_spawn_flag(target))
		(q["tasks"] as Array).append({"kind": "build", "target": building})
		_renumber_flags(q)
		return

	if existing_index != -1:
		_free_queue_flags(_move_queues[existing_index])
		_move_queues.remove_at(existing_index)
	var new_queue := {
		"units": units.duplicate(),
		"waypoints": [],
		"flags": [],
		"tasks": [],
		"current_flag": _spawn_flag(target),
		"current_task": {"kind": "build", "target": building},
	}
	_move_queues.append(new_queue)
	_renumber_flags(new_queue)
	_dispatch_task(units, new_queue["current_task"], target)

## Raycasts for a WorldItem under the cursor -- items live on
## WorldItem.ITEM_MASK (an Area3D, not a body), so this needs its own query
## with collide_with_areas on, unlike the body-only lookups above. Falls
## back to the same click-tolerance widening _raycast_unit gets, once a
## direct hit against the item's own (fairly small) pickup collider
## misses, so right-clicking just next to a pickup still collects it.
## Shows ItemTooltipPanel for whichever WorldItem is directly under the
## cursor; if there's no item there, falls back to whichever Entity
## (tree, unit, building -- anything interactable, selectable or not --
## see World.gd/Unit.gd/Building.gd) is under the cursor instead, so
## hovering a tree with nothing selected still shows its name/health.
## Hides the panel only once neither kind of hover target is present.
## Called every _process frame. Skipped entirely while the mouse is over
## any UI Control: a hovered ItemSlotButton already drives the panel
## itself (see the item_hovered/item_unhovered connections in _ready()),
## and anywhere else over UI (the Menu button, an empty panel) shouldn't
## show map-item stats for whatever happens to be underneath it on the
## 3D scene. Uses a plain direct raycast rather than _raycast_item's
## click-tolerance widening -- that widening is meant to make an
## intentional CLICK forgiving, not to make hover trigger on an item the
## cursor isn't actually over.
## Whichever WorldItem or Entity is currently shown (null for neither).
## A single tracker rather than one nullable var per kind -- two
## separate "_hovered_map_item"/"_hovered_map_entity" vars both being
## null is ambiguous between "showing an item" (which always nulls the
## entity tracker out) and "nothing hovered at all", and comparing
## null == null on the wrong one skipped the final hide_item() call
## entirely once the cursor moved off an item onto empty ground --
## confirmed by the tooltip staying up indefinitely after moving the
## cursor away from a weapon pickup. One Variant sidesteps that: it's
## only ever equal to itself.
var _hovered_map_object: Variant = null

func _update_map_item_hover() -> void:
	if get_viewport().gui_get_hovered_control() != null:
		if _hovered_map_object != null:
			_hovered_map_object = null
			item_tooltip_panel.hide_item()
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var item_hit := _raycast(mouse_pos, WorldItem.ITEM_MASK, true, false)
	var hovered: Variant = item_hit["collider"] if not item_hit.is_empty() and item_hit["collider"] is WorldItem else null
	if hovered == null:
		var entity_hit := _raycast(mouse_pos, UNIT_MASK)
		hovered = entity_hit["collider"] if not entity_hit.is_empty() and entity_hit["collider"] is Entity else null
	if hovered == _hovered_map_object:
		return
	_hovered_map_object = hovered
	if hovered is WorldItem:
		item_tooltip_panel.show_item(hovered.item_type)
	elif hovered is Entity:
		item_tooltip_panel.show_entity(hovered.get_tooltip_title(), hovered, hovered.get_tooltip_extra_stats())
	else:
		item_tooltip_panel.hide_item()

func _raycast_item(screen_pos: Vector2) -> WorldItem:
	return _raycast_service.raycast_item(screen_pos, WorldItem.ITEM_MASK)

func _raycast(screen_pos: Vector2, mask: int, collide_with_areas: bool = false, collide_with_bodies: bool = true) -> Dictionary:
	return _raycast_service.raycast(screen_pos, mask, collide_with_areas, collide_with_bodies)
