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

@onready var title_label: Label = $TitleLabel
@onready var subtitle_label: Label = $SubtitleLabel
@onready var stats_label: RichTextLabel = $StatsLabel
@onready var stats_label_right: RichTextLabel = $StatsLabelRight

func _ready() -> void:
	visible = false

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
## tree's Wood yield), prepended before Health.
func show_entity(display_name: String, entity: Entity, extra_stats: Dictionary = {}) -> void:
	var stats := extra_stats.duplicate()
	stats["Health"] = "%d/%d" % [entity.current_health, entity.max_health]
	_show_stats(display_name, "", stats)

## Splits stats into two even columns (left column gets the extra line
## when the count is odd) rather than one tall single-column list, so
## a longer stat block stays readable without the panel growing taller.
## Stat values may contain BBCode (see show_item's Damage delta) --
## stats_label/stats_label_right are bbcode_enabled RichTextLabels so it
## renders as actual color rather than literal tag text.
func _show_stats(title: String, subtitle: String, stats: Dictionary) -> void:
	visible = true
	title_label.text = title
	subtitle_label.text = subtitle
	var lines: Array[String] = []
	for stat_name in stats:
		lines.append("%s: %s" % [stat_name, stats[stat_name]])
	var split := ceili(lines.size() / 2.0)
	stats_label.text = "\n".join(lines.slice(0, split))
	stats_label_right.text = "\n".join(lines.slice(split))

func hide_item() -> void:
	visible = false
