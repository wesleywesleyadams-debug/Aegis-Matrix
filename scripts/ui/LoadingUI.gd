class_name LoadingUI
## Shared pieces of the boot screen and the match loading overlay: stepped
## dark shade bands (no smooth gradient, to sit with the pixel art), labels
## in the game font and the slim green/solar progress bar.

const FONT := preload("res://assets/fonts/JetBrainsMono.ttf")
const GREEN := Color("6fe07a")
const SOLAR := Color("ffc93d")
const DIM := Color(0.6, 0.65, 0.58)

static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Darkens the band from y0 to y1 (fractions of the screen) in 8 hard steps,
## darkest at the screen edge (top when from_top, else bottom).
static func shade(parent: Control, y0: float, y1: float, from_top: bool, strength: float = 0.9) -> void:
	var steps := 8
	for i in steps:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var a := float(i + 1) / steps
		r.color = Color(0.012, 0.03, 0.024, strength * a * a)
		r.anchor_left = 0.0
		r.anchor_right = 1.0
		var band := (y1 - y0) / steps
		if from_top:
			r.anchor_top = y1 - band * (i + 1)
			r.anchor_bottom = y1 - band * i
		else:
			r.anchor_top = y0 + band * i
			r.anchor_bottom = y0 + band * (i + 1)
		parent.add_child(r)

## A bottom-centred bar `width` wide, `from_bottom` px above the screen's
## foot. Returns [ProgressBar, status Label, percent Label].
static func progress(parent: Control, width: float, from_bottom: float) -> Array:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-width / 2.0, -from_bottom)
	box.size = Vector2(width, 60)
	parent.add_child(box)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size = Vector2(width, 12)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color("0a160e")
	bgs.border_color = Color(0.24, 0.43, 0.24)
	bgs.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GREEN
	fill.border_color = Color("0a160e")
	fill.set_border_width_all(3)
	bar.add_theme_stylebox_override("background", bgs)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	var status := label("", 22, DIM)
	status.position = Vector2(0, 20)
	box.add_child(status)
	var pct := label("0%", 22, SOLAR)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.position = Vector2(width - 120, 20)
	pct.size = Vector2(120, 30)
	box.add_child(pct)
	return [bar, status, pct]
