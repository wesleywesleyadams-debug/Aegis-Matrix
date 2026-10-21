class_name WarpGate
extends FortConstruct
## Warp Gate (Defs.WARP_GATE): no gun. Own ships ordered into it garrison
## inside (no limit) — hidden, out of the grid and targeting like a depot's
## docked ships (Ship.enter_gate) but still paying upkeep. The gate can eject
## them one at a time or all at once, or WARP them: every garrisoned ship is
## flung at a point warp_min..warp_max px away and flies there in a straight
## line at warp_speed_mult x its speed, deaf to orders and unable to fire
## until it arrives (Ship.warping). Then the gate cools down for
## warp_cooldown seconds.
##
## If the gate dies, every ship inside dies with it.

## Ships inside, in the order they came in.
var garrison: Array = []
## Seconds until the gate can warp again.
var cooldown_left: float = 0.0
## Launch flash, seconds left (drawn as a bright ring).
var _flash: float = 0.0

const FLASH_TIME := 0.6

func def() -> Dictionary:
	return Defs.WARP_GATE

func sprite_name() -> String:
	return "ship_warp_gate"

func _done_note() -> String:
	return "%s complete: right-click it with ships selected to garrison them." % label()

func is_open() -> bool:
	return not under_construction and is_alive()

## Takes a ship in: it disappears inside until ejected or warped.
func admit(s: Ship) -> void:
	if not is_open() or garrison.has(s) or s.owner_id != owner_id:
		return
	garrison.append(s)
	s.enter_gate(self)
	queue_redraw()
	if owner_id == Game.instance.player_id:
		Game.instance.selection_changed.emit()

## Live garrisoned ships (drops any freed by a save load).
func ships() -> Array:
	garrison = garrison.filter(func(s): return is_instance_valid(s) and s.is_alive())
	return garrison

func eject(s: Ship) -> void:
	if not garrison.has(s):
		return
	garrison.erase(s)
	if is_instance_valid(s):
		s.leave_gate(self)
	queue_redraw()

func eject_all() -> void:
	for s in ships().duplicate():
		eject(s)

## "" if the gate can warp to `pos` right now, else why not.
func warp_problem(pos: Vector2) -> String:
	if not is_open():
		return "The gate is not finished"
	if cooldown_left > 0.0:
		return "The gate is recharging (%ds)" % int(ceil(cooldown_left))
	if ships().is_empty():
		return "No ships in the gate"
	var d := global_position.distance_to(pos)
	if d < def()["warp_min"]:
		return "Too close: warp at least %d px" % int(def()["warp_min"])
	if d > def()["warp_max"]:
		return "Too far: warp at most %d px" % int(def()["warp_max"])
	if pos.length() > Game.MAP_RADIUS:
		return "Outside the system"
	return ""

## Flings the whole garrison at `pos`. Returns "" or why it could not.
func warp(pos: Vector2) -> String:
	var why := warp_problem(pos)
	if why != "":
		return why
	var out := ships().duplicate()
	garrison.clear()
	for s in out:
		s.start_warp(self, pos)
	cooldown_left = def()["warp_cooldown"]
	_flash = FLASH_TIME
	queue_redraw()
	if owner_id == Game.instance.player_id:
		Game.instance.selection_changed.emit()
	return ""

func _operate(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
		queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

## Destroyed with ships inside: they are lost with it.
func _die() -> void:
	var lost := ships().duplicate()
	garrison.clear()
	for s in lost:
		s.docked = false
		s._die()
	if owner_id == Game.instance.player_id and not lost.is_empty():
		Game.instance.alert("%s destroyed with %d ships inside!" % [label(), lost.size()], "alert_starbase_lost", true, global_position)
	super._die()

func _draw() -> void:
	super._draw()
	if under_construction:
		return
	# Garrison pips under the gate (up to 12 shown).
	var n := mini(garrison.size(), 12)
	for i in n:
		draw_rect(Rect2(-n * 2.5 + i * 5.0, radius + 18.0, 3.0, 3.0), Color("7fd8ff"))
	# Recharging: a dim arc that fills back up clockwise.
	if cooldown_left > 0.0:
		var frac: float = 1.0 - cooldown_left / def()["warp_cooldown"]
		draw_arc(Vector2.ZERO, radius + 16.0, 0.0, TAU, 48, Color(0.5, 0.85, 1.0, 0.15), 2.0)
		draw_arc(Vector2.ZERO, radius + 16.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, Color(0.5, 0.85, 1.0, 0.8), 2.0)
	# Launch flash: a bright ring blowing outward.
	if _flash > 0.0:
		var k := 1.0 - _flash / FLASH_TIME
		draw_circle(Vector2.ZERO, radius * (0.6 + 0.4 * k), Color(0.8, 0.95, 1.0, 0.6 * (1.0 - k)))
		draw_arc(Vector2.ZERO, radius * (1.0 + 2.5 * k), 0.0, TAU, 48, Color(0.6, 0.9, 1.0, 1.0 - k), 3.0)
