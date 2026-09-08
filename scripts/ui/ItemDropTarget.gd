extends Control
## Full-screen drop target for ItemSlotButton's drag data (see
## EquipmentPanel/BuildingStoragePanel). Only actually intercepts mouse
## input while an item drag is in progress (see _process) -- mouse_filter
## sits at IGNORE the rest of the time, so this invisible full-screen
## overlay doesn't steal ordinary clicks meant for the Menu button or any
## other UI underneath it, and doesn't even block the press that starts a
## drag on an ItemSlotButton in the first place. Switching to PASS (rather
## than STOP) while dragging still lets the drop -- once handled here --
## fall through if anything else downstream cared, though nothing
## currently does.
##
## Forwards the actual drop to RTSController, which owns the
## raycasting/unequip/equip/store/spawn logic -- this node only exists
## because _can_drop_data/_drop_data are Control-only virtuals, and
## RTSController's own root is a Node3D.

func _process(_delta: float) -> void:
	mouse_filter = MOUSE_FILTER_PASS if get_viewport().gui_is_dragging() else MOUSE_FILTER_IGNORE

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		typeof(data) == TYPE_DICTIONARY and data.has("item_type")
		and (data.get("source_unit") != null or data.get("source_building") != null)
	)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	owner.handle_item_drag_drop(data["item_type"], data.get("source_slot", ""), data.get("source_unit"), data.get("source_building"), at_position)
