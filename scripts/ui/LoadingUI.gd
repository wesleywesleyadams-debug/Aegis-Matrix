class_name LoadingUI
## Shared pieces of the boot screen and the match loading overlay: dithered
## dark shade bands (grain on the art's pixel grid, no visible steps), labels
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

## Darkens the band from y0 to y1 (fractions of the screen), darkest at the
## screen edge (top when from_top, else bottom). One ordered-dithered alpha
## ramp on the 480x270 art grid (one texel = one art pixel), so there are no
## visible steps and the grain matches the pixel art.
const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static func shade(parent: Control, y0: float, y1: float, from_top: bool, strength: float = 0.9) -> void:
	var w := 480
	var h := maxi(2, int(round(270.0 * (y1 - y0))))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		# d: 0 at the dark screen edge .. 1 at the inner (clear) edge.
		var t := (float(y) + 0.5) / h
		var d := (1.0 - t) if not from_top else t
		var a := strength * (1.0 - d) * (1.0 - d)
		for x in w:
			var thr: float = (BAYER4[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			var a8 := floorf(a * 255.0 + thr)
			img.set_pixel(x, y, Color8(3, 8, 6, int(a8)))
	var r := TextureRect.new()
	r.texture = ImageTexture.create_from_image(img)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = y0
	r.anchor_bottom = y1
	r.offset_left = 0.0
	r.offset_right = 0.0
	r.offset_top = 0.0
	r.offset_bottom = 0.0
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
