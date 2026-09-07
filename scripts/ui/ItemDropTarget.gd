extends Control
## Full-screen, invisible drop target for ItemSlotButton's drag data (see
## EquipmentPanel/BuildingStoragePanel) -- placed as the topmost UI child
## so it's checked first for every drop regardless of what's underneath,
## but mouse_filter=PASS lets ordinary clicks fall straight through to
## whatever control (or the 3D world, via RTSController's own
## _unhandled_input) is actually there. Just forwards to RTSController,
## which owns the actual raycasting/unequip/equip/store/spawn logic -- this
## node only exists because _can_drop_data/_drop_data are Control-only
## virtuals, and RTSController's own root is a Node3D.

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		typeof(data) == TYPE_DICTIONARY and data.has("item_type")
		and (data.get("source_unit") != null or data.get("source_building") != null)
	)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	owner.handle_item_drag_drop(data["item_type"], data.get("source_unit"), data.get("source_building"), at_position)
