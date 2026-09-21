extends Node3D

func _run_test(right_item: String, left_item: String) -> float:
	var unit_scene: PackedScene = load("res://scenes/ParentUnit.tscn")
	var attacker = unit_scene.instantiate()
	attacker.player_id = 1
	add_child(attacker)
	attacker.equip_item(right_item)
	attacker.equip_item(left_item)

	var target = unit_scene.instantiate()
	target.player_id = 2
	target.aggressive_stance = false
	add_child(target)
	target.global_position = Vector3(0.6, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	var start_health: float = target.current_health
	var right_dmg: float = ItemDefs.get_damage(right_item)
	var left_dmg: float = ItemDefs.get_damage(left_item)
	var expected: float = right_dmg + left_dmg

	attacker.attack(target)

	var start_ms := Time.get_ticks_msec()
	var started_attacking := false
	while (Time.get_ticks_msec() - start_ms) < 15000:
		await get_tree().physics_frame
		if attacker._attacking:
			started_attacking = true
		elif started_attacking:
			break

	var dealt: float = start_health - target.current_health
	attacker.queue_free()
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return dealt / expected

func _ready() -> void:
	for scale in [2.5, 3.0, 4.0, 5.0]:
		Entity.HIT_CHECK_SPHERE_SCALE = scale
		var results: Array = []
		for trial in range(4):
			results.append(await _run_test("iron_shortsword", "iron_shortsword"))
			results.append(await _run_test("sword", "sword"))
		print("scale=", scale, " results=", results, " min=", results.min(), " avg=", results.reduce(func(a, b): return a + b) / results.size())
	print("DONE")
	get_tree().quit()
