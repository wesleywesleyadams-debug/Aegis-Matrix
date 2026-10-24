class_name TechScenes
## Pictures of things for the technologies: a domed city for Citadel
## Protocols, three hull sections for Modular Frames, a drill biting a rock
## for Deep-Core Drills. Each is a small pixel-art scene on a starfield,
## painted into TechIcons' tile, mixing drawn objects with the game's own
## sprites so a tech looks like the thing it gives you.
##
## paint() returns false for a tech with no scene, and TechIcons falls back
## to its symbol for it.

const S := TechIcons.SIZE
const C := Vector2(32, 32)
## Scenes are laid out on a 64-unit grid and drawn at the icon's real size.
const K := TechIcons.K

static func paint(id: String, img: Image) -> bool:
	if not has_method_scene(id):
		return false

	call_scene(id, img)
	return true

static func has_method_scene(id: String) -> bool:
	return SCENES.has(id)

## id -> painter. Written as a lookup so a missing scene is just a missing key.
const SCENES := [
	"garrison_guns", "orbital_yards", "modular_frames", "depots", "reinforced_docks", "forward_bases",
	"outposts", "rapid_assembly", "citadel_protocols", "warp_gates", "shipyard_networks", "orbital_elevators",
	"phase_shields", "crystal_prisms", "aegis_matrix", "composite_plating", "reactive_armor", "neutronium_armor",
	"reinforced_frames", "living_metals", "adaptive_hulls", "glance_plates", "graviton_shunts", "iron_umbrella",
	"ion_cannons", "particle_lances", "capital_batteries", "targeting_arrays", "beam_focusing", "starfire_batteries",
	"autoloaders", "heavy_mounts", "scatter_arrays", "overcharged_coils", "burst_cyclers", "dark_matter",
	"solar_collectors", "plasma_reactors", "hullbreaker_rounds",
	"target_prediction", "gyro_stabilizers", "overkill_awareness",
	"hydroponics", "colony_pods", "rationing", "habitat_modules", "gene_clinics", "arcologies",
	"orbital_farms", "planetary_shields", "terraforming", "deep_vaults", "gene_forges", "planetary_citadels",
	"deep_drills", "bulk_holds", "cutting_lasers", "resonance_drills", "gas_skimming", "ion_thrusters",
	"fusion_drives", "jump_drives", "convoy_protocols", "mass_drivers", "logistics_command", "spice_navigation",
	"vectored_thrusters", "strafing_thrusters", "reverse_thrusters",
	"mod_proton_torpedoes", "mod_kinetic_repeaters", "mod_arc_emitters", "mod_flak_cannons", "mod_cluster_bombs",
	"mod_homing_missiles", "mod_ion_lance", "mod_rail_cannons", "mod_point_defense_lattice",
	"mod_interceptor_drones", "mod_tractor_beams", "mod_missile_barrage",
]

