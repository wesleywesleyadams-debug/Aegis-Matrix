class_name SpiceNebula
extends Node2D
## Kharon Expanse's signature feature: a ring of spice-laden gas around the
## star, between `inner` and `outer` (px from the star). Extra spice rocks
## drift in it (SystemGen places them). Anything with shields inside it loses
## DRAIN of its max shield per second and can't regenerate; hulls are never
## hurt, so going in is safe but leaves you exposed.

const DRAIN := 0.1
## The cloud is painted at 1/PIXEL resolution so it matches the pixel art.
const PIXEL := 4

var inner: float = 300.0
var outer: float = 700.0

func _ready() -> void:
	add_to_group("nebulae")
	z_index = -1
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(_paint())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * PIXEL
	add_child(sprite)

func contains(p: Vector2) -> bool:
	var d := p.distance_to(global_position)
	return d >= inner and d <= outer

## Soft orange-magenta haze, densest mid-ring, fading at both edges.
func _paint() -> Image:
	var n := int(ceil(outer * 2.0 / PIXEL)) + 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var cols := [Color("5a1f3a"), Color("8a2e3f"), Color("c8522a"), Color("ff9a2e")]
	var bayer := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
	var c := n / 2.0
	var mid := (inner + outer) / 2.0
	var half := (outer - inner) / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() * PIXEL
			if d < inner - 40.0 or d > outer + 40.0:
				continue
			var ring := 1.0 - clampf(absf(d - mid) / (half + 40.0), 0.0, 1.0)
			var v := ring * 0.8 + noise.get_noise_2d(x, y) * 0.5
			if v <= 0.1:
				continue
			# Color bands picked with a light ordered dither; alpha stays soft.
			var t: float = (bayer[y % 4][x % 4] + 0.5) / 16.0 - 0.5
			var col: Color = cols[clampi(int((v + t * 0.25) * cols.size()), 0, cols.size() - 1)]
			col.a = clampf(v, 0.0, 1.0) * 0.26
			img.set_pixel(x, y, col)
	return img
