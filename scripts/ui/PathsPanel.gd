extends Control
class_name PathsPanel
## Left-side HUD panel (below GameCalendar, see Main.tscn) showing the
## human player's own Paths progress -- PathDefs.MAX_FOLLOWED_PATHS
## circular slots stacked vertically, filled left-to-right in the order
## PathState.followed_paths recorded them, empty (dim grey ring) for any
## pick not spent yet, or showing a live countdown ring (see PathSlot.
## is_researching) for whichever one is currently mid-research. Hovering
## a FOLLOWED slot pops out a small panel with that path's full name and
## perk description. Left-clicking opens PathTreeModal (the actual, only
## way a path research ever gets started -- there's no Castle
## interaction at all, per the user's own explicit redesign) -- but ONLY
## from the one slot that's actually "next up" (index ==
## path_state.followed_paths.size(), see _on_slot_clicked), and only
## while nothing is already being researched: an already-FOLLOWED slot
## has nothing left to choose (its path is permanent), a slot further
## out than the next one can't be reached yet anyway (you can't skip a
## pick), and the next-pick slot itself stops being clickable the moment
## its own research starts (nothing to choose until it finishes).
##
## Reads GameState.human_path_state directly (never caches a local copy)
## so it can't go stale -- RTSController._ready() replaces that autoload
## field with a fresh PathState at the start of every match, and Godot
## runs a child's own _ready() (this panel) before its parent's (the
## Main scene root, whose script is RTSController) -- caching the
## reference here first would capture the PREVIOUS match's now-stale
## instance.

## 56, not the original 44 -- the countdown number (see PathSlot.
## research_seconds_remaining) needs to actually be readable at this size.
const SLOT_SIZE: float = 56.0
const SLOT_SPACING: float = 12.0

var path_state: PathState:
	get:
		return GameState.human_path_state

@onready var _popout: Panel = $Popout
@onready var _popout_title: Label = $Popout/VBox/Title
@onready var _popout_body: Label = $Popout/VBox/Body

var _slots: Array[PathSlot] = []
var _tree_modal: PathTreeModal = null

func _ready() -> void:
	_popout.visible = false
	for i in PathDefs.MAX_FOLLOWED_PATHS:
		var slot := PathSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.position = Vector2(0, i * (SLOT_SIZE + SLOT_SPACING))
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		slot.clicked.connect(_on_slot_clicked.bind(i))
		add_child(slot)
		_slots.append(slot)
	refresh_from_state()

## Ticks the actual research timer (PathState never ticks itself -- see
## its own doc comment) and keeps the slots' live countdown/progress
## ring in step every frame while something's researching. Cheap to
## call unconditionally when idle (refresh_from_state's own loop is a
## handful of field assignments), so no need to gate this on
## path_state.is_researching() first.
func _process(delta: float) -> void:
	path_state.advance_research(delta)
	refresh_from_state()

## Pushes path_state's current followed/researching state into the 4
## slots, and marks whichever one is next up (see PathSlot.is_next_pick's
## own doc comment) -- called every frame (see _process) since research
## progress needs to animate live, not just refresh on state changes.
func refresh_from_state() -> void:
	var followed_count := path_state.followed_paths.size()
	var next_index := followed_count
	for i in _slots.size():
		var slot := _slots[i]
		if i < followed_count:
			slot.path_id = path_state.followed_paths[i]
			slot.is_researching = false
			slot.is_next_pick = false
		elif i == next_index and path_state.is_researching():
			slot.path_id = path_state.researching_path
			slot.is_researching = true
			slot.research_progress = path_state.get_research_progress()
			slot.research_seconds_remaining = int(ceil(path_state.get_research_seconds_remaining()))
			slot.is_next_pick = false
		else:
			slot.path_id = ""
			slot.is_researching = false
			slot.is_next_pick = i == next_index

func _on_slot_hovered(slot: PathSlot) -> void:
	if slot.path_id.is_empty() or slot.is_researching:
		return
	_popout_title.text = PathDefs.get_display_name(slot.path_id)
	_popout_body.text = PathDefs.get_perk_description(slot.path_id)
	_popout.position = slot.position + Vector2(SLOT_SIZE + 10.0, 0.0)
	_popout.visible = true

func _on_slot_unhovered() -> void:
	_popout.visible = false

## Looked up lazily (not @onready) since PathTreeModal is a sibling
## under UI, not a child of this panel -- see Main.tscn (it needs to be
## a top-level UI child, not nested inside this panel's own small fixed-
## size rect, so it can actually cover the center of the screen).
func _get_tree_modal() -> PathTreeModal:
	if _tree_modal == null:
		_tree_modal = get_tree().current_scene.get_node_or_null("UI/PathTreeModal")
	return _tree_modal

## Only the slot at index == path_state.followed_paths.size() (the next
## unspent pick) actually opens the tree, and only while nothing is
## already being researched -- see this class's own doc comment.
func _on_slot_clicked(slot_index: int) -> void:
	if path_state.is_researching() or slot_index != path_state.followed_paths.size():
		return
	_popout.visible = false
	var modal := _get_tree_modal()
	if modal != null:
		modal.show_modal(path_state)
