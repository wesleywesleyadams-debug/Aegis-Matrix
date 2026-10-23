extends CanvasLayer
## Autoload -- top-right account status, shown only on the title screen's
## main menu (hidden in the Codex, lobby, load list, in-game, etc., so other
## screens get the full height). Plain text, no button box -- reads
## "Signed in as: "User"" in green when signed in (inert; see _refresh's
## disabled toggle), or a clickable "Sign In" that opens AccountMenu when
## not. Width is generous but still bounded, with clip_text + ellipsis
## trimming, so an unusually long account name can't run off-screen.
## Listens to GameState.active_account_changed rather than polling every
## frame.

const SIGNED_IN_COLOR := Color(0.25, 0.75, 0.3, 1)

@onready var status_button: Button = $StatusButton

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	status_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_button.pressed.connect(AccountMenu.open)
	GameState.active_account_changed.connect(_refresh)
	_refresh()

## Visible only while the title screen's main menu is showing.
func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	var want: bool = cs != null and cs.scene_file_path == "res://scenes/TitleMenu.tscn" 			and cs.has_node("TitleLabel") and cs.get_node("TitleLabel").visible
	if visible != want:
		visible = want

func _refresh() -> void:
	var signed_in := not GameState.active_account.is_empty()
	status_button.text = "Signed in as: \"%s\"" % GameState.active_account if signed_in else "Sign In"
	# Signed in: just a status readout, not a click target (there's nothing
	# useful to do by clicking your own name here -- use the Account panel
	# to sign out). Signed out: a real button, so its hover/press styling
	# actually reads as "click me to sign in".
	status_button.disabled = signed_in
	status_button.add_theme_color_override("font_disabled_color", SIGNED_IN_COLOR)
