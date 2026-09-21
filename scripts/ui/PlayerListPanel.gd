extends Panel
## Small always-on readout, positioned directly above the minimap, of each
## match participant (player_id 1 and 2 -- the only two an actual match
## ever simulates, see RTSController._assign_players) -- their username in
## their own player color, current score (see RTSController.
## get_player_score), a faction-color swatch (stand-in for real per-race
## art -- see GameState.player_slots' "race" field), and a static age-icon
## swatch (this game has no age/era system at all, so every player shows
## the same placeholder rather than pretending one exists).
##
## No background of its own -- reuses the exact same StyleBoxFlat as
## ItemTooltipPanel (black, translucent, no border) so it reads as part of
## the same minimal HUD chrome instead of another parchment panel.

const FACTION_COLORS: Dictionary = {
	"human": Color(0.6, 0.55, 0.45),
	"elf": Color(0.4, 0.7, 0.45),
	"orc": Color(0.5, 0.55, 0.3),
	"undead": Color(0.45, 0.4, 0.5),
}
## Purely a placeholder -- see this script's own doc comment on there
## being no real age/era system to reflect yet.
const AGE_PLACEHOLDER_COLOR: Color = Color(0.75, 0.65, 0.3)
const REFRESH_INTERVAL: float = 0.5

@onready var rows_root: Control = $Rows

var _rts: Node = null
var _elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rts = get_tree().current_scene
	_refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		_refresh()

func _refresh() -> void:
	for child in rows_root.get_children():
		child.free()
	for player_id: int in [1, 2]:
		var slot_index: int = player_id - 1
		if slot_index >= GameState.player_slots.size():
			continue
		var slot: Dictionary = GameState.player_slots[slot_index]
		if slot["slot_type"] == "open":
			continue
		rows_root.add_child(_build_row(player_id, slot))

func _build_row(player_id: int, slot: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = _display_name_for(player_id, slot)
	name_label.custom_minimum_size = Vector2(110, 0)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Entity.PLAYER_COLORS.get(player_id, Color.WHITE))
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.text = str(_rts.get_player_score(player_id)) if _rts != null else "0"
	score_label.custom_minimum_size = Vector2(36, 0)
	score_label.add_theme_font_size_override("font_size", 14)
	score_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	row.add_child(score_label)

	var faction_icon := ColorRect.new()
	faction_icon.color = FACTION_COLORS.get(slot["race"], Color.GRAY)
	faction_icon.custom_minimum_size = Vector2(18, 18)
	faction_icon.tooltip_text = String(slot["race"]).capitalize()
	row.add_child(faction_icon)

	var age_icon := ColorRect.new()
	age_icon.color = AGE_PLACEHOLDER_COLOR
	age_icon.custom_minimum_size = Vector2(18, 18)
	age_icon.tooltip_text = "Age (placeholder -- no age system yet)"
	row.add_child(age_icon)

	return row

## Mirrors Lobby._resolve_username's fallback chain for the human slot;
## an AI slot just reads as "AI".
func _display_name_for(player_id: int, slot: Dictionary) -> String:
	if slot["slot_type"] == "ai":
		return "AI"
	if not GameState.active_account.is_empty():
		return GameState.active_account
	var os_name := OS.get_environment("USERNAME")
	if os_name.is_empty():
		os_name = OS.get_environment("USER")
	return os_name if not os_name.is_empty() else "Player %d" % player_id
