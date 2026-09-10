extends Panel
## The tooltip panel -- shows a title and a few stat lines while the
## player is hovering over something on the map or in a HUD panel: an
## item (a WorldItem pickup, or a slot in the backpack/equipment/storage
## panels -- see show_item, ItemDefs.get_stats) or any other
## interactable Entity (a tree, a unit, a building -- see show_entity,
## RTSController's per-frame map-hover check). Hidden the rest of the
## time -- there's nothing to show when nothing's being hovered.

@onready var title_label: Label = $TitleLabel
@onready var stats_label: Label = $StatsLabel

func _ready() -> void:
	visible = false

func show_item(item_type: String) -> void:
	_show_stats(item_type.capitalize(), ItemDefs.get_stats(item_type))

## Generic hover info for any interactable Entity that isn't an item --
## a tree, a unit, a building. Just its display name and current/max
## health for now; callers needing more (e.g. a future resource-node
## yield) can pass richer `extra_stats`, prepended before Health.
func show_entity(display_name: String, entity: Entity, extra_stats: Dictionary = {}) -> void:
	var stats := extra_stats.duplicate()
	stats["Health"] = "%d/%d" % [entity.current_health, entity.max_health]
	_show_stats(display_name, stats)

func _show_stats(title: String, stats: Dictionary) -> void:
	visible = true
	title_label.text = title
	var lines: Array[String] = []
	for stat_name in stats:
		lines.append("%s: %s" % [stat_name, stats[stat_name]])
	stats_label.text = "\n".join(lines)

func hide_item() -> void:
	visible = false
