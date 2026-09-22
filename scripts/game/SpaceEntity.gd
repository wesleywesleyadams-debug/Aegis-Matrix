class_name SpaceEntity
extends Node2D
## Anything with an owner and defenses that can be selected and shot: ships
## and starbases. Defenses are layered: shields (regenerate), then armor
## (doesn't regenerate; Repair Tenders restore it), then hull. Damage drains
## them in that order; the entity dies when its hull reaches 0. Hit detection is a plain circle (radius).

signal died(entity: SpaceEntity)

@export var owner_id: int = 1

var display_name: String = ""
var max_hp: float = 100.0
var hp: float = 100.0
var max_shield: float = 0.0
var shield: float = 0.0
var max_armor: float = 0.0
var armor: float = 0.0
var radius: float = 8.0
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()

## Layer bar colors (Defs.LAYER_COLORS): shields light blue, armor red, hull green.
const ARMOR_COLOR := Color("ff4a4a")

var _last_hit_time: float = -100.0
var _dead: bool = false

func _ready() -> void:
	add_to_group("entities")

func is_alive() -> bool:
	return not _dead and is_inside_tree()

func is_enemy_of(other_owner: int) -> bool:
	return owner_id != 0 and other_owner != 0 and owner_id != other_owner

## `profile` (Defs.damage_profile): "vs" multiplies damage against a layer,
## "pierce" skips layers (1 = shields, 2 = shields and armor). Damage works
## through the layers in order; what a layer can't absorb carries on to the
## next at base value.
func take_damage(amount: float, _from: SpaceEntity = null, profile: Dictionary = {}) -> void:
	if _dead:
		return
	_last_hit_time = Game.now()
	var vs: Dictionary = profile.get("vs", {})
	var pierce: int = profile.get("pierce", 0)
	var rest := amount
	var absorbed := 0.0
	if pierce < 1:
		var m: float = vs.get("shield", 1.0)
		absorbed = minf(shield, rest * m)
		shield -= absorbed
		rest -= absorbed / m
	if pierce < 2 and rest > 0.0:
		var m: float = vs.get("armor", 1.0)
		var plated := minf(armor, rest * m)
		armor -= plated
		rest -= plated / m
	if rest > 0.0:
		hp -= rest * vs.get("hull", 1.0)
	if absorbed > 0.0:
		Game.instance.spawn_shield_hit(global_position, radius, (_from.global_position if is_instance_valid(_from) else global_position + Vector2.RIGHT))
	queue_redraw()
	if hp <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	Game.instance.spawn_explosion(global_position, radius / 10.0)
	died.emit(self)
	queue_free()

func _regen_shields(delta: float) -> void:
	# Spice nebula: shields bleed away and can't recharge while inside.
	if max_shield > 0.0 and Game.instance.in_nebula(global_position) and not Abilities.nebula_protected(self):
		if shield > 0.0:
			shield = maxf(0.0, shield - max_shield * SpiceNebula.DRAIN * delta)
			queue_redraw()
			if owner_id == Game.instance.player_id:
				Game.instance.warn_nebula(global_position)
		return
	if max_shield > 0.0 and shield < max_shield and Game.now() - _last_hit_time > Defs.SHIELD_REGEN_DELAY:
		var gain := minf(max_shield - shield, max_shield * Defs.SHIELD_REGEN_PER_SEC * delta)
		# Regeneration costs a little energy (spice covers any shortfall);
		# regen slows or stops only when both run out.
		var f := Game.instance.pay_over_time(owner_id, {"energy": gain * Defs.SHIELD_ENERGY_PER_POINT}, 1.0)
		if f > 0.0:
			shield += gain * f
			queue_redraw()

## Selection brackets plus hull/shield bars, drawn in world space so they
## scale with the pixel zoom like everything else.
func _draw() -> void:
	var damaged := hp < max_hp or (max_shield > 0.0 and shield < max_shield) or armor < max_armor
	if not selected and not damaged:
		return
	var r := radius + 3.0
	var col := Defs.team_color(owner_id) if selected else Color(1, 1, 1, 0.0)
	# Rotation-independent: undo the node's rotation for the overlay.
	draw_set_transform(Vector2.ZERO, -global_rotation, Vector2.ONE)
	if selected:
		var l := maxf(3.0, r * 0.45)
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var corner: Vector2 = c * r
			draw_line(corner, corner - Vector2(c.x * l, 0), col, 1.0)
			draw_line(corner, corner - Vector2(0, c.y * l), col, 1.0)
	var w := r * 2.0
	var top := -r - 5.0
	draw_rect(Rect2(-r, top, w, 2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-r, top, w * clampf(hp / max_hp, 0, 1), 2), Color("58e07a"))
	# Bars, bottom to top: hull (green), armor (red), shields (light blue).
	var row := 3.0
	if max_armor > 0.0:
		draw_rect(Rect2(-r, top - row, w, 2), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-r, top - row, w * clampf(armor / max_armor, 0, 1), 2), ARMOR_COLOR)
		row += 3.0
	if max_shield > 0.0:
		draw_rect(Rect2(-r, top - row, w, 2), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-r, top - row, w * clampf(shield / max_shield, 0, 1), 2), Color("7fd8ff"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
