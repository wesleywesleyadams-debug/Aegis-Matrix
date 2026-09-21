extends Panel
## Single bottom-left panel that swaps its contents based on what's
## selected -- a Unit shows the Build/Stop/Attack-Move (+ stub) command
## icons, a training-capable Building (see Building.can_train)
## shows the train-queue/upgrades UI instead. Merges what used to be three
## separate sibling panels (UnitBackpackPanel, CommandCardPanel,
## TrainingUpgradesPanel) into one, per user request -- the pre-merge
## state is preserved on the "backup/panel-consolidation-pre-merge" branch
## on GitHub.
##
## No equipment/backpack UI here at all -- that existed briefly (first
## merged in from UnitBackpackPanel, then shrunk to a single row) but was
## removed entirely per explicit user request; see the "backup/pre-
## backpack-removal" branch on GitHub for that last state before removal,
## including the ItemSlotButton-based wiring this file used to have.
##
## Same division of responsibility as every other HUD panel here: this
## only displays state and reports interaction via signals, RTSController/
## Building own the actual train/command logic.

signal build_pressed
signal stop_pressed
signal attack_move_pressed
## Emitted when a specific building icon is chosen from the build submenu
## (see _show_build_menu) -- RTSController arms placement for that exact
## type via BuildPlacementController.set_building_type. Does NOT replace
## build_pressed: the B hotkey still arms the plain generic building
## immediately (unchanged, existing behavior) -- this submenu is purely
## an additional, slower-but-richer path reached by clicking the Build
## icon specifically.
signal build_type_selected(type_id: String)
## Repair is real now too (RTSController arms a click-to-target repair
## order, see its _on_command_card_repair_pressed/Unit.repair_building) --
## Seek Shelter/Garrison are the only two still-stub signals left, with no
## backend behind them (RTSController connects both to a stub handler that
## just acknowledges the click, until a real shelter/garrison system
## exists). Build Military used to be a stub here too, but now opens the
## same real build submenu as Build (see BUILD_MENU_SIGNALS) with the
## military-flavored subset of building types instead.
signal repair_pressed
signal seek_shelter_pressed
signal garrison_pressed
## Peasant-only, same "arm, then click a target" shape as Repair -- click
## a ground spot to spend 1 Acorn/1 Apple and plant a seedling there (see
## RTSController._on_command_card_plant_oak_pressed/_issue_plant_click).
signal plant_oak_pressed
signal plant_apple_pressed

## -- Unit mode: command card icons (same as the old CommandCardPanel) --
## Build/Build Military/Stop/Attack/Repair are real, working commands
## (Stop/Attack mirror the H/Tab hotkeys exactly; Build/Build Military
## open the build submenu below with a different subset of types each --
## see BUILD_MENU_SIGNALS; Repair arms a click-a-building order). Seek
## Shelter/Garrison are UI-only stubs for now -- see the *_pressed
## signals' own doc comment.
const COMMAND_BUTTON_SIZE: Vector2 = Vector2(48, 48)
const COMMAND_GRID_COLUMNS: int = 4
const COMMANDS: Array[Dictionary] = [
	{"label": "Build", "color": Color(0.55, 0.4, 0.25), "signal_name": "build_pressed"},
	{"label": "Stop", "color": Color(0.7, 0.25, 0.2), "signal_name": "stop_pressed"},
	{"label": "Attack", "color": Color(0.6, 0.2, 0.2), "signal_name": "attack_move_pressed"},
	{"label": "Build Military", "color": Color(0.45, 0.3, 0.2), "signal_name": "build_military_pressed"},
	{"label": "Repair", "color": Color(0.35, 0.55, 0.3), "signal_name": "repair_pressed"},
	{"label": "Seek Shelter", "color": Color(0.3, 0.4, 0.6), "signal_name": "seek_shelter_pressed"},
	{"label": "Garrison", "color": Color(0.5, 0.45, 0.2), "signal_name": "garrison_pressed"},
	{"label": "Plant Oak", "color": Color(0.5, 0.4, 0.15), "signal_name": "plant_oak_pressed"},
	{"label": "Plant Apple", "color": Color(0.35, 0.55, 0.25), "signal_name": "plant_apple_pressed"},
]
## Which COMMANDS signal_name opens the build submenu, and which building
## types it shows -- "build_pressed" (the plain Build icon) shows economy
## structures, "build_military_pressed" (Build Military) shows the
## defensive/military ones. Both funnel into the exact same submenu
## mechanism (_show_build_menu) and the exact same build_type_selected
## signal -- RTSController doesn't need to know which button opened it.
const BUILD_MENU_SIGNALS: Dictionary = {
	"build_pressed": "ECONOMY",
	"build_military_pressed": "MILITARY",
}