static func call_scene(id: String, img: Image) -> void:
	match id:
		# ---------------------------------------------------------- warships
		# ---------------------------------------------------------- mods
		# The class's hull small in a corner, its new weapon doing its thing.
		"mod_proton_torpedoes":
			# C: a torpedo in cutaway: steel casing open at the front, the proton
			# core inside a hot round glow.
			var dir := Vector2(1, -0.45).normalized()
			var nose := Vector2(54, 20)
			_torpedo(img, nose, dir, 42.0, 6.0)
			var core := nose - dir * 14.0
			_disc(img, core, 5.4, STEEL[0])
			_disc(img, core, 4.6, Color("1a0a04"))
			_glow(img, core, 5.6)
		"mod_kinetic_repeaters":
			# R1: a corvette at 45 degrees lit by its own muzzle bloom, a stream of
			# brass slugs receding up the gun's axis (smaller and dimmer with distance).
			_kin_scene(img, Vector2(17.5, 44.5), 26.0, [13.0, 22.0, 30.0, 37.0, 43.0], 2.5, 1.4, 4.6)
		"mod_arc_emitters":
			# G: our corvette (violet muzzle-lit) arcs into a close enemy corvette,
			# then the bolt chains on to three more, each further, smaller, dimmer
			# and hit by a thinner bolt.
			_arc_chain(img, [Vector2(42, 32), Vector2(33, 13), Vector2(48, 9), Vector2(55, 26)], [20.0, 13.0, 10.0, 7.5], [1.2, 0.85, 0.65, 0.5])
		"mod_flak_cannons":
			# D3: the destroyer's two boom turrets each tracer a flak shell onto its own
			# smoke puff (a near big one and a far small one); shrapnel streaks fly out
			# of the puffs and spark on the corvettes caught in them.
			_flak_scene(img, [[Vector2(31, 21), 8.0], [Vector2(51, 31), 4.5]], [[Vector2(44, 9), 12.0, 1.0], [Vector2(55, 19), 8.0, 0.8], [Vector2(58, 41), 5.5, 0.62]])
		"mod_cluster_bombs":
			_sprite(img, "ship_destroyer", Vector2(14, 48), 22.0)
			for k in 6:
				var a := -1.2 + k * 0.28
				var q := Vector2(22, 40) + Vector2.from_angle(a) * (16.0 + (k % 2) * 8.0)
				_disc(img, q, 2.2, Color("c8a04a"))
				_disc(img, q, 0.9, Color("fff0c0"))
		"mod_homing_missiles":
			_sprite(img, "ship_destroyer", Vector2(12, 50), 20.0)
			for k in 3:
				var c := Vector2(30 + k * 6, 44 - k * 4)
				_arc(img, c, 16.0, -2.2, -1.0, 1.4, Color("ff6a4a", 0.8))
			_ring(img, Vector2(48, 16), 6.0, 1.5, Color("ff6a4a"))
			_disc(img, Vector2(48, 16), 1.5, Color("ff6a4a"))
		"mod_ion_lance":
			_sprite(img, "ship_cruiser", Vector2(14, 48), 22.0)
			_beam(img, Vector2(22, 40), Vector2(56, 10), Color("7fd8ff"), 3.5)
			_disc(img, Vector2(56, 10), 4.0, Color("dff6ff"))
		"mod_rail_cannons":
			_sprite(img, "ship_cruiser", Vector2(12, 50), 20.0)
			_line(img, Vector2(20, 44), Vector2(60, 6), 1.2, Color("e8eefc"))
			for k in 4:
				_ring(img, Vector2(20, 44).lerp(Vector2(60, 6), 0.2 + k * 0.2), 2.5, 1.0, Color("7fa8ff", 0.7))
		"mod_point_defense_lattice":
			_sprite(img, "ship_cruiser", Vector2(32, 40), 26.0)
			for q in [Vector2(14, 14), Vector2(32, 10), Vector2(50, 14)]:
				_hex(img, q, 5.0, 1.0, Color("7fd8ff", 0.8))
				_line(img, q + Vector2(-3, -3), q + Vector2(3, 3), 1.2, Color("ff6a4a"))
				_line(img, q + Vector2(-3, 3), q + Vector2(3, -3), 1.2, Color("ff6a4a"))
		"mod_interceptor_drones":
			_sprite(img, "ship_carrier", C, 26.0)
			_ring(img, C, 22.0, 1.0, Color("7fd8ff", 0.35))
			for k in 4:
				var q := C + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 22.0
				_poly(img, [q + Vector2(-3, 3), q + Vector2(0, -4), q + Vector2(3, 3)], Color("c8d2ea"))
		"mod_tractor_beams":
			_sprite(img, "ship_carrier", Vector2(16, 44), 24.0)
			_poly(img, [Vector2(24, 38), Vector2(52, 10), Vector2(58, 18)], Color("9fffb0", 0.25))
			_line(img, Vector2(24, 38), Vector2(52, 10), 1.0, Color("9fffb0"))
			_line(img, Vector2(24, 38), Vector2(58, 18), 1.0, Color("9fffb0"))
			_sprite(img, "ship_corvette", Vector2(54, 14), 12.0)
		"mod_missile_barrage":
			_sprite(img, "ship_carrier", Vector2(14, 48), 22.0)
			for k in 7:
				var q := Vector2(26 + k * 4, 36 - k * 4)
				_line(img, q, q + Vector2(5, -2), 1.5, Color("ff6a4a"))
				_disc(img, q, 1.0, Color("ffd84a"))
		# ---------------------------------------------------------- constructs
		"garrison_guns":
			_sprite(img, "starbase", C + Vector2(-4, 4), 34.0)
			for a in [-0.5, 0.2, 0.9]:
				_beam(img, C + Vector2(-4, 4) + Vector2.from_angle(a) * 14.0, C + Vector2(-4, 4) + Vector2.from_angle(a) * 30.0, Color("ffd84a"), 2.0)
		"orbital_yards":
			_sprite(img, "starbase", Vector2(22, 34), 30.0)
			_scaffold(img, Vector2(38, 18), Vector2(58, 34))
			_sprite(img, "ship_corvette", Vector2(48, 26), 16.0)
		"modular_frames":
			for k in 3:
				_wing(img, Vector2(10 + k * 16, 16 + k * 4), 12.0, 32.0 - k * 4.0, Color("8a95b8").lerp(Color("c8d2ea"), k * 0.3))
		"depots":
			_sprite(img, "ship_depot_plazer", C, 40.0)
		"reinforced_docks":
			_sprite(img, "starbase", C, 30.0)
			for a in [0.0, PI / 2.0, PI, PI * 1.5]:
				_arc(img, C, 21.0, a - 0.5, a + 0.5, 4.0, Color("9aa6c4"))
		"forward_bases":
			_sprite(img, "starbase", Vector2(16, 44), 20.0)
			_dashes(img, Vector2(22, 38), Vector2(44, 20), Color("ffd84a"))
			_sprite(img, "starbase", Vector2(46, 18), 22.0)
		"outposts":
			# A lone fort on the edge of the map, its laser reaching out.
			_sprite(img, "ship_frontier_outpost", Vector2(22, 40), 30.0)
			_beam(img, Vector2(28, 34), Vector2(54, 12), Color("ff6a4a"), 2.0)
			_burst(img, Vector2(54, 12), 5.0, Color("ffd84a"))
		"rapid_assembly":
			_sprite(img, "ship_mining_station", C + Vector2(0, 4), 34.0)
			# The top half is still only scaffold.
			_box(img, Vector2(10, 8), Vector2(54, 30), Color(0.02, 0.03, 0.08, 0.85))
			_scaffold(img, Vector2(14, 10), Vector2(50, 30))
		"citadel_protocols":
			_ellipse(img, Vector2(32, 48), Vector2(24, 6), Color("5a6488"))
			for k in 6:
				var hgt: float = [14, 24, 32, 28, 20, 12][k]
				_tower(img, 14 + k * 6, 46, 5, hgt, Color("7f8bb0"))
			_arc(img, Vector2(32, 46), 26.0, PI, TAU, 1.5, Color("7fd8ff", 0.7))
		"warp_gates":
			# The gate, and a ship streaking away from it at warp.
			_sprite(img, "ship_warp_gate", Vector2(18, 44), 30.0)
			for k in 3:
				_line(img, Vector2(26 + k * 2, 34 - k * 3), Vector2(46 + k * 2, 18 - k * 3), 1.0, Color("7fd8ff", 0.5 + k * 0.2))
			_sprite(img, "ship_corvette", Vector2(52, 12), 14.0)
		"shipyard_networks":
			var pts := [Vector2(14, 16), Vector2(50, 22), Vector2(28, 48)]
			for i in 3:
				_line(img, pts[i], pts[(i + 1) % 3], 1.5, Color("ffd84a", 0.8))
			for q in pts:
				_sprite(img, "starbase", q, 16.0)
		"orbital_elevators":
			_planet(img, Vector2(32, 60), 22.0, Color("3d8fc8"))
			_line(img, Vector2(32, 40), Vector2(32, 12), 1.5, Color("c8d2ea"))
			_sprite(img, "ship_mining_station", Vector2(32, 12), 16.0)
		# ---------------------------------------------------------- defense
		"phase_shields":
			# C: a ship in a bubble that is phasing in: the right half solid and
			# lit by a hit, the left half still resolving as cyan scanlines.
			_sprite(img, "ship_destroyer", C, 28.0)
			for k in 15:
				var y := 12.0 + k * 3.0
				var dy := y - C.y
				if absf(dy) >= 21.0:
					continue
				var hx := sqrt(21.0 * 21.0 - dy * dy)
				_line(img, Vector2(C.x - hx, y), Vector2(C.x - hx + 3.0, y), 1.2, SH[3])
				_line(img, Vector2(C.x - hx + 3.0, y), Vector2(C.x - 2.0, y), 1.0, Color(SH[2], 0.35))
			_band_arc(img, C, 21.0, -PI * 0.5, PI * 0.5, 3.6, SH)
			var hit := C + Vector2.from_angle(-0.6) * 22.0
			for k in 3:
				_arc(img, hit, 4.0 + k * 3.5, 1.7, 4.0, 1.0, Color(SH[3], 0.9 - k * 0.25))
			_impact(img, hit, Vector2(60, 4))
		"crystal_prisms":
			# The big prism with two small satellite crystals orbiting it; the
			# split rays pass between them.
			var c := Vector2(26, 34)
			var entry := c + Vector2(-5, -3)
			_impact(img, entry, Vector2(2, 12))
			for k in 5:
				_ray(img, c + Vector2(6, 1), c + Vector2(6, 1) + Vector2.from_angle(-0.5 + k * 0.25) * 28.0, 1.5, SPECTRUM[k])
			_crystal_rich(img, c, 15.0, 7.0, -1.25)
			_crystal(img, Vector2(46, 12), 5.0, 2.4, -1.0)
			_crystal(img, Vector2(14, 54), 4.5, 2.2, -1.5)
			_arc(img, c, 26.0, -1.45, -1.0, 1.0, Color(SH[3], 0.5))
			_arc(img, c, 26.0, 1.75, 2.15, 1.0, Color(SH[3], 0.5))
			_disc(img, entry, 1.8, Color.WHITE)
		"aegis_matrix":
			# The matrix itself: a glowing geodesic globe taking a hit.
			_disc(img, C, 24.0, Color("0d2a44", 0.9))
			var imp := C + Vector2.from_angle(-2.3) * 24.0
			_honeycomb(img, C, 24.0, 4.4, imp, 0.45)
			_line(img, imp + Vector2(-12, -9), imp + Vector2(-2, -1.5), 2.0, Color("ff4a3a"))
			_burst(img, imp, 6.0, Color("fff2b0"))
			_disc(img, imp, 2.2, Color.WHITE)
		"composite_plating":
			for k in 3:
				_plate(img, Vector2(14 + k * 6, 14 + k * 6), Vector2(34, 26), Color("8a5a5a").lightened(k * 0.15))
		"reactive_armor":
			_plate(img, Vector2(12, 18), Vector2(40, 30), Color("9a6060"))
			_burst(img, Vector2(20, 22), 6.0, Color("ffd84a"))
			_burst(img, Vector2(42, 40), 5.0, Color("ff8a3a"))
		"neutronium_armor":
			_plate(img, Vector2(12, 14), Vector2(40, 36), Color("2c2a3a"))
			_line(img, Vector2(18, 18), Vector2(26, 18), 1.5, Color("ffffff", 0.7))
			_frame(img, Vector2(12, 14), Vector2(52, 50), 2.0, Color("ff4a4a", 0.7))
		"reinforced_frames":
			# The X-braced frame as a chunky 3D block; a glowing green energy
			# brace snapping into place across it.
			var d := Vector2(7, -6)
			var a := Vector2(10, 18)
			var b := Vector2(46, 54)
			var cs := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
			# back frame and depth edges
			for k in 4:
				_girder(img, cs[k] + d, cs[(k + 1) % 4] + d, 3.0, [STEEL[0], STEEL[0], STEEL[1], STEEL[2], STEEL[3]])
			for k in 3:
				_girder(img, cs[k], cs[k] + d, 3.4, STEEL)
			# the steel diagonal already fixed
			_girder(img, cs[1], cs[3], 4.0, STEEL)
			# the green energy brace locking in
			_line(img, a, b, 7.0, Color(HU[2], 0.35))
			_girder(img, a, b, 4.0, HU)
			_line(img, a, b, 1.0, HU[4])
			for k in 4:
				_girder(img, cs[k], cs[(k + 1) % 4], 4.2, STEEL)
			for q in cs:
				_joint(img, q, 2.8, STEEL)
			var m := a.lerp(b, 0.5)
			_hex(img, m, 5.5, 2.0, HU[0])
			_disc(img, m, 4.5, HU[2])
			_disc(img, m, 2.2, HU[4])
			for k in 4:
				var dd := Vector2.from_angle(k * PI / 2 + PI / 4)
				_line(img, m + dd * 7.0, m + dd * 10.0, 1.0, HU[3])
		"living_metals":
			# Living chrome: the droplet wraps tendrils round a hull fragment and
			# draws it in; a faint cyan pulse at its heart says it is alive.
			var c := Vector2(24, 38)
			var frag := [Vector2(40, 10), Vector2(54, 14), Vector2(56, 26), Vector2(44, 30), Vector2(38, 22)]
			_poly(img, frag, Color("3a4150"))
			_line(img, frag[0], frag[1], 1.2, Color("8a93a3"))
			_line(img, Vector2(42, 18), Vector2(52, 20), 1.0, Color("58e07a"))
			_chrome_ribbon(img, [c, Vector2(34, 30), Vector2(40, 26), Vector2(48, 30), Vector2(56, 22), Vector2(52, 12)], 3.6, 1.0)
			_chrome_ribbon(img, [c, Vector2(28, 22), Vector2(36, 12), Vector2(46, 8)], 3.0, 0.8, 1.3)
			_chrome_ribbon(img, [c, Vector2(38, 46), Vector2(50, 44), Vector2(56, 36)], 2.4, 0.6, 1.2)
			_chrome_ribbon(img, [c, Vector2(12, 48), Vector2(8, 40)], 2.0, 0.6, 1.0)
			_chrome_blob(img, c, 9.0, [[0.6, 3, 1.2], [0.3, 4, 0.2]])
			_disc(img, c + Vector2(1.5, 1.5), 2.6, Color("7fe8ff", 0.55))
			_disc(img, c + Vector2(1.5, 1.5), 1.2, Color("c8f8ff"))
		"adaptive_hulls":
			# Hull scales: small and flat far from the hit, swollen and bright at it.
			var imp := Vector2(40, 22)
			for j in 7:
				for i in 7:
					var p := Vector2(10 + i * 7.5 + (3.75 if j % 2 == 1 else 0.0), 12 + j * 7.0)
					if p.x > 58:
						continue
					var near := clampf(1.0 - p.distance_to(imp) / 26.0, 0.0, 1.0)
					var r := lerpf(2.2, 4.6, near)
					var col := Color("4a5a50").lerp(Color("58e07a"), near)
					_disc(img, p, r + 0.8, col.darkened(0.5))
					_disc(img, p, r, col)
					_disc(img, p + Vector2(-r * 0.35, -r * 0.35), r * 0.35, col.lightened(0.5))
			_line(img, Vector2(60, 4), imp + Vector2(2, -2), 2.0, Color("ff4a3a"))
			_burst(img, imp, 4.0, Color("fff2b0"))
		"glance_plates":
			# A wedge of two angled plates (a prow), shots glancing off both faces.
			var tip := Vector2(20, 32)
			var dv := Color("c9b6ff")
			_poly(img, [tip, Vector2(50, 10), Vector2(56, 16), tip + Vector2(6, 0)], dv.darkened(0.3))
			_poly(img, [tip, Vector2(50, 54), Vector2(56, 48), tip + Vector2(6, 0)], dv.darkened(0.55))
			_line(img, tip, Vector2(50, 10), 1.6, dv.lightened(0.4))
			_line(img, tip, Vector2(50, 54), 1.2, dv)
			for sh in [[Vector2(4, 12), Vector2(32, 23), Vector2(40, 4)], [Vector2(4, 50), Vector2(32, 41), Vector2(42, 60)]]:
				_line(img, sh[0], sh[1], 1.8, Color("ff4a3a"))
				_dashes(img, sh[1], sh[2], Color("ff4a3a", 0.8))
				_burst(img, sh[1], 4.0, Color("fff2b0"))
		"graviton_shunts":
			# Space-grid dimpled by the shunt around a small ship; shots slide off.
			var gc := Vector2(36, 32)
			var dv := Color("c9b6ff")
			for k in range(0, 6):
				var ph := []
				var pv := []
				for st in range(0, 33):
					var qh := Vector2(5 + st * 1.7, 8 + k * 10.0)
					var qv := Vector2(8 + k * 10.0, 5 + st * 1.7)
					ph.append(qh + (qh - gc).normalized() * 6.0 * exp(-(qh - gc).length() / 9.0))
					pv.append(qv + (qv - gc).normalized() * 6.0 * exp(-(qv - gc).length() / 9.0))
				for pts in [ph, pv]:
					for st in pts.size() - 1:
						_line(img, pts[st], pts[st + 1], 0.8, Color(dv, 0.45))
			_ring(img, gc, 8.0, 1.4, dv)
			_sprite(img, "ship_destroyer", gc, 14.0)
			_bent(img, Vector2(6, 28), Vector2(1.5, 0.0), gc, 28.0, Color("ff4a3a"))
			_bent(img, Vector2(6, 10), Vector2(1.4, 0.6), gc, 28.0, Color("ff4a3a"))
		"iron_umbrella":
			# A1: bolts end in clean flashes on the canopy, violet ripples spreading
			# from each hit.
			_umbrella_base(img)
			for x in [14.0, 24.0, 36.0, 47.0]:
				var p := Vector2(x, _dome_y(x) - 0.5)
				var from := p + Vector2(-4, -12)
				_line(img, from, p, 2.2, Color("6a0e08"))
				_line(img, from, p, 1.2, SHOT)
				for k in 2:
					_arc(img, p, 3.0 + k * 2.5, PI + 0.3, TAU - 0.3, 1.0, Color(DF[3], 0.9 - k * 0.35))
				_burst(img, p, 3.0, FLASH)
				_disc(img, p, 1.2, Color.WHITE)
		"ion_cannons":
			# B: the muzzle charging: coil rings glowing, an ion sphere swelling at
			# the mouth, sparks being pulled in.
			_cannon(img, Vector2(4, 60), Vector2(30, 34), 9.0, 3)
			var c := Vector2(38, 26)
			_ion_orb(img, c, 9.0)
			for k in 6:
				var d := Vector2.from_angle(-2.4 + k * 0.62)
				_zap(img, c + d * 10.0, c + d * 18.0, 20 + k, 1.6)
			for k in 5:
				var d := Vector2.from_angle(-1.8 + k * 0.7)
				_put(img, int(c.x + d.x * 22.0), int(c.y + d.y * 22.0), IO[3])
		"particle_lances":
			# A2: a chunk of layered hull armour; the lance burns through and
			# molten metal drips from the wound.
			var lay := [STEEL[1], Color("6e6250"), Color("7a1616"), STEEL[1]]
			var h := Vector2(28, 34)
			_lance(img, h, Vector2(62, 10), 3.0)
			_thick_plate(img, Vector2(14, 18), 28.0, 32.0, 5.0, STEEL, lay)
			_spray(img, Vector2(48, 22), -0.6)
			for k in 3:
				var x := 25.0 + k * 3.0
				var len := 4.0 + (k % 2) * 5.0
				_line(img, Vector2(x, 37), Vector2(x, 37 + len), 1.6, PL[2])
				_disc(img, Vector2(x, 38 + len), 1.2, PL[3])
			_molten_hole(img, h, 3.0)
			_lance(img, Vector2(0, 56), h, 4.4)
		"capital_batteries":
			# A domed twin-barrel capital turret firing heavy bolts straight
			# down each barrel's line toward a far-off reticle.
			var dir := Vector2(1, -0.62).normalized()
			var base := Vector2(14, 50)
			var tips := _turret(img, base, dir, 22.0)
			for i in tips.size():
				var t: Vector2 = tips[i]
				_burst(img, t, 2.6, Color(QCYAN, 0.8))
				for k in 2:
					var c0: Vector2 = t + dir * (7.0 + k * 11.0 + i * 4.0)
					_line(img, c0 - dir * 3.5, c0 + dir * 3.5, 3.4, Color(QCYAN, 0.4))
					_line(img, c0 - dir * 3.0, c0 + dir * 3.0, 1.8, QCYAN)
					_line(img, c0 - dir * 1.5, c0 + dir * 2.5, 1.0, QL[4])
			_reticle(img, Vector2(12, 12), 4.5, QCYAN)
		"targeting_arrays":
			# B: three lenses in a row, each a little smaller, stretching the beam
			# further; faint quantum ghosts flicker beside each lens.
			_line(img, Vector2(2, 34), Vector2(62, 34), 5.0, Color(QL[2], 0.3))
			_line(img, Vector2(2, 34), Vector2(62, 34), 1.0, QL[4])
			for k in 3:
				var c := Vector2(14 + k * 15, 34)
				var h := 15.0 - k * 3.5
				_ellipse(img, c + Vector2(3, -2), Vector2(3.0, h), Color(QCYAN, 0.25))
				_lens(img, c, h, 3.4)
			_disc(img, Vector2(60, 34), 2.4, QCYAN)
			_disc(img, Vector2(60, 34), 1.0, QL[4])
		"beam_focusing":
			# C: an iris of steel blades closes around the beam, squeezing it into
			# a bright pinpoint stream.
			var c := Vector2(26, 34)
			_disc(img, c, 19.0, STEEL[0])
			_disc(img, c, 17.5, STEEL[1])
			for k in 7:
				var a := k * TAU / 7.0
				var p0 := c + Vector2.from_angle(a) * 17.0
				var p1 := c + Vector2.from_angle(a + 0.9) * 17.0
				var p2 := c + Vector2.from_angle(a + 1.6) * 3.4
				_poly(img, [p0, p1, p2], STEEL[0])
				_poly(img, [p0.lerp(c, 0.06), p1.lerp(c, 0.06), p2.lerp(p0, 0.08)], STEEL[2] if k % 2 == 0 else STEEL[3])
				_line(img, p0.lerp(c, 0.08), p2, 1.0, STEEL[4] if k < 3 else STEEL[1])
			_ring(img, c, 18.0, 1.4, STEEL[3])
			_disc(img, c, 3.2, Color(QCYAN, 0.6))
			_disc(img, c, 1.8, QL[4])
			_line(img, c, Vector2(62, 10), 3.4, Color(QCYAN, 0.35))
			_line(img, c, Vector2(62, 10), 1.4, QL[4])
		"starfire_batteries":
			# A star held in a containment ring - the battery - venting a jet of
			# starfire out of its muzzle.
			var c := Vector2(24, 36)
			_line(img, c, Vector2(62, 10), 9.0, Color(SF[1], 0.5))
			_line(img, c, Vector2(62, 10), 5.0, SF[2])
			_line(img, c, Vector2(62, 10), 2.4, SF[4])
			_sun(img, c, 9.0)
			_ring(img, c, 17.0, 4.0, STEEL[0])
			_ring(img, c, 17.0, 2.6, STEEL[2])
			_arc(img, c, 18.0, PI * 0.9, PI * 1.5, 1.0, STEEL[4])
			for k in 4:
				var a := PI * 0.25 + k * PI / 2.0
				_joint(img, c + Vector2.from_angle(a) * 17.0, 2.6, STEEL)
		"target_prediction":
			# Z: a chunky targeting scope - a beveled steel unit with a glowing
			# screen: grid, a blip, its predicted arc and the lead marker.
			var a := Vector2(6, 10)
			var b := Vector2(54, 46)
			_box(img, a - Vector2(1, 1), b + Vector2(1, 1), STEEL[0])
			_box(img, a, b, STEEL[2])
			_box(img, a, Vector2(b.x, a.y + 2), STEEL[3])
			_line(img, a + Vector2(1, 0.5), Vector2(b.x - 1, a.y + 0.5), 1.0, STEEL[4])
			_box(img, Vector2(a.x, b.y - 2), b, STEEL[1])
			var sa := a + Vector2(4, 4)
			var sb := b - Vector2(4, 5)
			_box(img, sa - Vector2(1, 1), sb + Vector2(1, 1), STEEL[0])
			_box(img, sa, sb, Color("04121c"))
			for x in range(int(sa.x) + 6, int(sb.x), 7):
				_line(img, Vector2(x, sa.y), Vector2(x, sb.y), 1.0, Color(QCYAN, 0.08))
			for y in range(int(sa.y) + 6, int(sb.y), 7):
				_line(img, Vector2(sa.x, y), Vector2(sb.x, y), 1.0, Color(QCYAN, 0.08))
			var pts := []
			for k in 11:
				var t := k / 10.0
				pts.append(Vector2(lerpf(sa.x + 4, sb.x - 6, t), sb.y - 6.0 - sin(t * PI * 0.8) * 16.0))
			for k in 4:
				_disc(img, pts[k], 0.9, Color(QL[3], 0.4 + k * 0.12))
			_disc(img, pts[4], 2.2, QL[3])
			for k in range(5, 10, 1):
				if k % 2 == 1:
					_line(img, pts[k], pts[k + 1], 1.2, QCYAN)
			_lead_pip(img, pts[10], 1.8)
		"gyro_stabilizers":
			# A: a gyroscope - a spinning rotor held in two crossed gimbal rings,
			# cyan spin arcs sweeping its rim.
			var c := Vector2(30, 28)
			_gimbal(img, c, 22.0, 8.0, -0.5, PI, TAU, 2.6)
			_gimbal(img, c, 7.0, 21.0, 0.2, PI * 0.5, PI * 1.5, 2.6)
			_rotor(img, c, 13.0, 5.0)
			_gimbal(img, c, 22.0, 8.0, -0.5, 0.0, PI, 2.6)
			_gimbal(img, c, 7.0, 21.0, 0.2, -PI * 0.5, PI * 0.5, 2.6)
			for p in [c + Vector2(0, -21).rotated(0.2), c + Vector2(0, 21).rotated(0.2)]:
				_joint(img, p, 2.0, STEEL)
		"overkill_awareness":
			# V1: the iris in the middle; the doomed target in the left of the eye,
			# the locked target in the right.
			var c := Vector2(30, 30)
			_eye(img, c, 9.0, 3.4)
			_disc(img, c + Vector2(-4, -4), 1.3, Color.WHITE)
			var t1 := Vector2(16.5, 29)
			var t2 := Vector2(44, 30)
			_blip(img, t1, 2.0, true)
			_doomed(img, t1, 2.8)
			_cblip(img, t2, 2.0)
			_brackets(img, t2, 4.2, QCYAN)
		"autoloaders":
			# B: a spinning drum magazine seen end-on, rounds in every chamber, one
			# kicked out of the loading gate.
			var c := Vector2(28, 34)
			_disc(img, c, 19.0, STEEL[0])
			_disc(img, c, 17.6, STEEL[1])
			_disc(img, c + Vector2(-1.5, -1.5), 15.0, STEEL[2])
			for k in 6:
				var q := c + Vector2.from_angle(k * TAU / 6.0 + 0.3) * 10.0
				_disc(img, q, 4.2, STEEL[0])
				_disc(img, q, 3.4, BR[1])
				_disc(img, q + Vector2(-0.6, -0.6), 2.4, BR[2])
				_disc(img, q, 1.0, BR[0])
				_put(img, int(q.x - 1.5), int(q.y - 1.5), BR[4])
			_disc(img, c, 3.0, STEEL[0])
			_disc(img, c, 2.0, STEEL[3])
			for k in 2:
				_arc(img, c, 22.0 + k * 3.0, -0.9 - k * 0.2, 0.4 - k * 0.2, 1.4, Color(BR[3], 0.8 - k * 0.3))
			_round(img, Vector2(54, 12), Vector2(0.5, -1).normalized(), 9.0, 1.8)
		"heavy_mounts":
			# V1: a battleship turret in profile - sloped gun house on a ring base,
			# twin barrels out of its front face, one firing.
			var dir := Vector2(1, -0.42).normalized()
			_twin_fire(img, [Vector2(26, 30), Vector2(26, 36)], dir, 24.0, 0)
			var house := [Vector2(6, 42), Vector2(8, 28), Vector2(16, 22), Vector2(28, 24), Vector2(32, 34), Vector2(30, 42)]
			var out := []
			for p in house:
				out.append(Vector2(18, 33) + (p - Vector2(18, 33)) * 1.08)
			_poly(img, out, STEEL[0])
			_poly(img, house, STEEL[2])
			_poly(img, [Vector2(8, 28), Vector2(16, 22), Vector2(28, 24), Vector2(26, 27), Vector2(16, 25.5), Vector2(10, 30)], STEEL[3])
			_line(img, Vector2(9, 27.5), Vector2(16, 22.5), 1.0, STEEL[4])
			_poly(img, [Vector2(28, 24), Vector2(32, 34), Vector2(30, 42), Vector2(27, 42), Vector2(29, 34), Vector2(26, 26)], STEEL[1])
			_box(img, Vector2(4, 42), Vector2(34, 48), STEEL[0])
			_box(img, Vector2(5, 43), Vector2(33, 47), STEEL[1])
			_line(img, Vector2(5, 43.5), Vector2(33, 43.5), 1.0, STEEL[3])
			for x in [10.0, 18.0, 26.0]:
				_joint(img, Vector2(x, 45), 1.1, STEEL)
			_joint(img, Vector2(14, 34), 1.4, STEEL)
		"scatter_arrays":
			# B: five barrels fanned out from one hub, each with its own stream of
			# fire - a wall of shot.
			var hub := Vector2(14, 46)
			for k in 5:
				var d := Vector2.from_angle(-1.45 + k * 0.3)
				_girder(img, hub + d * 4.0, hub + d * 18.0, 3.0, STEEL)
				_line(img, hub + d * 17.0 + d.orthogonal() * 2.4, hub + d * 17.0 - d.orthogonal() * 2.4, 2.2, STEEL[0])
				_burst(img, hub + d * 20.0, 2.4, BR[4])
				for m in 2:
					var tp := hub + d * (28.0 + m * 9.0)
					if tp.x > 40 and tp.y > 48:
						continue
					_tracer(img, tp, d, 4.0)
			_disc(img, hub, 7.0, STEEL[0])
			_disc(img, hub + Vector2(-1, -1), 5.4, STEEL[2])
			_joint(img, hub, 2.4, STEEL)
		"overcharged_coils":
			# B: the coil itself: copper windings round a core, glowing past their
			# limit, arcs leaping off, a bolt leaving its tip.
			var a := Vector2(10, 50)
			var b := Vector2(38, 22)
			var d := (b - a).normalized()
			var n := d.orthogonal()
			_girder(img, a, b, 5.0, STEEL)
			for k in 7:
				var p := a.lerp(b, 0.12 + k * 0.12)
				var hot := k / 6.0
				var col: Color = COPPER[2].lerp(OC[3], hot)
				_line(img, p + n * 6.0 - d * 1.0, p - n * 6.0 + d * 1.0, 3.2, COPPER[0])
				_line(img, p + n * 5.4 - d * 1.0, p - n * 5.4 + d * 1.0, 2.0, col)
				_line(img, p + n * 5.0 - d * 1.4, p + n * 1.0 - d * 1.2, 1.0, COPPER[4])
			_oc_zap(img, a.lerp(b, 0.7) + n * 6.0, a.lerp(b, 0.75) + n * 13.0, 21)
			_oc_zap(img, a.lerp(b, 0.85) - n * 6.0, a.lerp(b, 0.95) - n * 12.0, 22)
			_disc(img, b + d * 2.0, 3.4, Color(OC[2], 0.5))
			_oc_bolt(img, b + d * 2.0, b + d * 26.0, 2.6)
		"burst_cyclers":
			# Three barrels reaching in from the frame's edge, each with a cycle
			# lamp lit in turn; the bottom one fires, its flash flowing into the
			# bolt, while the burst's earlier bolts fly on ahead.
			for k in 3:
				var y := 21.0 + k * 11.0
				_cannon(img, Vector2(-2, y), Vector2(24, y), 4.0, 0)
				# Muzzle brake: a flared, vented tip.
				_box(img, Vector2(22, y - 4.2), Vector2(30, y + 4.2), STEEL[0])
				_box(img, Vector2(23, y - 3.4), Vector2(29, y + 3.4), STEEL[2])
				_box(img, Vector2(23, y - 3.4), Vector2(29, y - 2.0), STEEL[4])
				_box(img, Vector2(23, y + 2.0), Vector2(29, y + 3.4), STEEL[1])
				for vx in [24.5, 27.0]:
					_box(img, Vector2(vx, y - 2.0), Vector2(vx + 1.0, y + 2.0), STEEL[0])
				# Cycle lamp, set into the barrel.
				var q := Vector2(12, y)
				_disc(img, q, 2.0, STEEL[0])
				_disc(img, q, 1.3, OC[1].lerp(OC[4], 1.0 - k * 0.45))
				if k == 2:
					# Firing: a soft round flash at the muzzle that tapers into
					# the bolt.
					var m := Vector2(31, y)
					_disc(img, m, 5.0, Color(OC[2], 0.18))
					_disc(img, m, 3.6, Color(OC[2], 0.35))
					_disc(img, m, 2.4, Color(OC[3], 0.8))
					_disc(img, m, 1.3, OC[4])
					_poly(img, [m + Vector2(0, -2.4), m + Vector2(12, -1.0), m + Vector2(12, 1.0), m + Vector2(0, 2.4)], Color(OC[2], 0.6))
					_oc_bolt(img, m + Vector2(3, 0), m + Vector2(13, 0), 2.0)
					_disc(img, m + Vector2(13, 0), 1.5, OC[4])
				else:
					var x := 60.0 - k * 9.0
					_oc_bolt(img, Vector2(x - 9, y), Vector2(x, y), 2.0)
					_disc(img, Vector2(x, y), 1.5, OC[4])
		"hullbreaker_rounds":
			# A charge clamped to a green hull plate goes off; the plate tears
			# open outward in curled petals around a soft fireball.
			_hull_panel(img, Vector2(6, 8), Vector2(58, 48))
			var c := Vector2(30, 28)
			_disc(img, c, 11.0, HU[0])
			for k in 6:
				var a := k * TAU / 6.0 + 0.3
				var d := Vector2.from_angle(a)
				var tip := c + d * 17.0
				var p0 := c + d.rotated(0.45) * 10.0
				var p1 := c + d.rotated(-0.45) * 10.0
				_poly(img, [p0, tip + d.orthogonal() * 1.5, tip - d.orthogonal() * 1.5, p1], HU[0])
				_poly(img, [p0.lerp(c, 0.08), tip, p1.lerp(c, 0.08)], HU[3] if k % 2 == 0 else HU[4].lerp(HU[3], 0.5))
				_line(img, p1.lerp(c, 0.08), tip, 1.0, HU[1])
			_disc(img, c, 9.0, Color("1a0a04"))
			_glow(img, c, 11.0)
		"solar_collectors":
			_disc(img, Vector2(14, 14), 7.0, Color("ffd84a"))
			for k in 3:
				var o := Vector2(16 + k * 12, 28 + k * 8)
				_poly(img, [o, o + Vector2(14, -4), o + Vector2(18, 8), o + Vector2(4, 12)], Color("3d6fc8"))
				_line(img, o + Vector2(2, 6), o + Vector2(16, 2), 1.0, Color("b0d8ff"))
		"plasma_reactors":
			_box(img, Vector2(20, 14), Vector2(44, 52), Color("6a7596"))
			_ellipse(img, Vector2(32, 33), Vector2(8, 14), Color("ff6ad8"))
			_ellipse(img, Vector2(32, 33), Vector2(4, 9), Color("ffd0f4"))
			for k in 4:
				_line(img, Vector2(16, 18 + k * 10), Vector2(48, 18 + k * 10), 1.5, Color("9aa6c4"))
		"dark_matter":
			_disc(img, C, 14.0, Color("1a0f2a"))
			_ring(img, C, 18.0, 2.0, Color("b06cff"))
			_arc(img, C, 24.0, -2.0, 0.5, 1.5, Color("b06cff", 0.6))
		# ---------------------------------------------------------- worlds
		"hydroponics":
			_box(img, Vector2(12, 40), Vector2(52, 50), Color("5a6488"))
			_arc(img, Vector2(32, 40), 18.0, PI, TAU, 2.0, Color("b0f0ff", 0.8))
			for k in 4:
				_line(img, Vector2(20 + k * 8, 40), Vector2(20 + k * 8, 30 - (k % 2) * 4), 2.0, Color("6fe07a"))
		"colony_pods":
			_planet(img, Vector2(32, 60), 24.0, Color("3d8fc8"))
			_ellipse(img, Vector2(32, 20), Vector2(6, 8), Color("c8d2ea"))
			_line(img, Vector2(32, 28), Vector2(32, 34), 2.0, Color("ff8a3a"))
		"rationing":
			for k in 3:
				_box(img, Vector2(12 + k * 14, 34), Vector2(24 + k * 14, 48), Color("8a6a3a"))
			_ellipse(img, Vector2(32, 26), Vector2(12, 4), Color("6fe07a"))
		"habitat_modules":
			_planet(img, Vector2(32, 70), 34.0, Color("3d8fc8"))
			for k in 3:
				_sprite(img, "bld_habitat", Vector2(16 + k * 16, 34), 14.0)
		"gene_clinics":
			_helix(img, Color("6fe07a"))
		"arcologies":
			_planet(img, Vector2(32, 72), 34.0, Color("6a8a5a"))
			_tower(img, 28, 40, 8, 32, Color("9aa6c4"))
			_tower(img, 20, 40, 5, 18, Color("7f8bb0"))
			_tower(img, 38, 40, 5, 22, Color("7f8bb0"))
		"orbital_farms":
			_planet(img, C, 12.0, Color("3d8fc8"))
			_ring(img, C, 22.0, 3.0, Color("6fe07a"))
		"planetary_shields":
			_planet(img, Vector2(32, 36), 14.0, Color("3d8fc8"))
			_ring(img, Vector2(32, 36), 20.0, 2.5, Color("7fd8ff", 0.85))
		"terraforming":
			_planet(img, C, 20.0, Color("b08a5a"))
			_half(img, C, 20.0, Color("3d8fc8"))
		"deep_vaults":
			for k in 4:
				_box(img, Vector2(10, 14 + k * 11), Vector2(54, 22 + k * 11), Color("5a6488").darkened(k * 0.12))
				for w in 5:
					_put(img, 14 + w * 9, 18 + k * 11, Color("ffd84a"))
		"gene_forges":
			_disc(img, C, 22.0, Color("ff8a3a", 0.35))
			_helix(img, Color("ffd84a"))
		"planetary_citadels":
			_planet(img, Vector2(32, 64), 30.0, Color("3d8fc8"))
			_sprite(img, "bld_battery", Vector2(32, 30), 18.0)
			_arc(img, Vector2(32, 44), 24.0, PI, TAU, 2.0, Color("7fd8ff", 0.8))
		# ---------------------------------------------------------- logistics
		"deep_drills":
			_sprite(img, "asteroid_big_0", Vector2(42, 40), 30.0)
			_poly(img, [Vector2(8, 10), Vector2(16, 10), Vector2(34, 34), Vector2(28, 38)], Color("c8d2ea"))
		"bulk_holds":
			_sprite(img, "ship_miner", Vector2(20, 26), 22.0)
			for k in 3:
				_box(img, Vector2(26 + k * 10, 40), Vector2(34 + k * 10, 50), Color("8a6a3a"))
		"cutting_lasers":
			_sprite(img, "asteroid_big_1", Vector2(42, 36), 30.0)
			_beam(img, Vector2(8, 14), Vector2(36, 32), Color("ff6a4a"), 2.0)
			_burst(img, Vector2(36, 32), 4.0, Color("ffd84a"))
		"resonance_drills":
			_sprite(img, "asteroid_big_0", C, 22.0)
			for r in [16.0, 21.0, 26.0]:
				_ring(img, C, r, 1.2, Color("3fd6b0", 0.7))
		"gas_skimming":
			_planet(img, Vector2(32, 58), 26.0, Color("9a5e7e"))
			_sprite(img, "ship_skimmer", Vector2(32, 18), 22.0)
		"ion_thrusters":
			_poly(img, [Vector2(14, 22), Vector2(30, 26), Vector2(30, 38), Vector2(14, 42)], Color("8a95b8"))
			_poly(img, [Vector2(30, 28), Vector2(56, 32), Vector2(30, 36)], Color("7fd8ff"))
		# Maneuvers: the hull faces right; the white arrow is the motion,
		# the flame points the other way.
		"vectored_thrusters":
			_sprite(img, "ship_destroyer", C + Vector2(0, 6), 28.0)
			_arc(img, C, 22.0, -2.6, -0.3, 2.5, Color("f2f2f2"))
			var e := C + Vector2.from_angle(-0.3) * 22.0
			var tg := Vector2.from_angle(-0.3 + PI * 0.5)
			_poly(img, [e + tg * 7.0, e - tg.orthogonal() * 5.0, e + tg.orthogonal() * 5.0], Color("f2f2f2"))
		"strafing_thrusters":
			_sprite(img, "ship_destroyer", Vector2(30, 38), 28.0)
			_arrow(img, Vector2(30, 28), Vector2(30, 4), Color("f2f2f2"))
			_flame(img, Vector2(30, 48), Vector2(0, 1))
		"reverse_thrusters":
			_sprite(img, "ship_destroyer", Vector2(34, 32), 28.0)
			_arrow(img, Vector2(19, 32), Vector2(2, 32), Color("f2f2f2"))
			_flame(img, Vector2(49, 32), Vector2(1, 0))
		"fusion_drives":
			_sprite(img, "ship_cruiser", Vector2(38, 32), 28.0)
			_poly(img, [Vector2(24, 28), Vector2(4, 32), Vector2(24, 36)], Color("ff8a3a"))
		"jump_drives":
			_ring(img, Vector2(22, 32), 14.0, 3.0, Color("b06cff"))
			_sprite(img, "ship_destroyer", Vector2(38, 32), 22.0)
		"convoy_protocols":
			for k in 3:
				_sprite(img, "ship_miner", Vector2(14 + k * 18, 22 + k * 10), 14.0)
		"mass_drivers":
			_box(img, Vector2(6, 40), Vector2(40, 46), Color("8a95b8"))
			_sprite(img, "asteroid_0", Vector2(50, 22), 12.0)
			_dashes(img, Vector2(40, 40), Vector2(48, 26), Color("3fd6b0"))
		"logistics_command":
			_sprite(img, "ship_mining_station", C, 22.0)
			for q in [Vector2(10, 12), Vector2(54, 14), Vector2(12, 52), Vector2(52, 50)]:
				_line(img, C, q, 1.0, Color("3fd6b0", 0.7))
				_sprite(img, "ship_miner", q, 10.0)
		"spice_navigation":
			for k in 4:
				_disc(img, Vector2(14 + k * 12, 20 + (k % 2) * 20), 12.0, Color("ff9a2e", 0.18))
			_sprite(img, "ship_corvette", C, 22.0)

