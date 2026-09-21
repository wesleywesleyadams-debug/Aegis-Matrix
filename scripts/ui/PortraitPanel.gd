extends Control
## Bottom-of-screen panel showing whatever is currently selected --
## exactly one of two mutually exclusive views inside SelectedObjectsPanel:
## a single object's portrait/name/team/level (see _show_single), or, for
## more than one selected unit, a row of tiny per-unit icon+health-bar
## slots with no stats text (see MultiSelectIcons, merged in from the old
## standalone SelectionPanel.gd -- see the "backup/pre-selectedobjects-
## merge" branch on GitHub for its pre-merge state as its own bottom-
## screen tray). This Control itself is always visible and purely a
## layout container (mouse_filter IGNORE, no visual of its own) -- it also
## parents TaskPanel and ItemTooltipPanel, both of which manage their own
## visibility independently (the tooltip in particular must still show
## while hovering a map item with nothing selected), so only
## SelectedObjectsPanel itself gets hidden when nothing is selected.
@onready var selected_objects_panel: Control = $SelectedObjectsPanel
@onready var icon_display = $SelectedObjectsPanel/IconDisplay
@onready var name_label: Label = $SelectedObjectsPanel/NameLabel
@onready var team_label: Label = $SelectedObjectsPanel/TeamLabel
@onready var level_label: Label = $SelectedObjectsPanel/LevelLabel
@onready var background: Control = $SelectedObjectsPanel/Background
@onready var multi_select_icons: Control = $SelectedObjectsPanel/MultiSelectIcons
@onready var stats_row: Control = $SelectedObjectsPanel/StatsRow

## Shown in LevelLabel's own row instead of that label while a seedling
## (see World.is_seedling) is the single selected object -- a live growth
## percentage reads better as a bar than as the plain "%d%%" text
## get_tooltip_extra_stats gives the hover tooltip (see that function's own
## doc comment for why the tooltip stays text-only: a tooltip can vanish/
## reappear over a different object at any time, so it isn't worth the
## upkeep a live-refreshed widget needs -- this panel, by contrast, stays
## on one selected object until the selection actually changes, which is
## exactly when a continuously-updating bar earns its keep). Built in code
## (not the scene) -- same "throw together a plain dynamic ProgressBar"
## shape TaskPanel's own upgrade-research bars use.
var _growth_progress: ProgressBar = null
## The single unit/building/World object currently shown by _show_single,
## or null while empty/multi-selected -- kept so _process can keep
## LevelLabel's resource-count text and _growth_progress live-updated for
## as long as that same object stays selected, rather than freezing at
## whatever value was true the instant selection last changed.
var _current_single_unit: Node3D = null
## A gatherable World resource node's remaining/total yield (e.g.
## "Acorns: 60/100") -- shown below the portrait itself (see
## RESOURCE_LABEL_RECT) rather than in LevelLabel's row, since that row
## reads as the object's name-adjacent stat line and a resource count
## belongs with the portrait it's counting instead. Built in code (not the
## scene), same reasoning _growth_progress has for being dynamic.
var _resource_count_label: Label = null

const ALLY_COLOR: Color = Color(0.3, 1.0, 0.4)
const ENEMY_COLOR: Color = Color(1.0, 0.25, 0.25)
## Small colored swatch per stat (stand-in for real stat icons -- AoE2:DE's
## reference equivalent uses a sword/shield/etc. icon per stat; no such art
## exists here yet) -- see _build_stats_row. Only stats Entity actually
## tracks are shown (no armor field exists in this project, so unlike the
## AoE2 reference there's no armor swatch here -- showing a fake 0 would
## be worse than not showing it at all).
const STAT_COLORS: Dictionary = {
	"hp": Color(0.75, 0.2, 0.2),
	"attack": Color(0.8, 0.6, 0.2),
	"range": Color(0.3, 0.55, 0.75),
	"vision": Color(0.4, 0.7, 0.4),
}

