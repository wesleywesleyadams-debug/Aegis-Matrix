extends Control
## Pre-match setup screen. Two panels: Players (left) lists up to
## MAX_PLAYER_SLOTS pre-match slots, each with a slot-type/race/team choice
## (see GameState.player_slots); Match Settings (right) holds the
## match-wide options (Starting Item/Map are single-option placeholders for
## now, same "wired up as real OptionButtons so adding more options later is
## just adding entries" status the old Race/AI Opponents fields had).
##
## Only slot 1 (the player) and slot 2 (the one opposing side the match
## actually spawns -- see RTSController._assign_players) do anything right
## now; slots 3-8's race/team/AI choices are captured here for a future
## multi-opponent/team-combat system that doesn't exist yet, same as
## Starting Item/Map already were placeholders.

const RACE_OPTIONS: Array = [["terran", "Terran Union"], ["vorr", "Vorr Hive"], ["aeth", "Aetheric Choir"], ["krell", "Krell Dominion"]]
## Index i's team value; "No Team" is stored as team 0.
const TEAM_OPTIONS: Array = [["1", 1], ["2", 2], ["3", 3], ["4", 4], ["No Team", 0]]
## Purely a visual accent for each slot's player-number badge -- distinct
## from Entity.PLAYER_COLORS (which only defines real gameplay colors for
## players 1/2, plus the fixed Gaia/Mob neutral factions) since slots
## 3-8 here don't correspond to any actual in-match faction yet.
const BADGE_COLORS: Array = [
	Color(0.2, 0.45, 0.9), Color(0.85, 0.2, 0.2), Color(0.2, 0.7, 0.3), Color(0.85, 0.75, 0.2),
	Color(0.6, 0.35, 0.8), Color(0.9, 0.55, 0.15), Color(0.3, 0.75, 0.75), Color(0.8, 0.4, 0.65),
]
## Dimmed badge color for a slot currently set to Open -- same "available,
## not active" language as the old Play As buttons' UNSELECTED_MODULATE.
const OPEN_BADGE_COLOR := Color(0.5, 0.45, 0.4)

@onready var players_grid: GridContainer = $MainHBox/PlayersPanel/PlayersVBox/PlayersGrid
@onready var start_button: Button = $MainHBox/SettingsPanel/SettingsVBox/ButtonRow/StartButton
@onready var back_button: Button = $MainHBox/SettingsPanel/SettingsVBox/ButtonRow/BackButton
@onready var options_button: Button = $MainHBox/SettingsPanel/SettingsVBox/OptionsButton

## Shown as the slot-dropdown option for "this slot is me" -- the signed-in
## account's name (see GameState.active_account) if there is one, since
## that's the identity actually driving everything else (saves, settings),
## otherwise falls back to the OS username, or "Player" if even that isn't
## available (e.g. some non-Windows/Linux environments).
var _username: String = ""

## One entry per slot: {"badge": Label, "slot": OptionButton, "race":
## OptionButton, "team": OptionButton}, in slot order -- built by
## _populate_players_grid(), read back by _on_slot_selected/_save_slot.
var _slot_rows: Array = []

func _ready() -> void:
	Music.play_screen(Music.LOBBY_TRACK)
	# Dev aid: SL_LOBBY_SHOT=single|multi opens that lobby, saves
	# user://lobby.png and quits.
	var shot := OS.get_environment("SL_LOBBY_SHOT")
	if shot != "":
		if OS.get_environment("SL_SYSTEM") != "":
			GameState.system_id = OS.get_environment("SL_SYSTEM")
		GameState.game_mode = shot
		_capture.call_deferred()
	_username = _resolve_username()

	_setup_deathmatch_toggle()
	options_button.pressed.connect(OptionsMenu.open)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	# Full-width "Exit to Main Menu" under the Start row.
	back_button.text = "Exit to Main Menu"
	var row := back_button.get_parent()
	row.remove_child(back_button)
	row.get_parent().add_child(back_button)
	# Pushed to the bottom of the panel, in red.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	back_button.get_parent().add_child(spacer)
	back_button.get_parent().move_child(back_button, -1)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("5a1a22"), "hover": Color("7a2430"), "pressed": Color("3a1016")}[st]
		sb.border_color = Color("ff6a5a")
		sb.set_border_width_all(2)
		sb.set_content_margin_all(12)
		back_button.add_theme_stylebox_override(st, sb)
	back_button.add_theme_color_override("font_color", Color("ffd6d0"))
	back_button.add_theme_color_override("font_hover_color", Color.WHITE)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Start Match in green.
	for st in ["normal", "hover", "pressed"]:
		var gb := StyleBoxFlat.new()
		gb.bg_color = {"normal": Color("1a5a2a"), "hover": Color("247a38"), "pressed": Color("103a1a")}[st]
		gb.border_color = Color("6aff8a")
		gb.set_border_width_all(2)
		gb.set_content_margin_all(12)
		start_button.add_theme_stylebox_override(st, gb)
	start_button.add_theme_color_override("font_color", Color("d6ffe0"))
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	# Same button size as the other menus.
	for b in [options_button, start_button, back_button]:
		MenuStyle.button(b)

	_setup_system_picker()
	_add_mode_title()
	_populate_players_grid()
	_claim_slot_for_self()

	# Signing in/out (e.g. via the Account panel) while the lobby is open
	# should update "this slot is me"'s label live, not just next time the
	# lobby loads.
	GameState.active_account_changed.connect(_on_active_account_changed)