# ---------------------------------------------------------------- scenery

static func _space(img: Image, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for y in range(5, S - 5):
		for x in range(5, S - 5):
			img.set_pixel(x, y, Color(0.03, 0.035, 0.08))
	for k in 18:
		var x := rng.randi_range(6, S - 7)
		var y := rng.randi_range(6, S - 7)
		img.set_pixel(x, y, Color(1, 1, 1, rng.randf_range(0.25, 0.8)))

## A warship's real hull art drawn at exactly one art pixel per icon pixel
## (no resampling), centred at c: a lit engine at each stern,
## a drop shadow, the hull in `team` colour, and its turret sprites placed
## and sized as Ship.gd does in game.
static func _ship_art(img: Image, cls: String, c: Vector2, team: Color) -> void:
	var hull: Image = Defs.tex("ship_" + cls).get_image().duplicate()
	var tm: Image = Defs.tex("ship_" + cls + "_team").get_image().duplicate()
	var tur: Image = Defs.tex("ship_turret").get_image().duplicate()
	for im in [hull, tm, tur]:
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
	var w := hull.get_width()
	var h := hull.get_height()
	var o := Vector2i(int(c.x * K) - w / 2, int(c.y * K) - h / 2)
	# Engine glows: each run of solid pixels in the stern column.
	var sx := 0
	while sx < w and not range(h).any(func(y): return hull.get_pixel(sx, y).a > 0.5):
		sx += 1
	var start := -1
	for y in h + 1:
		var solid: bool = y < h and hull.get_pixel(sx, y).a > 0.5
		if solid and start < 0:
			start = y
		elif not solid and start >= 0:
			var e := Vector2(o.x + sx - 1, o.y + (start + y - 1) / 2.0) / K
			_disc(img, e, 1.8, Color(SF[2], 0.85))
			_disc(img, e, 1.0, SF[4])
			start = -1
	var Z := TechIcons.SIZE
	var put := func(x: int, y: int, col: Color) -> void:
		if x >= 0 and y >= 0 and x < Z and y < Z:
			img.set_pixel(x, y, img.get_pixel(x, y).blend(col))
	for y in h:
		for x in w:
			if hull.get_pixel(x, y).a > 0.5:
				put.call(o.x + x + 2, o.y + y + 2, Color(0, 0, 0, 0.6))
	for y in h:
		for x in w:
			var col := hull.get_pixel(x, y)
			var t := tm.get_pixel(x, y)
			if t.a > 0.0:
				col = team * t.r
				col.a = 1.0
			if col.a > 0.0:
				put.call(o.x + x, o.y + y, col)
	var d: Dictionary = Defs.SHIPS[cls]
	var ts := float(d.get("turret_scale", 1.0))
	var tw := int(round(tur.get_width() * ts))
	var th := int(round(tur.get_height() * ts))
	for m in d.get("turrets", []):
		var cx := o.x + w / 2.0 + (float(m[0]) - 0.5) * w
		var cy := o.y + h / 2.0 + float(m[1]) * h
		for y in th:
			for x in tw:
				var col := tur.get_pixel(int(x / ts), int(y / ts))
				if col.a > 0.0:
					put.call(int(cx - tw / 2.0) + x, int(cy - th / 2.0) + y, col)

static func _sprite(img: Image, tex_name: String, c: Vector2, box: float) -> void:
	c *= K
	box *= K
	var src := TechIcons.source(tex_name)
	if src == null:
		return
	var k: float = box / maxf(src.get_width(), src.get_height())
	var w := maxi(1, int(src.get_width() * k))
	var h := maxi(1, int(src.get_height() * k))
	src.resize(w, h, Image.INTERPOLATE_NEAREST)
	var tim := TechIcons.source(tex_name + "_team")
	if tim:
		tim.resize(w, h, Image.INTERPOLATE_NEAREST)
	var o := Vector2i(int(c.x) - w / 2, int(c.y) - h / 2)
	for y in h:
		for x in w:
			var col: Color = src.get_pixel(x, y)
			if tim != null and tim.get_pixel(x, y).a > 0.0:
				col = Defs.team_color(1) * tim.get_pixel(x, y).r
				col.a = 1.0
			if col.a > 0.0:
				TechIcons._put(img, o.x + x, o.y + y, col)

static func _planet(img: Image, c: Vector2, r: float, base: Color) -> void:
	c *= K
	r *= K
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			var v := (Vector2(x, y) - c) / r
			if v.length() > 1.0:
				continue
			# Lit from the top-left.
			var lit := clampf(0.55 - v.dot(Vector2(0.6, 0.7)) * 0.5, 0.15, 1.0)
			TechIcons._put(img, x, y, base * lit + Color(0, 0, 0, 1) * (1.0 - lit) * 0.0)

static func _half(img: Image, c: Vector2, r: float, col: Color) -> void:
	c *= K
	r *= K
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x) + 1):
			if Vector2(x, y).distance_to(c) <= r:
				TechIcons._put(img, x, y, col * clampf(0.9 - (Vector2(x, y) - c).y / r * 0.3, 0.3, 1.0))

