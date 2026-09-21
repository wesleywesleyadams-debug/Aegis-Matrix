extends Node3D
class_name MapEditorController
## Main script for the map editor (see scenes/MapEditor.tscn) -- a blank
## sandbox scene (no pre-placed roster, unlike Main.tscn) that lets the
## user place any EditorPalette-registered object, pick which player owns
## it, save the layout to GameState.maps_dir(), reload a previously saved
## layout, or hand a saved map straight to Main.tscn for a real playtest
## (see RTSController._load_custom_map, which reads the exact same JSON
## shape this writes).
##
## Reuses RTSCamera.gd for the camera rig and RaycastService.gd for ground
## raycasting -- both already fully general-purpose (RaycastService only
## needs a Camera3D; RTSCamera only needs its own rig node), so neither
## needed any change to work here.

const GROUND_MASK: int = 1
const UNIT_MASK: int = 2

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var palette_panel: Control = $UI/PalettePanel
@onready var player_selector: OptionButton = $UI/BottomBar/PlayerSelector
@onready var save_button: Button = $UI/BottomBar/SaveButton
@onready var load_button: Button = $UI/BottomBar/LoadButton
@onready var test_button: Button = $UI/BottomBar/TestButton
@onready var back_button: Button = $UI/BottomBar/BackButton
@onready var status_label: Label = $UI/BottomBar/StatusLabel
@onready var save_name_panel: Panel = $UI/SaveNamePanel
@onready var save_name_input: LineEdit = $UI/SaveNamePanel/VBox/NameInput
@onready var confirm_save_button: Button = $UI/SaveNamePanel/VBox/ButtonRow/ConfirmSaveButton
@onready var cancel_save_button: Button = $UI/SaveNamePanel/VBox/ButtonRow/CancelSaveButton
@onready var load_list_panel: Panel = $UI/LoadListPanel
@onready var maps_list: VBoxContainer = $UI/LoadListPanel/OuterVBox/ScrollContainer/MapsList
@onready var close_load_button: Button = $UI/LoadListPanel/OuterVBox/CloseButton

var _raycast_service: RaycastService
var _placement: EditorPlacementController
## Every currently-placed object, in placement order -- kept as a flat
## list rather than re-walking Units/Buildings/World each save, since
## deletion (right-click) needs to remove a single specific entry too.
var _placed: Array[Node3D] = []
## category/type_id this same list's parallel entries were placed as --
## a plain Node3D alone can't tell us that back (e.g. every unit's own
## scene is the same ParentUnit.tscn), so this is tracked alongside
## rather than re-derived.
var _placed_meta: Array[Dictionary] = []

## Path most recently saved to/loaded from, so "Test This Map" and
## repeat "Save" both have somewhere sane to go without prompting again.
var _current_map_path: String = ""

func _ready() -> void:
	_raycast_service = RaycastService.new(camera)
	_placement = EditorPlacementController.new(self, _raycast_service)

	player_selector.clear()
	player_selector.add_item("Player 1", 1)
	player_selector.add_item("Player 2", 2)
	player_selector.select(0)

	_build_palette()

	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	test_button.pressed.connect(_on_test_pressed)
	back_button.pressed.connect(_on_back_pressed)
	confirm_save_button.pressed.connect(_on_confirm_save_pressed)
	cancel_save_button.pressed.connect(func() -> void: save_name_panel.visible = false)
	close_load_button.pressed.connect(func() -> void: load_list_panel.visible = false)
	save_name_panel.visible = false
	load_list_panel.visible = false
	status_label.text = ""

	if GameState.load_map_on_start:
		GameState.load_map_on_start = false
		_load_map(GameState.load_map_path)

## One collapsible section + one button per entry, for every category
## EditorPalette knows about -- built once at startup since the palette's
## own contents (unlike ItemDefs-derived "Item" entries, which are read
## live) don't change while the editor is open.
func _build_palette() -> void:
	for category in EditorPalette.categories().keys():
		var section := Label.new()
		section.text = category
		section.add_theme_font_size_override("font_size", 14)
		palette_panel.add_child(section)
		for entry in EditorPalette.categories()[category]:
			var button := Button.new()
			button.text = entry["display_name"]
			button.pressed.connect(_on_palette_button_pressed.bind(category, entry["type_id"]))
			palette_panel.add_child(button)

func _on_palette_button_pressed(category: String, type_id: String) -> void:
	var player_id: int = player_selector.get_selected_id()
	_placement.arm(category, type_id, player_id)

