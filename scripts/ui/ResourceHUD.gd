extends PanelContainer
class_name ResourceHUD
## Top-left HUD bar, AoE2:DE's own top-bar formula: one icon+count pair
## per resource (Acorns, Apples, Mist, Crystal -- this game's 4x economy;
## Grace is gone entirely, no code anywhere should reference it), then
## Villagers, Population ("cur/cap"), and Idle Villagers, in that left-
## to-right order. There used to be an Age icon + "X Age" label after
## that -- this game never had a real age/era system, only a fixed
## placeholder label, and it's been replaced entirely by the Paths
## system (see PathDefs/PathState/PathsPanel) instead of ever being
## built out, so it's removed rather than left sitting there unused.
## A PanelContainer (light brown fill, dark brown border -- see
## PANEL_STYLE) wrapping a single inner HBoxContainer (see _row), rather
## than being the HBoxContainer itself, so the whole bar reads as one
## bordered strip instead of just floating icons over the game world.
## Icons are ResourceIcon instances (procedurally drawn glyphs, not real
## art -- see that script's own doc comment), square and a bit larger
## than this HUD's very first version.
##
## Resource banking is real (per player_id, see get_resource/add_resource/
## spend_resources below -- the actual economy backend other scripts call
## into, e.g. BuildPlacementController.confirm_placement, TaskPanel's
## peasant-training cost, and now PathTreeModal's own path-following
## cost). Villager/idle/population counts are read live off the "units"/
## "buildings" groups each refresh, same throttled-timer shape
## PlayerListPanel's own _refresh uses, rather than tracked as a running
## total.
##
## The whole bar only ever reflects the human player's own economy/army
## (see GameState.human_player_id) -- same "one on-screen number" scope
## the old single-Label Grace counter had.

## Display order, left to right -- matches AoE2:DE's own resource-bar
## ordering convention (food/wood-equivalent commons first, rarer
## resources after).
const RESOURCE_ORDER: Array[String] = ["acorns", "apples", "mist", "crystal"]
## Resource name -> starting stockpile. Acorns/Apples (the common,
## everyday resources) start higher than Crystal/Mist (the rarer,
## stronger-building resources) -- see BuildingDefs.get_cost's own doc
## comment for how building costs draw on this same rarity split.
const STARTING_AMOUNTS: Dictionary = {
	"acorns": 200,
	"apples": 200,
	"crystal": 50,
	"mist": 50,
}

const IDLE_BLINK_INTERVAL: float = 0.5
## Square icon size -- larger than this HUD's very first version (plain
## 20px ColorRects), big enough for ResourceIcon's drawn glyphs to
## actually read at a glance.
const ICON_SIZE: float = 28.0
const REFRESH_INTERVAL: float = 0.5

## Reserved width for one of the 4 resource count labels (Acorns/Apples/
## Mist/Crystal) -- wide enough for 6 digits at this label's own font
## size (18, see _build_count_label), so a resource ticking up from a
## single digit into the hundreds/thousands never changes that label's
## own width, which is what was making the whole bar (an HBoxContainer,
## sized to fit its children -- see _row) keep resizing/reflowing every
## time any count crossed a digit boundary. Left-aligned text (Label's
## own default) just leaves blank space after a short number rather than
## centering/shifting it, so the icon-to-number gap stays fixed too.
const RESOURCE_COUNT_MIN_WIDTH: float = 70.0

## Light brown fill, dark brown border -- wraps the whole bar in one
## bordered strip rather than floating icons over the game world.
const PANEL_BG_COLOR: Color = Color(0.62, 0.48, 0.32)
const PANEL_BORDER_COLOR: Color = Color(0.3, 0.2, 0.1)

## player_id -> {resource_name -> amount}.
var _resources: Dictionary = {}

var _row: HBoxContainer = null
var _resource_count_labels: Dictionary = {}
var _peasant_count_label: Label = null
var _population_label: Label = null
var _idle_count_label: Label = null
var _idle_icon: ResourceIcon = null

var _elapsed: float = 0.0
var _idle_blink_elapsed: float = 0.0
var _idle_blink_on: bool = false