## Guarantees whoever's signed in actually has a claimed slot on entering
## the lobby -- a no-op in the common case (slot 1 defaults to "human"),
## but a real safety net for whenever real multiplayer exists: a player
## joining a hosted lobby should land in an open slot as themselves, not
## silently control nothing because some earlier session left every slot
## set to "ai"/"open". Only takes over an Open slot, never an AI one --
## claiming a slot someone deliberately set to AI would bump that choice
## without asking.
func _claim_slot_for_self() -> void:
	for slot in GameState.player_slots:
		if slot["slot_type"] == "human":
			return
	for i in GameState.player_slots.size():
		if GameState.player_slots[i]["slot_type"] == "open":
			GameState.player_slots[i]["slot_type"] = "human"
			_slot_rows[i]["slot"].selected = _slot_type_index("human")
			_sync_human_player_id()
			_update_row_visuals(i)
			GameState.save_settings()
			return

func _resolve_username() -> String:
	if not GameState.active_account.is_empty():
		return GameState.active_account
	var os_name := OS.get_environment("USERNAME")
	if os_name.is_empty():
		os_name = OS.get_environment("USER")
	return os_name if not os_name.is_empty() else "Player"

func _on_active_account_changed() -> void:
	_username = _resolve_username()
	for row in _slot_rows:
		row["slot"].set_item_text(0, _username)

## Builds one row per slot in GameState.player_slots, below the header row
## already in the scene -- GridContainer lays out direct children in
## row-major order, so this just keeps appending cells.
func _populate_players_grid() -> void:
	for i in GameState.player_slots.size():
		var slot: Dictionary = GameState.player_slots[i]

		var badge := Label.new()
		badge.text = str(i + 1)
		badge.custom_minimum_size = Vector2(40, 0)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", BADGE_COLORS[i % BADGE_COLORS.size()])
		players_grid.add_child(badge)

		var slot_option := OptionButton.new()
		slot_option.custom_minimum_size = Vector2(200, 0)
		slot_option.clip_text = true
		slot_option.add_item(_username)
		slot_option.add_item("AI")
		# Experimental: the trained neural commander (res://ai/commander.json).
		slot_option.add_item("Neural AI")
		# Single-player has no Open slots (nobody else can join): unused slots
		# are simply Closed, so every opponent is AI.
		slot_option.add_item("Closed" if _single() else "Open")
		slot_option.selected = _slot_type_index(slot["slot_type"])
		players_grid.add_child(slot_option)

		var race_option := OptionButton.new()
		race_option.custom_minimum_size = Vector2(190, 0)
		race_option.clip_text = true
		for pair in RACE_OPTIONS:
			race_option.add_item(pair[1])
		race_option.selected = _race_index(slot["race"])
		players_grid.add_child(race_option)

		var team_option := OptionButton.new()
		team_option.custom_minimum_size = Vector2(140, 0)
		team_option.clip_text = true
		for pair in TEAM_OPTIONS:
			team_option.add_item(pair[0])
		team_option.selected = _team_index(slot["team"])
		players_grid.add_child(team_option)

		var row := {"badge": badge, "slot": slot_option, "race": race_option, "team": team_option}
		_slot_rows.append(row)
		_update_row_visuals(i)

		slot_option.item_selected.connect(_on_slot_selected.bind(i))
		race_option.item_selected.connect(_on_race_selected.bind(i))
		team_option.item_selected.connect(_on_team_selected.bind(i))

