extends Node3D
## Floating health bar shown above a unit: a neutral dark background
## (health lost -- shows through wherever the fill has shrunk away from)
## and a fill (health remaining, colored to match the unit's player/team --
## see set_fill_color()) that shrinks from the right as health drops.
## Billboarded (see Background/Fill's own `billboard` property) so it stays
## readable regardless of viewing angle.

## The fill's full-health scale.x -- see Background/Fill in Unit.tscn /
## ParentUnit.tscn. Kept here so set_health_fraction() can scale relative
## to it without needing to read the node's current scale back out.
const FULL_SCALE_X: float = 7.5
const BAR_WIDTH: float = 0.6
## white_pixel.png's width in texture pixels -- needed to convert the
## desired world-space anchoring shift into `offset` (which is measured in
## texture pixels), see the note below.
const TEXTURE_WIDTH_PX: float = 8.0

@onready var fill: Sprite3D = $Fill

## Recolors the fill to match the owning unit's player/team color.
## `modulate` is a plain per-node property (unlike a shared material
## resource), so this only ever affects this one unit's bar.
func set_fill_color(color: Color) -> void:
	fill.modulate = color

func set_health_fraction(fraction: float) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	fill.scale.x = FULL_SCALE_X * fraction
	# Anchor the shrunken fill against the bar's fixed LEFT edge (instead of
	# letting it shrink symmetrically from both sides) using `offset`
	# rather than `position.x`. This camera is perspective (see
	# Camera3D.projection in Main.tscn), and billboard rotation is computed
	# per-object from camera-position-relative-to-object -- moving Fill's
	# actual transform.position away from Background's (as this used to do)
	# made their independently-computed billboard rotations diverge
	# slightly, visibly misaligning the two bars (worse as the shift grew,
	# i.e. at lower health). `offset` shifts the rendered quad within the
	# same billboard-rotated plane without moving transform.position, so
	# Fill's rotation always exactly matches Background's.
	if fraction > 0.0:
		var world_shift: float = (BAR_WIDTH * (1.0 - fraction)) / 2.0
		fill.offset.x = -world_shift / (fill.pixel_size * fill.scale.x)
	else:
		fill.offset.x = 0.0
