class_name CostRow
extends HBoxContainer
## Inline cost readout: each resource's pixel icon followed by its amount,
## in the standard resource order, optionally with a build/research time.
## Use CostRow.make(cost) anywhere a price is shown.

static func make(cost: Dictionary, font_size: int = 13, seconds: float = -1.0, icon_scale: int = 2) -> CostRow:
	var row := CostRow.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	for r in Defs.RESOURCES:
		if not cost.has(r):
			continue
		var icon := TextureRect.new()
		icon.texture = Defs.tex("icon_" + r)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(12, 12) * icon_scale
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.tooltip_text = Defs.RESOURCE_NAMES[r]
		row.add_child(icon)
		var l := Label.new()
		l.text = "%d" % int(cost[r])
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", Defs.RESOURCE_COLORS[r])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		row.add_child(gap)
	if seconds >= 0.0:
		var t := Label.new()
		t.text = "%ds" % int(seconds)
		t.add_theme_font_size_override("font_size", font_size)
		# Bright enough to read on a panel: the old DIM sank into the card.
		t.add_theme_color_override("font_color", HUD.MUTED)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(t)
	return row
