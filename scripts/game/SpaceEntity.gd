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
## Inside a Weapons Depot: hidden, safe and not a target (see Ship.enter_depot).
var docked: bool = false
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
	# Screens (Defense) soak a slice of everything before the layers see it.
	amount /= Game.instance.mod(owner_id, "damage_taken") if Game.instance else 1.0
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
## Status arcs: a ring for the selection and three curved gauges above the
## hull â innermost hull, then armor, then shields.
##
## Every point is built in WORLD space and converted with to_local(), rather
## than leaning on draw_set_transform to undo the node's rotation, so the
## gauges stay upright and sit above the ship no matter how it is pointing
## (and no matter what transform anything else left behind).
const ARC_SPAN := deg_to_rad(95.0)
const ARC_STEPS := 20

## An arc of `radius` around this entity, centred on `mid` world-angle, as
## local-space points ready for draw_polyline.
func _arc_points(radius: float, mid: float, span: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var from := mid - span / 2.0
	for i in steps + 1:
		var a: float = from + span * float(i) / float(steps)
		# Snapped to whole world pixels: the game is pixel art, and a line on
		# a fractional coordinate renders as a smear.
		pts.append(to_local((global_position + Vector2(cos(a), sin(a)) * radius).round()))
	return pts

func _draw() -> void:
	var damaged := hp < max_hp or (max_shield > 0.0 and shield < max_shield) or armor < max_armor
	if not selected and not damaged:
		return
	var r := radius + 3.0
	if selected:
		# A ring rather than corner brackets, so the marker reads the same
		# whatever the hull under it is doing.
		var col := Defs.team_color(owner_id)
		draw_polyline(_arc_points(r, 0.0, TAU, 32), Color(col, 0.85), 1.0, false)
	# Gauges arc over the top of the hull (world "up" is -Y), filling left
	# to right as the layer fills.
	var up := -PI / 2.0
	var ring := r + 1.5
	for gauge in [[hp, max_hp, Color("58e07a")], [armor, max_armor, ARMOR_COLOR], [shield, max_shield, Color("7fd8ff")]]:
		var full: float = gauge[1]
		if full <= 0.0:
			continue
		draw_polyline(_arc_points(ring, up, ARC_SPAN, ARC_STEPS), Color(0, 0, 0, 0.7), 2.0, false)
		var frac: float = clampf(gauge[0] / full, 0.0, 1.0)
		if frac > 0.0:
			# Centred on the same start edge, so a part-full gauge grows from
			# the left rather than from the middle.
			var span: float = ARC_SPAN * frac
			var mid: float = up - ARC_SPAN / 2.0 + span / 2.0
			draw_polyline(_arc_points(ring, mid, span, maxi(2, int(ARC_STEPS * frac))), gauge[2], 2.0, false)
		ring += 2.2

## A construction site that cannot pay says so on the map, not just in the
## selection panel: a pulsing amber tag above the scaffold.
func _draw_stall_notice() -> void:
	var f := ThemeDB.fallback_font
	var t := "INSUFFICIENT FUNDS"
	var size := 11
	var w: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(-w / 2.0, -radius - 16.0)
	var a: float = 0.55 + 0.45 * sin(Game.now() * 6.0)
	draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
	draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.72, 0.35, a))
