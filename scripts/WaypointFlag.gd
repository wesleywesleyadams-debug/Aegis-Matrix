extends Node3D
## A pole-and-pennant marker showing one step of a group's queued
## waypoint route (see RTSController._move_queues). The small number
## label shows this flag's position in that sequence -- 1 for the leg
## currently being traveled to, 2 for the next queued after it, and so on
## -- kept in sync by RTSController whenever the queue changes.

@onready var number_label: Label3D = $NumberLabel

func set_number(n: int) -> void:
	number_label.text = str(n)
