extends Control
## A small circular dial, divided into four colored quadrants (Spring/
## Summer/Fall/Winter), with a needle that completes one full rotation per
## in-game year -- the user's own "seasonal dial that slowly spins on an
## annual cycle" request. Purely presentational: reads SeasonClock (see
## season_clock_path) every frame rather than holding any state of its own.

const QUADRANT_COLORS: Dictionary = {
	"Spring": Color(0.45, 0.75, 0.35, 1.0),
	"Summer": Color(0.95, 0.8, 0.2, 1.0),
	"Fall": Color(0.85, 0.45, 0.15, 1.0),
	"Winter": Color(0.7, 0.85, 0.95, 1.0),
}
## Draw order matches SeasonClock.SEASONS -- each quadrant is a 90-degree
## wedge starting at -90 degrees (straight up) so the year begins (Spring,
## progress 0.0) with the needle pointing straight up like a clock's own
## 12 o'clock, and advances clockwise through Summer/Fall/Winter exactly
## the way SeasonClock.SEASON_START_DAYS orders them.
const SEASON_ORDER: Array[String] = ["Spring", "Summer", "Fall", "Winter"]
const ARC_POINTS_PER_QUADRANT: int = 16
const NEEDLE_COLOR: Color = Color(0.15, 0.1, 0.05, 1.0)
const RING_COLOR: Color = Color(0.2, 0.12, 0.06, 1.0)

@export var season_clock_path: NodePath
@onready var season_clock: Node = get_node(season_clock_path)
## Optional -- a sibling Label this dial keeps in sync with the current
## season name (e.g. "Fall"), since a 4-color wedge alone doesn't say
## which season is currently active in as many words. Left empty, this is
## a no-op.
@export var season_label_path: NodePath
@onready var season_label: Label = get_node_or_null(season_label_path)

func _process(_delta: float) -> void:
	queue_redraw()
	if season_label != null and season_clock != null:
		season_label.text = season_clock.current_season()

func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5
	var center := size * 0.5
	for i in range(SEASON_ORDER.size()):
		var season: String = SEASON_ORDER[i]
		var start_deg: float = -90.0 + 90.0 * i
		_draw_quadrant(center, radius, start_deg, QUADRANT_COLORS[season])
	draw_arc(center, radius, 0.0, TAU, 48, RING_COLOR, 2.0, true)

	var year_progress: float = season_clock.year_progress() if season_clock != null else 0.0
	var needle_angle: float = deg_to_rad(-90.0 + 360.0 * year_progress)
	var needle_end := center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius * 0.85)
	draw_line(center, needle_end, NEEDLE_COLOR, 3.0, true)
	draw_circle(center, radius * 0.08, NEEDLE_COLOR)

## Draws one 90-degree pie slice of the dial, from start_deg to
## start_deg + 90, as a filled polygon (draw_arc's own "filled" mode draws
## an outline only, not a solid wedge, so a real wedge needs its own
## triangle-fan polygon through the arc's sampled points instead).
func _draw_quadrant(center: Vector2, radius: float, start_deg: float, color: Color) -> void:
	var points := PackedVector2Array()
	points.append(center)
	for i in range(ARC_POINTS_PER_QUADRANT + 1):
		var deg: float = start_deg + 90.0 * float(i) / float(ARC_POINTS_PER_QUADRANT)
		var rad: float = deg_to_rad(deg)
		points.append(center + Vector2(cos(rad), sin(rad)) * radius)
	draw_colored_polygon(points, color)
