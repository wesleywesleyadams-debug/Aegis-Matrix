extends Node
## Autoload -- thin wrapper around the GodotSteam GDExtension's "Steam"
## engine singleton (see addons/godotsteam). Named SteamService rather than
## "Steam" to avoid colliding with that singleton's own name.
##
## Requires the Steam client to be running and logged in locally -- there is
## no separate username/password to check here, unlike GameState's local
## accounts (see AccountMenu.gd): if Steam says you're you, you're signed
## in. Development/testing runs against Valve's public Spacewar test App ID
## (480, see steam_appid.txt) rather than a real registered App ID.

var available: bool = false
var steam_id: int = 0
var persona_name: String = ""

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		return
	var steam := Engine.get_singleton("Steam")
	available = bool(steam.steamInit())
	if not available:
		return
	steam_id = steam.getSteamID()
	persona_name = steam.getPersonaName()