## Where any progress bar this panel ever shows lives -- always this same
## spot, immediately to the right of StatsRow's own swatches, rather than
## each kind of progress (growth today, maybe construction/repair later)
## picking its own ad hoc position. StatsRow itself sits at local
## (144, 92)-(460, 112) (see Main.tscn); this starts past the widest that
## row's 4 stat entries ever get.
const PROGRESS_BAR_RECT: Rect2 = Rect2(300, 90, 150, 22)
## Directly below Background/IconDisplay's own (12,34)-(132,154) portrait
## box (see Main.tscn) -- same width, just under it, so the resource count
## reads as belonging to the portrait rather than to the name/level column
## beside it.
const RESOURCE_LABEL_RECT: Rect2 = Rect2(12, 156, 120, 20)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_objects_panel.visible = true
	_growth_progress = ProgressBar.new()
	_growth_progress.position = PROGRESS_BAR_RECT.position
	_growth_progress.custom_minimum_size = PROGRESS_BAR_RECT.size
	_growth_progress.min_value = 0.0
	_growth_progress.max_value = 100.0
	_growth_progress.show_percentage = true
	_growth_progress.visible = false
	selected_objects_panel.add_child(_growth_progress)
	_resource_count_label = Label.new()
	_resource_count_label.position = RESOURCE_LABEL_RECT.position
	_resource_count_label.custom_minimum_size = RESOURCE_LABEL_RECT.size
	_resource_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resource_count_label.add_theme_font_size_override("font_size", 12)
	_resource_count_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	_resource_count_label.visible = false
	selected_objects_panel.add_child(_resource_count_label)
	_show_empty()

## Keeps LevelLabel's resource-count text and _growth_progress's value
## live while the same single object stays selected -- both are set once
## in _show_single, which only runs again when the selection itself
## changes, so without this a resource node's count (or a seedling's
## growth) would freeze at whatever it read the instant it got selected
## instead of ticking down/up in front of the player.
func _process(_delta: float) -> void:
	if _current_single_unit == null or not is_instance_valid(_current_single_unit):
		return
	if _current_single_unit is World:
		_refresh_world_extras(_current_single_unit)

## Called by RTSController whenever selection (or, for a unit/building not
## owned by the player, read-only inspection -- see RTSController.
## _inspect_foreign) changes. `units` is every currently selected/inspected
## entity: empty shows this panel's own empty/placeholder state (see
## _show_empty -- the panel itself always stays visible, per this game's
## HUD design, rather than popping in/out with selection), exactly one
## shows that one object's portrait+stats, more than one switches to the
## tiny multi-icon row instead (no stats -- see MultiSelectIcons).
func set_selection(units: Array) -> void:
	var live_units: Array = units.filter(is_instance_valid)
	selected_objects_panel.visible = true
	if live_units.size() > 1:
		_show_multi(live_units)
	elif live_units.size() == 1:
		_show_single(live_units[0])
	else:
		_show_empty()

func _show_single(unit: Node3D) -> void:
	_current_single_unit = unit
	multi_select_icons.visible = false
	multi_select_icons.set_selected_units([])
	icon_display.visible = true
	background.visible = true
	name_label.visible = true
	team_label.visible = true
	level_label.visible = true

	# get_tooltip_title(), not the bare Entity.display_name_for() this used
	# to call directly -- that skipped every override (World's own species/
	# display_name_override prefixing, see World.get_tooltip_title), so a
	# selected Oak Tree read as "OakTree" here while its hover tooltip
	# correctly said "Oak Tree". This panel and the tooltip should always
	# agree on an object's name.
	name_label.text = unit.get_tooltip_title() if unit is Entity else Entity.display_name_for(unit)
	icon_display.set_player_id(unit.player_id if unit is Entity else null)
	# Three distinct cases, not two: "Enemy" for an actually hostile side;
	# "Ally" for a genuinely different, non-hostile combat side (once this
	# game ever has more than one human/allied player_id in play, see
	# is_hostile_to_player's own doc comment on why player_id 1/2 is the
	# only pair that can be hostile today); and no label at all for the
	# human player's own units (not an "ally" of yourself) or a neutral
	# Gaia/Mob object (not a combat side at all). Right now, with the
	# match hardcoded to exactly player 1 (human) vs player 2 (AI enemy),
	# the "Ally" case never actually fires -- that's correct, not a bug,
	# until a real third allied side exists.
	var is_own: bool = unit.player_id == GameState.human_player_id
	var is_enemy: bool = unit.is_hostile_to_player(GameState.human_player_id)
	var is_ally: bool = not is_own and not is_enemy and unit.player_id in [1, 2]
	team_label.visible = is_enemy or is_ally
	team_label.text = "Enemy" if is_enemy else "Ally"
	# font_color, not modulate -- modulate multiplies onto whatever the
	# label's underlying theme font color already is, which read as a
	# muddy, still-mostly-brown tint rather than actual green/red.
	team_label.add_theme_color_override("font_color", ENEMY_COLOR if is_enemy else ALLY_COLOR)
	# Only a Unit has a level (see Unit.level) -- a Building, or a World
	# object (which shows its own resource count/growth bar elsewhere --
	# see _refresh_world_extras), shows no level text.
	level_label.text = "Level %d" % unit.level if unit is Unit else ""

	# A World resource node has no real combat stats (has_health is false
	# for exactly these -- see World.has_health's own doc comment), so the
	# HP/Attack/Range/Vision row would just show meaningless inherited
	# Entity defaults; _refresh_world_extras's own resource count/growth
	# bar covers what's worth showing instead. A decorative World object
	# (has_health true, e.g. a choppable-but-not-gatherable pine Tree)
	# still gets the normal row.
	var show_stats_row: bool = unit is Entity and not (unit is World and not unit.has_health)
	stats_row.visible = show_stats_row
	if show_stats_row:
		_refresh_stats_row(unit)

	_growth_progress.visible = false
	_resource_count_label.visible = false
	if unit is World:
		_refresh_world_extras(unit)

