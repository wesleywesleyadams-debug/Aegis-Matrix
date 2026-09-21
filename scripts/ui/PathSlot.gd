extends Control
class_name PathSlot
## One circular path node -- drawn procedurally (no image assets, same
## "stand-in art via primitives" convention ResourceIcon.gd already uses
## for this project's HUD icons). Reused in two places with slightly
## different meaning:
## - PathsPanel's vertical stack of PathDefs.MAX_FOLLOWED_PATHS slots:
##   empty ("" path_id) draws a dim grey ring, UNLESS is_next_pick is
##   true (see its own doc comment), in which case it glows instead --
##   filled always draws as Status.FOLLOWED (a slot in that stack is
##   never SELECTABLE/LOCKED -- it just shows what's already been spent).
## - PathTreeModal's full 14-node tree: path_id is always set (every
##   real path has a permanent node there), and `status` distinguishes
##   FOLLOWED (solid, already spent) from SELECTABLE (bright ring,
##   clickable right now) from LOCKED (dimmed, not currently reachable).
## Either way this draws a solid circle in that path's own tier color
## (see PathDefs.get_color) with its first letter overlaid.

@export var path_id: String = "":
	set(value):
		path_id = value
		queue_redraw()

enum Status { FOLLOWED, SELECTABLE, LOCKED }
## Ignored entirely when path_id is empty (PathsPanel's own empty-slot
## case, see this class's own doc comment) -- only meaningful for a
## real path_id.
@export var status: Status = Status.FOLLOWED:
	set(value):
		status = value
		queue_redraw()

const EMPTY_RING_COLOR: Color = Color(0.5, 0.5, 0.5, 0.6)
const EMPTY_FILL_COLOR: Color = Color(0.15, 0.15, 0.15, 0.5)
const LETTER_COLOR: Color = Color(1, 1, 1, 1)
const RING_WIDTH: float = 3.0
## Brighter, thicker ring than a plain followed node's own darkened-tier
## outline -- SELECTABLE needs to visually say "clickable, look here"
## at a glance, distinct from both FOLLOWED (already spent) and LOCKED.
const SELECTABLE_RING_COLOR: Color = Color(1.0, 0.95, 0.6, 1.0)
const SELECTABLE_RING_WIDTH: float = 5.0
## How much LOCKED darkens/desaturates the node's normal tier color --
## reads as "not reachable right now", distinct from the plain darkened
## ring a FOLLOWED node's own outline already uses.
const LOCKED_DARKEN: float = 0.55
## Translucent red laid over a node the player currently can't act on --
## per the user's own wording, that's LOCKED (not currently available)
## OR SELECTABLE-but-can't-afford (see `unaffordable`); a FOLLOWED node
## never gets this (nothing left to buy) and a SELECTABLE + affordable
## one doesn't either (nothing stopping the player right now).
const UNAFFORDABLE_OVERLAY_COLOR: Color = Color(1.0, 0.0, 0.0, 0.4)

## Only meaningful when status == SELECTABLE (a LOCKED node already
## gets the same red overlay unconditionally, see UNAFFORDABLE_OVERLAY_COLOR's
## own doc comment) -- true when the human player can't currently
## afford PathDefs.get_cost for this path, set by PathTreeModal._refresh().
@export var unaffordable: bool = false:
	set(value):
		unaffordable = value
		queue_redraw()

## Only meaningful when path_id is empty (PathsPanel's own stack slots --
## see this class's own doc comment): true for the ONE slot that's
## actually clickable right now -- index == the player's next unspent
## pick, see PathsPanel.refresh_from_state -- so it reads as "click me to
## choose your next path" instead of looking identical to every other
## not-yet-reachable empty slot.
@export var is_next_pick: bool = false:
	set(value):
		is_next_pick = value
		queue_redraw()

## PathsPanel-only (see this class's own doc comment): true for the
## slot currently mid-research -- path_id is already set to whichever
## path was picked (so its tier color/abbr show through), but it isn't
## in followed_paths yet. Draws a partial progress ring (research_progress)
## and a countdown (research_seconds_remaining) in place of the normal
## solid FOLLOWED look, instead of the plain letter/unaffordable-overlay
## drawing every other state uses.
@export var is_researching: bool = false:
	set(value):
		is_researching = value
		queue_redraw()
@export var research_progress: float = 0.0:
	set(value):
		research_progress = value
		queue_redraw()
@export var research_seconds_remaining: int = 0:
	set(value):
		research_seconds_remaining = value
		queue_redraw()

const RESEARCH_BASE_DARKEN: float = 0.35
const RESEARCH_TRACK_COLOR: Color = Color(0.3, 0.3, 0.3, 0.8)
const RESEARCH_RING_COLOR: Color = Color(1.0, 0.85, 0.2, 1.0)
const RESEARCH_RING_WIDTH: float = 6.0

## Emitted on a left-click release within this node's own bounds -- only
## PathTreeModal actually listens (PathsPanel's own small stack slots
## connect it too, but only to open that modal; clicking a stack slot
## never follows a path directly).
signal clicked

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit()

func _draw() -> void:
	var radius: float = size.x * 0.5
	var center: Vector2 = size * 0.5
	if path_id.is_empty():
		draw_circle(center, radius, EMPTY_FILL_COLOR)
		if is_next_pick:
			draw_arc(center, radius - SELECTABLE_RING_WIDTH * 0.5, 0.0, TAU, 32, SELECTABLE_RING_COLOR, SELECTABLE_RING_WIDTH)
		else:
			draw_arc(center, radius - RING_WIDTH * 0.5, 0.0, TAU, 32, EMPTY_RING_COLOR, RING_WIDTH)
		return
	var color := PathDefs.get_color(path_id)
	if is_researching:
		draw_circle(center, radius, color.darkened(RESEARCH_BASE_DARKEN))
		draw_arc(center, radius - RESEARCH_RING_WIDTH * 0.5, 0.0, TAU, 32, RESEARCH_TRACK_COLOR, RESEARCH_RING_WIDTH)
		draw_arc(center, radius - RESEARCH_RING_WIDTH * 0.5, -PI * 0.5, -PI * 0.5 + TAU * research_progress, 32, RESEARCH_RING_COLOR, RESEARCH_RING_WIDTH)
		var countdown := str(int(ceil(research_seconds_remaining)))
		var font := ThemeDB.fallback_font
		var font_size := int(radius * 0.85)
		var text_size := font.get_string_size(countdown, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, center - text_size * 0.5 + Vector2(0, text_size.y * 0.35), countdown, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, LETTER_COLOR)
		return
	if status == Status.LOCKED:
		color = color.darkened(LOCKED_DARKEN)
	draw_circle(center, radius, color)
	if status == Status.SELECTABLE:
		draw_arc(center, radius - SELECTABLE_RING_WIDTH * 0.5, 0.0, TAU, 32, SELECTABLE_RING_COLOR, SELECTABLE_RING_WIDTH)
	else:
		draw_arc(center, radius - RING_WIDTH * 0.5, 0.0, TAU, 32, color.darkened(0.4), RING_WIDTH)
	var letter := PathDefs.get_abbr(path_id)
	var font := ThemeDB.fallback_font
	var font_size := int(radius * 0.85)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center - text_size * 0.5 + Vector2(0, text_size.y * 0.35), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, LETTER_COLOR)
	if status == Status.LOCKED or (status == Status.SELECTABLE and unaffordable):
		draw_circle(center, radius, UNAFFORDABLE_OVERLAY_COLOR)