static func _wing(img: Image, at: Vector2, w: float, h: float, col: Color) -> void:
	_poly(img, [at, at + Vector2(w, 4), at + Vector2(w, h - 4), at + Vector2(0, h)], col)
	_line(img, at + Vector2(2, h * 0.33), at + Vector2(w - 1, h * 0.36), 1.0, col.darkened(0.35))
	_line(img, at + Vector2(2, h * 0.66), at + Vector2(w - 1, h * 0.62), 1.0, col.darkened(0.35))
	_line(img, at, at + Vector2(w, 4), 1.0, col.lightened(0.3))

static func _plate(img: Image, at: Vector2, size: Vector2, col: Color) -> void:
	_box(img, at, at + size, col)
	_frame(img, at, at + size, 1.5, col.lightened(0.3))
	for q in [at + Vector2(3, 3), at + Vector2(size.x - 4, 3), at + Vector2(3, size.y - 4), at + size - Vector2(4, 4)]:
		_put(img, int(q.x), int(q.y), col.lightened(0.5))

static func _tower(img: Image, x: int, base_y: int, w: int, h: float, col: Color) -> void:
	_box(img, Vector2(x - w / 2.0, base_y - h), Vector2(x + w / 2.0, base_y), col)
	for k in int(h / 4):
		_put(img, x, int(base_y - 3 - k * 4), Color("ffd84a"))

static func _scaffold(img: Image, a: Vector2, b: Vector2) -> void:
	var col := Color("ffb347", 0.8)
	_frame(img, a, b, 1.0, col)
	for k in range(1, 4):
		var x := a.x + (b.x - a.x) * k / 4.0
		_line(img, Vector2(x, a.y), Vector2(x, b.y), 1.0, col)
	_line(img, a, b, 1.0, col)

static func _barrel(img: Image, a: Vector2, b: Vector2, w: float) -> void:
	_line(img, a, b, w, Color("8a95b8"))
	_line(img, a, b, maxf(w * 0.35, 1.0), Color("c8d2ea"))

static func _shell(img: Image, at: Vector2) -> void:
	_box(img, at + Vector2(-3, -8), at + Vector2(3, 10), Color("c8a04a"))
	_poly(img, [at + Vector2(-3, -8), at + Vector2(0, -14), at + Vector2(3, -8)], Color("c8d2ea"))