## The one stat that's actually meaningful for a World object with no
## level of its own -- either a gatherable resource node's remaining/total
## yield (e.g. "Acorns: 60/100", at RESOURCE_LABEL_RECT below the portrait)
## or, for a still-growing planted seedling (see World.is_seedling), a live
## progress bar at PROGRESS_BAR_RECT instead (a percentage reads better as
## a bar than as get_tooltip_extra_stats' own plain "%d%%" text -- see
## _growth_progress's own doc comment for why the hover tooltip stays
## text-only while this panel gets the bar). Called once from _show_single
## and every frame after from _process for as long as this same object
## stays selected, so both keep updating live rather than freezing at
## whatever was true the instant selection last changed.
func _refresh_world_extras(world: World) -> void:
	if world.is_seedling:
		_resource_count_label.visible = false
		_growth_progress.visible = true
		_growth_progress.value = world.get_growth_progress() * 100.0
		return
	_growth_progress.visible = false
	if not world.resource_type.is_empty():
		_resource_count_label.visible = true
		_resource_count_label.text = "%s: %d/%d" % [world.resource_type.capitalize(), int(world.current_resource), int(world.max_resource)]
	else:
		_resource_count_label.visible = false

## Nothing selected -- background frame stays up (per this panel's
## "always visible" HUD design) but every actual content row hides,
## leaving a plain empty panel rather than faking a portrait for nothing.
func _show_empty() -> void:
	_current_single_unit = null
	multi_select_icons.visible = false
	multi_select_icons.set_selected_units([])
	icon_display.visible = false
	background.visible = true
	name_label.visible = false
	team_label.visible = false
	level_label.visible = false
	stats_row.visible = false
	_growth_progress.visible = false
	_resource_count_label.visible = false

func _show_multi(units: Array) -> void:
	_current_single_unit = null
	icon_display.visible = false
	background.visible = false
	name_label.visible = false
	team_label.visible = false
	level_label.visible = false
	stats_row.visible = false
	_growth_progress.visible = false
	_resource_count_label.visible = false
	multi_select_icons.visible = true
	multi_select_icons.set_selected_units(units)

## Rebuilds the small icon+number stat row (HP/Attack/Range/Vision) each
## call -- cheap, short-lived UI state, same "throw away and redraw"
## pattern as MultiSelectIcons/TaskPanel's queue icons rather than diffed
## in place.
func _refresh_stats_row(entity: Entity) -> void:
	for child in stats_row.get_children():
		child.free()
	var stats: Array = [
		["hp", "%d/%d" % [int(entity.current_health), int(entity.max_health)]],
		["attack", "%d" % int(entity.attack_damage)],
		["range", "%.1f" % entity.attack_range],
		["vision", "%.1f" % entity.vision_range],
	]
	for stat in stats:
		stats_row.add_child(_build_stat_entry(stat[0], stat[1]))

func _build_stat_entry(stat_key: String, value_text: String) -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	var swatch := ColorRect.new()
	swatch.color = STAT_COLORS.get(stat_key, Color.GRAY)
	swatch.custom_minimum_size = Vector2(12, 12)
	entry.add_child(swatch)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	entry.add_child(value_label)

	return entry