## -- Building mode: train/upgrade buttons (same as the old TrainingUpgradesPanel) --
## "peasant" first, matching Castle's own build-menu-adjacent priority as
## the basic worker unit -- costs Building.PEASANT_TRAIN_COST, checked/
## spent in _on_train_pressed before queue_training is ever called; the
## other four are still free (no cost defined for them yet).
const TRAINABLE_TYPES: Array[String] = ["peasant", "squire", "apprentice", "knight", "mage"]
const TRAINABLE_TYPE_COLORS: Dictionary = {
	"peasant": Color(0.8, 0.7, 0.5),
	"squire": Color(0.55, 0.55, 0.6),
	"apprentice": Color(0.55, 0.35, 0.75),
	"knight": Color(0.75, 0.75, 0.8),
	"mage": Color(0.25, 0.65, 0.7),
}
const UPGRADES: Array[String] = ["Wild Rot"]
const TRAIN_ICON_SIZE: float = 28.0
const QUEUE_ICON_SIZE: float = 20.0

## -- Unit mode: build submenu, shown in place of the command grid while
## picking a building type (see _show_build_menu) -- one entry per real
## EditorPalette "Building" scene, split into the same two groups the
## Build/Build Military icons open (see BUILD_MENU_SIGNALS). Deliberately
## excludes "wall": it shares ParentBuilding.tscn with "building" (no
## distinct Wall scene exists yet -- see EditorPalette.BUILDINGS' own doc
## comment), so listing it here as if it were a real separate structure
## would be misleading.
const ECONOMY_BUILD_TYPES: Array[Dictionary] = [
	{"type_id": "building", "label": "Building", "color": Color(0.55, 0.4, 0.25)},
	{"type_id": "hut", "label": "Hut", "color": Color(0.6, 0.45, 0.3)},
]
const MILITARY_BUILD_TYPES: Array[Dictionary] = [
	{"type_id": "tower", "label": "Tower", "color": Color(0.5, 0.5, 0.55)},
	{"type_id": "castle", "label": "Castle", "color": Color(0.45, 0.4, 0.6)},
]
const BUILD_ICON_SIZE: float = 44.0

@onready var unit_section: Control = $UnitSection
@onready var command_buttons_root: Control = $UnitSection/CommandButtons
@onready var build_menu_root: Control = $UnitSection/BuildMenu
@onready var build_type_buttons_root: Control = $UnitSection/BuildMenu/BuildTypeButtons
@onready var building_section: Control = $BuildingSection
@onready var train_buttons_root: Control = $BuildingSection/TrainSection/TrainButtons
@onready var queue_icons_root: Control = $BuildingSection/TrainSection/QueueRow/QueueIcons
@onready var queue_progress: ProgressBar = $BuildingSection/TrainSection/QueueRow/ProgressBar
@onready var upgrade_buttons_root: Control = $BuildingSection/UpgradeSection/UpgradeButtons

var _building: Building = null
## Set externally by RTSController right after both nodes are ready --
## needed here to check/spend a training cost (peasant) before actually
## queuing it. Null-checked before use so this file never hard-depends
## on RTSController's own wiring order.
var resource_hud: ResourceHUD = null