static func _dish(img: Image, c: Vector2) -> void:
	_arc(img, c, 12.0, -2.4, -0.2, 3.0, Color("c8d2ea"))
	_line(img, c, c + Vector2(8, -8), 1.5, Color("c8d2ea"))
	_line(img, c, c + Vector2(0, 12), 2.0, Color("8a95b8"))

static func _helix(img: Image, col: Color) -> void:
	for y in range(10, 54):
		var t := float(y) * 0.32
		var x1 := 32.0 + sin(t) * 10.0
		var x2 := 32.0 - sin(t) * 10.0
		_disc(img, Vector2(x1, y), 1.4, col)
		_disc(img, Vector2(x2, y), 1.4, col.darkened(0.3))
		if y % 5 == 0:
			_line(img, Vector2(x1, y), Vector2(x2, y), 1.0, col.darkened(0.45))

static func _beam(img: Image, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_line(img, a, b, w * 2.2, Color(col, col.a * 0.3))
	_line(img, a, b, w, col)

## A motion arrow from `a` to `b`, head at `b`.
static func _arrow(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var d := (b - a).normalized()
	_line(img, a, b - d * 5.0, 2.5, col)
	_poly(img, [b, b - d * 8.0 + d.orthogonal() * 5.0, b - d * 8.0 - d.orthogonal() * 5.0], col)

## A thruster flame from `at` pointing along `dir` (opposite the motion).
static func _flame(img: Image, at: Vector2, dir: Vector2) -> void:
	var n := dir.orthogonal()
	_poly(img, [at + n * 6.0, at + dir * 15.0, at - n * 6.0], Color("ff6a1a"))
	_poly(img, [at + n * 3.0, at + dir * 9.0, at - n * 3.0], Color("ffffff"))

static func _dashes(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := 6
	for k in n:
		if k % 2 == 0:
			_line(img, a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), 1.5, col)

# ---------------------------------------------------------------- primitives
# TechIcons' primitives, taking scene units (a 64 grid) and drawing at K.

## One scene pixel: a K-sized block.
static func _put(img: Image, x: int, y: int, col: Color) -> void:
	for dy in ceili(K):
		for dx in ceili(K):
			TechIcons._put(img, int(x * K) + dx, int(y * K) + dy, col)

static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	TechIcons._disc(img, c * K, r * K, col)

static func _ring(img: Image, c: Vector2, r: float, w: float, col: Color) -> void:
	TechIcons._ring(img, c * K, r * K, w * K, col)

static func _arc(img: Image, c: Vector2, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	TechIcons._arc(img, c * K, r * K, a0, a1, w * K, col)

static func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	TechIcons._line(img, a * K, b * K, w * K, col)

static func _poly(img: Image, pts: Array, col: Color) -> void:
	var out: Array = []
	for q in pts:
		out.append(q * K)
	TechIcons._poly(img, out, col)

static func _box(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	TechIcons._box(img, a * K, b * K, col)

static func _frame(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	TechIcons._frame(img, a * K, b * K, w * K, col)

static func _ellipse(img: Image, c: Vector2, r: Vector2, col: Color) -> void:
	TechIcons._ellipse(img, c * K, r * K, col)

static func _hex(img: Image, c: Vector2, r: float, w: float, col: Color) -> void:
	TechIcons._hex(img, c * K, r * K, w * K, col)

static func _burst(img: Image, c: Vector2, r: float, col: Color) -> void:
	TechIcons._burst(img, c * K, r * K, col)

## Aegis Matrix: hex cells laid on a globe of radius R around c, packed and
## brightened toward the rim; cells near `imp` (a hit) flare white.
static func _honeycomb(img: Image, c: Vector2, R: float, cell: float, imp: Vector2, inner_a: float) -> void:
	var dx := cell * 1.5
	var dy := cell * sqrt(3.0)
	for i in range(-9, 10):
		for j in range(-9, 10):
			var p := Vector2(i * dx, j * dy + (dy * 0.5 if absi(i) % 2 == 1 else 0.0))
			var d := p.length() / R
			if d > 0.98 or (inner_a < 0.2 and d < 0.5):
				continue
			var q := c + p.normalized() * sin(d * PI * 0.5) * R if p.length() > 0.01 else c
			var r := cell * lerpf(1.0, 0.55, d * d)
			var a := lerpf(inner_a, 1.0, pow(d, 2.0))
			var col := Color("7fd8ff").lerp(Color("e8fbff"), pow(d, 3.0))
			if imp != Vector2.ZERO:
				var hit := clampf(1.0 - q.distance_to(imp) / 10.0, 0.0, 1.0)
				a = maxf(a, hit)
				col = col.lerp(Color.WHITE, hit)
			_hex(img, q, r, 0.9, Color(col, a))
	_ring(img, c, R + 0.5, 1.4, Color("e8fbff"))

## Graviton Shunts: a shot's path bent away from `center` (repelled, speed
## kept), drawn until it leaves the tile.
static func _bent(img: Image, start: Vector2, vel: Vector2, center: Vector2, g: float, col: Color) -> void:
	var p := start
	var v := vel
	for k in 80:
		var r := p - center
		v += r.normalized() * g / maxf(r.length_squared(), 40.0)
		v = v.normalized() * vel.length()
		var n := p + v
		_line(img, p, n, 1.6, col)
		p = n
		if p.x < 5 or p.x > 59 or p.y < 5 or p.y > 59:
			break
	_disc(img, p, 1.6, col.lightened(0.4))

# ------------------------------------------------ liquid chrome (Living Metals)
const CHROME := [
	[-1.0, 1.0, Color("15171d")],    # outline
	[-0.78, 0.78, Color("5c6370")],  # gunmetal body
	[-0.45, 0.0, Color("2a2e37")],   # dark reflection
	[0.12, 0.62, Color("b9c1cd")],   # silver band
	[0.66, 0.84, Color("ffffff")],   # edge highlight
]

static func _cr(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)

## A liquid-chrome ribbon through `pts` (64 grid), half-width w0 -> w1.
## Each tone band is one continuous strip of quads (flat colour, so no
## seams), painted whole-curve, darkest/widest first. Round start cap;
## ends in a bead if `drop` > 0.
static func _chrome_ribbon(img: Image, pts: Array, w0: float, w1: float, drop: float = 0.0) -> void:
	var P := [pts[0]] + pts + [pts[-1]]
	var cv := []
	for s in range(1, P.size() - 2):
		for k in 10:
			cv.append(_cr(P[s - 1], P[s], P[s + 1], P[s + 2], k / 10.0))
	cv.append(pts[-1])
	var n := cv.size()
	var nor := []
	var hw := []
	for k in n:
		var tan: Vector2 = (cv[mini(k + 1, n - 1)] - cv[maxi(k - 1, 0)]).normalized()
		nor.append(tan.orthogonal())
		var t := float(k) / (n - 1)
		hw.append(lerpf(w0, w1, smoothstep(0.0, 1.0, t)))
	_bead(img, cv[0], w0, true)
	for band in CHROME:
		if band[0] > 0.6 and w0 < 1.6:
			continue
		for k in n - 1:
			var a: Vector2 = cv[k]
			var b: Vector2 = cv[k + 1]
			var na: Vector2 = nor[k] * hw[k]
			var nb: Vector2 = nor[k + 1] * hw[k + 1]
			_poly(img, [a + na * band[0], b + nb * band[0], b + nb * band[1], a + na * band[1]], band[2])
	if drop > 0.0:
		_bead(img, pts[-1], drop)

## A mercury bead: dark outline, gunmetal body, a dark reflection low-right,
## a silver dome upper-left and a white glint.
static func _bead(img: Image, c: Vector2, r: float, cap := false) -> void:
	_disc(img, c, r, Color("15171d"))
	_disc(img, c, r * 0.8, Color("5c6370"))
	if cap:
		return
	if r >= 3.0:
		_disc(img, c + Vector2(0.18, 0.22) * r, r * 0.45, Color("2a2e37"))
	_disc(img, c + Vector2(-0.2, -0.22) * r, r * 0.5, Color("b9c1cd"))
	_disc(img, c + Vector2(-0.36, -0.36) * r, maxf(r * 0.2, 0.6), Color.WHITE)

## A blobby chrome body: radius wobbles with angle (lobes), stretched along
## `axis` by `stretch`. Flat bands: outline, gunmetal, dark reflection
## low-right, silver upper-left, glint, plus one surface ripple.
static func _chrome_blob(img: Image, c: Vector2, r: float, lobes: Array, axis: Vector2 = Vector2.RIGHT, stretch: float = 1.0) -> void:
	var shape := func(scale: float, off: Vector2) -> Array:
		var out := []
		for k in 96:
			var a := TAU * k / 96.0
			var rr := r
			for l in lobes:
				rr += l[0] * sin(a * l[1] + l[2])
			var v := Vector2.from_angle(a) * rr * scale
			var along := v.dot(axis) * stretch
			var across := v.dot(axis.orthogonal())
			out.append(c + off + axis * along + axis.orthogonal() * across)
		return out
	_poly(img, shape.call(1.0, Vector2.ZERO), Color("15171d"))
	_poly(img, shape.call(0.82, Vector2.ZERO), Color("5c6370"))
	_poly(img, shape.call(0.42, Vector2(0.2, 0.26) * r), Color("2a2e37"))
	_poly(img, shape.call(0.46, Vector2(-0.22, -0.24) * r), Color("b9c1cd"))
	_arc(img, c + Vector2(0.05, 0.1) * r, r * 0.62, 0.3, 1.5, 1.0, Color("8d95a3"))
	_disc(img, c + Vector2(-0.4, -0.4) * r, r * 0.16, Color.WHITE)

# ------------------------------------------------ shared icon pieces
const SHOT := Color("ff4a3a")
const FLASH := Color("fff2b0")
## Shield tones: outline, deep, body, light, highlight.
const SH := [Color("0b2c44"), Color("1f6d9c"), Color("3fa8dc"), Color("7fd8ff"), Color("e8fbff")]

## Crisp banded arc: outline, body, deep inner band, light outer band, highlight line.
static func _band_arc(img: Image, c: Vector2, r: float, a0: float, a1: float, w: float, tones: Array) -> void:
	_arc(img, c, r, a0, a1, w + 1.6, tones[0])
	_arc(img, c, r, a0, a1, w, tones[2])
	_arc(img, c, r - w * 0.28, a0, a1, w * 0.3, tones[1])
	_arc(img, c, r + w * 0.22, a0, a1, w * 0.3, tones[3])
	_arc(img, c, r + w * 0.3, a0 + 0.12, a1 - 0.35, 1.0, tones[4])

## A red bolt from `from` stopped at `at` with a white-yellow flash.
static func _impact(img: Image, at: Vector2, from: Vector2) -> void:
	_line(img, from, at, 2.4, Color("6a0e08"))
	_line(img, from, at, 1.4, SHOT)
	_burst(img, at, 5.0, FLASH)
	_disc(img, at, 1.8, Color.WHITE)

const SPECTRUM := [Color("ff8ac4"), Color("ffd86a"), Color("8cff9e"), Color("6fd4ff"), Color("b89cff")]

## A faceted shield crystal (elongated hex prism) centred at c, long axis
## along `ang`: dark outline, light left facet, mid right facet, a deep
## core sliver, one white highlight edge.
static func _crystal(img: Image, c: Vector2, h: float, w: float, ang: float) -> void:
	var u := Vector2.from_angle(ang)
	var v := u.orthogonal()
	var tip := c + u * h
	var tail := c - u * h
	var l1 := c + u * h * 0.45 - v * w
	var l2 := c - u * h * 0.45 - v * w
	var r1 := c + u * h * 0.45 + v * w
	var r2 := c - u * h * 0.45 + v * w
	var grow := func(pts: Array, d: float) -> Array:
		var out := []
		for p in pts:
			out.append(c + (p - c) * d)
		return out
	_poly(img, grow.call([tip, r1, r2, tail, l2, l1], 1.0 + 1.4 / h), SH[0])
	_poly(img, [tip, l1, l2, tail, c - v * w * 0.1], SH[3])
	_poly(img, [tip, r1, r2, tail, c - v * w * 0.1], SH[2])
	_poly(img, [tip, c + v * w * 0.35, tail, c - v * w * 0.1], SH[1])
	_line(img, l1, l2, 1.0, SH[4])
	_line(img, tip, l1, 1.0, SH[4])

## A tapering light ray: a wedge from width w at a to a point at b, solid
## for the first 60% then a paler tail, a bead at the tip.
static func _ray(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal()
	var m := a.lerp(b, 0.6)
	_poly(img, [a + n * w, m + n * w * 0.6, m - n * w * 0.6, a - n * w], col)
	_poly(img, [m + n * w * 0.6, b, m - n * w * 0.6], Color(col, 0.55))
	_disc(img, b, 1.2, col.lightened(0.5))

## A richer crystal: _crystal plus an extra bevel facet, an inner cyan
## glow and star glints on the tip.
static func _crystal_rich(img: Image, c: Vector2, h: float, w: float, ang: float) -> void:
	_crystal(img, c, h, w, ang)
	var u := Vector2.from_angle(ang)
	var v := u.orthogonal()
	_poly(img, [c + u * h * 0.45 - v * w * 0.55, c - u * h * 0.2 - v * w * 0.55, c - u * h * 0.1 - v * w * 0.15, c + u * h * 0.5 - v * w * 0.15], SH[4])
	_disc(img, c + v * w * 0.15, w * 0.32, Color(SH[3], 0.45))
	var t := c + u * h
	_line(img, t + Vector2(-2.5, 0), t + Vector2(2.5, 0), 1.0, Color.WHITE)
	_line(img, t + Vector2(0, -2.5), t + Vector2(0, 2.5), 1.0, Color.WHITE)

## Hull tones (58e07a): outline, deep, body, light, highlight.
const HU := [Color("082414"), Color("1f7a3c"), Color("3fbf5f"), Color("8ff0a8"), Color("eaffee")]

const STEEL := [Color("101318"), Color("3a414d"), Color("6a7486"), Color("a3adbd"), Color("e8eef8")]

## A structural girder from a to b, w wide: outline, body, light top
## edge, deep lower edge, highlight line.
static func _girder(img: Image, a: Vector2, b: Vector2, w: float, t: Array) -> void:
	var n := (b - a).normalized().orthogonal()
	if n.y > 0:
		n = -n
	_line(img, a, b, w + 1.8, t[0])
	_line(img, a, b, w, t[2])
	_line(img, a + n * w * 0.3, b + n * w * 0.3, w * 0.3, t[3])
	_line(img, a - n * w * 0.32, b - n * w * 0.32, w * 0.28, t[1])
	_line(img, a + n * w * 0.42, b + n * w * 0.42, 1.0, t[4])

## A gusset plate with a bolt at a joint.
static func _joint(img: Image, c: Vector2, r: float, t: Array) -> void:
	_disc(img, c, r + 0.9, t[0])
	_disc(img, c, r, t[1])
	_disc(img, c + Vector2(-0.3, -0.3) * r, r * 0.6, t[2])
	_disc(img, c, r * 0.35, t[0])
	_put(img, int(c.x - r * 0.5), int(c.y - r * 0.5), t[4])

## Deflector tones (c9b6ff): outline, deep, body, light, highlight.
const DF := [Color("1a0f30"), Color("4a3488"), Color("8a72d8"), Color("c9b6ff"), Color("f6f0ff")]

## An umbrella canopy seen from the side: tip at `tip`, rim spanning
## `half` either side at `rim_y`, `n` panels alternating tones, iron ribs,
## scalloped rim and a highlight on the lit panels.
static func _canopy(img: Image, tip: Vector2, half: float, rim_y: float, n: int) -> void:
	# ribs curve out and down from the tip like a dome
	var ribs := []
	for i in n + 1:
		var t := float(i) / n
		var u := 2.0 * t - 1.0
		var end := Vector2(tip.x + half * u, rim_y + 3.0 * u * u)
		var pts := []
		for k in 9:
			var f := k / 8.0
			var q := tip.lerp(end, f)
			q.y -= sin(f * PI) * (rim_y - tip.y) * 0.32 * (1.0 - 0.3 * absf(u))
			pts.append(q)
		ribs.append(pts)
	# silhouette outline
	var outline := []
	for i in n + 1:
		outline.append(ribs[i][8] + Vector2(0, 1.4))
	var left: Array = ribs[0].duplicate()
	var right: Array = ribs[n].duplicate()
	right.reverse()
	_poly(img, left + outline + right, DF[0])
	for i in n:
		var a2: Array = ribs[i]
		var b2: Array = ribs[i + 1].duplicate()
		b2.reverse()
		var col: Color = DF[3] if i < n / 2 and i % 2 == 0 else (DF[2] if i % 2 == 0 else DF[1])
		_poly(img, a2 + b2, col)
		var mid: Vector2 = (ribs[i][8] + ribs[i + 1][8]) * 0.5 + Vector2(0, -1.8)
		_poly(img, [ribs[i][8], mid, ribs[i + 1][8]], DF[0])
	for i in n + 1:
		for k in 8:
			_line(img, ribs[i][k], ribs[i][k + 1], 1.0, STEEL[3] if i <= n / 2 else STEEL[2])
		_disc(img, ribs[i][8], 1.2, STEEL[3])
	for k in 4:
		_line(img, ribs[1][k] + Vector2(0.8, 0.6), ribs[1][k + 1] + Vector2(0.8, 0.6), 1.0, DF[4])
	_disc(img, tip, 1.8, STEEL[3])
	_put(img, int(tip.x - 1), int(tip.y - 1), STEEL[4])

const UT := Vector2(32, 12)

const UH := 27.0

const URIM := 32.0

## Top of the canopy at x (matches _canopy(UT, UH, URIM, n)).
static func _dome_y(x: float) -> float:
	var best := 999.0
	for i in 81:
		var u := 2.0 * i / 80.0 - 1.0
		var end := Vector2(UT.x + UH * u, URIM + 3.0 * u * u)
		for k in 33:
			var f := k / 32.0
			var q := UT.lerp(end, f)
			q.y -= sin(f * PI) * (URIM - UT.y) * 0.32 * (1.0 - 0.3 * absf(u))
			if absf(q.x - x) < 0.6:
				best = minf(best, q.y)
	return best

static func _umbrella_base(img: Image) -> void:
	for q in [Vector2(19, 47), Vector2(39, 50)]:
		_sprite(img, "ship_corvette", q, 17.0)
	_canopy(img, UT, UH, URIM, 8)

## Ion tones: outline, deep, body, light, highlight.
const IO := [Color("06203c"), Color("1660a8"), Color("3fa8ff"), Color("9fe0ff"), Color("ffffff")]

## A jagged electric arc a -> b: soft blue underlay, bright core.
static func _zap(img: Image, a: Vector2, b: Vector2, seed_v: int, amp: float = 2.5) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts := [a]
	var n := (b - a).normalized().orthogonal()
	for k in range(1, 5):
		pts.append(a.lerp(b, k / 5.0) + n * rng.randf_range(-amp, amp))
	pts.append(b)
	for k in pts.size() - 1:
		_line(img, pts[k], pts[k + 1], 2.4, Color(IO[2], 0.45))
	for k in pts.size() - 1:
		_line(img, pts[k], pts[k + 1], 1.0, IO[3] if k % 2 == 0 else IO[4])

## A crackling ion orb: halo, banded body, white core, glint.
static func _ion_orb(img: Image, c: Vector2, r: float) -> void:
	_disc(img, c, r * 1.6, Color(IO[2], 0.25))
	_disc(img, c, r + 0.9, IO[0])
	_disc(img, c, r, IO[2])
	_disc(img, c + Vector2(-0.2, -0.2) * r, r * 0.65, IO[3])
	_disc(img, c, r * 0.35, IO[4])
	_put(img, int(c.x - r * 0.5), int(c.y - r * 0.55), IO[4])

## A beveled steel cannon barrel a -> b with a muzzle collar and coil bands.
static func _cannon(img: Image, a: Vector2, b: Vector2, w: float, coils: int = 3) -> void:
	_girder(img, a, b, w, STEEL)
	var d := (b - a).normalized()
	for k in coils:
		var p := a.lerp(b, 0.35 + k * 0.15)
		_line(img, p - d.orthogonal() * (w * 0.75), p + d.orthogonal() * (w * 0.75), 2.2, IO[0])
		_line(img, p - d.orthogonal() * (w * 0.65), p + d.orthogonal() * (w * 0.65), 1.2, IO[2])
	_line(img, b - d.orthogonal() * (w * 0.9), b + d.orthogonal() * (w * 0.9), 3.0, STEEL[0])
	_line(img, b - d.orthogonal() * (w * 0.8), b + d.orthogonal() * (w * 0.8), 1.8, STEEL[3])

## Particle-lance tones (hot amber): outline, deep, body, light, highlight.
const PL := [Color("2e1204"), Color("a8460e"), Color("ff8a2a"), Color("ffc880"), Color("fff6e0")]

## A lance of particles from a (base, w wide) to a needle point at b:
## halo, outlined body, light inner blade, white core, particles flecking it.
static func _lance(img: Image, a: Vector2, b: Vector2, w: float) -> void:
	var d := (b - a).normalized()
	var n := d.orthogonal()
	_poly(img, [a + n * (w + 2.0), b + d * 2.0, a - n * (w + 2.0)], Color(PL[2], 0.25))
	_poly(img, [a + n * (w + 0.9), b + d * 1.2, a - n * (w + 0.9)], PL[0])
	_poly(img, [a + n * w, b, a - n * w], PL[2])
	_poly(img, [a + n * w * 0.55, b - d * 1.0, a - n * w * 0.2], PL[3])
	_line(img, a, b - d * 2.0, 1.0, PL[4])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 7:
		var t := rng.randf_range(0.05, 0.8)
		var side := rng.randf_range(-1.0, 1.0) * w * (1.0 - t) * 1.8
		_put(img, int(a.lerp(b, t).x + n.x * side), int(a.lerp(b, t).y + n.y * side), PL[4] if k % 2 == 0 else PL[3])

## A thick plate seen slightly in 3/4: front face at `a` (w x h), a lit top
## face and a dark side face `th` deep, rivets with glints on the front.
static func _thick_plate(img: Image, a: Vector2, w: float, h: float, th: float, t: Array, layers: Array = []) -> void:
	var dd := Vector2(th, -th * 0.6)
	var b := a + Vector2(w, h)
	var tr := Vector2(b.x, a.y)
	var bl := Vector2(a.x, b.y)
	_poly(img, [a - Vector2(1, 1), a + dd + Vector2(0, -1), tr + dd + Vector2(1, -1), b + dd + Vector2(1, 1), b + Vector2(1, 1), bl + Vector2(-1, 1)], t[0])
	_poly(img, [a, a + dd, tr + dd, tr], t[3])
	_poly(img, [tr, tr + dd, b + dd, b], t[1])
	if not layers.is_empty():
		for k in layers.size():
			var f0 := float(k) / layers.size()
			var f1 := float(k + 1) / layers.size()
			_poly(img, [tr.lerp(b, f0), (tr + dd).lerp(b + dd, f0), (tr + dd).lerp(b + dd, f1), tr.lerp(b, f1)], layers[k])
	_box(img, a, b, t[2])
	_line(img, a + Vector2(0, 0.5), tr + Vector2(0, 0.5), 1.0, t[4])
	_line(img, a + Vector2(0.5, 0), bl + Vector2(0.5, 0), 1.0, t[3])
	for q in [a + Vector2(3.5, 3.5), tr + Vector2(-3.5, 3.5), bl + Vector2(3.5, -3.5), b - Vector2(3.5, 3.5)]:
		_disc(img, q, 1.5, t[0])
		_disc(img, q, 0.9, t[3])
		_put(img, int(q.x - 0.5), int(q.y - 0.5), t[4])

## A punched hole with a molten rim.
static func _molten_hole(img: Image, c: Vector2, r: float) -> void:
	_disc(img, c, r + 1.6, PL[1])
	_disc(img, c, r + 0.8, PL[2])
	_disc(img, c, r, PL[0])
	_arc(img, c, r + 0.8, PI * 0.9, PI * 1.6, 1.0, PL[4])

static func _spray(img: Image, p: Vector2, dir: float) -> void:
	for k in 6:
		var d := Vector2.from_angle(dir - 0.9 + k * 0.36)
		_line(img, p + d * 3.0, p + d * (6.0 + (k % 3) * 2.0), 1.0, PL[3] if k % 2 == 0 else PL[4])

## Starfire tones (sun-hot): outline, deep, body, light, highlight.
const SF := [Color("3a1402"), Color("c2460a"), Color("ff9a1e"), Color("ffd860"), Color("fffbe8")]

## A miniature sun: corona glow, flame spikes, outlined banded body,
## white-gold core, prominence loops and a glint.
static func _sun(img: Image, c: Vector2, r: float) -> void:
	_disc(img, c, r * 1.35, Color(SF[1], 0.25))
	for k in 12:
		var a := k * TAU / 12.0 + 0.2
		var len := r * (1.85 if k % 2 == 0 else 1.45)
		var d := Vector2.from_angle(a)
		_poly(img, [c + d.rotated(0.2) * r * 0.85, c + d * (len + 0.8), c + d.rotated(-0.2) * r * 0.85], SF[0])
		_poly(img, [c + d.rotated(0.16) * r * 0.85, c + d * len, c + d.rotated(-0.16) * r * 0.85], SF[3] if k % 2 == 0 else SF[2])
	_disc(img, c, r + 0.9, SF[0])
	_disc(img, c, r, SF[1])
	_disc(img, c + Vector2(-0.12, -0.12) * r, r * 0.78, SF[2])
	_disc(img, c + Vector2(-0.2, -0.2) * r, r * 0.52, SF[3])
	_disc(img, c + Vector2(-0.22, -0.22) * r, r * 0.26, SF[4])
	_arc(img, c + Vector2(r * 0.7, -r * 0.6), r * 0.4, -PI * 0.9, PI * 0.1, 1.0, SF[3])

## Quantum tones (violet): outline, deep, body, light, highlight.
const QL := [Color("1a0a34"), Color("5a2aa8"), Color("9a6aff"), Color("d0b8ff"), Color("ffffff")]

const QCYAN := Color("7ff0ff")

## A biconvex lens seen edge-on: outline, glassy body, light crescent,
## highlight streak, steel rim caps top and bottom.
static func _lens(img: Image, c: Vector2, h: float, w: float) -> void:
	_ellipse(img, c, Vector2(w + 1.0, h + 1.0), QL[0])
	_ellipse(img, c, Vector2(w, h), QL[2])
	_ellipse(img, c + Vector2(-w * 0.3, 0), Vector2(w * 0.5, h * 0.85), QL[3])
	_line(img, c + Vector2(-w * 0.35, -h * 0.55), c + Vector2(-w * 0.35, -h * 0.15), 1.0, QL[4])
	for s in [-1.0, 1.0]:
		_box(img, c + Vector2(-w * 0.8, s * h - 1.5), c + Vector2(w * 0.8, s * h + 1.5), STEEL[0])
		_box(img, c + Vector2(-w * 0.6, s * h - 0.8), c + Vector2(w * 0.6, s * h + 0.8), STEEL[3])

## A heavy capital turret: domed armoured base with two long barrels.
static func _turret(img: Image, base: Vector2, dir: Vector2, len: float) -> Array:
	var n := dir.orthogonal()
	var tips := []
	for s in [-1.0, 1.0]:
		var a: Vector2 = base + n * s * 3.2
		_cannon(img, a, a + dir * len, 4.0, 2)
		tips.append(a + dir * (len + 1.0))
	_disc(img, base, 10.0, STEEL[0])
	_disc(img, base, 9.0, STEEL[1])
	_disc(img, base + Vector2(-1.5, -1.5), 7.0, STEEL[2])
	_arc(img, base, 8.0, PI * 1.0, PI * 1.5, 1.4, STEEL[4])
	_disc(img, base, 2.4, QL[2])
	_disc(img, base + Vector2(-0.6, -0.6), 1.0, QL[4])
	return tips

## A far-off target reticle.
static func _reticle(img: Image, c: Vector2, r: float, col: Color) -> void:
	_ring(img, c, r, 1.0, col)
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2.0)
		_line(img, c + d * (r - 1.5), c + d * (r + 2.5), 1.0, col)
	_put(img, int(c.x), int(c.y), col)

## Brass tones: outline, deep, body, light, highlight.
const BR := [Color("2a1a04"), Color("8a5a14"), Color("d8a032"), Color("ffd870"), Color("fff6d0")]

## A cartridge pointing along dir: outlined brass case, rim, copper ogive
## tip, highlight along the lit side.
static func _round(img: Image, p: Vector2, dir: Vector2, len: float, w: float) -> void:
	var n := dir.orthogonal()
	var base := p - dir * len * 0.5
	var neck := p + dir * len * 0.15
	var tip := p + dir * len * 0.5
	_poly(img, [base + n * (w + 0.8) - dir * 0.8, neck + n * (w + 0.8), tip + dir * 0.9, neck - n * (w + 0.8), base - n * (w + 0.8) - dir * 0.8], BR[0])
	_poly(img, [base + n * w, neck + n * w, neck - n * w, base - n * w], BR[2])
	_poly(img, [base + n * w, neck + n * w, neck + n * w * 0.3, base + n * w * 0.3], BR[3])
	_poly(img, [neck + n * w, tip, neck - n * w], Color("b5562a"))
	_poly(img, [neck + n * w, tip, neck + n * w * 0.2], Color("e88a5a"))
	_line(img, base + n * w, base - n * w, 1.2, BR[1])

## A tracer round: short bright streak with a hot head.
static func _tracer(img: Image, p: Vector2, dir: Vector2, len: float) -> void:
	_line(img, p - dir * len, p, 2.2, Color(BR[2], 0.5))
	_line(img, p - dir * len, p, 1.0, BR[3])
	_disc(img, p, 1.0, BR[4])

## Overcharge tones (electric yellow): outline, deep, body, light, highlight.
const OC := [Color("2a2400"), Color("a89a10"), Color("ffe628"), Color("fff59a"), Color("ffffff")]

const COPPER := [Color("2a1206"), Color("7a3a14"), Color("c8642a"), Color("f0a070"), Color("fff0e0")]

## An overcharged bolt a -> b: fat glow, yellow body, white core.
static func _oc_bolt(img: Image, a: Vector2, b: Vector2, w: float) -> void:
	_line(img, a, b, w + 3.0, Color(OC[2], 0.3))
	_line(img, a, b, w + 1.2, OC[1])
	_line(img, a, b, w, OC[2])
	_line(img, a, b, maxf(w * 0.4, 1.0), OC[4])

## A jagged yellow crackle.
static func _oc_zap(img: Image, a: Vector2, b: Vector2, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := (b - a).normalized().orthogonal()
	var prev := a
	for k in range(1, 5):
		var q := a.lerp(b, k / 4.0) + (n * rng.randf_range(-2.0, 2.0) if k < 4 else Vector2.ZERO)
		_line(img, prev, q, 1.0, OC[3] if k % 2 == 0 else OC[4])
		prev = q

static func _twin_fire(img: Image, roots: Array, dir: Vector2, len: float, firing: int) -> void:
	for k in roots.size():
		var r: Vector2 = roots[k]
		var l := len if k == firing else len - 4.0
		_cannon(img, r, r + dir * l, 4.2, 2)
		if k == firing:
			_burst(img, r + dir * (l + 3.0), 3.6, BR[4])
			_tracer(img, r + dir * (l + 12.0), dir, 5.0)

## A soft round layered glow (no star spikes).
static func _glow(img: Image, c: Vector2, r: float) -> void:
	_disc(img, c, r, Color(SF[2], 0.18))
	_disc(img, c, r * 0.75, Color(SF[2], 0.35))
	_disc(img, c, r * 0.5, Color(SF[3], 0.85))
	_disc(img, c, r * 0.28, SF[4])

## A green hull plate (flat panel with bevel and seams).
static func _hull_panel(img: Image, a: Vector2, b: Vector2) -> void:
	_box(img, a - Vector2(1, 1), b + Vector2(1, 1), HU[0])
	_box(img, a, b, HU[1])
	_box(img, a + Vector2(1, 1), b - Vector2(2, 2), HU[2])
	_line(img, a + Vector2(1, 0.5), Vector2(b.x - 2, a.y + 0.5), 1.0, HU[4])
	_line(img, a + Vector2(0.5, 1), Vector2(a.x + 0.5, b.y - 2), 1.0, HU[3])

static func _lead_pip(img: Image, p: Vector2, r: float) -> void:
	_disc(img, p, r * 2.2, Color(QCYAN, 0.18))
	_disc(img, p, r * 1.4, Color(QCYAN, 0.45))
	_disc(img, p, r, QCYAN)
	_disc(img, p, r * 0.45, Color.WHITE)

## Part of a rotated elliptical gimbal ring (angles t0..t1 on the ellipse),
## outlined steel with a lit band. Draw back half before contents, front after.
static func _gimbal(img: Image, c: Vector2, rx: float, ry: float, rot: float, t0: float, t1: float, w: float) -> void:
	var pts := []
	for k in 41:
		var t := lerpf(t0, t1, k / 40.0)
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry).rotated(rot))
	for k in 40:
		_line(img, pts[k], pts[k + 1], w + 1.8, STEEL[0])
	for k in 40:
		_line(img, pts[k], pts[k + 1], w, STEEL[2])
	for k in 40:
		var mid: Vector2 = (pts[k] + pts[k + 1]) * 0.5
		if (mid - c).y < 0:
			_line(img, pts[k] + Vector2(0, -w * 0.25), pts[k + 1] + Vector2(0, -w * 0.25), 1.0, STEEL[4])

## A spinning rotor disc seen at an angle: outlined, banded, hub, cyan spin arcs.
static func _rotor(img: Image, c: Vector2, rx: float, ry: float) -> void:
	_ellipse(img, c + Vector2(0, 1.5), Vector2(rx + 1, ry + 1), STEEL[0])
	_ellipse(img, c + Vector2(0, 1.5), Vector2(rx, ry), STEEL[1])
	_ellipse(img, c, Vector2(rx + 1, ry + 1), STEEL[0])
	_ellipse(img, c, Vector2(rx, ry), STEEL[2])
	_ellipse(img, c + Vector2(-rx * 0.15, -ry * 0.2), Vector2(rx * 0.7, ry * 0.6), STEEL[3])
	_ellipse(img, c, Vector2(rx * 0.25, ry * 0.25), STEEL[0])
	_ellipse(img, c, Vector2(rx * 0.15, ry * 0.15), QCYAN)

## The steel-lidded targeting eye (Target Prediction Y); iris radius `ir`,
## pupil radius `pr` (0 = none). Returns nothing; draw contents after.
static func _eye(img: Image, c: Vector2, ir: float, pr: float) -> void:
	var lid := []
	for k in 25:
		var t := k / 24.0
		lid.append(Vector2(lerpf(4, 56, t), c.y - sin(t * PI) * 16.0))
	for k in 25:
		var t := 1.0 - k / 24.0
		lid.append(Vector2(lerpf(4, 56, t), c.y + sin(t * PI) * 14.0))
	var outl := []
	var inner := []
	for p in lid:
		outl.append(c + (p - c) * 1.08)
		inner.append(c + (p - c) * 0.82)
	_poly(img, outl, STEEL[0])
	_poly(img, lid, STEEL[2])
	_poly(img, inner, Color("061420"))
	_line(img, lid[3] + Vector2(1, 1.5), lid[12] + Vector2(0, 1.5), 1.0, STEEL[4])
	_disc(img, c, ir + 1.0, QL[0])
	_disc(img, c, ir, QL[1])
	_disc(img, c + Vector2(-1, -1), ir * 0.78, QL[2])
	if pr > 0.0:
		_disc(img, c, pr, Color("05060c"))

## A target blip.
static func _blip(img: Image, p: Vector2, r: float, dim: bool) -> void:
	_disc(img, p, r + 0.8, QL[0])
	_disc(img, p, r, QL[1] if dim else QL[2])
	_disc(img, p + Vector2(-r * 0.3, -r * 0.3), r * 0.45, QL[2] if dim else QL[4])

## A bright cyan-white target blip (reads on the violet iris).
static func _cblip(img: Image, p: Vector2, r: float) -> void:
	_disc(img, p, r + 0.8, QL[0])
	_disc(img, p, r, QCYAN)
	_disc(img, p + Vector2(-r * 0.3, -r * 0.3), r * 0.45, Color.WHITE)

## "Already doomed" mark: a small X.
static func _doomed(img: Image, p: Vector2, s: float) -> void:
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		_line(img, p - d * s, p + d * s, 2.2, Color("1a0a10"))
		_line(img, p - d * s, p + d * s, 1.0, Color("ff6a8a"))

## Corner brackets locking a target.
static func _brackets(img: Image, p: Vector2, s: float, col: Color) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var q := p + Vector2(sx, sy) * s
			_line(img, q, q - Vector2(sx * s * 0.5, 0), 1.0, col)
			_line(img, q, q - Vector2(0, sy * s * 0.5), 1.0, col)

## A torpedo pointing along dir, nose at `nose`: bevelled steel body, glowing
## proton warhead window, tail fins, soft round exhaust glow.
static func _torpedo(img: Image, nose: Vector2, dir: Vector2, len: float, w: float, round_nose: bool = false) -> void:
	var n := dir.orthogonal()
	var tail := nose - dir * len
	for s in [-1.0, 1.0]:
		var f0: Vector2 = tail + dir * 5.0 + n * s * w
		var f1: Vector2 = tail - dir * 3.0 + n * s * (w + 5.5)
		var f2: Vector2 = tail + n * s * w
		_poly(img, [f0 + n * s * 0.8, f1 + n * s * 1.0, f2 - dir * 1.0], STEEL[0])
		_poly(img, [f0, f1, f2], STEEL[1] if s > 0 else STEEL[3])
	_girder(img, tail, nose - dir * w * 1.2, w * 2.0, STEEL)
	var cap := nose - dir * w * 1.2
	if round_nose:
		# A plain rounded steel nose.
		_disc(img, cap, w + 0.9, STEEL[0])
		_disc(img, cap, w, STEEL[2])
		_disc(img, cap + (-dir + n).normalized() * w * 0.35, w * 0.45, STEEL[3])
	else:
		_poly(img, [cap + n * (w + 0.9), nose + dir * 1.0, cap - n * (w + 0.9)], STEEL[0])
		_poly(img, [cap + n * w, nose, cap - n * w], PL[2])
		_poly(img, [cap + n * w, nose, cap + n * w * 0.2], PL[3])
	_disc(img, tail - dir * 4.5, w * 1.1, Color(PL[2], 0.3))
	_disc(img, tail - dir * 3.5, w * 0.75, Color(PL[3], 0.8))
	_disc(img, tail - dir * 3.0, w * 0.4, PL[4])
	for k in 2:
		var p := tail.lerp(cap, 0.3 + k * 0.12)
		_line(img, p + n * w, p - n * w, 1.0, STEEL[0])
	var win := tail.lerp(cap, 0.72)
	_disc(img, win, w * 0.7, STEEL[0])
	_disc(img, win, w * 0.52, PL[2])
	_disc(img, win, w * 0.28, PL[4])

## A game sprite rotated to `ang`, lit by a warm source at `light` (scene
## units): warm and brighter near it, cooler and darker away from it.
static func _spr_lit(img: Image, tex_name: String, c: Vector2, box: float, ang: float, light: Vector2, reach: float) -> void:
	var src := TechIcons.source(tex_name)
	if src == null:
		return
	var tim := TechIcons.source(tex_name + "_team")
	var k: float = box * K / maxf(src.get_width(), src.get_height())
	var sc := Vector2(src.get_width(), src.get_height()) * 0.5
	var r := int(box * K * 0.8)
	var cc := c * K
	var warm := Color("ffb060")
	var cool := Color("6a86b8")
	for y in range(-r, r):
		for x in range(-r, r):
			var q := Vector2(x + 0.5, y + 0.5).rotated(-ang) / k + sc
			var sx := int(q.x)
			var sy := int(q.y)
			if sx < 0 or sy < 0 or sx >= src.get_width() or sy >= src.get_height():
				continue
			var col: Color = src.get_pixel(sx, sy)
			if tim != null and tim.get_pixel(sx, sy).a > 0.0:
				col = Defs.team_color(1) * tim.get_pixel(sx, sy).r
				col.a = 1.0
			if col.a <= 0.0:
				continue
			var f := clampf(1.0 - ((cc + Vector2(x, y)) / K).distance_to(light) / reach, 0.0, 1.0)
			f *= f
			var shade := col.lerp(cool, 0.14)
			shade = Color(shade.r * 0.82, shade.g * 0.84, shade.b * 0.9, col.a)
			var lit := Color(minf(col.r * 1.35 + 0.1, 1.0), minf(col.g * 1.25 + 0.05, 1.0), minf(col.b * 1.05, 1.0), col.a).lerp(warm, 0.35)
			TechIcons._put(img, int(cc.x) + x, int(cc.y) + y, shade.lerp(lit, f))

## A soft solid warm bloom (no ring).
static func _kin_bloom(img: Image, p: Vector2, r: float) -> void:
	_disc(img, p, r * 1.2, Color(SF[2], 0.14))
	_disc(img, p, r, Color(SF[2], 0.4))
	_disc(img, p, r * 0.68, Color("ffd878", 0.9))
	_disc(img, p, r * 0.38, Color("fff6d8"))

## Brass slugs at distances `ss` from `nose` along `ang`, sizes falling from
## dia0 to dia1 and dimming with distance, each with a short soft trail.
static func _kin_stream(img: Image, nose: Vector2, ang: float, ss: Array, dia0: float, dia1: float) -> void:
	var d := Vector2.from_angle(ang)
	var n := ss.size()
	for k in n:
		var t := float(k) / float(maxi(1, n - 1))
		var dia := lerpf(dia0, dia1, t)
		var p := nose + d * float(ss[k])
		_line(img, p - d * dia * 2.2, p - d * dia * 1.3, dia * 0.6, Color(BR[2], 0.26 * (1.0 - t * 0.5)))
		_round(img, p, d, dia * 2.7, dia * 0.5)
		if t > 0.04:
			_line(img, p - d * dia * 1.5, p + d * dia * 1.5, dia * 1.3, Color(0, 0, 0, t * 0.55))

## Kinetic Repeaters: the ship at 45 degrees, its muzzle bloom, the slug stream.
static func _kin_scene(img: Image, c: Vector2, box: float, ss: Array, dia0: float, dia1: float, bloom: float) -> void:
	var ang := -PI / 4.0
	var d := Vector2.from_angle(ang)
	var nose := c + d * box * 0.5
	var bl := nose + d * 2.2
	_spr_lit(img, "ship_corvette", c, box, ang, bl, box * 0.75)
	_kin_bloom(img, bl, bloom)
	_kin_stream(img, nose, ang, ss, dia0, dia1)

## A game sprite rotated to `ang`; its edges that face `light` (within `reach`)
## get a bright `rimcol` rim, the rest stays cool and shadowed. `dim` darkens it,
## `redmix` pulls it toward red, `is_enemy` swaps the team band for red.
static func _spr_rim(img: Image, tex_name: String, c: Vector2, box: float, ang: float, light: Vector2, reach: float, rimcol: Color, dim: float, redmix: float, is_enemy: bool) -> void:
	var src := TechIcons.source(tex_name)
	if src == null:
		return
	var tim := TechIcons.source(tex_name + "_team")
	var k: float = box * K / maxf(src.get_width(), src.get_height())
	var sc := Vector2(src.get_width(), src.get_height()) * 0.5
	var r := int(box * K * 0.8)
	var tmp := Image.create(2 * r, 2 * r, false, Image.FORMAT_RGBA8)
	for y in 2 * r:
		for x in 2 * r:
			var q := Vector2(x - r + 0.5, y - r + 0.5).rotated(-ang) / k + sc
			var sx := int(q.x)
			var sy := int(q.y)
			if sx < 0 or sy < 0 or sx >= src.get_width() or sy >= src.get_height():
				continue
			var col: Color = src.get_pixel(sx, sy)
			if tim != null and tim.get_pixel(sx, sy).a > 0.0:
				col = (Color("e03030") if is_enemy else Defs.team_color(1)) * tim.get_pixel(sx, sy).r
				col.a = 1.0
			if col.a > 0.0:
				tmp.set_pixel(x, y, col)
	var cc := c * K
	var cool := Color("6a86b8")
	for y in 2 * r:
		for x in 2 * r:
			var col := tmp.get_pixel(x, y)
			if col.a <= 0.0:
				continue
			var wp := (cc + Vector2(x - r, y - r)) / K
			var f := clampf(1.0 - wp.distance_to(light) / reach, 0.0, 1.0)
			var L := (light - wp).normalized()
			var nb := Vector2(x, y) + L * 2.6
			var nx := int(nb.x)
			var ny := int(nb.y)
			var edge := nx < 0 or ny < 0 or nx >= 2 * r or ny >= 2 * r or tmp.get_pixel(nx, ny).a <= 0.0
			var base := col.lerp(Color("c04040"), redmix).lerp(cool, 0.14)
			base = Color(minf(base.r * 1.25 * dim, 1.0), minf(base.g * 1.25 * dim, 1.0), minf(base.b * 1.35 * dim, 1.0), 1.0)
			if edge and f > 0.04:
				base = base.lerp(rimcol, clampf(0.35 + f * 0.9, 0.0, 1.0) * minf(dim + 0.2, 1.0))
			else:
				base = base.lerp(rimcol * 0.6, f * f * 0.22)
			TechIcons._put(img, int(cc.x) - r + x, int(cc.y) - r + y, Color(base.r, base.g, base.b, 1.0))

## A soft solid layered glow in any colour.
static func _soft_glow(img: Image, c: Vector2, r: float, col: Color, hot: Color = Color.WHITE) -> void:
	_disc(img, c, r, Color(col, 0.16))
	_disc(img, c, r * 0.75, Color(col, 0.34))
	_disc(img, c, r * 0.52, Color(col.lerp(hot, 0.5), 0.85))
	_disc(img, c, r * 0.28, hot)

## A jagged glowing bolt a -> b: soft violet underlay, bright core, `wm` scales its width.
static func _arc_bolt(img: Image, a: Vector2, b: Vector2, seed_v: int, amp: float, under: Color, core: Color, wm: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts := [a]
	var n := (b - a).normalized().orthogonal()
	var segs := maxi(3, int((b - a).length() / 5.0))
	for k in range(1, segs):
		pts.append(a.lerp(b, float(k) / segs) + n * rng.randf_range(-amp, amp))
	pts.append(b)
	for k in pts.size() - 1:
		_line(img, pts[k], pts[k + 1], 3.6 * wm, Color(under, 0.45))
	for k in pts.size() - 1:
		_line(img, pts[k], pts[k + 1], 1.5 * wm, core)

## Arc Emitters: our corvette lower-left, then a chain of four enemy corvettes
## (centres `ts`, box sizes `tb`, bolt width scales `wms`), receding along it.
static func _arc_chain(img: Image, ts: Array, tb: Array, wms: Array) -> void:
	var violet := Color("b48cff")
	var ship := Vector2(15, 46)
	var ang := -PI / 4.0
	var d := Vector2.from_angle(ang)
	var bl := ship + d * 15.2
	var rim := Color("e6d4ff")
	_spr_rim(img, "ship_corvette", ship, 26.0, ang, bl, 18.0, rim, 1.0, 0.0, false)
	var dims := [1.0, 0.86, 0.74, 0.62]
	var prev := bl
	var hits := []
	for k in 4:
		var to: Vector2 = ts[k]
		var dd := (to - prev).normalized()
		var hit: Vector2 = to - dd * float(tb[k]) * 0.45
		hits.append(hit)
		var face := roundf((prev - to).angle() / (PI / 4.0)) * (PI / 4.0)
		_spr_rim(img, "ship_corvette", to, tb[k], face, hit, float(tb[k]) * 0.9, rim, dims[k], 0.12 + 0.12 * k, true)
		prev = to + dd * float(tb[k]) * 0.45
	prev = bl
	for k in 4:
		var h: Vector2 = hits[k]
		_arc_bolt(img, prev, h, 80 + k, 1.8, Color(violet, 1.0 - 0.2 * k), Color.WHITE.lerp(violet, 0.2 * k), wms[k])
		_soft_glow(img, h, 2.4 - 0.25 * k, violet)
		var to: Vector2 = ts[k]
		prev = to + (to - h).normalized() * float(tb[k]) * 0.1
	_soft_glow(img, bl, 4.4, violet)

## A lumpy dark smoke puff with a hot flash core showing through.
static func _flak_puff(img: Image, c: Vector2, r: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lobes := []
	for k in 10:
		var an := k * TAU / 10.0 + rng.randf_range(-0.2, 0.2)
		lobes.append([c + Vector2.from_angle(an) * r * rng.randf_range(0.5, 0.78), r * rng.randf_range(0.42, 0.58)])
	lobes.append([c, r * 0.7])
	for l in lobes:
		_disc(img, l[0], l[1] + 0.8, Color("0f0c0a"))
	for l in lobes:
		_disc(img, l[0], l[1], Color("2a221d"))
	for l in lobes:
		_disc(img, l[0] + Vector2(-0.18, -0.2) * l[1], l[1] * 0.66, Color("3d332b"))
	for l in lobes:
		_disc(img, l[0] + Vector2(-0.3, -0.35) * l[1], l[1] * 0.3, Color("5a4b3e"))
	_soft_glow(img, c + Vector2(0.15, 0.1) * r, r * 0.66, Color("ff8a2a"), Color("fff0c8"))
	for k in 4:
		var an := rng.randf() * TAU
		_disc(img, c + Vector2.from_angle(an) * r * 0.42, r * 0.3, Color(0.12, 0.09, 0.07, 0.3))

## One thin shrapnel streak a -> b, bright at the start and fading toward its tip.
static func _flak_streak(img: Image, a: Vector2, b: Vector2, w: float) -> void:
	var n := 4
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var f := 1.0 - t0
		var col := Color("fff2c0").lerp(Color("ff9a2a"), t0)
		col.a = 0.25 + 0.75 * f
		_line(img, a.lerp(b, t0), a.lerp(b, t1), w * (0.55 + 0.45 * f), col)

## Streaks fanning out of a puff, skipping the directions in `skips`.
static func _flak_streaks(img: Image, c: Vector2, r: float, n: int, seed_v: int, skips: Array, lmin: float, lmax: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for k in n:
		var an := k * TAU / n + rng.randf_range(-0.1, 0.1)
		var bad := false
		for sk in skips:
			if absf(angle_difference(an, sk)) < 0.45:
				bad = true
		if bad:
			continue
		var d := Vector2.from_angle(an)
		var st := r * 1.25 + 1.8 + rng.randf() * 1.2
		_flak_streak(img, c + d * st, c + d * (st + rng.randf_range(lmin, lmax)), 1.2)

## Flak Cannons: our destroyer, two smoke puffs ([centre, radius]), enemy
## corvettes ([centre, box, dim]) lit by the nearest puff, each boom turret
## tracing onto its own puff.
static func _flak_scene(img: Image, puffs: Array, ships: Array) -> void:
	var ship := Vector2(15, 46)
	var ang := -PI / 4.0
	var d := Vector2.from_angle(ang)
	var nose := ship + d * 12.5
	var rim := Color("ffd9a0")
	_spr_rim(img, "ship_destroyer", ship, 25.0, ang, nose, 17.0, rim, 1.0, 0.0, false)
	for sh in ships:
		var e: Vector2 = sh[0]
		var best := 0
		for i in 2:
			if e.distance_to(puffs[i][0]) < e.distance_to(puffs[best][0]):
				best = i
		var face := roundf((ship - e).angle() / (PI / 4.0)) * (PI / 4.0)
		var bx: float = sh[1]
		_spr_rim(img, "ship_corvette", e, bx, face, puffs[best][0], bx * 1.8 + float(puffs[best][1]) * 1.2, rim, sh[2], 0.14, true)
	for i in 2:
		var pc: Vector2 = puffs[i][0]
		_flak_streaks(img, pc, puffs[i][1], 12, 5 + i, [(ship - pc).angle(), (puffs[1 - i][0] - pc).angle()], 5.0, 9.0)
	for sh in ships:
		var e: Vector2 = sh[0]
		var best := 0
		for i in 2:
			if e.distance_to(puffs[i][0]) < e.distance_to(puffs[best][0]):
				best = i
		var pc: Vector2 = puffs[best][0]
		var dd := (e - pc).normalized()
		var bx: float = sh[1]
		_flak_streak(img, pc + dd * (float(puffs[best][1]) * 1.25 + 1.8), e - dd * bx * 0.42, 1.2)
		_soft_glow(img, e - dd * bx * 0.42, 1.8, Color("ffb23a"), Color("fff6d8"))
	for i in 2:
		_flak_puff(img, puffs[i][0], puffs[i][1], 3 + 4 * i)
	# The two boom turrets, placed as the game does (fractions of the sprite
	# from the stern and off the keel), each tracing onto its own puff.
	var k_px := 25.0 / 95.0
	var tpos := [Vector2(-16.0, -14.5), Vector2(-16.0, 11.5)]
	for i in 2:
		var tc: Vector2 = ship + (tpos[i] * k_px).rotated(ang)
		var pc: Vector2 = puffs[i][0]
		_spr_rim(img, "ship_turret", tc, 7.0, ang, pc, 45.0, rim, 1.0, 0.0, false)
		var muz := tc + d * 3.6
		var aim := (pc - muz).normalized()
		var tgt := pc - aim * (float(puffs[i][1]) * 1.6)
		for q in 5:
			var t0 := float(q) / 5.0
			var t1 := float(q + 1) / 5.0
			_line(img, muz.lerp(tgt, t0), muz.lerp(tgt, t1), 1.3 - 0.5 * t0, Color(1.0, 0.85, 0.5, 0.95 - 0.55 * t0))
		_soft_glow(img, muz + aim * 1.2, 2.6, Color("ff9a2a"), Color("fff0b0"))
