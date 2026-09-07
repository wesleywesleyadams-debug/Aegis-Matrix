extends CanvasLayer
## Autoload -- the one Account panel shared by every scene (see
## SignedInLabel's Sign In button and TitleMenu's Account button), same
## "genuinely only one of these" reasoning as OptionsMenu.
##
## Purely local, single-player profile switching -- not real authentication
## against any server. The "password" is only ever checked against a
## locally-stored SHA-256 hash (see GameState.accounts), never sent
## anywhere, so this is enough to stop someone else picking your saved
## name, not meant to be actual account security.

@onready var background: Control = $Background
@onready var account_panel: Panel = $Background/AccountPanel
@onready var active_account_label: Label = $Background/AccountPanel/OuterVBox/ActiveAccountLabel
@onready var accounts_list: VBoxContainer = $Background/AccountPanel/OuterVBox/ScrollContainer/AccountsList
@onready var account_status_label: Label = $Background/AccountPanel/OuterVBox/StatusLabel
@onready var sign_in_button: Button = $Background/AccountPanel/OuterVBox/SignInButton
@onready var create_account_button: Button = $Background/AccountPanel/OuterVBox/CreateAccountButton
@onready var steam_button: Button = $Background/AccountPanel/OuterVBox/SteamButton
@onready var account_close_button: Button = $Background/AccountPanel/OuterVBox/CloseButton

@onready var new_account_panel: Panel = $Background/NewAccountPanel
@onready var new_account_input: LineEdit = $Background/NewAccountPanel/VBox/NameInput
@onready var new_account_password_input: LineEdit = $Background/NewAccountPanel/VBox/PasswordInput
@onready var new_account_stay_checkbox: CheckBox = $Background/NewAccountPanel/VBox/StayCheckBox
@onready var new_account_status_label: Label = $Background/NewAccountPanel/VBox/StatusLabel
@onready var new_account_confirm_button: Button = $Background/NewAccountPanel/VBox/ButtonRow/ConfirmButton
@onready var new_account_cancel_button: Button = $Background/NewAccountPanel/VBox/ButtonRow/CancelButton

@onready var sign_in_panel: Panel = $Background/SignInPanel
@onready var sign_in_prompt_label: Label = $Background/SignInPanel/VBox/PromptLabel
@onready var sign_in_password_input: LineEdit = $Background/SignInPanel/VBox/PasswordInput
@onready var sign_in_stay_checkbox: CheckBox = $Background/SignInPanel/VBox/StayCheckBox
@onready var sign_in_status_label: Label = $Background/SignInPanel/VBox/StatusLabel
@onready var sign_in_confirm_button: Button = $Background/SignInPanel/VBox/ButtonRow/ConfirmButton
@onready var sign_in_cancel_button: Button = $Background/SignInPanel/VBox/ButtonRow/CancelButton

## Which account row is currently highlighted in the list -- separate from
## GameState.active_account (who's actually signed in), since selecting a
## row is just aiming the Sign In button, not a sign-in by itself.
var _selected_account_name: String = ""

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	background.visible = false
	new_account_panel.visible = false
	sign_in_panel.visible = false

	account_close_button.pressed.connect(close)
	sign_in_button.pressed.connect(_on_sign_in_button_pressed)
	create_account_button.pressed.connect(_on_create_account_pressed)
	steam_button.pressed.connect(_on_steam_pressed)
	new_account_confirm_button.pressed.connect(_on_new_account_confirm_pressed)
	new_account_cancel_button.pressed.connect(_on_new_account_cancel_pressed)
	new_account_password_input.text_submitted.connect(func(_text: String) -> void: _on_new_account_confirm_pressed())
	sign_in_confirm_button.pressed.connect(_on_sign_in_confirm_pressed)
	sign_in_cancel_button.pressed.connect(_on_sign_in_cancel_pressed)
	sign_in_password_input.text_submitted.connect(func(_text: String) -> void: _on_sign_in_confirm_pressed())

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if sign_in_panel.visible:
		_on_sign_in_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif new_account_panel.visible:
		_on_new_account_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif background.visible:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	account_status_label.text = ""
	_selected_account_name = ""
	_refresh_accounts_list()
	background.visible = true

func close() -> void:
	background.visible = false
	new_account_panel.visible = false
	sign_in_panel.visible = false

func _hash_password(password: String) -> String:
	return password.sha256_text()

