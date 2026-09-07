extends Control

const SAVES_DIR := "user://saves"

@onready var play_button: Button = $VBox/PlayButton
@onready var load_button: Button = $VBox/LoadButton
@onready var account_button: Button = $VBox/AccountButton
@onready var options_button: Button = $VBox/OptionsButton
@onready var quit_button: Button = $VBox/QuitButton
@onready var load_list_panel: Panel = $LoadListPanel
@onready var saves_list: VBoxContainer = $LoadListPanel/OuterVBox/ScrollContainer/SavesList
@onready var close_button: Button = $LoadListPanel/OuterVBox/CloseButton

@onready var account_panel: Panel = $AccountPanel
@onready var active_account_label: Label = $AccountPanel/OuterVBox/ActiveAccountLabel
@onready var accounts_list: VBoxContainer = $AccountPanel/OuterVBox/ScrollContainer/AccountsList
@onready var account_status_label: Label = $AccountPanel/OuterVBox/StatusLabel
@onready var sign_in_button: Button = $AccountPanel/OuterVBox/SignInButton
@onready var create_account_button: Button = $AccountPanel/OuterVBox/CreateAccountButton
@onready var steam_button: Button = $AccountPanel/OuterVBox/SteamButton
@onready var account_close_button: Button = $AccountPanel/OuterVBox/CloseButton

@onready var new_account_panel: Panel = $NewAccountPanel
@onready var new_account_input: LineEdit = $NewAccountPanel/VBox/NameInput
@onready var new_account_password_input: LineEdit = $NewAccountPanel/VBox/PasswordInput
@onready var new_account_stay_checkbox: CheckBox = $NewAccountPanel/VBox/StayCheckBox
@onready var new_account_status_label: Label = $NewAccountPanel/VBox/StatusLabel
@onready var new_account_confirm_button: Button = $NewAccountPanel/VBox/ButtonRow/ConfirmButton
@onready var new_account_cancel_button: Button = $NewAccountPanel/VBox/ButtonRow/CancelButton

@onready var sign_in_panel: Panel = $SignInPanel
@onready var sign_in_prompt_label: Label = $SignInPanel/VBox/PromptLabel
@onready var sign_in_password_input: LineEdit = $SignInPanel/VBox/PasswordInput
@onready var sign_in_stay_checkbox: CheckBox = $SignInPanel/VBox/StayCheckBox
@onready var sign_in_status_label: Label = $SignInPanel/VBox/StatusLabel
@onready var sign_in_confirm_button: Button = $SignInPanel/VBox/ButtonRow/ConfirmButton
@onready var sign_in_cancel_button: Button = $SignInPanel/VBox/ButtonRow/CancelButton

## Which account row is currently highlighted in the list -- separate from
## GameState.active_account (who's actually signed in), since selecting a
## row is just aiming the Sign In button, not a sign-in by itself.
var _selected_account_name: String = ""

func _ready() -> void:
	Music.play_track(Music.TITLE_TRACK)
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	options_button.pressed.connect(OptionsMenu.open)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_on_close_load_list_pressed)
	load_list_panel.visible = false
	load_button.disabled = _list_saves().is_empty()

	account_button.pressed.connect(_on_account_pressed)
	account_close_button.pressed.connect(_on_close_account_panel_pressed)
	sign_in_button.pressed.connect(_on_sign_in_button_pressed)
	create_account_button.pressed.connect(_on_create_account_pressed)
	steam_button.pressed.connect(_on_steam_pressed)
	new_account_confirm_button.pressed.connect(_on_new_account_confirm_pressed)
	new_account_cancel_button.pressed.connect(_on_new_account_cancel_pressed)
	new_account_password_input.text_submitted.connect(func(_text: String) -> void: _on_new_account_confirm_pressed())
	sign_in_confirm_button.pressed.connect(_on_sign_in_confirm_pressed)
	sign_in_cancel_button.pressed.connect(_on_sign_in_cancel_pressed)
	sign_in_password_input.text_submitted.connect(func(_text: String) -> void: _on_sign_in_confirm_pressed())
	account_panel.visible = false
	new_account_panel.visible = false
	sign_in_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if sign_in_panel.visible:
		_on_sign_in_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif new_account_panel.visible:
		_on_new_account_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif account_panel.visible:
		_on_close_account_panel_pressed()
		get_viewport().set_input_as_handled()
	elif load_list_panel.visible:
		_on_close_load_list_pressed()
		get_viewport().set_input_as_handled()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

## Returns {"path": String, "name": String, "timestamp": float} for every
## save file, newest first.
func _list_saves() -> Array:
	var saves: Array = []
	var dir := DirAccess.open(SAVES_DIR)
	if dir == null:
		return saves
	for file_name in DirAccess.get_files_at(SAVES_DIR):
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [SAVES_DIR, file_name]
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed == null or not parsed.has("units"):
			continue
		saves.append({
			"path": path,
			"name": parsed.get("name", "Save"),
			"timestamp": parsed.get("timestamp", 0.0),
		})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return saves

func _on_load_pressed() -> void:
	for child in saves_list.get_children():
		child.queue_free()

	for save in _list_saves():
		var button := Button.new()
		var date_str := Time.get_datetime_string_from_unix_time(int(save["timestamp"]), true)
		button.text = "%s  —  %s" % [save["name"], date_str]
		button.pressed.connect(_on_save_entry_pressed.bind(save["path"]))
		saves_list.add_child(button)

	load_list_panel.visible = true

func _on_save_entry_pressed(path: String) -> void:
	GameState.load_on_start = true
	GameState.load_save_path = path
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_close_load_list_pressed() -> void:
	load_list_panel.visible = false

