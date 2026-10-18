class_name NeuralVersion
## Which trained version of the learning AI is available: train.py keeps a
## numbered copy of its checkpoint every 50 updates (tools/rl/runs/
## ckpt_<update>.pt); the newest is what a Neural AI slot plays, and its
## update number is the version shown in the lobby and in-game ("v3800").

static func runs_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("tools/rl/runs")

## Full path of the newest numbered checkpoint, or "" if there is none.
static func newest_path() -> String:
	var dir := DirAccess.open(runs_dir())
	if dir == null:
		return ""
	var best := -1
	for f in dir.get_files():
		if f.begins_with("ckpt_") and f.ends_with(".pt"):
			best = maxi(best, int(f.trim_prefix("ckpt_").trim_suffix(".pt")))
	return "" if best < 0 else runs_dir().path_join("ckpt_%d.pt" % best)

static func of(path: String) -> int:
	return int(path.get_file().trim_prefix("ckpt_").trim_suffix(".pt"))

## "v3800", or "" when no trained version exists.
static func label() -> String:
	var p := newest_path()
	return "" if p == "" else "v%d" % of(p)
