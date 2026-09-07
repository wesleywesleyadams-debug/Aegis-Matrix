extends CanvasLayer
## Autoload -- top-right account status shown on every scene (title, lobby,
## in-game), left of Main's own Menu button rather than overlapping it (see
## StatusButton's offsets, tuned to sit just left of that button's corner
## position). Reads "Signed in as: "User"" when signed in (inert -- see
## _refresh's disabled toggle) or a clickable "Sign In" that opens
## AccountMenu when not. Listens to GameState.active_account_changed
## rather than polling every frame.

@onready var status_button: Button = $StatusButton

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	status_button.pressed.connect(AccountMenu.open)
	GameState.active_account_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var signed_in := not GameState.active_account.is_empty()
	status_button.text = "Signed in as: \"%s\"" % GameState.active_account if signed_in else "Sign In"
	# Signed in: just a status readout, not a click target (there's nothing
	# useful to do by clicking your own name here -- use the Account panel
	# to sign out). Signed out: a real button, so its hover/press styling
	# actually reads as "click me to sign in".
	status_button.disabled = signed_in
