extends Node
class_name SeasonClock
## Slowly-rotating annual season cycle -- Spring/Summer/Fall/Winter, each an
## equal quarter of the in-game year. Purely a reading of GameTimer's own
## elapsed time (see game_timer_path), same "no separate state of its own,
## so nothing needs saving/restoring" reasoning GameCalendar.gd already has
## -- DAY_SECONDS/YEAR_DAYS deliberately mirror GameCalendar's own so the
## two clocks can never drift apart.
##
## Broadcasts season_changed/day_changed once per real transition so
## gameplay (see World.gd's own oak/apple fall-refresh and winter-lifespan
## death) can react to the moment something actually changes, rather than
## every World node independently re-deriving "did this juuust happen"
## from raw elapsed time each physics frame.

## Fires the instant the calendar crosses into a new season -- `year` is
## how many full in-game years have elapsed (0 during the very first year).
signal season_changed(season: String, year: int)
## Fires once per elapsed in-game day, carrying the same total_days() a
## caller would get by polling -- e.g. World.gd's tree-lifespan check uses
## this to notice "today is the last day of winter" without needing its
## own per-frame timer.
signal day_changed(total_days: int)

const DAY_SECONDS: float = 1.0
const YEAR_DAYS: int = 365
const SEASONS: Array[String] = ["Spring", "Summer", "Fall", "Winter"]
## Cumulative day-of-year each season STARTS on -- 91/92/91/91 split so the
## four quarters sum to exactly YEAR_DAYS with nothing left over, the same
## "can't divide evenly, so absorb the remainder somewhere" reasoning
## GameCalendar's own MONTH_LENGTHS has. Winter is therefore the one
## quarter that ends the calendar year outright -- its own last day is
## always YEAR_DAYS - 1, which is what World.gd's 4-winters-and-it-dies
## check keys off.
const SEASON_START_DAYS: Array[int] = [0, 91, 183, 274]

@export var game_timer_path: NodePath
@onready var game_timer: Label = get_node(game_timer_path)

var _last_season_index: int = -1
var _last_total_days: int = -1

func _process(_delta: float) -> void:
	var td := total_days()
	if td != _last_total_days:
		_last_total_days = td
		day_changed.emit(td)
	var index := _season_index_for_day(td % YEAR_DAYS)
	if index != _last_season_index:
		_last_season_index = index
		season_changed.emit(SEASONS[index], td / YEAR_DAYS)

func _season_index_for_day(day_of_year: int) -> int:
	for i in range(SEASON_START_DAYS.size() - 1, -1, -1):
		if day_of_year >= SEASON_START_DAYS[i]:
			return i
	return 0

## Total whole in-game days elapsed since the match started -- also what
## World.gd would use to timestamp a tree's own spawn day, if it ever
## needed one (it doesn't -- see World._on_day_changed's own doc comment
## for why a shared calendar day works just as well).
func total_days() -> int:
	return int(game_timer.get_elapsed() / DAY_SECONDS)

## Current season name ("Spring"/"Summer"/"Fall"/"Winter").
func current_season() -> String:
	return SEASONS[_season_index_for_day(total_days() % YEAR_DAYS)]

## 0..1 fraction of the way through the CURRENT season -- unused by the
## dial itself (see SeasonDial.gd's own year_progress-only needle), kept
## as a small public convenience for anything wanting finer-grained
## progress within just the current season.
func season_progress() -> float:
	var day_of_year := total_days() % YEAR_DAYS
	var index := _season_index_for_day(day_of_year)
	var start := SEASON_START_DAYS[index]
	var end: int = SEASON_START_DAYS[index + 1] if index + 1 < SEASON_START_DAYS.size() else YEAR_DAYS
	return clampf(float(day_of_year - start) / float(end - start), 0.0, 1.0)

## 0..1 fraction of the way through the full year -- drives the dial
## needle's overall rotation (see SeasonDial.gd).
func year_progress() -> float:
	return float(total_days() % YEAR_DAYS) / float(YEAR_DAYS)
