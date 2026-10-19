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
	"siege_platforms", "rapid_assembly", "citadel_protocols", "fortress_doctrine", "shipyard_networks", "orbital_elevators",
	"deflectors", "phase_shields", "aegis_matrix", "composite_plating", "reactive_armor", "neutronium_armor",
	"reinforced_frames", "nanite_plating", "adaptive_hulls", "flak_screens", "point_defense", "aegis_umbrella",
	"ion_cannons", "particle_lances", "capital_batteries", "targeting_arrays", "beam_focusing", "lance_batteries",
	"autoloaders", "heavy_mounts", "scatter_arrays", "overcharged_coils", "burst_cyclers", "dark_matter",
	"solar_collectors", "plasma_reactors", "hullbreaker_rounds",
	"target_prediction", "gyro_stabilizers", "defensive_fire",
	"hydroponics", "colony_pods", "rationing", "habitat_modules", "gene_clinics", "arcologies",
	"orbital_farms", "planetary_shields", "terraforming", "deep_vaults", "gene_forges", "planetary_citadels",
	"deep_drills", "bulk_holds", "cutting_lasers", "resonance_drills", "gas_skimming", "ion_thrusters",
	"fusion_drives", "jump_drives", "convoy_protocols", "mass_drivers", "logistics_command", "spice_navigation",
	"mod_proton_torpedoes", "mod_kinetic_repeaters", "mod_arc_emitters", "mod_flak_cannons", "mod_cluster_bombs",
	"mod_homing_missiles", "mod_ion_lance", "mod_rail_cannons", "mod_point_defense_lattice",
	"mod_interceptor_drones", "mod_tractor_beams", "mod_missile_barrage",
]

