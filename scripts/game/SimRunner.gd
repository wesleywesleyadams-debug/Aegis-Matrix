class_name SimRunner
extends Node
## AI-vs-AI balance harness. Enabled with SL_SIM="<run id>" (Game adds this
## node and lets the AI play both sides). Runs the match as fast as the
## machine allows (launch with --headless --fixed-fps 60), samples both
## sides every SAMPLE game seconds, and ends on a win or at SL_SIM_MINUTES
## (default 40) as a draw. Writes user://sims/<system>_<run>.json and prints
## one "SIM RESULT" line, then quits.

const SAMPLE := 60.0

var run_id: String = "0"
var max_minutes: float = 40.0
var samples: Array = []
var _next_sample: float = 0.0
var _done := false
var _t0_ms: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run_id = OS.get_environment("SL_SIM")
	if OS.get_environment("SL_SIM_MINUTES") != "":
		max_minutes = float(OS.get_environment("SL_SIM_MINUTES"))
	Engine.time_scale = float(OS.get_environment("SL_SIM_SCALE")) if OS.get_environment("SL_SIM_SCALE") != "" else 4.0
	_t0_ms = Time.get_ticks_msec()
	Game.instance.match_over.connect(func(won: bool): _finish("defeat", Game.instance.player_id if won else 3 - Game.instance.player_id))

func _process(_delta: float) -> void:
	if _done:
		return
	var t := Game.now()
	if t >= _next_sample:
		samples.append(_sample(t))
		_next_sample += SAMPLE
	if t >= max_minutes * 60.0:
		_finish("time", 0)

## One snapshot per side (see MatchStats.sample).
func _sample(t: float) -> Dictionary:
	return MatchStats.sample(t)

## How often each side's neural commander picked each action (if any).
func _nn_actions() -> Dictionary:
	var out := {}
	for pid in Game.instance.ai._state:
		var nn = Game.instance.ai._state[pid].get("nn")
		if nn:
			out[str(pid)] = nn.counts
	return out

func _finish(reason: String, winner: int) -> void:
	if _done:
		return
	_done = true
	samples.append(_sample(Game.now()))
	var result := {"system": GameState.system_id, "seed": GameState.system_seed, "run": run_id, "winner": winner,
		"reason": reason, "minutes": snappedf(Game.now() / 60.0, 0.1), "real_seconds": snappedf((Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.1),
		"samples": samples, "nn_actions": _nn_actions(), "counters": Game.instance.stats.counters}
	DirAccess.make_dir_recursive_absolute("user://sims")
	var f := FileAccess.open("user://sims/%s_%s.json" % [GameState.system_id, run_id], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result))
		f.close()
	var last: Dictionary = samples[-1]
	print("SIM RESULT system=%s run=%s winner=%d reason=%s minutes=%.1f real=%.0fs  P1 worlds %d ships %d  P2 worlds %d ships %d" % [
		GameState.system_id, run_id, winner, reason, Game.now() / 60.0, (Time.get_ticks_msec() - _t0_ms) / 1000.0,
		last["1"]["worlds"], last["1"]["warships"], last["2"]["worlds"], last["2"]["warships"]])
	get_tree().quit()