## signal_name -> its own Button, so set_armed_command can highlight
## whichever one (if any) RTSController currently has armed as a pending
## click-a-target order (Repair, Garrison, ...) -- see that func's own
## doc comment for why this exists.
var _command_buttons: Dictionary = {}

## upgrade_name -> its own Button -- same "keep a handle so _process can
## keep it updated" reasoning as _command_buttons, but here it's
## Building.get_research_progress()/researched_upgrades driving the
## button's own text/enabled state each frame (see
## _refresh_upgrade_buttons) rather than a pending click-target order.
var _upgrade_buttons: Dictionary = {}
## upgrade_name -> its own ProgressBar, shown in the button's own place
## (same HBoxContainer slot) while researching -- see the user's own
## "button should disappear, [a bar] should show" request. Re-appearing
## the button on cancel is just switching visibility back the other way
## (see _refresh_upgrade_buttons); nothing about the button itself changes.
var _upgrade_progress_bars: Dictionary = {}

func _ready() -> void:
	visible = false
	build_menu_root.visible = false
	for command in COMMANDS:
		command_buttons_root.add_child(_build_command_button(command))
	build_menu_root.add_child(_build_back_button())
	for type_id in TRAINABLE_TYPES:
		train_buttons_root.add_child(_build_train_button(type_id))
	for upgrade_name in UPGRADES:
		var button := Button.new()
		button.text = upgrade_name
		button.custom_minimum_size = Vector2(84, 28)
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = "Click to research"
		button.pressed.connect(_on_upgrade_pressed.bind(upgrade_name))
		upgrade_buttons_root.add_child(button)
		_upgrade_buttons[upgrade_name] = button

		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(84, 28)
		progress.min_value = 0.0
		progress.max_value = 100.0
		progress.show_percentage = true
		progress.mouse_filter = Control.MOUSE_FILTER_STOP
		progress.tooltip_text = "Click to cancel"
		progress.visible = false
		progress.gui_input.connect(_on_upgrade_progress_gui_input.bind(upgrade_name))
		upgrade_buttons_root.add_child(progress)
		_upgrade_progress_bars[upgrade_name] = progress

