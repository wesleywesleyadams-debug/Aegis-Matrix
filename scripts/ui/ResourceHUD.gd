extends Label
## Top-left resource (Grace) counter. Grace is the universal
## experience-style currency -- earned by the player through kills and
## other in-match achievements, spent later on unlocking skills from
## the (not yet built) skill tree, rather than a build/spend economy
## resource like a traditional RTS's gold. No reward system or skill
## tree exists yet, so this just displays a fixed starting amount, the
## same "capability now, behavior later" placeholder pattern used by
## the Lobby's Race/Item/Map/AI options. add_grace()/spend_grace() are
## here so wiring up real kill rewards and skill-tree purchases later
## is just calling these, not touching the display logic.

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