static func call_scene(id: String, img: Image) -> void:
	match id:
		# ---------------------------------------------------------- mods
		# The class's hull small in a corner, its new weapon doing its thing.
		"mod_proton_torpedoes":
			_sprite(img, "ship_corvette", Vector2(14, 48), 18.0)
			_dashes(img, Vector2(20, 42), Vector2(40, 22), Color("ffb347", 0.7))
			_disc(img, Vector2(44, 18), 5.0, Color("ff8a2a"))
			_disc(img, Vector2(44, 18), 2.5, Color("fff0c0"))
		"mod_kinetic_repeaters":
			_sprite(img, "ship_corvette", Vector2(12, 46), 18.0)
			for k in 5:
				var p := Vector2(22 + k * 8, 40 - k * 6)
				_line(img, p, p + Vector2(4, -3), 2.0, Color("ffd84a"))
		"mod_arc_emitters":
			_sprite(img, "ship_corvette", Vector2(12, 48), 18.0)
			var pts := [Vector2(18, 42), Vector2(26, 30), Vector2(22, 26), Vector2(34, 18), Vector2(44, 24), Vector2(52, 12)]
			for k in pts.size() - 1:
				_line(img, pts[k], pts[k + 1], 3.0, Color("bfe6ff", 0.5))
				_line(img, pts[k], pts[k + 1], 1.2, Color.WHITE)
			for q in [Vector2(34, 18), Vector2(52, 12), Vector2(44, 34)]:
				_disc(img, q, 2.5, Color("e85a5a"))
			_line(img, Vector2(34, 18), Vector2(44, 34), 1.2, Color("dff3ff"))
		"mod_flak_cannons":
			_sprite(img, "ship_destroyer", Vector2(14, 48), 22.0)
			for b in [Vector2(36, 18), Vector2(50, 30), Vector2(30, 34)]:
				_burst(img, b, 7.0, Color("ffb347"))
				_disc(img, b, 2.0, Color("fff0c0"))
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
			_sprite(img, "ship_depot_plasma", C, 40.0)
		"reinforced_docks":
			_sprite(img, "starbase", C, 30.0)
			for a in [0.0, PI / 2.0, PI, PI * 1.5]:
				_arc(img, C, 21.0, a - 0.5, a + 0.5, 4.0, Color("9aa6c4"))
		"forward_bases":
			_sprite(img, "starbase", Vector2(16, 44), 20.0)
			_dashes(img, Vector2(22, 38), Vector2(44, 20), Color("ffd84a"))
			_sprite(img, "starbase", Vector2(46, 18), 22.0)
		"siege_platforms":
			_sprite(img, "starbase", Vector2(14, 46), 22.0)
			_beam(img, Vector2(20, 40), Vector2(54, 12), Color("ff6a4a"), 2.5)
			_burst(img, Vector2(54, 12), 6.0, Color("ffd84a"))
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
		"fortress_doctrine":
			_sprite(img, "starbase", C, 26.0)
			_hex(img, C, 24.0, 3.0, Color("ffb347"))
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
		"deflectors":
			_sprite(img, "ship_destroyer", C, 30.0)
			_arc(img, C, 22.0, -0.9, 0.9, 3.0, Color("7fd8ff"))
		"phase_shields":
			_sprite(img, "ship_destroyer", C, 28.0)
			_ring(img, C, 22.0, 2.0, Color("7fd8ff", 0.9))
			_ring(img, C, 18.0, 1.5, Color("b0f0ff", 0.5))
		"aegis_matrix":
			_sprite(img, "ship_cruiser", C, 30.0)
			for k in 6:
				_hex(img, C + Vector2.from_angle(TAU * k / 6.0) * 18.0, 7.0, 1.2, Color("7fd8ff", 0.85))
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
			for k in 4:
				_line(img, Vector2(10 + k * 14, 14), Vector2(10 + k * 14, 50), 2.0, Color("9aa6c4"))
			_line(img, Vector2(10, 14), Vector2(52, 14), 2.0, Color("9aa6c4"))
			_line(img, Vector2(10, 50), Vector2(52, 50), 2.0, Color("9aa6c4"))
			for k in 3:
				_line(img, Vector2(10 + k * 14, 14), Vector2(24 + k * 14, 50), 1.5, Color("6fe07a"))
		"nanite_plating":
			_sprite(img, "ship_destroyer", C, 30.0)
			for k in 24:
				var a := float(k) * 2.4
				_put(img, int(32 + cos(a) * (10 + k % 9)), int(32 + sin(a) * (8 + k % 7)), Color("6fe07a"))
		"adaptive_hulls":
			_sprite(img, "ship_cruiser", C, 34.0)
			_hex(img, C + Vector2(-8, -6), 5.0, 1.2, Color("6fe07a"))
			_hex(img, C + Vector2(4, 4), 5.0, 1.2, Color("6fe07a"))
			_hex(img, C + Vector2(12, -6), 5.0, 1.2, Color("6fe07a"))
		"flak_screens":
			_sprite(img, "ship_corvette", C, 22.0)
			for q in [Vector2(14, 14), Vector2(50, 18), Vector2(48, 48), Vector2(16, 46), Vector2(32, 10)]:
				_burst(img, q, 4.5, Color("c9b6ff"))
		"point_defense":
			_sprite(img, "ship_destroyer", Vector2(20, 42), 24.0)
			_beam(img, Vector2(26, 36), Vector2(48, 14), Color("c9b6ff"), 1.5)
			_burst(img, Vector2(48, 14), 5.0, Color("ffd84a"))
		"aegis_umbrella":
			for q in [Vector2(18, 44), Vector2(32, 48), Vector2(46, 44)]:
				_sprite(img, "ship_corvette", q, 14.0)
			_arc(img, Vector2(32, 50), 28.0, PI, TAU, 3.0, Color("c9b6ff"))
		# ---------------------------------------------------------- weapons
		"ion_cannons":
			_barrel(img, Vector2(8, 46), Vector2(30, 30), 6.0)
			_beam(img, Vector2(32, 28), Vector2(56, 12), Color("7fd8ff"), 3.0)
		"particle_lances":
			_barrel(img, Vector2(6, 50), Vector2(22, 38), 5.0)
			_beam(img, Vector2(24, 36), Vector2(60, 8), Color("ff6a4a"), 1.5)
		"capital_batteries":
			_disc(img, Vector2(26, 40), 12.0, Color("6a7596"))
			_barrel(img, Vector2(26, 36), Vector2(52, 18), 4.0)
			_barrel(img, Vector2(26, 44), Vector2(52, 26), 4.0)
		"targeting_arrays":
			_dish(img, Vector2(16, 44))
			_sprite(img, "ship_corvette", Vector2(46, 20), 16.0)
			_ring(img, Vector2(46, 20), 10.0, 1.5, Color("ff6a4a"))
		"beam_focusing":
			_beam(img, Vector2(6, 22), Vector2(28, 32), Color("ff6a4a", 0.6), 4.0)
			_beam(img, Vector2(6, 42), Vector2(28, 32), Color("ff6a4a", 0.6), 4.0)
			_ellipse(img, Vector2(30, 32), Vector2(3, 12), Color("b0f0ff"))
			_beam(img, Vector2(32, 32), Vector2(60, 32), Color("ffd84a"), 1.5)
		"lance_batteries":
			for k in 3:
				_beam(img, Vector2(8, 18 + k * 14), Vector2(58, 12 + k * 14), Color("ff6a4a"), 2.5)
		"target_prediction":
			# A shot aimed at the reticle ahead of the ship, not at the ship.
			_sprite(img, "ship_corvette", Vector2(22, 44), 16.0)
			for k in 4:
				_line(img, Vector2(28 + k * 6, 38 - k * 5), Vector2(31 + k * 6, 35 - k * 5), 1.0, Color("b0f0ff"))
			_ring(img, Vector2(50, 16), 8.0, 1.5, Color("ff6a4a"))
			_line(img, Vector2(50, 6), Vector2(50, 26), 1.0, Color("ff6a4a"))
			_line(img, Vector2(40, 16), Vector2(60, 16), 1.0, Color("ff6a4a"))
			_beam(img, Vector2(6, 58), Vector2(48, 18), Color("ffd84a"), 1.5)
		"gyro_stabilizers":
			_ring(img, Vector2(32, 32), 20.0, 2.5, Color("8a95b8"))
			_ellipse(img, Vector2(32, 32), Vector2(20, 7), Color("6a7596"))
			_ellipse(img, Vector2(32, 32), Vector2(7, 20), Color("6a7596"))
			_disc(img, Vector2(32, 32), 5.0, Color("ffd84a"))
		"defensive_fire":
			_disc(img, Vector2(14, 48), 9.0, Color("6a7596"))
			_barrel(img, Vector2(14, 46), Vector2(30, 32), 4.0)
			_beam(img, Vector2(32, 30), Vector2(48, 18), Color("ffd84a"), 1.5)
			_disc(img, Vector2(50, 16), 5.0, Color("ff8a2a"))
			_line(img, Vector2(44, 10), Vector2(56, 22), 2.0, Color("ff4a4a"))
			_line(img, Vector2(44, 22), Vector2(56, 10), 2.0, Color("ff4a4a"))
		"autoloaders":
			for k in 5:
				_shell(img, Vector2(10 + k * 10, 32))
		"heavy_mounts":
			_box(img, Vector2(14, 40), Vector2(50, 52), Color("6a7596"))
			_disc(img, Vector2(32, 38), 10.0, Color("8a95b8"))
			_barrel(img, Vector2(32, 34), Vector2(54, 12), 6.0)
		"scatter_arrays":
			_barrel(img, Vector2(8, 32), Vector2(22, 32), 6.0)
			for k in 5:
				_beam(img, Vector2(24, 32), Vector2(58, 12 + k * 10), Color("ffd84a"), 1.5)
		"overcharged_coils":
			for k in 5:
				_ellipse(img, Vector2(18 + k * 7, 32), Vector2(3, 12), Color("c87a3a"))
			for q in [Vector2(16, 14), Vector2(48, 50), Vector2(52, 16)]:
				_line(img, q, q + Vector2(4, 6), 1.5, Color("b0f0ff"))
		"burst_cyclers":
			_disc(img, Vector2(18, 32), 10.0, Color("6a7596"))
			for k in 3:
				_barrel(img, Vector2(18, 26 + k * 6), Vector2(36, 26 + k * 6), 3.0)
			for k in 3:
				_burst(img, Vector2(44 + k * 6, 26 + k * 6), 3.0, Color("ffd84a"))
		"hullbreaker_rounds":
			_plate(img, Vector2(30, 10), Vector2(10, 44), Color("6a7596"))
			_poly(img, [Vector2(6, 30), Vector2(26, 26), Vector2(34, 32), Vector2(26, 38), Vector2(6, 34)], Color("c8a04a"))
			_burst(img, Vector2(44, 32), 9.0, Color("ff8a3a"))
			for k in 4:
				_line(img, Vector2(40, 32), Vector2(40, 32) + Vector2.from_angle(-1.2 + k * 0.8) * 14.0, 1.0, Color("2c2a3a"))
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

static func _sprite(img: Image, tex_name: String, c: Vector2, box: float) -> void:
	c *= K
	box *= K
	var tex := Defs.tex(tex_name)
	if tex == null:
		return
	var src := tex.get_image().duplicate()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var k: float = box / maxf(src.get_width(), src.get_height())
	var w := maxi(1, int(src.get_width() * k))
	var h := maxi(1, int(src.get_height() * k))
	src.resize(w, h, Image.INTERPOLATE_NEAREST)
	var tim: Image = null
	var team: Texture2D = Defs.tex(tex_name + "_team") if ResourceLoader.exists("res://assets/pixel/" + tex_name + "_team.png") else null
	if team:
		tim = team.get_image().duplicate()
		if tim.is_compressed():
			tim.decompress()
		tim.convert(Image.FORMAT_RGBA8)
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
