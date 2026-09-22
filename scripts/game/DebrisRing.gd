class_name DebrisRing
extends Node2D
## Tethys Cluster's signature feature: a dense, impassable ring of rubble
## around the star (centered on this node) with a few gaps. Ships can't fly
## through it (Game.is_blocked / the nav grid route them to a gap), which
## turns the gaps into chokepoints. Shots pass over it.

const PIXEL := 2

var radius: float = 700.0
var width: float = 70.0
## Gap centers (radians) and their angular half-width.
var gaps: Array = []
var gap_half: float = 0.1

func _ready() -> void:
	add_to_group("debris_rings")
	z_index = -1
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(_paint())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * PIXEL
	add_child(sprite)

func in_gap(angle: float) -> bool:
	for g in gaps:
		if absf(angle_difference(angle, g)) < gap_half:
			return true
	return false

## Solid debris at p, grown by `margin` (for ship radius / grid safety).
func blocks(p: Vector2, margin: float = 0.0) -> bool:
	var v := p - global_position
	if absf(v.length() - radius) > width / 2.0 + margin:
		return false
	return not in_gap(v.angle())

## Packed rubble: grey-brown specks, densest along the ring's middle, with
## clean gaps.
func _paint() -> Image:
	var n := int(ceil((radius + width) * 2.0 / PIXEL)) + 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var cols := [Color("2a2422"), Color("4a3e36"), Color("6e5c4a"), Color("9a8468"), Color("c8b08a")]
	var c := n / 2.0
	for y in n:
		for x in n:
			var v := Vector2(x - c, y - c) * PIXEL
			var off := absf(v.length() - radius)
			if off > width / 2.0 + 6.0 or in_gap(v.angle()):
				continue
			var dens := 1.0 - off / (width / 2.0 + 6.0)
			if rng.randf() > 0.25 + 0.6 * dens:
				continue
			var col: Color = cols[clampi(int(rng.randf() * (2.0 + dens * 3.0)), 0, cols.size() - 1)]
			img.set_pixel(x, y, col)
	return img
