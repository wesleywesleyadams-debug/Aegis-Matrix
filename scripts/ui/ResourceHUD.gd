extends Label
## Top-left resource (Grace) counter. No economy system exists yet -- no
## income, no costs, nothing spends or earns Grace -- so this just displays
## a fixed starting amount, the same "capability now, behavior later"
## placeholder pattern used by the Lobby's Race/Item/Map/AI options.
## add_grace()/spend_grace() are here so wiring up a real economy later is
## just calling these, not touching the display logic.

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