## Square, black-background, with the command's own name as visible text
## on the button (not just a tooltip) -- word-wrapped since some labels
## ("Seek Shelter", "Build Military") are too long for a single line at
## this size.
func _build_command_button(command: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = COMMAND_BUTTON_SIZE
	button.text = command["label"]
	button.tooltip_text = command["label"]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = false
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_stylebox_override("normal", _command_button_style())
	button.add_theme_stylebox_override("hover", _command_button_style())
	button.add_theme_stylebox_override("pressed", _command_button_style())
	button.add_theme_stylebox_override("focus", _command_button_style())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	# Build/Build Military open the build submenu (see BUILD_MENU_SIGNALS)
	# with their own subset of building types instead of emitting their
	# signal directly -- everything else just emits its own signal as normal.
	if command["signal_name"] in BUILD_MENU_SIGNALS:
		var group: String = BUILD_MENU_SIGNALS[command["signal_name"]]
		button.pressed.connect(_show_build_menu.bind(group))
	else:
		button.pressed.connect(func() -> void: emit_signal(command["signal_name"]))
	_command_buttons[command["signal_name"]] = button
	return button

## Highlights whichever command button (Repair, Garrison, ...) is currently
## armed and waiting for a click-a-target, or clears every highlight if
## none is (pass "" or any unrecognized name) -- without this, arming a
## pending order was completely invisible, so a player unsure whether
## their first click registered would naturally click the button again,
## silently disarming it, right before their real target click landed as
## a plain select/move instead of the order they meant to give.
## RTSController is the single source of truth for which pending flag (if
## any) is currently true; this only ever mirrors that, never decides it.
func set_armed_command(signal_name: String) -> void:
	for name in _command_buttons:
		var button: Button = _command_buttons[name]
		button.add_theme_stylebox_override(
			"normal", _command_button_style(name == signal_name)
		)

## Swaps the command grid out for a row of specific building icons --
## picking one emits build_type_selected and closes the submenu again;
## the Back button closes it without picking anything. Rebuilds
## build_type_buttons_root fresh each call since Build and Build Military
## show different type lists through this same container.
func _show_build_menu(group: String) -> void:
	# free(), not queue_free() -- queue_free() is deferred, so the stale
	# children would still be in the tree (and returned by get_children())
	# when a same-frame re-call rebuilds this from a different group,
	# leaking last time's buttons in alongside the new ones.
	for child in build_type_buttons_root.get_children():
		child.free()
	_build_type_buttons.clear()
	var types: Array[Dictionary] = MILITARY_BUILD_TYPES if group == "MILITARY" else ECONOMY_BUILD_TYPES
	for build_type in types:
		var button := _build_build_type_button(build_type)
		build_type_buttons_root.add_child(button)
		_build_type_buttons[build_type["type_id"]] = button
	_refresh_build_type_buttons()
	command_buttons_root.visible = false
	build_menu_root.visible = true

func _hide_build_menu() -> void:
	build_menu_root.visible = false
	command_buttons_root.visible = true

## type_id -> its own Button, so _refresh_build_type_buttons can grey out
## whichever ones the human player can no longer afford (see
## BuildingDefs.get_cost/ResourceHUD.can_afford) -- rebuilt fresh each
## _show_build_menu call since the submenu's own contents change (economy
## vs military types).
var _build_type_buttons: Dictionary = {}
## type_id -> its own red UNAFFORDABLE_OVERLAY_COLOR ColorRect (see
## _add_unaffordable_overlay) -- toggled alongside .disabled in
## _refresh_build_type_buttons.
var _build_type_overlays: Dictionary = {}

## Disables (greys out) any build-type button the human player can't
## currently afford -- called once when the submenu opens and every frame
## it stays open (see _process), since resources can change while it's
## sitting there (a peasant finishing a delivery, another build's cost
## landing first).
func _refresh_build_type_buttons() -> void:
	if resource_hud == null:
		return
	for type_id in _build_type_buttons:
		var button: Button = _build_type_buttons[type_id]
		var unaffordable := not resource_hud.can_afford(GameState.human_player_id, BuildingDefs.get_cost(type_id))
		button.disabled = unaffordable
		var overlay: ColorRect = _build_type_overlays.get(type_id)
		if overlay != null:
			overlay.visible = unaffordable

## Translucent red laid over any button (build type, or in principle
## anything else with the same "greyed out via .disabled when unaffordable"
## shape) the human player currently can't afford -- per the user's own
## "if you can't afford it, it will have a red shader over the button"
## request, generalizing the same visual PathSlot.UNAFFORDABLE_OVERLAY_COLOR
## already uses for path nodes.
const UNAFFORDABLE_OVERLAY_COLOR: Color = Color(1.0, 0.0, 0.0, 0.35)

## Adds a hidden red overlay ColorRect as `button`'s own last child (so it
## draws on top of the swatch/label already added) and returns it --
## callers toggle `.visible` each refresh (see _refresh_build_type_buttons)
## rather than adding/removing the node each time.
func _add_unaffordable_overlay(button: Button, over_size: Vector2) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = UNAFFORDABLE_OVERLAY_COLOR
	overlay.size = over_size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	button.add_child(overlay)
	return overlay

func _build_build_type_button(build_type: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(BUILD_ICON_SIZE + 10, BUILD_ICON_SIZE + 20)
	button.pressed.connect(func() -> void:
		emit_signal("build_type_selected", build_type["type_id"])
		_hide_build_menu()
	)

	var swatch := ColorRect.new()
	swatch.color = build_type["color"]
	swatch.custom_minimum_size = Vector2(BUILD_ICON_SIZE, BUILD_ICON_SIZE)
	swatch.position = Vector2(5, 4)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(swatch)

	var label := Label.new()
	label.text = build_type["label"]
	label.position = Vector2(0, BUILD_ICON_SIZE + 6)
	label.size = Vector2(BUILD_ICON_SIZE + 10, 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)

	_build_type_overlays[build_type["type_id"]] = _add_unaffordable_overlay(button, Vector2(BUILD_ICON_SIZE + 10, BUILD_ICON_SIZE + 20))

	return button

func _build_back_button() -> Button:
	var button := Button.new()
	button.text = "Back"
	button.position = Vector2(0, BUILD_ICON_SIZE + 30)
	button.size = Vector2(64, 26)
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(_hide_build_menu)
	return button

## `armed` (see set_armed_command) swaps in a bright border and a lighter
## fill so a pending click-a-target order reads as visibly "on" -- every
## other button stays the plain black default.
func _command_button_style(armed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.22, 0.05, 1) if armed else Color(0, 0, 0, 1)
	style.border_width_left = 2 if armed else 1
	style.border_width_top = 2 if armed else 1
	style.border_width_right = 2 if armed else 1
	style.border_width_bottom = 2 if armed else 1
	style.border_color = Color(1, 0.85, 0.2, 1) if armed else Color(0.35, 0.22, 0.12, 1)
	return style

## A small colored swatch (stand-in for real art) stacked above the type
## name, the whole thing clickable as one unit -- children have
## mouse_filter = IGNORE so clicks always reach the underlying Button
## rather than getting absorbed by the swatch/label on top of it.
func _build_train_button(type_id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(TRAIN_ICON_SIZE + 10, TRAIN_ICON_SIZE + 20)
	button.pressed.connect(_on_train_pressed.bind(type_id))

	var swatch := ColorRect.new()
	swatch.color = TRAINABLE_TYPE_COLORS.get(type_id, Color.GRAY)
	swatch.custom_minimum_size = Vector2(TRAIN_ICON_SIZE, TRAIN_ICON_SIZE)
	swatch.position = Vector2(5, 4)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(swatch)

	var label := Label.new()
	label.text = type_id.capitalize()
	label.position = Vector2(0, TRAIN_ICON_SIZE + 6)
	label.size = Vector2(TRAIN_ICON_SIZE + 10, 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)

	return button

func _process(_delta: float) -> void:
	if building_section.visible:
		_refresh_queue_display()
		_refresh_upgrade_buttons()
	if build_menu_root.visible:
		_refresh_build_type_buttons()

func _on_train_pressed(type_id: String) -> void:
	if _building == null:
		return
	if type_id == "peasant":
		if resource_hud == null or not resource_hud.spend_resources(GameState.human_player_id, Building.PEASANT_TRAIN_COST):
			return
	_building.queue_training(type_id)
	_refresh_queue_display()

## Starts researching -- a no-op if `_building` has already finished
## this upgrade, or something else is already researching (Building only
## has one research slot -- see Building.start_research's own refusal).
## Cancelling is now done by clicking the progress bar that replaces
## this button while researching, not by clicking this button again --
## see _on_upgrade_progress_gui_input.
func _on_upgrade_pressed(upgrade_name: String) -> void:
	if _building == null or upgrade_name in _building.researched_upgrades:
		return
	_building.start_research(upgrade_name)
	_refresh_upgrade_buttons()

## Cancelling a research is a click on its OWN progress bar (the thing
## that's actually visible while researching -- the button itself is
## hidden, see _refresh_upgrade_buttons), per the user's own "if the tech
## is cancelled while researching the button should reappear" request.
func _on_upgrade_progress_gui_input(event: InputEvent, upgrade_name: String) -> void:
	if _building == null or not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _building.researching_upgrade == upgrade_name:
		_building.cancel_research()
		_refresh_upgrade_buttons()

## Keeps every upgrade's button-vs-progress-bar visibility (and the bar's
## own fill amount) in sync with `_building`'s own researching_upgrade/
## researched_upgrades -- called every frame (see _process) the same way
## _refresh_queue_display is, since Building's timer ticks on its own
## _physics_process independent of any button click. The button
## disappears (visible = false) the instant research starts and
## reappears the instant it's cancelled or finishes -- see this class's
## own doc comment on _upgrade_progress_bars for why cancelling now
## happens on the bar itself rather than the (hidden) button.
func _refresh_upgrade_buttons() -> void:
	if _building == null:
		return
	for upgrade_name in _upgrade_buttons:
		var button: Button = _upgrade_buttons[upgrade_name]
		var progress: ProgressBar = _upgrade_progress_bars[upgrade_name]
		if upgrade_name in _building.researched_upgrades:
			button.visible = true
			progress.visible = false
			# Just "Researched", not "Wild Rot ✓" -- the button is a fixed
			# 84px wide, and the full name-plus-checkmark form silently
			# clipped down to unreadable "Wild R" with the checkmark cut
			# off entirely. The tooltip still names which upgrade this is.
			button.text = "Researched"
			button.disabled = true
		elif _building.researching_upgrade == upgrade_name:
			button.visible = false
			progress.visible = true
			progress.value = _building.get_research_progress() * 100.0
		else:
			button.visible = true
			progress.visible = false
			button.text = upgrade_name
			button.disabled = false

## `unit`/`building` are mutually exclusive by construction (a selection
## is never simultaneously a Unit and a Building) -- exactly one, or
## neither, is ever non-null. Hides this whole panel when both are null.
func refresh(unit: Unit, building: Building) -> void:
	_building = building
	var show_unit_section: bool = unit != null
	var show_building_section: bool = building != null and building.can_train
	# Always visible, per this game's HUD design -- selecting a
	# non-trainable building (a Tower, an unfinished foundation) or
	# nothing at all just means both inner sections stay hidden, not that
	# the whole panel disappears.
	visible = true
	unit_section.visible = show_unit_section
	building_section.visible = show_building_section
	if show_unit_section:
		_hide_build_menu()
	if show_building_section:
		_refresh_queue_display()
		_refresh_upgrade_buttons()

func _refresh_queue_display() -> void:
	if _building == null:
		return
	for child in queue_icons_root.get_children():
		child.free()
	var queue: Array[String] = _building.get_training_queue()
	for index in queue.size():
		var type_id: String = queue[index]
		queue_icons_root.add_child(_build_queue_icon_button(type_id, index))
	queue_progress.value = _building.get_queue_progress() * 100.0 if not queue.is_empty() else 0.0

## One queued-training icon, left-clickable to cancel that specific entry
## (see Building.cancel_training) -- a plain swatch button, same "child
## ignores the mouse so clicks always reach the Button" shape as
## _build_train_button, plus a tooltip spelling out the click actually
## does something, since nothing else about a small colored square
## suggests it.
func _build_queue_icon_button(type_id: String, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(QUEUE_ICON_SIZE, QUEUE_ICON_SIZE)
	button.tooltip_text = "%s (click to cancel)" % type_id.capitalize()
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_on_queue_icon_pressed.bind(index))

	var swatch := ColorRect.new()
	swatch.color = TRAINABLE_TYPE_COLORS.get(type_id, Color.GRAY)
	swatch.custom_minimum_size = Vector2(QUEUE_ICON_SIZE, QUEUE_ICON_SIZE)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(swatch)

	return button

func _on_queue_icon_pressed(index: int) -> void:
	if _building == null:
		return
	_building.cancel_training(index)
	# Deferred, not immediate -- this runs from inside the clicked button's
	# own "pressed" signal, and _refresh_queue_display() frees every queue
	# icon (including the one still mid-emit) to rebuild the row; freeing a
	# Node while it's still emitting a signal is a locked-object error.
	# _process() would also eventually catch this same rebuild on its own,
	# but not doing it here too would leave a one-frame-stale queue row.
	_refresh_queue_display.call_deferred()
