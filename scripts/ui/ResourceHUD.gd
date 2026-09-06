extends Label
## Top-left resource (gold) counter. No economy system exists yet -- no
## income, no costs, nothing spends or earns gold -- so this just displays
## a fixed starting amount, the same "capability now, behavior later"
## placeholder pattern used by the Lobby's Race/Item/Map/AI options.
## add_gold()/spend_gold() are here so wiring up a real economy later is
## just calling these, not touching the display logic.

@export var starting_gold: int = 500

var gold: int

func _ready() -> void:
	gold = starting_gold
	_update_text()

func add_gold(amount: int) -> void:
	gold += amount
	_update_text()

## Returns true and deducts if there's enough gold; false (no change)
## otherwise -- the usual "can afford it" pattern once purchases exist.
func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	_update_text()
	return true

func _update_text() -> void:
	text = "Gold: %d" % gold
