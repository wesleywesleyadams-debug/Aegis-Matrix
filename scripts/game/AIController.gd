class_name AIController
extends Node
## Simple computer opponent: keeps ~6 miners working, builds a mixed fleet,
## claims nearby neutral planets, defends its starbase, and launches
## growing attack waves at the nearest enemy asset.

const TARGET_MINERS := 6

var players: Array[int] = []
var _state := {}

func setup(ai_players: Array) -> void:
	for pid in ai_players:
		players.append(pid)
		_state[pid] = {"wave": 8, "timer": randf(), "claimers": []}

func _process(delta: float) -> void:
	var game := Game.instance
	if game == null or game.is_over:
		return
	for pid in players:
		var st: Dictionary = _state[pid]
		st["timer"] -= delta
		if st["timer"] > 0.0:
			continue
		st["timer"] = 1.0
		_think(pid, st, game)

func _think(pid: int, st: Dictionary, game: Game) -> void:
	var base := game.nearest_starbase(pid, Vector2.ZERO)
	if base == null:
		return
	var ships: Array = game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid)
	var miners := ships.filter(func(s): return s.is_miner())
	var war := ships.filter(func(s): return not s.is_miner())

	# Economy first.
	var queued_miners := base.queue.count("miner")
	if miners.size() + queued_miners < TARGET_MINERS and base.queue.size() < 2:
		base.enqueue("miner")
	elif base.queue.size() < 2:
		var pick := _pick_warship(pid, game)
		if pick != "":
			base.enqueue(pick)

	# Idle miners go back to work.
	for m in miners:
		if m.state == Ship.State.IDLE:
			var rock := game.nearest_asteroid(m.global_position, 1200.0)
			if rock:
				m.order_mine(rock)

	# Defend: enemies near the starbase pull every warship home.
	var threat := game.nearest_enemy(base, 450.0)
	if threat:
		for s in war:
			if s.state != Ship.State.ATTACK:
				s.order_attack_move(threat.global_position)
		return

	var idle := war.filter(func(s): return s.state == Ship.State.IDLE)

	# Send a pair of idle corvettes to claim the nearest unowned planet.
	st["claimers"] = st["claimers"].filter(func(s): return is_instance_valid(s))
	if st["claimers"].is_empty() and idle.size() >= 2:
		var planet := _nearest_planet(base.global_position, game, func(p): return p.owner_id != pid)
		if planet:
			for s in idle.slice(0, 2):
				s.order_attack_move(planet.global_position + Vector2.from_angle(randf() * TAU) * planet.radius * 1.4)
				st["claimers"].append(s)
			idle = idle.slice(2)

	# Attack wave once the idle fleet is big enough.
	var idle_supply := 0
	for s in idle:
		idle_supply += s.def["supply"]
	if idle_supply >= st["wave"]:
		var goal := _attack_goal(pid, base.global_position, game)
		for s in idle:
			s.order_attack_move(goal + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
		st["wave"] = mini(st["wave"] + 4, 30)

func _pick_warship(pid: int, game: Game) -> String:
	var options: Array[String] = ["corvette", "corvette", "destroyer", "destroyer", "cruiser"]
	options.shuffle()
	for t in options:
		if game.can_afford(pid, Defs.SHIPS[t]["cost"]) and game.supply_used(pid) + Defs.SHIPS[t]["supply"] <= Defs.FLEET_CAP:
			return t
	return ""

func _nearest_planet(from: Vector2, game: Game, filter: Callable) -> Planet:
	var best: Planet = null
	var best_d := INF
	for p in game.get_tree().get_nodes_in_group("planets"):
		if filter.call(p):
			var d := from.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best

func _attack_goal(pid: int, from: Vector2, game: Game) -> Vector2:
	# Enemy-held planets first (they're closer and pay the enemy), then the base.
	var p := _nearest_planet(from, game, func(pl): return pl.owner_id != 0 and pl.owner_id != pid)
	var enemy_base: Starbase = null
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id != pid:
			enemy_base = sb
	if p and (enemy_base == null or from.distance_to(p.global_position) < from.distance_to(enemy_base.global_position)):
		return p.global_position
	return enemy_base.global_position if enemy_base else from
