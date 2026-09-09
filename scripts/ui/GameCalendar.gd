extends Label
## In-game calendar shown just below GameTimer's elapsed-time clock --
## purely a reading of GameTimer's own elapsed time (see game_timer_path),
## not separate state of its own, so it never needs saving/restoring the
## way GameTimer.set_elapsed() does: whatever match time a save resumes
## at, this just recomputes from that.

## Seconds per in-game day / days per in-game year / years per in-game
## century -- the user's own chosen scale (24s/day, 365 days/year, 100
## years/century), arbitrary game-time units with no other significance.
const DAY_SECONDS: float = 24.0
const YEAR_DAYS: int = 365
const CENTURY_YEARS: int = 100

@export var game_timer_path: NodePath
@onready var game_timer: Label = get_node(game_timer_path)

func _process(_delta: float) -> void:
	var total_days := int(game_timer.get_elapsed() / DAY_SECONDS)
	var total_years := total_days / YEAR_DAYS
	var centuries := total_years / CENTURY_YEARS
	var years := total_years % CENTURY_YEARS
	var days := total_days % YEAR_DAYS
	text = "%d centuries, %d years, and %d days" % [centuries, years, days]
