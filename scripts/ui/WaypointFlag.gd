extends Node3D
class_name WaypointFlag
## A pole-and-pennant marker showing one step of a group's queued
## waypoint route (see RTSController._move_queues) or a building's gather
## queue (see Building.gather_points). The small number label shows this
## flag's position in that sequence -- 1 for the leg currently being
## traveled to, 2 for the next queued after it, and so on -- kept in sync
## by the caller whenever the queue changes.

const SCENE: PackedScene = preload("res://scenes/WaypointFlag.tscn")

@onready var number_label: Label3D = $NumberLabel

func set_number(n: int) -> void:
	number_label.text = str(n)

## Instantiates, parents, and positions/numbers a flag in one call -- the
## shared spawn logic both RTSController (unit move-order queues) and
## Building (gather-point queues) need, so it's not duplicated in both.
static func spawn(parent: Node, world_position: Vector3, number: int = 1) -> WaypointFlag:
	var flag: WaypointFlag = SCENE.instantiate()
	parent.add_child(flag)
	flag.global_position = world_position
	flag.set_number(number)
	return flag
