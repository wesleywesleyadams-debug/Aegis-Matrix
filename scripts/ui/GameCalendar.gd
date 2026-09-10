extends Label
## In-game calendar shown just below GameTimer's elapsed-time clock --
## purely a reading of GameTimer's own elapsed time (see game_timer_path),
## not separate state of its own, so it never needs saving/restoring the
## way GameTimer.set_elapsed() does: whatever match time a save resumes
## at, this just recomputes from that.

## Seconds per in-game day / years per in-game century -- the user's own
## chosen scale (1s/day, 100 years/century), arbitrary game-time units
## with no other significance.
const DAY_SECONDS: float = 1.0
const CENTURY_YEARS: int = 100

## Always 12 months/year, but not all the same length -- 365 doesn't
## divide evenly by 12, so these mirror the real (non-leap) Gregorian
## calendar's lengths, which do sum to exactly 365 with nothing left
## over, rather than forcing every month to match at the cost of an
## odd total.
const MONTH_LENGTHS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const YEAR_DAYS: int = 365

@export var game_timer_path: NodePath
@onready var game_timer: Label = get_node(game_timer_path)

func _process(_delta: float) -> void:
	var total_days := int(game_timer.get_elapsed() / DAY_SECONDS)
	var total_years := total_days / YEAR_DAYS
	var centuries := total_years / CENTURY_YEARS
	var years := total_years % CENTURY_YEARS
	var day_of_year := total_days % YEAR_DAYS
	var months := 0
	for month_length in MONTH_LENGTHS:
		if day_of_year < month_length:
			break
		day_of_year -= month_length
		months += 1
	text = "%d centuries, %d years, %d months, and %d days" % [centuries, years, months, day_of_year]
