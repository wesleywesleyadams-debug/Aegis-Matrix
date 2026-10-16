class_name DemoDirector
extends Node
## Runs the camera for the title screen's background match (Game.demo_mode):
## it holds on one side's starbase, then drifts across to the other's. It also says when the
## match is done, so the title screen can start a fresh one: when a side
## wins, or when it has run long without one.

signal finished

## Real seconds between choosing where to look.
const RESHOT := 12.0
## How quickly the camera eases toward its target (per real second).
const EASE := 0.6
## A match that has not been decided by now is cut, so the title screen
## keeps showing openings and fights rather than a long stalemate.
const MAX_GAME_SECONDS := 900.0
## Real seconds the final moment is held before the next match.
const HOLD_AFTER := 5.0

var _target := Vector2.ZERO
var _timer := 0.0
var _done := false
var _shot := -1
var _max_seconds := MAX_GAME_SECONDS

func _ready() -> void:
	var g := Game.instance
	g.match_over.connect(func(_won): _finish())
	_choose()
	g.camera.global_position = _framed(_target)
	# Dev: SL_DEMO_MAX=<game seconds> cuts matches short, to test the restart.
	if OS.get_environment("SL_DEMO_MAX") != "":
		_max_seconds = float(OS.get_environment("SL_DEMO_MAX"))

func _process(_delta: float) -> void:
	var g := Game.instance
	if g == null:
		return
	# Real time, so the pacing is the same whatever speed the match runs at.
	var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.001)
	_timer -= dt
	if _timer <= 0.0:
		_timer = RESHOT
		_choose()
	var look := _framed(_target)
	g.camera.global_position = g.camera.global_position.lerp(look, clampf(EASE * dt, 0.0, 1.0))
	if not _done and Game.now() > _max_seconds:
		_finish()

## Where the camera sits to show `p`: centred on it, but held where its whole
## view stays inside the map.
func _framed(p: Vector2) -> Vector2:
	var g := Game.instance
	var z: float = g.camera.zoom.x
	var half := g.get_viewport().get_visible_rect().size / 2.0 / z
	var r := Game.MAP_RECT.grow_individual(-half.x, -half.y, -half.x, -half.y)
	return p.clamp(r.position, r.end) if r.size.x > 0.0 and r.size.y > 0.0 else p

## The starbases, one side and then the other each shot: they are where a
## match is built, defended and finally decided.
func _choose() -> void:
	var g := Game.instance
	var bases: Array = g.get_tree().get_nodes_in_group("starbases").filter(func(b): return b.is_alive() and not b.under_construction)
	if bases.is_empty():
		return
	bases.sort_custom(func(a, b): return a.owner_id < b.owner_id)
	_shot += 1
	_target = bases[_shot % bases.size()].global_position

func _finish() -> void:
	if _done:
		return
	_done = true
	await get_tree().create_timer(HOLD_AFTER, true, false, true).timeout
	finished.emit()
