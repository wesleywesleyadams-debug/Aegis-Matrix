extends Control
class_name PathTreeModal
## Large center-screen popup showing the entire 14-path tree at once --
## opened by left-clicking PathsPanel's "next pick" slot (per the user's
## own redesign: no Castle interaction at all, this modal IS how a path
## research gets started). Every node is always visible; PathSlot.status
## (see its own doc comment) shows which of the 3 states each one is in
## right now: FOLLOWED (already permanently spent), SELECTABLE (adjacent
## to the most recently followed path -- also shown red-tinted if the
## human player can't currently afford it, see PathSlot.unaffordable),
## or LOCKED (everything else, also red-tinted -- see the user's own
## "if it's not available OR you can't afford it" wording). Clicking a
## SELECTABLE-and-affordable node spends its PathDefs.get_cost and
## starts researching it (see PathState.start_researching) -- a no-op
## for a FOLLOWED/LOCKED click, or a SELECTABLE one the player can't pay
## for (ResourceHUD.spend_resources itself shows the "Insufficient
## Funds" flash for that case). The modal closes itself once research
## actually starts -- see _on_node_clicked's own doc comment.
##
## This Control fills the whole UI layer (see Main.tscn) and darkens
## the background behind $Panel purely so clicking outside the panel has
## something obvious to hit (see _on_background_clicked) -- the actual
## tree content all lives inside the centered $Panel.

const NODE_SIZE: float = 64.0
const TIER_ROW_HEIGHT: float = 118.0
const TIER_ROW_TOP: float = 56.0
const GRID_WIDTH: float = 860.0
## Fixed center-to-center distance between adjacent nodes in the same
## tier -- tight enough that tier 3's 5 nodes (the widest row) still fit
## within GRID_WIDTH. Using one fixed spacing for every tier (rather
## than stretching each tier's own row to fill the full width, which is
## what made every row the same width regardless of node count) is what
## actually produces a pyramid: a narrower tier's row is just plain
## narrower, not the same width with bigger gaps.
const NODE_SPACING: float = 172.0

@onready var _panel: Panel = $Panel
@onready var _grid_root: Control = $Panel/GridRoot
@onready var _info_title: Label = $Panel/InfoPanel/InfoTitle
@onready var _info_body: Label = $Panel/InfoPanel/InfoBody
@onready var _close_button: Button = $Panel/CloseButton

## Set by whoever opens this (PathsPanel) right before show_modal() --
## this modal has no opinion of its own about which player it's showing;
## see PathsPanel.path_state's own doc comment for why there's only ever
## one instance in play right now (the human player's own).
var path_state: PathState = null

var _nodes: Dictionary = {}

func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_background_gui_input)
	_close_button.pressed.connect(hide_modal)
	_build_nodes()

func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hide_modal()

## One PathSlot per PathDefs.all_path_ids() entry, positioned by tier
## (row) and its own slot position within that tier -- each row's nodes
## use the SAME fixed NODE_SPACING and are centered as a group within
## GRID_WIDTH, rather than each tier's row being stretched to fill the
## same full width regardless of node count (which made every row look
## the same width with just bigger gaps at the top). Centering a fixed-
## spacing row per tier is what actually gives the classic pyramid
## shape -- 2 nodes up top, widening row by row down to 5 at the bottom.
func _build_nodes() -> void:
	for path_id in PathDefs.all_path_ids():
		var node := PathSlot.new()
		node.path_id = path_id
		node.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
		var tier := PathDefs.get_tier(path_id)
		var slot := PathDefs.get_slot_in_tier(path_id)
		var count := PathDefs.get_tier_slot_count(tier)
		var row_width := (count - 1) * NODE_SPACING
		var row_left := (GRID_WIDTH - row_width) * 0.5
		node.position = Vector2(
			row_left + slot * NODE_SPACING - NODE_SIZE * 0.5,
			TIER_ROW_TOP + tier * TIER_ROW_HEIGHT
		)
		node.mouse_entered.connect(_on_node_hovered.bind(node))
		node.clicked.connect(_on_node_clicked.bind(node))
		_grid_root.add_child(node)
		_nodes[path_id] = node

func show_modal(state: PathState) -> void:
	path_state = state
	_refresh()
	visible = true

func hide_modal() -> void:
	visible = false

func _refresh() -> void:
	if path_state == null:
		return
	var selectable := path_state.get_selectable_paths()
	var resource_hud: ResourceHUD = get_tree().current_scene.get_node_or_null("UI/ResourceHUD")
	for path_id in _nodes:
		var node: PathSlot = _nodes[path_id]
		if path_state.has_followed(path_id):
			node.status = PathSlot.Status.FOLLOWED
		elif path_id in selectable:
			node.status = PathSlot.Status.SELECTABLE
			node.unaffordable = resource_hud != null and not resource_hud.can_afford(GameState.human_player_id, PathDefs.get_cost(path_id))
		else:
			node.status = PathSlot.Status.LOCKED

func _on_node_hovered(node: PathSlot) -> void:
	_info_title.text = PathDefs.get_display_name(node.path_id)
	_info_body.text = "%s\nCost: %s" % [PathDefs.get_perk_description(node.path_id), _format_cost(PathDefs.get_cost(node.path_id))]

func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: Array[String] = []
	for resource_name in cost:
		parts.append("%d %s" % [cost[resource_name], resource_name.capitalize()])
	return ", ".join(parts)

## Spends PathDefs.get_cost and starts researching `node`'s path if it's
## currently SELECTABLE and the human player can afford it -- silently
## does nothing otherwise (a FOLLOWED/LOCKED click, or a SELECTABLE one
## the player can't pay for -- ResourceHUD.spend_resources itself shows
## the "Insufficient Funds" flash for that case, nothing extra needed
## here), same "refuse quietly, caller doesn't need to react" shape
## BuildPlacementController.confirm_placement's own afford-check has.
## Closes the modal once research actually starts -- there's nothing
## else selectable until it finishes (get_selectable_paths returns
## empty while researching), so leaving the tree open showing every
## node LOCKED isn't useful; PathsPanel's own slot shows the live
## countdown instead (see PathSlot.research_progress).
func _on_node_clicked(node: PathSlot) -> void:
	if path_state == null or node.status != PathSlot.Status.SELECTABLE:
		return
	var resource_hud: ResourceHUD = get_tree().current_scene.get_node_or_null("UI/ResourceHUD")
	if resource_hud == null:
		return
	if not resource_hud.spend_resources(GameState.human_player_id, PathDefs.get_cost(node.path_id)):
		return
	path_state.start_researching(node.path_id)
	hide_modal()
