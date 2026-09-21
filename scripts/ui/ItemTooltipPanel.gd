extends Panel
## The tooltip panel -- shows a title, an optional subtitle, and a few
## stat lines laid out in two side-by-side columns (see StatsLabel/
## StatsLabelRight in Main.tscn, RichTextLabels so the Damage line can
## color in a bonus/penalty -- see show_item) so there's room for more
## stats without the panel growing taller -- while the player is
## hovering over something on the map or in a HUD panel: an item (a
## WorldItem pickup, or a slot in the backpack/equipment/storage panels
## -- see show_item, ItemDefs.get_item_name/get_stats) or any other
## interactable Entity (a tree, a unit, a building -- see show_entity,
## RTSController's per-frame map-hover check). Hidden the rest of the
## time -- there's nothing to show when nothing's being hovered.

const BONUS_COLOR: Color = Color(0.2, 0.6, 0.2, 1)
const PENALTY_COLOR: Color = Color(0.75, 0.15, 0.15, 1)
const FADE_OUT_DURATION: float = 1.0

@onready var title_label: Label = $TitleLabel
@onready var subtitle_label: Label = $SubtitleLabel
@onready var stats_label: RichTextLabel = $StatsLabel
@onready var stats_label_right: RichTextLabel = $StatsLabelRight
## Bottom-left, small (12pt) faction/race readout -- only ever set for a
## Unit (see show_entity); empty/hidden for an item or a non-Unit Entity
## (Building, World), which have no race concept at all.
@onready var faction_label: Label = $FactionLabel

## Whatever fade-out is currently running, if any -- killed and replaced
## on every show_item/show_entity/hide_item call rather than left to run
## alongside a new one, so rapidly hovering on/off doesn't stack tweens
## fighting over the same modulate:a property.
var _fade_tween: Tween = null

func _ready() -> void:
	visible = false
	modulate.a = 1.0

## E.g. title "Iron Longsword", subtitle "Hybrid-Handed Sword" (see
## ItemDefs.get_item_name/get_display_name). `source_slot` is only
## non-empty for a hover from an actual BACKPACK_SLOTS button (see
## ItemSlotButton.hovered) -- when it's specifically "two_hand" and this
## item is hybrid_hand kind, the two-handed wield bonus (see
## Unit.TWO_HANDED_HYBRID_DAMAGE_MULTIPLIER/
## TWO_HANDED_HYBRID_ATTACK_SPEED_MULTIPLIER, read from Unit directly so
## this can't drift out of sync with the actual combat math) gets both
## a summary line and a colored delta right next to the Damage stat
## (green for a bonus, red for a penalty -- currently only ever a bonus,
## but the color logic doesn't assume that). A ground pickup or a
## dual-wielded right_hand/left_hand hover never shows either, since
## the bonus only applies gripped two-handed.
func show_item(item_type: String, source_slot: String = "") -> void:
	var stats := ItemDefs.get_stats(item_type)
	var base_damage := ItemDefs.get_damage(item_type)
	var two_handed_bonus := source_slot == "two_hand" and ItemDefs.get_slot_kind(item_type) == "hybrid_hand"
	if base_damage >= 0.0 and stats.has("Damage"):
		stats = stats.duplicate()
		var total_damage := base_damage * Unit.TWO_HANDED_HYBRID_DAMAGE_MULTIPLIER if two_handed_bonus else base_damage
		var delta: int = int(total_damage) - int(base_damage)
		if delta != 0:
			var color := BONUS_COLOR if delta > 0 else PENALTY_COLOR
			var sign_str := "+" if delta > 0 else ""
			stats["Damage"] = "%d [color=#%s]%s%d[/color]" % [int(base_damage), color.to_html(false), sign_str, delta]
	if two_handed_bonus:
		var damage_bonus_pct: int = roundi((Unit.TWO_HANDED_HYBRID_DAMAGE_MULTIPLIER - 1.0) * 100)
		var speed_bonus_pct: int = roundi((Unit.TWO_HANDED_HYBRID_ATTACK_SPEED_MULTIPLIER - 1.0) * 100)
		stats["Two-Hand Wield"] = "+%d%% attack damage, +%d%% attack speed" % [damage_bonus_pct, speed_bonus_pct]
	_show_stats(ItemDefs.get_item_name(item_type), ItemDefs.get_display_name(item_type), stats)

## Generic hover info for any interactable Entity that isn't an item --
## a tree, a unit, a building. No subtitle (nothing generic to say);
## just its display name and current/max health for now, plus whatever
## `extra_stats` the caller passes (e.g. a unit's Level/Attack, or a
## tree's Wood yield), prepended before Health. A Unit also gets its
## race/faction (e.g. "Human") shown separately at the bottom-left in a
## small font -- see faction_label -- rather than replacing its actual
## name as the title (Unit.get_tooltip_title() used to do that; now it
## returns the real display name like everything else, and race lives
## here instead).
func show_entity(display_name: String, entity: Entity, extra_stats: Dictionary = {}) -> void:
	var stats := extra_stats.duplicate()
	# A pure resource node (World.has_health == false -- Oak/Apple Tree,
	# Crystal Cave, Mist Fissure) has no health at all, not just a hidden
	# bar -- showing a "Health: 1/1" row here would contradict that.
	if not (entity is World and not entity.has_health):
		stats["Health"] = "%d/%d" % [entity.current_health, entity.max_health]
	_show_stats(display_name, "", stats)
	if entity is Unit:
		faction_label.text = entity.race.capitalize()
		faction_label.visible = true
	else:
		faction_label.visible = false

## Splits stats into two even columns (left column gets the extra line
## when the count is odd) rather than one tall single-column list, so
## a longer stat block stays readable without the panel growing taller.
## Stat values may contain BBCode (see show_item's Damage delta) --
## stats_label/stats_label_right are bbcode_enabled RichTextLabels so it
## renders as actual color rather than literal tag text.
func _show_stats(title: String, subtitle: String, stats: Dictionary) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	visible = true
	modulate.a = 1.0
	title_label.text = title
	subtitle_label.text = subtitle
	# Default hidden -- only show_entity (Unit case) turns this back on;
	# an item hover (show_item) has no race/faction concept at all.
	faction_label.visible = false
	var lines: Array[String] = []
	for stat_name in stats:
		lines.append("%s: %s" % [stat_name, stats[stat_name]])
	var split := ceili(lines.size() / 2.0)
	stats_label.text = "\n".join(lines.slice(0, split))
	stats_label_right.text = "\n".join(lines.slice(split))

## Fades out over FADE_OUT_DURATION rather than vanishing instantly, so
## moving the cursor off whatever was hovered reads as the tooltip
## settling away instead of blinking off. Safe to call repeatedly while
## already hidden/fading -- callers (RTSController's per-frame map-hover
## check, ItemSlotButton's mouse_exited) don't need to track whether a
## fade is already in progress themselves.
func hide_item() -> void:
	var already_fading := _fade_tween != null and _fade_tween.is_valid() and _fade_tween.is_running()
	if not visible or already_fading:
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.finished.connect(func() -> void: visible = false)
