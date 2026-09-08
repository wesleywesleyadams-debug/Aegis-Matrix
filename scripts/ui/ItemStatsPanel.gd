extends Panel
## Shows an item's stats (see ItemDefs.get_stats) while the player is
## hovering over it -- either a WorldItem sitting on the map, or a slot in
## the backpack/equipment/storage panels (see RTSController's per-frame
## map-hover check and each panel's item_hovered/item_unhovered signals,
## all of which funnel into show_item/hide_item here). Hidden the rest of
## the time -- there's nothing to show when nothing's being hovered.

@onready var title_label: Label = $TitleLabel
@onready var stats_label: Label = $StatsLabel

func _ready() -> void:
	visible = false

func show_item(item_type: String) -> void:
	visible = true
	title_label.text = item_type.capitalize()
	var stats := ItemDefs.get_stats(item_type)
	var lines: Array[String] = []
	for stat_name in stats:
		lines.append("%s: %s" % [stat_name, stats[stat_name]])
	stats_label.text = "\n".join(lines)

func hide_item() -> void:
	visible = false