## Rebuilds the account list from GameState.accounts -- one selectable row
## per saved account (a single-select toggle group: picking one just aims
## the Sign In button, it doesn't sign you in by itself), the currently
## signed-in one called out by its own color.
func _refresh_accounts_list() -> void:
	for child in accounts_list.get_children():
		child.queue_free()

	for account in GameState.accounts:
		var account_name: String = account["name"]
		var tag := ""
		if account_name == GameState.active_account:
			tag = " (signed in)"
		elif int(account.get("steam_id", 0)) != 0:
			tag = " (Steam)"
		var button := Button.new()
		button.text = account_name + tag
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
		_sign_in_as("", false)
		return

	var account := _find_account(_selected_account_name)
	var linked_steam_id: int = int(account.get("steam_id", 0))
	if linked_steam_id != 0:
		# Steam-linked accounts have no password -- Steam itself already
		# authenticated the player, so this only re-checks that the
		# currently-running Steam client is still that same identity,
		# rather than prompting for a password that was never set.
		if SteamService.available and SteamService.steam_id == linked_steam_id:
			_sign_in_as(_selected_account_name, true)
		else:
			account_status_label.text = "Sign in to Steam as %s first." % _selected_account_name
		return

	sign_in_prompt_label.text = "Sign in as: %s" % _selected_account_name
	sign_in_password_input.text = ""
	sign_in_stay_checkbox.button_pressed = GameState.stay_signed_in
	sign_in_status_label.text = ""
	sign_in_panel.visible = true
	sign_in_password_input.grab_focus()

## Shared by every way the active account can change -- password sign-in,
## Steam sign-in, a brand-new account just created, and signing out
## (account_name = "") all funnel through here. Reloads that account's own
## settings (audio/visuals/lobby -- see GameState.load_account_settings())
## and pushes them onto the live systems immediately, rather than only
## taking effect the next time the game launches.
func _sign_in_as(account_name: String, stay_signed_in: bool) -> void:
	GameState.active_account = account_name
	GameState.stay_signed_in = stay_signed_in
	GameState.remembered_account = account_name if stay_signed_in else ""
	GameState.load_account_settings()
	OptionsMenu.apply_current_settings()
	GameState.save_settings()
	sign_in_panel.visible = false
	account_status_label.text = ""
	_refresh_accounts_list()

func _on_sign_in_confirm_pressed() -> void:
	var account := _find_account(_selected_account_name)
	if account.is_empty():
		sign_in_status_label.text = "That account no longer exists."
		return
	if account["password_hash"] != _hash_password(sign_in_password_input.text):
		sign_in_status_label.text = "Incorrect password."
		return
	_sign_in_as(_selected_account_name, sign_in_stay_checkbox.button_pressed)

func _on_sign_in_cancel_pressed() -> void:
	sign_in_panel.visible = false

func _find_account(account_name: String) -> Dictionary:
	for account in GameState.accounts:
		if account["name"] == account_name:
			return account
	return {}

func _find_account_by_steam_id(id: int) -> Dictionary:
	for account in GameState.accounts:
		if int(account.get("steam_id", 0)) == id:
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
	_selected_account_name = new_name
	new_account_panel.visible = false
	_sign_in_as(new_name, new_account_stay_checkbox.button_pressed)

func _on_new_account_cancel_pressed() -> void:
	new_account_panel.visible = false

## Real Steamworks sign-in (see SteamService) -- Steam itself already
## authenticated the player (they're logged into the Steam client locally),
## so this just links/reuses a local account for that Steam identity and
## signs straight in, no password step needed. Running against Valve's
## public test App ID (480, see steam_appid.txt) until a real one is
## registered -- swapping it later is a one-line change there, nothing
## here.
func _on_steam_pressed() -> void:
	if not SteamService.available:
		account_status_label.text = "Steam isn't running. Launch Steam and try again."
		return

	var existing := _find_account_by_steam_id(SteamService.steam_id)
	if not existing.is_empty():
		_sign_in_as(existing["name"], true)
		return

	if GameState.accounts.size() >= GameState.MAX_ACCOUNTS:
		account_status_label.text = "Max of %d accounts reached." % GameState.MAX_ACCOUNTS
		return

	var new_name := SteamService.persona_name
	if _find_account(new_name).size() > 0:
		# Same display name already used by a different (non-Steam) local
		# account -- disambiguate rather than silently colliding with it.
		new_name = "%s (Steam)" % SteamService.persona_name
	GameState.accounts.append({"name": new_name, "password_hash": "", "steam_id": SteamService.steam_id})
	_sign_in_as(new_name, true)
