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
	_status = StatusOverlay.new()
	_status.host = self
	# top_level: the overlay keeps its own transform instead of inheriting the
	# hull's, which is what makes the gauges immune to the ship turning.
	_status.top_level = true
	_status.z_index = 50
	add_child(_status)

func is_alive() -> bool:
	return not _dead and is_inside_tree()

func is_enemy_of(other_owner: int) -> bool:
	return owner_id != 0 and other_owner != 0 and not (Game.instance.are_allies(owner_id, other_owner) if Game.instance else owner_id == other_owner)

## `profile` (Defs.damage_profile): "vs" multiplies damage against a layer,
## "pierce" skips layers (1 = shields, 2 = shields and armor). Damage works
## through the layers in order; what a layer can't absorb carries on to the
## next at base value.
## The last enemy player to hit this (credited with the kill).
var _killer := 0
var _shield_fx: Effect = null   # this entity's live shield-hit flash
var _siege_frac := 0.0   # leftover thousandths for the starbase_damage tally

func take_damage(amount: float, _from: SpaceEntity = null, profile: Dictionary = {}) -> void:
	if _dead:
		return
	_last_hit_time = Game.now()
	if Game.instance and is_instance_valid(_from):
		Game.instance.note_attack(owner_id, _from.owner_id)
		if Game.instance.is_hostile(owner_id, _from.owner_id):
			_killer = _from.owner_id
	# Screens (Defense) soak a slice of everything before the layers see it.
	# Each screen tech cuts its own share off (all three: -52%).
	if Game.instance:
		amount *= maxf(0.1, 2.0 - Game.instance.mod(owner_id, "damage_taken"))
	# Under a Radiation Sail Array's bubble, the pooled solar shield takes
	# the hit first - for an array too, so its own shield drains with the pool.
	if Game.instance:
		amount = Abilities.sail_absorb(self, amount, _from, profile)
		if amount <= 0.0:
			return
	# Training tally: damage dealt by an enemy, in thousandths of this
	# target's whole toughness (hull + armor + shield) - "starbase_damage"
	# for starbases, "damage_dealt" for ships and constructs.
	if Game.instance and is_instance_valid(_from) and Game.instance.is_hostile(owner_id, _from.owner_id) and max_hp > 0.0:
		_siege_frac += 1000.0 * minf(amount, hp + armor + shield) / (max_hp + max_armor + max_shield)
		Game.instance.stats.count(_from.owner_id, "starbase_damage" if self is Starbase else "damage_dealt", int(_siege_frac))
		# ...and the same, as damage taken, for this side.
		Game.instance.stats.count(owner_id, "starbase_hurt" if self is Starbase else "damage_hurt", int(_siege_frac))
		_siege_frac -= floorf(_siege_frac)
	var vs: Dictionary = profile.get("vs", {})
	var pierce: int = profile.get("pierce", 0)
	var rest := amount
	var absorbed := 0.0
	var g := Game.instance
	var src_ok := g != null and is_instance_valid(_from)
	# Overcharged Coils: a share of the shot passes through the shields.
	var past_shield := 0.0
	# An array's own shield is the pooled solar shield, already handled.
	if self is Ship and self.def.has("solar_sail"):
		pierce = maxi(pierce, 1)
	if pierce < 1 and shield > 0.0 and src_ok:
		past_shield = rest * clampf(g.mod(_from.owner_id, "shield_pierce") - 1.0, 0.0, 1.0)
		rest -= past_shield
	if pierce < 1:
		var m: float = vs.get("shield", 1.0)
		absorbed = minf(shield, rest * m)
		shield -= absorbed
		rest -= absorbed / m
	rest += past_shield
	# Burst Cyclers: a share of the shot goes past the plating to the hull.
	var through := 0.0
	if pierce < 2 and rest > 0.0 and armor > 0.0 and src_ok:
		through = rest * clampf(g.mod(_from.owner_id, "armor_pierce") - 1.0, 0.0, 1.0)
		rest -= through
	if pierce < 2 and rest > 0.0:
		var m: float = vs.get("armor", 1.0)
		var plated := minf(armor, rest * m)
		armor -= plated
		rest -= plated / m
	rest += through
	if rest > 0.0:
		# Rupture Charges: what reaches the hull hits harder.
		if src_ok:
			rest *= g.mod(_from.owner_id, "hull_damage")
		hp -= rest * vs.get("hull", 1.0)
	if absorbed > 0.0 and not (self is Ship and self.def.has("solar_sail")):
		_shield_fx = Game.instance.spawn_shield_hit(global_position, radius, (_from.global_position if is_instance_valid(_from) else global_position + Vector2.RIGHT), call("shield_color") if has_method("shield_color") else Color("7fd8ff"), _shield_fx if is_instance_valid(_shield_fx) else null)
	queue_redraw()
	if hp <= 0.0:
		_die()