func _ready() -> void:
	_resources[1] = STARTING_AMOUNTS.duplicate()
	_resources[2] = STARTING_AMOUNTS.duplicate()

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(3)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 14)
	add_child(_row)

	for resource_name in RESOURCE_ORDER:
		_row.add_child(_build_icon_count_pair(resource_name, resource_name.capitalize(), RESOURCE_COUNT_MIN_WIDTH))
		_resource_count_labels[resource_name] = _last_built_label

	_row.add_child(_build_separator())
	_row.add_child(_build_icon_count_pair("peasant", "Villagers"))
	_peasant_count_label = _last_built_label

	_row.add_child(_build_separator())
	_row.add_child(_build_icon_count_pair("population", "Population"))
	_population_label = _last_built_label

	_row.add_child(_build_separator())
	var idle_pair := _build_icon_count_pair("idle", "Idle villagers -- click (or press '.') to jump to the nearest one")
	_row.add_child(idle_pair)
	_idle_icon = _last_built_icon
	_idle_count_label = _last_built_label
	# STOP, not the Control default IGNORE -- this pair needs to actually
	# receive the click below rather than letting it fall through to
	# whatever's behind the HUD panel.
	idle_pair.mouse_filter = Control.MOUSE_FILTER_STOP
	idle_pair.gui_input.connect(_on_idle_pair_gui_input)

	_refresh()

## Left-clicking the idle-villagers icon/count is the same command as the
## "." hotkey (see RTSController._unhandled_input) -- both just emit this
## signal and let RTSController do the actual find-nearest-idle-peasant/
## select/recenter work, since this HUD has no camera or selection state
## of its own to act on directly.
signal idle_villagers_clicked

func _on_idle_pair_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		idle_villagers_clicked.emit()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		_refresh()
	_update_idle_blink(delta)

## Ticks the idle-villager icon's blink independent of REFRESH_INTERVAL
## (blinking needs to keep animating smoothly regardless of how often
## counts themselves actually change) -- swaps its whole glyph to a
## bright yellow warning tint every IDLE_BLINK_INTERVAL while any
## villager is idle; holds its normal look otherwise.
func _update_idle_blink(delta: float) -> void:
	if _idle_icon == null:
		return
	var any_idle: bool = _idle_count_label.text != "0"
	if not any_idle:
		_idle_blink_on = false
		_idle_blink_elapsed = 0.0
		_idle_icon.modulate = Color.WHITE
		return
	_idle_blink_elapsed += delta
	if _idle_blink_elapsed >= IDLE_BLINK_INTERVAL:
		_idle_blink_elapsed = 0.0
		_idle_blink_on = not _idle_blink_on
		_idle_icon.modulate = Color(1.4, 1.2, 0.3) if _idle_blink_on else Color.WHITE

## One ResourceIcon + one count Label, side by side -- stashes both in
## `_last_built_icon`/`_last_built_label` for the caller to grab, since
## GDScript has no multi-value return and every call site here
## immediately needs at least the label (the idle pair also needs the
## icon, for blinking).
var _last_built_icon: ResourceIcon = null
var _last_built_label: Label = null
## `label_min_width` is 0.0 (no reservation, sized to fit whatever text
## it currently holds) for every caller except the 4 primary resources --
## see RESOURCE_COUNT_MIN_WIDTH's own doc comment for why only those
## get a fixed-width label; Villagers/Population/Idle Villagers realistically
## never run past a couple digits, so reserving 6-figures'-worth of empty
## space there would just be wasted bar width for no visible benefit.
func _build_icon_count_pair(icon_type: String, tooltip: String, label_min_width: float = 0.0) -> HBoxContainer:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 4)
	var icon := ResourceIcon.new()
	icon.icon_type = icon_type
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.tooltip_text = tooltip
	pair.add_child(icon)
	var label := _build_count_label()
	label.custom_minimum_size.x = label_min_width
	pair.add_child(label)
	_last_built_icon = icon
	_last_built_label = label
	return pair

## White, no outline/border -- per this HUD's own redesign (the original
## gold-with-brown-outline text no longer applies now the bar has its own
## bordered background to read against).
func _build_count_label() -> Label:
	var label := Label.new()
	label.text = "0"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## A thin blank gap -- visually groups resources / villagers / population
## / idle into their own clusters, same segmented look AoE2:DE's
## own top bar has, rather than one undifferentiated row of icons.
func _build_separator() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	return gap

func get_resource(player_id: int, resource_name: String) -> int:
	return _resources.get(player_id, {}).get(resource_name, 0)

