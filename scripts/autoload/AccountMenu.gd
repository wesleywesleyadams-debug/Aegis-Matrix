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

	# Successfully signing in (from any state this panel opened in -- the
	# title screen's auto-prompt included) closes the whole panel
	# automatically rather than leaving the player to notice they're done
	# and hunt for Close themselves. Signing back out deliberately does NOT
	# trigger this -- only a "" -> non-empty transition counts as signing
	# in, so closing on sign-out (already handled by _sign_in_as itself)
	# isn't duplicated here.
	GameState.active_account_changed.connect(_on_active_account_changed)

func _on_active_account_changed() -> void:
	if _docked:
		new_account_panel.visible = false
		sign_in_panel.visible = false
		_refresh_accounts_list()
		return
	if not GameState.active_account.is_empty():
		close()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if sign_in_panel.visible:
		_on_sign_in_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif new_account_panel.visible:
		_on_new_account_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif background.visible and not _docked:
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

# ---------------------------------------------------------------- docked mode

## True while the account panel is shown inline under the title screen's
## main menu (no dim, no Close button) instead of as a pop-up.
var _docked := false
var _saved_offsets := []
var _sub_saved := {}

## Shows the account options inline, top edge at `top_y` (screen px),
## horizontally centered. The title screen calls this on load.
func dock(top_y: float) -> void:
	_docked = true
	background.color = Color(0, 0, 0, 0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _saved_offsets.is_empty():
		_saved_offsets = [account_panel.anchor_top, account_panel.anchor_bottom, account_panel.offset_top, account_panel.offset_bottom]
	var h := account_panel.offset_bottom - account_panel.offset_top
	h = minf(minf(h, 400.0), get_viewport().get_visible_rect().size.y - top_y - 16.0)
	account_panel.anchor_top = 0.0
	account_panel.anchor_bottom = 0.0
	account_panel.offset_top = top_y
	account_panel.offset_bottom = top_y + h
	# Contents follow the panel's (now shorter) height.
	var outer := account_panel.get_node("OuterVBox") as Control
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 14
	outer.offset_top = 14
	outer.offset_right = -14
	outer.offset_bottom = -14
	# Let the account list shrink to fit (it scrolls when there are many).
	(outer.get_node("ScrollContainer") as Control).custom_minimum_size.y = 60.0
	# The sign-in / create-account forms open in the same spot, in place of
	# the account list, instead of popping up over the screen.
	for sub in [new_account_panel, sign_in_panel]:
		if not _sub_saved.has(sub):
			_sub_saved[sub] = [sub.anchor_left, sub.anchor_right, sub.anchor_top, sub.anchor_bottom, sub.offset_left, sub.offset_right, sub.offset_top, sub.offset_bottom]
		var sh: float = sub.offset_bottom - sub.offset_top
		var sw: float = sub.offset_right - sub.offset_left
		sub.anchor_left = 0.5
		sub.anchor_right = 0.5
		sub.anchor_top = 0.0
		sub.anchor_bottom = 0.0
		sub.offset_left = -sw / 2.0
		sub.offset_right = sw / 2.0
		sub.offset_top = top_y
		sub.offset_bottom = top_y + sh
	account_close_button.visible = false
	open()

## Back to the normal pop-up (used when leaving the title screen).
func undock() -> void:
	if not _docked:
		return
	_docked = false
	background.color = Color(0, 0, 0, 0.6)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	account_panel.anchor_top = _saved_offsets[0]
	account_panel.anchor_bottom = _saved_offsets[1]
	account_panel.offset_top = _saved_offsets[2]
	account_panel.offset_bottom = _saved_offsets[3]
	account_panel.visible = true
	for sub in _sub_saved:
		var v: Array = _sub_saved[sub]
		sub.anchor_left = v[0]
		sub.anchor_right = v[1]
		sub.anchor_top = v[2]
		sub.anchor_bottom = v[3]
		sub.offset_left = v[4]
		sub.offset_right = v[5]
		sub.offset_top = v[6]
		sub.offset_bottom = v[7]
	account_close_button.visible = true
	(account_panel.get_node("OuterVBox/ScrollContainer") as Control).custom_minimum_size.y = 170.0
	close()

## While docked, show either the account list or one of its forms, never
## both stacked on top of each other.
func _process(_delta: float) -> void:
	if _docked and background.visible:
		account_panel.visible = not (new_account_panel.visible or sign_in_panel.visible)