## What this cost to build (all resources), for the value tallies.
func _worth() -> float:
	var c: Dictionary = {}
	if self is Ship:
		c = self.def.get("cost", {})
	elif self is Starbase:
		c = Defs.STARBASE["cost"]
	elif self is MiningStation:
		c = Defs.MINING_STATION["cost"]
	elif self is WeaponsDepot:
		c = Defs.WEAPONS_DEPOT["cost"]
	var t := 0.0
	for k in c:
		t += float(c[k])
	return t

func _die() -> void:
	_dead = true
	# Credit the kill to whoever hit it last (enemy ship or starbase kills).
	if Game.instance and _killer != 0:
		Game.instance.stats.count(_killer, "starbase_kills" if self is Starbase else ("ship_kills" if self is Ship else "construct_kills"))
	# What it cost, for value-weighted kill and loss tallies.
	if Game.instance and owner_id != 0:
		var worth := int(_worth())
		Game.instance.stats.count(owner_id, "lost_value", worth)
		if _killer != 0:
			Game.instance.stats.count(_killer, "kill_value", worth)
	Game.instance.spawn_explosion(global_position, radius / 10.0)
	died.emit(self)
	queue_free()

func _regen_shields(delta: float) -> void:
	# Spice nebula: low-level radiation, like a star's outer zone. Taking it
	# counts as a hit, so shields don't regenerate while it lasts.
	if Game.instance.in_nebula(global_position):
		var m: float = Abilities.radiation_mult(self)
		if m > 0.0:
			take_damage(SpiceNebula.RADIATION_DPS * delta * m, null)
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

## The selection ring and the three curved layer gauges. They are NOT drawn by
## this node: a canvas item's drawing is cached in its own local space, so
## anything drawn here turns with the hull between redraws however the points
## were computed, and a ship only redraws when it is hit or regenerates. They
## are drawn instead by a child with top_level set, which keeps its own
## transform: it is moved to the hull's position every frame and its rotation
## is never touched, so the gauges are always level.
const ARC_SPAN := deg_to_rad(95.0)
const ARC_STEPS := 20

var _status: StatusOverlay

## A level overlay above one entity.
class StatusOverlay extends Node2D:
	var host: SpaceEntity

	func _process(_delta: float) -> void:
		if not is_instance_valid(host):
			return
		# Position only. Rotation stays 0 for the life of the node, which is
		# the whole point of drawing here rather than on the hull.
		global_position = host.global_position
		visible = host.visible

	func _draw() -> void:
		if is_instance_valid(host):
			host.draw_status(self)

## An arc of `radius` centred on the entity, as points in the overlay's own
## (unrotated) space, ready for draw_polyline.
func _arc_points(arc_radius: float, mid: float, span: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var from := mid - span / 2.0
	for i in steps + 1:
		var a: float = from + span * float(i) / float(steps)
		# Left on fractional coordinates and drawn antialiased: snapping these
		# to whole pixels made the curves step and look ragged.
		pts.append(Vector2(cos(a), sin(a)) * arc_radius)
	return pts

## Draws the gauges into `on` (the overlay), not into this node.
func draw_status(on: CanvasItem) -> void:
	var damaged := hp < max_hp or (max_shield > 0.0 and shield < max_shield) or armor < max_armor
	if not selected and not damaged:
		return
	var r := radius + 3.0
	if selected:
		# A ring rather than corner brackets, so the marker reads the same
		# whatever the hull under it is doing.
		var col := Defs.team_color(owner_id)
		# Faint, so a large selection doesn't bury the ships in rings.
		on.draw_polyline(_arc_points(r + 1.0, 0.0, TAU, 40), Color(col, 0.4), 1.0, true)
	# The gauges are for damage, not for decoration: an untouched ship shows
	# nothing above it, selected or not.
	if not damaged:
		return
	# They arc over the top of the hull (world "up" is -Y), filling left to
	# right as the layer fills.
	var up := -PI / 2.0
	var ring := r + 1.5
	for gauge in [[hp, max_hp, Color("58e07a")], [armor, max_armor, ARMOR_COLOR], [shield, max_shield, Color("7fd8ff")]]:
		var full: float = gauge[1]
		if full <= 0.0:
			continue
		on.draw_polyline(_arc_points(ring, up, ARC_SPAN, ARC_STEPS), Color(0, 0, 0, 0.7), 2.0, true)
		var frac: float = clampf(gauge[0] / full, 0.0, 1.0)
		if frac > 0.0:
			# Centred on the same start edge, so a part-full gauge grows from
			# the left rather than from the middle.
			var span: float = ARC_SPAN * frac
			var mid: float = up - ARC_SPAN / 2.0 + span / 2.0
			on.draw_polyline(_arc_points(ring, mid, span, maxi(2, int(ARC_STEPS * frac))), gauge[2], 2.0, true)
		ring += 2.2

## Everything that moves a layer, or the selection, calls queue_redraw() on
## the entity; that is forwarded to the overlay that actually draws them.
func _draw() -> void:
	if _status != null:
		_status.queue_redraw()

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
