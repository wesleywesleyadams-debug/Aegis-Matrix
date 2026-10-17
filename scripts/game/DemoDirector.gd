class_name DemoDirector
extends Node
## Runs the camera for the title screen's background match (Game.demo_mode):
## it holds still on one player's home - midway between their home world
## and starting starbase - then cuts to the other's. It also says when the
## match is done, so the title screen can start a fresh one: when a side
## wins, or when it has run long without one.

signal finished

## Real seconds between choosing where to look.
const RESHOT := 12.0
## A match that has not been decided by now is cut, so the title screen
## keeps showing openings and fights rather than a long stalemate.
const MAX_GAME_SECONDS := 900.0
## Real seconds the final moment is held before the next match.
const HOLD_AFTER := 5.0
## Real seconds of each cut between shots: half fading to black, half back in.
const FADE := 2.0

var _target := Vector2.ZERO
var _timer := 0.0
var _done := false
var _shot := -1
var _max_seconds := MAX_GAME_SECONDS
var _veil: ColorRect

func _ready() -> void:
	var g := Game.instance
	g.match_over.connect(func(_won): _finish())
	_choose()
	_timer = RESHOT
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_veil)
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
	# A straight cut to the shot, held still: no panning.
	# Fade to black over the last second of a shot, back in over the first.
	var half := FADE / 2.0
	var into := RESHOT - _timer
	_veil.color.a = clampf(maxf((half - _timer) / half, (half - into) / half if _shot > 0 else 0.0), 0.0, 1.0)
	g.camera.global_position = _framed(_target)
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

## The two shots, fixed at the start of the match: for each player, the open
## space midway between their home world and their starting starbase, where
## the opening plays out.
var _shots: Array = []

func _plan_shots() -> void:
	var g := Game.instance
	for pid in g.players:
		var base: Node2D = null
		for b in g.get_tree().get_nodes_in_group("starbases"):
			if b.owner_id == pid:
				base = b
				break
		if base == null:
			continue
		var home: Node2D = null
		var best := INF
		for p in g.get_tree().get_nodes_in_group("planets"):
			if p.owner_id == pid and p.global_position.distance_to(base.global_position) < best:
				best = p.global_position.distance_to(base.global_position)
				home = p
		_shots.append((base.global_position + home.global_position) / 2.0 if home else base.global_position)

## One player's shot, then the other's.
func _choose() -> void:
	if _shots.is_empty():
		_plan_shots()
	if _shots.is_empty():
		return
	_shot += 1
	_target = _shots[_shot % _shots.size()]

func _finish() -> void:
	if _done:
		return
	_done = true
	await get_tree().create_timer(HOLD_AFTER, true, false, true).timeout
	finished.emit()
