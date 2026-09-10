extends Label
## Top-left resource (Grace) counter. Intended to be earned by the
## player through kills and other in-match achievements (not a
## build/spend economy resource) -- but no such reward system exists
## yet, so this just displays a fixed starting amount, the same
## "capability now, behavior later" placeholder pattern used by the
## Lobby's Race/Item/Map/AI options. add_grace()/spend_grace() are here
## so wiring up real kill/achievement rewards later is just calling
## add_grace(), not touching the display logic.

@export var starting_grace: int = 500

var grace: int

func _ready() -> void:
	grace = starting_grace
	_update_text()

func add_grace(amount: int) -> void:
	grace += amount
	_update_text()

## Returns true and deducts if there's enough Grace; false (no change)
## otherwise -- the usual "can afford it" pattern once purchases exist.
func spend_grace(amount: int) -> bool:
	if amount > grace:
		return false
	grace -= amount
	_update_text()
	return true

func _update_text() -> void:
	text = "Grace: %d" % grace