func _process(_delta: float) -> void:
	if _placement.pending:
		_placement.update_ghost(get_viewport().get_mouse_position(), GROUND_MASK)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _placement.pending:
			var category := _placement.category
			var type_id := _placement.type_id
			var instance := _placement.confirm_placement()
			if instance != null:
				_placed.append(instance)
				_placed_meta.append({"category": category, "type_id": type_id})
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _placement.pending:
				_placement.disarm()
				get_viewport().set_input_as_handled()
			else:
				_try_delete_under_cursor(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _placement.pending:
		_placement.disarm()
		get_viewport().set_input_as_handled()

## Right-click (while nothing's armed) deletes whatever placed object is
## under the cursor -- reuses RaycastService's own click-tolerance-
## widened unit/building lookup rather than a fresh raycast, since a
## placed unit/building has exactly the same clickable footprint here as
## it would in a real match.
func _try_delete_under_cursor(screen_pos: Vector2) -> void:
	var target := _raycast_service.raycast_unit(screen_pos, UNIT_MASK)
	if target == null:
		return
	var idx := _placed.find(target)
	if idx == -1:
		return
	_placed.remove_at(idx)
	_placed_meta.remove_at(idx)
	target.queue_free()

func _on_save_pressed() -> void:
	save_name_input.text = _current_map_path.get_file().get_basename()
	save_name_panel.visible = true
	save_name_input.grab_focus()

func _on_confirm_save_pressed() -> void:
	var map_name := save_name_input.text.strip_edges()
	if map_name.is_empty():
		map_name = "map"
	save_name_panel.visible = false

	var objects: Array = []
	for i in _placed.size():
		var node := _placed[i]
		if not is_instance_valid(node):
			continue
		var meta := _placed_meta[i]
		var player_id: int = node.player_id if "player_id" in node else 1
		objects.append({
			"category": meta["category"],
			"type_id": meta["type_id"],
			"position": [node.global_position.x, node.global_position.y, node.global_position.z],
			"rotation_y": node.rotation.y,
			"player_id": player_id,
		})

	var maps_dir := GameState.maps_dir()
	DirAccess.make_dir_recursive_absolute(maps_dir)
	var safe_name := map_name.validate_filename()
	var path := "%s/%s.json" % [maps_dir, safe_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"objects": objects}))
	file.close()
	_current_map_path = path
	status_label.text = "Saved as \"%s\"" % map_name

## Returns {"path", "name"} for every saved map, newest first.
func _list_maps() -> Array:
	var maps: Array = []
	var maps_dir := GameState.maps_dir()
	var dir := DirAccess.open(maps_dir)
	if dir == null:
		return maps
	for file_name in DirAccess.get_files_at(maps_dir):
		if not file_name.ends_with(".json"):
			continue
		maps.append({
			"path": "%s/%s" % [maps_dir, file_name],
			"name": file_name.get_basename(),
		})
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return maps

func _on_load_pressed() -> void:
	for child in maps_list.get_children():
		child.queue_free()
	for map in _list_maps():
		var button := Button.new()
		button.text = map["name"]
		button.pressed.connect(func() -> void:
			load_list_panel.visible = false
			_load_map(map["path"])
		)
		maps_list.add_child(button)
	load_list_panel.visible = true

## Clears the current layout and repopulates it from a saved map --
## shares no code with RTSController._load_custom_map (that one loads
## into a real match with combat/nav baking concerns this editor doesn't
## have) but reads the exact same JSON shape, since both ultimately
## resolve through EditorPalette.
func _load_map(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed.has("objects"):
		return

	for node in _placed:
		if is_instance_valid(node):
			node.queue_free()
	_placed.clear()
	_placed_meta.clear()

	for entry in parsed["objects"]:
		var category: String = entry["category"]
		if category == "Item":
			var pos: Array = entry["position"]
			WorldItem.spawn_dropped(entry["type_id"], Vector3(pos[0], pos[1], pos[2]), self)
			continue
		var instance := EditorPalette.instantiate(category, entry["type_id"])
		if instance == null:
			continue
		add_child(instance)
		var pos: Array = entry["position"]
		instance.global_position = Vector3(pos[0], pos[1], pos[2])
		if "rotation_y" in entry:
			instance.rotation.y = entry["rotation_y"]
		if "player_id" in instance:
			instance.player_id = entry.get("player_id", 1)
		_placed.append(instance)
		_placed_meta.append({"category": category, "type_id": entry["type_id"]})

	_current_map_path = path
	status_label.text = "Loaded \"%s\"" % path.get_file().get_basename()

## Saves (if there's anything unsaved yet, prompting the name popup
## first would interrupt "Test" with an extra click every time -- so this
## always writes straight to _current_map_path, only falling back to the
## Save popup if nothing's ever been saved this session) then hands off
## to Main.tscn the same way MainMenu's own Load does for a real save.
func _on_test_pressed() -> void:
	if _current_map_path.is_empty():
		_on_save_pressed()
		return
	GameState.load_map_on_start = true
	GameState.load_map_path = _current_map_path
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")