func _capture() -> void:
	# Dev aid: SL_LOBBY_NEURAL=1 shows slot 2 set to Neural AI.
	if OS.get_environment("SL_LOBBY_NEURAL") != "":
		_slot_rows[1]["slot"].selected = 2
		# (Display only; the saved lobby settings are left untouched.)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://lobby.png")
	get_tree().quit()

func _single() -> bool:
	return GameState.game_mode == "single"

## Big mode heading at the top of the screen.
func _add_mode_title() -> void:
	var title := Label.new()
	title.text = "Single-Player" if _single() else "Multi-Player"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.85, 0.93, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.2, 1))
	title.add_theme_constant_override("outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 120
	add_child(title)
	if GameState.load_on_start:
		var note := Label.new()
		note.text = "Resuming saved game: %s" % GameState.load_save_name
		note.add_theme_font_size_override("font_size", 20)
		note.add_theme_color_override("font_color", Color(1, 0.83, 0.42))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.set_anchors_preset(Control.PRESET_TOP_WIDE)
		note.offset_top = 128
		note.offset_bottom = 160
		add_child(note)

func _slot_type_index(slot_type: String) -> int:
	match slot_type:
		"human": return 0
		"ai": return 1
		"neural": return 2
		_: return 3

func _race_index(race: String) -> int:
	for i in RACE_OPTIONS.size():
		if RACE_OPTIONS[i][0] == race:
			return i
	return 0

func _team_index(team: int) -> int:
	for i in TEAM_OPTIONS.size():
		if TEAM_OPTIONS[i][1] == team:
			return i
	return TEAM_OPTIONS.size() - 1

## The system map and its facts line (see the System panel).
var _preview: SystemPreview
var _facts: Label

func _on_slot_selected(index: int, slot_index: int) -> void:
	var slot_type: String = ["human", "ai", "neural", "open"][index]
	GameState.player_slots[slot_index]["slot_type"] = slot_type
	# The map is laid out for however many players are filled in.
	if _preview:
		_preview.show_system(GameState.system_id)
		_facts.text = _preview.facts
	_sync_human_player_id()
	_update_row_visuals(slot_index)
	GameState.save_settings()

func _on_race_selected(index: int, slot_index: int) -> void:
	GameState.player_slots[slot_index]["race"] = RACE_OPTIONS[index][0]
	GameState.save_settings()

func _on_team_selected(index: int, slot_index: int) -> void:
	GameState.player_slots[slot_index]["team"] = TEAM_OPTIONS[index][1]
	GameState.save_settings()

## Dims (rather than hides -- GridContainer drops invisible children from
## the grid flow entirely, which would shift every following row's cells
## left by one column) a slot's race/team dropdowns and badge once it's set
## to Open, since there's nothing meaningful to configure for an empty slot.
func _update_row_visuals(slot_index: int) -> void:
	var row: Dictionary = _slot_rows[slot_index]
	var is_open: bool = GameState.player_slots[slot_index]["slot_type"] == "open"
	# Empty (Open / Closed) slots show only their slot picker: Race and Team
	# are hidden (kept in the grid, just invisible) so the list reads cleanly.
	for k in ["race", "team"]:
		var o: OptionButton = row[k]
		o.disabled = is_open
		o.modulate.a = 0.0 if is_open else 1.0
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_open else Control.MOUSE_FILTER_STOP
	row["slot"].modulate = Color(1, 1, 1, 0.6) if is_open else Color.WHITE
	row["badge"].add_theme_color_override(
		"font_color", OPEN_BADGE_COLOR if is_open else BADGE_COLORS[slot_index % BADGE_COLORS.size()]
	)

## RTSController/Entity only know about a single human_player_id (1 or 2)
## -- the two sides an actual match spawns (see
## RTSController._assign_players) -- not the full 8-slot setup. Mirror
## whichever of *those two* slots is "human" into it so match-start keeps
## working exactly as before; slots 3-8 have no matching in-match faction
## to control yet, so a "human" pick there is captured but doesn't change
## who you actually play as.
func _sync_human_player_id() -> void:
	for i in range(mini(2, GameState.player_slots.size())):
		if GameState.player_slots[i]["slot_type"] == "human":
			GameState.human_player_id = i + 1
			return

func _on_start_pressed() -> void:
	# Every filled slot is a player, numbered in slot order (up to 8). The
	# first human slot is you; any other "human" plays as an AI for now
	# (no networking yet).
	GameState.match_players = []
	var human_taken := false
	for s in GameState.player_slots:
		if s["slot_type"] in ["open", "closed"]:
			continue
		var t: String = s["slot_type"]
		if t == "human" and human_taken:
			t = "ai"
		if t == "human":
			human_taken = true
			GameState.human_player_id = GameState.match_players.size() + 1
		GameState.match_players.append({"pid": GameState.match_players.size() + 1, "type": t, "team": int(s.get("team", 0))})
	if GameState.match_players.size() < 2:
		GameState.match_players.append({"pid": GameState.match_players.size() + 1, "type": "ai", "team": 0})
	if not human_taken:
		GameState.match_players[0]["type"] = "human"
		GameState.human_player_id = 1
	# More than two players: Orion Reach is hand-built for two, so a generated
	# layout of the same system takes its place (see Game._build_system).
	# Any "Neural AI" slot puts the trained commander in charge of the AI side.
	GameState.neural_ai = GameState.player_slots.any(func(s): return s["slot_type"] == "neural")
	# Resuming a save keeps the save's own system (SaveGame restores it).
	if not GameState.load_on_start:
		var sys := SystemGen.find(GameState.system_id)
		GameState.system_seed = int(sys.get("seed", 0)) if GameState.system_id != "random" else randi()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_back_pressed() -> void:
	GameState.load_on_start = false
	GameState.load_save_path = ""
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")

## Deathmatch (Match Settings): both sides open with a pile of every resource,
## so the match is a fight from the first minute rather than an economy ramp.
func _setup_deathmatch_toggle() -> void:
	var box := CheckBox.new()
	box.tooltip_text = "Every player starts with %d food, minerals, energy and spice, so the match is a fight from the first minute." % int(Defs.START_DEATHMATCH["minerals"])
	box.button_pressed = GameState.deathmatch
	box.focus_mode = Control.FOCUS_NONE
	# The lobby's theme draws no tick, so the label carries the state and the
	# text turns green when it is on.
	var paint := func(on: bool) -> void:
		box.text = "Deathmatch: ON" if on else "Deathmatch: off"
		box.add_theme_color_override("font_color", Color("6fe07a") if on else Color("c8d2ea"))
		box.add_theme_color_override("font_hover_color", Color("9fffae") if on else Color.WHITE)
	paint.call(GameState.deathmatch)
	box.toggled.connect(func(on: bool) -> void:
		GameState.deathmatch = on
		paint.call(on)
		GameState.save_settings())
	var vbox: Control = options_button.get_parent()
	vbox.add_child(box)
	vbox.move_child(box, options_button.get_index())

## System dropdown (Match Settings): the five named systems plus Random, with
## a one-line description under it.
func _setup_system_picker() -> void:
	# Its own panel, right of Match Settings: picker, description, preview,
	# facts.
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(440, 0)
	$MainHBox.add_child(panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 16
	box.offset_right = -16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "System"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var map_row: Control = $MainHBox/SettingsPanel/SettingsVBox/MapRow
	map_row.get_parent().remove_child(map_row)
	box.add_child(map_row)
	(map_row.get_node("Label") as Label).visible = false
	var opt: OptionButton = map_row.get_node("OptionButton")
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.button(opt)
	opt.clear()
	var pick := 0
	for i in SystemGen.SYSTEMS.size():
		var s: Dictionary = SystemGen.SYSTEMS[i]
		opt.add_item(s["name"])
		if s["id"] == GameState.system_id:
			pick = i
	opt.selected = pick
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := opt.get_parent()
	row.get_parent().add_child(desc)
	row.get_parent().move_child(desc, row.get_index() + 1)
	# Map preview and a facts line (star type, worlds, asteroids).
	var preview := SystemPreview.new()
	_preview = preview
	preview.custom_minimum_size = Vector2(0, 262)
	row.get_parent().add_child(preview)
	row.get_parent().move_child(preview, desc.get_index() + 1)
	var facts := Label.new()
	_facts = facts
	facts.add_theme_font_size_override("font_size", 15)
	facts.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.get_parent().add_child(facts)
	row.get_parent().move_child(facts, preview.get_index() + 1)
	var apply := func(i: int) -> void:
		GameState.system_id = SystemGen.SYSTEMS[i]["id"]
		desc.text = SystemGen.SYSTEMS[i]["desc"]
		preview.show_system(GameState.system_id)
		facts.text = preview.facts
	opt.item_selected.connect(apply)
	apply.call(pick)