func _on_quit_pressed() -> void:
	get_tree().quit()

## Purely local, single-player profile switching -- not real authentication
## against any server. The "password" is only ever checked against a
## locally-stored SHA-256 hash (see GameState.accounts), never sent
## anywhere, so this is enough to stop someone else picking your saved
## name, not meant to be actual account security.
func _hash_password(password: String) -> String:
	return password.sha256_text()

func _on_account_pressed() -> void:
	account_status_label.text = ""
	_selected_account_name = ""
	_refresh_accounts_list()
	account_panel.visible = true

func _on_close_account_panel_pressed() -> void:
	account_panel.visible = false

## Rebuilds the account list from GameState.accounts -- one selectable row
## per saved account (a single-select toggle group: picking one just aims
## the Sign In button, it doesn't sign you in by itself), the currently
## signed-in one called out by its own color.
func _refresh_accounts_list() -> void:
	for child in accounts_list.get_children():
		child.queue_free()

	for account in GameState.accounts:
		var account_name: String = account["name"]
		var button := Button.new()
		button.text = account_name + (" (signed in)" if account_name == GameState.active_account else "")
		button.toggle_mode = true
		button.button_pressed = account_name == _selected_account_name
		button.pressed.connect(_on_account_row_pressed.bind(account_name))
		accounts_list.add_child(button)

	active_account_label.text = (
		"Playing as: %s" % GameState.active_account if not GameState.active_account.is_empty()
		else "No account signed in"
	)
	_update_sign_in_button()
	create_account_button.disabled = GameState.accounts.size() >= GameState.MAX_ACCOUNTS
	create_account_button.text = (
		"Max Accounts Reached (%d)" % GameState.MAX_ACCOUNTS if create_account_button.disabled
		else "Create New Account"
	)

func _on_account_row_pressed(account_name: String) -> void:
	_selected_account_name = "" if _selected_account_name == account_name else account_name
	account_status_label.text = ""
	_refresh_accounts_list()

## The Sign In button doubles as Sign Out when the highlighted row is
## already the signed-in account -- one button rather than a second one
## that's only ever relevant for a single row.
func _update_sign_in_button() -> void:
	var is_active := not _selected_account_name.is_empty() and _selected_account_name == GameState.active_account
	sign_in_button.text = "Sign Out" if is_active else "Sign In"
	sign_in_button.disabled = _selected_account_name.is_empty()

func _on_sign_in_button_pressed() -> void:
	if _selected_account_name.is_empty():
		return
	if _selected_account_name == GameState.active_account:
		GameState.active_account = ""
		GameState.stay_signed_in = false
		GameState.remembered_account = ""
		GameState.save_settings()
		_refresh_accounts_list()
		return
	sign_in_prompt_label.text = "Sign in as: %s" % _selected_account_name
	sign_in_password_input.text = ""
	sign_in_stay_checkbox.button_pressed = GameState.stay_signed_in
	sign_in_status_label.text = ""
	sign_in_panel.visible = true
	sign_in_password_input.grab_focus()

func _on_sign_in_confirm_pressed() -> void:
	var account := _find_account(_selected_account_name)
	if account.is_empty():
		sign_in_status_label.text = "That account no longer exists."
		return
	if account["password_hash"] != _hash_password(sign_in_password_input.text):
		sign_in_status_label.text = "Incorrect password."
		return
	GameState.active_account = _selected_account_name
	GameState.stay_signed_in = sign_in_stay_checkbox.button_pressed
	GameState.remembered_account = _selected_account_name if GameState.stay_signed_in else ""
	GameState.save_settings()
	sign_in_panel.visible = false
	account_status_label.text = ""
	_refresh_accounts_list()

func _on_sign_in_cancel_pressed() -> void:
	sign_in_panel.visible = false

func _find_account(account_name: String) -> Dictionary:
	for account in GameState.accounts:
		if account["name"] == account_name:
			return account
	return {}

func _on_create_account_pressed() -> void:
	new_account_input.text = ""
	new_account_password_input.text = ""
	new_account_stay_checkbox.button_pressed = false
	new_account_status_label.text = ""
	new_account_panel.visible = true
	new_account_input.grab_focus()

func _on_new_account_confirm_pressed() -> void:
	var new_name := new_account_input.text.strip_edges()
	var password := new_account_password_input.text
	if new_name.is_empty():
		new_account_status_label.text = "Enter a username."
		return
	if password.is_empty():
		new_account_status_label.text = "Enter a password."
		return
	if _find_account(new_name).size() > 0:
		new_account_status_label.text = "That username already exists."
		return
	if GameState.accounts.size() >= GameState.MAX_ACCOUNTS:
		new_account_status_label.text = "Max of %d accounts reached." % GameState.MAX_ACCOUNTS
		return
	GameState.accounts.append({"name": new_name, "password_hash": _hash_password(password)})
	GameState.active_account = new_name
	GameState.stay_signed_in = new_account_stay_checkbox.button_pressed
	GameState.remembered_account = new_name if GameState.stay_signed_in else ""
	GameState.save_settings()
	new_account_panel.visible = false
	_selected_account_name = new_name
	account_status_label.text = ""
	_refresh_accounts_list()

func _on_new_account_cancel_pressed() -> void:
	new_account_panel.visible = false

## No Steamworks integration yet (would need the GodotSteam GDExtension
## plus a registered Steam App ID) -- this just tells the player that,
## rather than the button silently doing nothing.
func _on_steam_pressed() -> void:
	account_status_label.text = "Steam sign-in isn't available yet."