## Path of Avalon -- "+30% to all resource income" applies here, the one
## true entry point every gain (gathering, refunds, path/tech drop
## bonuses) already goes through -- but only to actual INCOME (a
## positive amount): spend_resources also routes its own deductions
## through this same function with a NEGATIVE amount, and Avalon boosting
## what a player pays would be backwards.
func add_resource(player_id: int, resource_name: String, amount: int) -> void:
	if amount > 0:
		amount = int(amount * PathPerks.resource_income_multiplier(player_id))
	if not _resources.has(player_id):
		_resources[player_id] = STARTING_AMOUNTS.duplicate()
	_resources[player_id][resource_name] = get_resource(player_id, resource_name) + amount
	if player_id == GameState.human_player_id:
		_refresh()

## Read-only affordability check -- same comparison spend_resources does,
## without ever deducting anything. Lets a caller (e.g. TaskPanel's build
## menu) grey out an option it can't afford yet without having to spend
## first and refund on failure.
func can_afford(player_id: int, cost: Dictionary) -> bool:
	for resource_name in cost:
		if cost[resource_name] > get_resource(player_id, resource_name):
			return false
	return true

## Returns true and deducts every resource in `cost` (resource_name ->
## amount) if that player can afford ALL of them; false (no change at
## all -- never a partial spend) otherwise. The usual "can afford it"
## pattern for building/training costs (see BuildingDefs.get_cost,
## Building.PEASANT_TRAIN_COST, PathDefs.get_cost). This is the one true
## entry point every resource spend in the whole game already goes
## through, which is exactly why the "couldn't afford it" flash (see
## _show_insufficient_funds) lives here instead of at each individual
## call site -- building placement, training, and path-following all
## get the same feedback for free.
func spend_resources(player_id: int, cost: Dictionary) -> bool:
	for resource_name in cost:
		if cost[resource_name] > get_resource(player_id, resource_name):
			if player_id == GameState.human_player_id:
				_show_insufficient_funds()
			return false
	for resource_name in cost:
		add_resource(player_id, resource_name, -cost[resource_name])
	return true

## Looked up lazily (not @onready) since InsufficientFundsNotice is a
## sibling under UI, not a child of this HUD -- see Main.tscn.
var _insufficient_funds_notice: InsufficientFundsNotice = null
func _show_insufficient_funds() -> void:
	if _insufficient_funds_notice == null:
		_insufficient_funds_notice = get_tree().current_scene.get_node_or_null("UI/InsufficientFundsNotice")
	if _insufficient_funds_notice != null:
		_insufficient_funds_notice.show_notice()

## Refunds every resource in `cost` -- the same shape spend_resources
## takes, used when a spend needs undoing (e.g. placement failed after
## the cost was already deducted).
func refund_resources(player_id: int, cost: Dictionary) -> void:
	for resource_name in cost:
		add_resource(player_id, resource_name, cost[resource_name])

## Summed across every "hut"/"castle" that player owns (see
## POPULATION_PER_HUT/POPULATION_PER_CASTLE), capped at
## POPULATION_CAP_MAXIMUM -- e.g. 5 huts + 1 castle = 50.
const POPULATION_PER_HUT: int = 5
const POPULATION_PER_CASTLE: int = 25
const POPULATION_CAP_MAXIMUM: int = 200
func get_population_cap(player_id: int) -> int:
	var cap := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or building.player_id != player_id:
			continue
		if building.unit_type_id == "hut":
			cap += POPULATION_PER_HUT
		elif building.unit_type_id == "castle":
			cap += POPULATION_PER_CASTLE
	return mini(cap, POPULATION_CAP_MAXIMUM)

## Every unit that player currently owns, regardless of type -- population
## counts the whole army, not just villagers (matches get_population_cap
## being a cap on everything, same as AoE2's own population mechanic).
func get_population_count(player_id: int) -> int:
	var count := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(unit) and unit.player_id == player_id:
			count += 1
	return count

func _refresh() -> void:
	var human_id: int = GameState.human_player_id
	for resource_name in RESOURCE_ORDER:
		_resource_count_labels[resource_name].text = str(get_resource(human_id, resource_name))

	var peasant_count := 0
	var idle_count := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or unit.player_id != human_id or unit.unit_type_id != "peasant":
			continue
		peasant_count += 1
		if unit.is_idle() and unit.attack_target == null:
			idle_count += 1
	_peasant_count_label.text = str(peasant_count)
	_idle_count_label.text = str(idle_count)
	_population_label.text = "%d/%d" % [get_population_count(human_id), get_population_cap(human_id)]
