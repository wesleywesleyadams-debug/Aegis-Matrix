class_name ConstructGuns
extends RefCounted
## A construct's laser battery (Starbase, Frontier Outpost):
## def["guns"] standard ship laser guns (Defs.LASER_DAMAGE every
## Defs.LASER_COOLDOWN s), spread evenly around the hull. Each gun keeps its
## own cooldown and target and fires from its own mount, exactly like a
## warship's turret: same Game.fire / Projectile path (Target Prediction,
## Overkill Awareness), same modifiers — damage (+ structure_damage),
## fire_rate, range (+ structure_range) and the energy-starved slowdown
## (ship_speed_factor).

const SCAN_INTERVAL := 0.25
## Mounts sit this far out, as a fraction of the construct's radius.
const MOUNT_FRAC := 0.8

var host: SpaceEntity
var mounts: Array[Vector2] = []
var _cd: Array[float] = []
var _target: Array = []
var _near: Array = []
var _scan := 0.0

func _init(h: SpaceEntity, guns: int) -> void:
	host = h
	for i in guns:
		# Evenly round the hull, the first one up-right so a lone gun isn't
		# hidden under the station's centre art.
		mounts.append(Vector2.from_angle(-PI / 4.0 + TAU * float(i) / float(guns)) * h.radius * MOUNT_FRAC)
		_cd.append(randf() * Defs.LASER_COOLDOWN)
		_target.append(null)

## The guns' reach from their own mounts.
static func reach(pid: int, def: Dictionary) -> float:
	var g := Game.instance
	return float(def["range"]) * g.mod(pid, "range") * g.mod(pid, "structure_range")

func tick(def: Dictionary, delta: float) -> void:
	var g := Game.instance
	var pid := host.owner_id
	var power := g.ship_speed_factor(pid)
	var ready := false
	for i in _cd.size():
		_cd[i] -= delta * power
		if _cd[i] <= 0.0:
			ready = true
	if not ready:
		return
	var rng := reach(pid, def)
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		_near = g.enemies_near(host, rng + host.radius * MOUNT_FRAC, mounts.size() + 4, Vector2.INF, true)
	var taken := {}
	for i in mounts.size():
		var cur = _target[i]
		if is_instance_valid(cur) and cur.is_alive():
			taken[cur] = true
	for i in mounts.size():
		if _cd[i] > 0.0:
			continue
		var mp := host.global_position + mounts[i]
		var tgt: Node2D = null
		var cur = _target[i]
		if is_instance_valid(cur) and cur.is_alive() and mp.distance_to(cur.global_position) <= rng + cur.radius \
				and not g.is_doomed(pid, cur):
			tgt = cur
		else:
			# Nearest not-doomed enemy in reach, one no other gun is on if
			# possible; double up (or pile onto a doomed one) only when
			# nothing else is in reach.
			var any_live: Node2D = null
			var double_up: Node2D = null
			for e in _near:
				if not is_instance_valid(e) or not e.is_alive() or mp.distance_to(e.global_position) > rng + e.radius:
					continue
				if any_live == null:
					any_live = e
				if g.is_doomed(pid, e):
					continue
				if not taken.has(e):
					tgt = e
					break
				if double_up == null:
					double_up = e
			if tgt == null:
				tgt = double_up if double_up != null else any_live
		_target[i] = tgt
		if tgt == null:
			continue
		taken[tgt] = true
		g.fire(host, tgt, def["weapon"], Defs.LASER_DAMAGE * g.mod(pid, "structure_damage"), 0.0, mp)
		_cd[i] = Defs.LASER_COOLDOWN / g.mod(pid, "fire_rate") * randf_range(0.9, 1.1)
