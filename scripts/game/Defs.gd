class_name Defs
## Static data for Stardust Dominion: resources, ship classes, stations, planet
## types, and the tech tree. Ranges/speeds are in world pixels.
##
## Economy rules (see Game.pay_over_time): ship/starbase construction and
## research costs are paid gradually over their build/research time.
## Progress only advances while the resources are there; any shortfall in
## food, minerals or energy is covered from spice automatically, SPICE_COVER_RATIO
## of the missing resource per spice (Game.spice_cover can switch it off).

const PIXEL := "res://assets/pixel/"

## Resource figures (building output, harvest rates, upkeep) are all per
## minute: steadier to read than a per-second trickle. The tick maths
## divides by this once, at the point resources are actually moved.
const PER_MIN := 60.0

## Ship sprites are drawn at this multiple of their design size (see the S
## constant in tools/gen_art.gd) and rendered at 1/ART_SCALE, so they keep
## their world size while carrying twice the detail.
const ART_SCALE := 2.0

## Sprites drawn at ART_SCALE: anything the game must shrink back down when
## it draws it, in the world or in a panel.
const ART_SCALED := ["ship_", "starbase", "asteroid", "asteroid_big", "debris", "spice_", "planet_", "star", "explosion", "shield_hit", "bolt_", "engine_flame", "icon_", "bld_"]

## How much to divide a sprite by when drawing it: ART_SCALE for the art that
## is generated oversized, 1 for everything else.
static func art_div(name: String) -> float:
	for p in ART_SCALED:
		if name.begins_with(p):
			return ART_SCALE
	return 1.0

const RESOURCES: Array[String] = ["food", "minerals", "energy", "spice"]
const RESOURCE_NAMES := {"food": "Food", "minerals": "Minerals", "energy": "Energy", "spice": "Spice"}
const RESOURCE_COLORS := {"food": Color("8fe060"), "minerals": Color("3fd6b0"), "energy": Color("ffd46b"), "spice": Color("ff9a2e")}

const START := {"food": 500.0, "minerals": 1000.0, "energy": 200.0, "spice": 100.0}
## Deathmatch start (lobby checkbox): enough of everything that the opening is
## a fight rather than an economy ramp.
const START_DEATHMATCH := {"food": 10000.0, "minerals": 10000.0, "energy": 10000.0, "spice": 10000.0}

## What a player opens the match with. The caller passes the lobby's
## Deathmatch setting, so this file stays free of autoloads and tools like
## gen_art.gd can still parse it.
static func starting_resources(deathmatch: bool) -> Dictionary:
	return (START_DEATHMATCH if deathmatch else START).duplicate()

const TEAM_COLORS: Array[Color] = [
	Color("9aa0b0"), # 0: neutral
	# In lobby order: blue, red, green, yellow, purple, orange, teal, pink.
	Color("4fb4ff"), Color("ff4f5e"), Color("6fe07a"), Color("ffc93d"),
	Color("c77dff"), Color("ff8c3a"), Color("3de0d0"), Color("ff7ac8"),
]

## Compact amounts: 950, 1.2k, 54.3k, 230k.
static func short_num(v: float) -> String:
	var a := absf(v)
	# Rounded down, so it never shows more than there is: 7935 -> 7.9k,
	# 123500 -> 123k, 99960 -> 99.9k.
	if a >= 100000.0:
		return "%dk" % int(floorf(v / 1000.0))
	if a >= 1000.0:
		return "%.1fk" % (floorf(v / 100.0) / 10.0)
	return "%d" % int(v)

## A player's colour follows their lobby slot (Game sets slot_of each match).
static var slot_of := {}

static func team_color(owner_id: int) -> Color:
	return TEAM_COLORS[clampi(int(slot_of.get(owner_id, owner_id)), 0, TEAM_COLORS.size() - 1)]

## Every class draws its turrets at the destroyer's on-screen size: a turret
## sprite is scaled by the hull's "size" times its own turret_scale, so each
## class sets turret_scale = TURRET_ON_SCREEN / its size (destroyer: 1.33 x 0.5).
const TURRET_ON_SCREEN := 1.33 * 0.5

## role: miner / warship / colony / constructor.
## cost is the total, paid over build_time. upkeep is energy per minute;
## harvest is how fast the hold fills, per minute (see Defs.PER_MIN).
## requires: tech id that must be researched before it can be queued.
## PROJECT SYMMETRY (experiment branch): every turret = one corvette gun
## (10 dmg / 1.0 s / 6 rad/s); cost 75/150/300/600; toughness sized so
## one hull ties its cost in corvettes under split fire (1x/2x/4.33x/12x of 150).
const BASE_SHIPS := {
	"miner": {
		"name": "Mining Barge", "role": "miner", "subclass": "harvester",
		"hp": 70.0, "shield": 0.0, "speed": 70.0, "radius": 8.0,
		"cost": {"minerals": 50}, "build_time": 15.0, "upkeep": 0.35,
		"cargo": 10, "harvest": 36.0,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"skimmer": {
		"name": "Gas Skimmer", "role": "skimmer", "subclass": "harvester", "requires": "gas_skimming",
		"hp": 90.0, "shield": 20.0, "speed": 65.0, "radius": 9.0,
		"cost": {"minerals": 110}, "build_time": 22.0, "upkeep": 0.7,
		"cargo": 20, "harvest": 18.0,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"colony": {
		"name": "Colony Ship", "role": "colony",
		"hp": 100.0, "armor": 20.0, "shield": 20.0, "speed": 60.0, "radius": 9.0,
		"cost": {"minerals": 100}, "build_time": 26.0, "upkeep": 0.7,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"constructor": {
		"name": "Constructor", "role": "constructor",
		"hp": 110.0, "armor": 40.0, "shield": 20.0, "speed": 65.0, "radius": 9.0,
		"cost": {"minerals": 60}, "build_time": 10.0, "upkeep": 0.7,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"corvette": {
		"name": "Corvette", "role": "warship",
		"hp": 66.0, "armor": 50.0, "shield": 34.0, "speed": 125.0, "radius": 8.0,
		"cost": {"minerals": 75}, "build_time": 15.0, "upkeep": 0.7,
		"weapon": "laser", "damage": LASER_DAMAGE, "cooldown": LASER_COOLDOWN, "range": 140.0, "sensor": 280.0, "refit": {"minerals": 5, "time": 8.0},
	},
	"destroyer": {
		"name": "Destroyer", "role": "warship", "requires": "destroyers",
		"hp": 99.0, "armor": 132.0, "shield": 69.0, "speed": 85.0, "radius": 14.6, "size": 1.33,
		"cost": {"minerals": 150}, "build_time": 38.0, "upkeep": 1.7,
		"weapon": "laser", "damage": LASER_DAMAGE, "cooldown": LASER_COOLDOWN, "range": 210.0, "sensor": 330.0, "refit": {"minerals": 10, "time": 10.0},
		# Two light turrets on the prongs: they track a circling corvette
		# without the hull coming about, and two smaller shots waste less on
		# a light target than one big one.
		"guns": 2, "turret_rate": 6.0, "turret_scale": TURRET_ON_SCREEN / 1.33, "turrets": [[0.62, -0.22], [0.62, 0.22]],
	},
	"cruiser": {
		"name": "Cruiser", "role": "warship", "requires": "cruisers",
		"hp": 264.0, "armor": 184.0, "shield": 352.0, "speed": 55.0, "radius": 26.6, "size": 1.66,
		"cost": {"minerals": 300}, "build_time": 80.0, "upkeep": 4.0,
		"weapon": "laser", "damage": LASER_DAMAGE, "cooldown": LASER_COOLDOWN, "range": 260.0, "sensor": 420.0, "refit": {"minerals": 15, "time": 12.0},
		# Three laser turrets: the hub and both forward wings.
		"guns": 3, "turret_rate": 6.0, "turret_scale": TURRET_ON_SCREEN / 1.66, "turrets": [[0.5, 0.0], [0.3, -0.28], [0.3, 0.28]],
	},
	"carrier": {
		"name": "Carrier", "role": "warship", "requires": "carriers", "base": "carrier",
		# About twice a cruiser in every dimension: slower across the map and
		# far slower to come about, since turn rate falls with radius. It
		# makes up for it with several mounts instead of one.
		"hp": 552.0, "armor": 792.0, "shield": 1056.0, "speed": 38.0, "radius": 64.0, "size": 2.0,
		"cost": {"minerals": 600}, "build_time": 153.0, "upkeep": 8.0,
		"weapon": "laser", "damage": LASER_DAMAGE, "cooldown": LASER_COOLDOWN, "range": 260.0, "sensor": 460.0,
		"guns": 4,
		# Turrets traverse on their own, so the hull does not have to come
		# about to shoot - but slowly, so a corvette that keeps moving can
		# stay off the bearing and flank it.
		"turret_rate": 6.0, "turret_scale": TURRET_ON_SCREEN / 2.0, "turrets": [[0.535, -0.375], [0.535, 0.375], [0.186, -0.375], [0.186, 0.375]],
		# Refitting a hull this size is proportionally dearer and slower than
		# a cruiser's (15 / 35 s) — twice the hull, twice the yard time.
		"refit": {"minerals": 30, "time": 14.0},
	},
	"scout": {
		"name": "Scout", "role": "scout",
		"hp": 50.0, "shield": 10.0, "speed": 155.0, "radius": 7.0,
		"cost": {"minerals": 45}, "build_time": 10.0, "upkeep": 0.35,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0, "sensor": 600.0, "job": "beacon",
	},
	"heatshield": {
		"name": "Radiation Sail Array", "short": "Rad Sail Array", "role": "support",
		# Solar sail: no ordinary shield. Inside a star's radiation or a spice
		# nebula it harvests "solar_sail" energy a minute, charging a solar
		# shield (base "shield", starts empty) first and sending the rest to the
		# energy pool (Ship._solar_tick).
		"solar_sail": 15.0, "shield_color": Color("c9a0ff"),
		"hp": 200.0, "armor": 140.0, "shield": 100.0, "speed": 80.0, "radius": 11.0,
		"cost": {"minerals": 130}, "build_time": 24.0, "upkeep": 1.3,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0, "sensor": 300.0, "job": "radiation_sail",
	},
	"tender": {
		"name": "Repair Tender", "role": "support",
		"hp": 150.0, "armor": 90.0, "shield": 60.0, "speed": 75.0, "radius": 11.0,
		"cost": {"minerals": 150}, "build_time": 28.0, "upkeep": 1.7,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0, "sensor": 300.0, "job": "field_repair",
	},
}

## Starbase build menu order (and G/J/K etc. hotkey lookup): economy,
## support, generalist warships. Specialist variants aren't built here: a
## generalist is refitted into one at a Weapons Depot (WEAPONS_DEPOT).
const BUILD_ORDER: Array[String] = ["miner", "skimmer", "colony", "constructor", "scout", "tender",
	"corvette", "destroyer", "cruiser", "carrier", "heatshield"]

## Weapons Depot: built by a Constructor like a starbase (paid over
## build_time). Each depot is built for ONE variant (Defs.VARIANTS) and refits
## generalists into it: a Plasma Depot makes Plasma ships, a Disruptor Depot Disruptor ships.
## Ships fly in, dock (CAPACITY at a time, hidden and safe inside) and are
## refitted automatically as minerals allow; each hull has its own refit cost
## and time (see SHIPS "refit"). A specialist can never be refitted again.
## Doesn't count as a starbase (losing it doesn't lose the match).
const WEAPONS_DEPOT := {
	"name": "Weapons Depot", "requires": "depots", "hp": 368.0, "armor": 704.0, "shield": 528.0, "radius": 22.0,
	"cost": {"minerals": 290}, "build_time": 30.0, "upkeep": 2.0,
	"capacity": 10,
}

## The standard laser gun: one shot of LASER_DAMAGE every LASER_COOLDOWN s.
## Every warship laser and every construct gun (ConstructGuns) reads these,
## so ships and constructs can't drift apart.
const LASER_DAMAGE := 10.0
const LASER_COOLDOWN := 1.0

## A construct's base gun damage per second (its guns x the standard laser).
static func construct_dps(d: Dictionary) -> float:
	return float(d.get("guns", 0)) * LASER_DAMAGE / LASER_COOLDOWN

const STARBASE := {
	"name": "Starbase", "hp": 1127.0, "armor": 2156.0, "shield": 1617.0, "radius": 26.0,
	"weapon": "laser", "guns": 6, "range": 260.0,
	# Built on site by a Constructor, paid over build_time.
	"cost": {"minerals": 1200}, "build_time": 40.0,
	"upkeep": 3.3,
	# No reactor and no refinery: a starbase generates nothing. Energy comes
	# only from Power Plants (and Radiation Sail Arrays), minerals only from
	# harvesters and worlds.
}

## Finite economy. Power Plants burn minerals as fuel: FUEL_PER_ENERGY
## minerals for every energy they actually produce (after every energy
## multiplier: population, research, a Molten world). Fuel comes from the
## mineral stockpile only - spice never covers it - and plants run at
## whatever share of full output the stockpile can fuel.
const FUEL_PER_ENERGY := 0.1
## Gas giants hold GAS_RESERVE minerals each and never refill. They shrink as
## they are drained (down to GAS_MIN_SCALE of full size), start to glow when
## below UNSTABLE_RESERVE, and explode when empty.
const GAS_RESERVE := 3000
const GAS_MIN_SCALE := 0.4
const UNSTABLE_RESERVE := 1000.0
## A habitable world holds WORLD_RESERVE_PER_SIZE minerals per field. Its
## Mining Complexes draw it down; at 0 the world implodes.
const WORLD_RESERVE_PER_SIZE := 300.0
## Blast of an exploding gas giant: BLAST_DAMAGE at the centre falling
## linearly to 0 at BLAST_RADIUS. A world's implosion scales both linearly by
## size / BLAST_REF_SIZE (a size-30 world matches a gas giant; size 20:
## 2,000 damage over 300 px; size 10: 1,000 over 150 px).
const BLAST_DAMAGE := 3000.0
const BLAST_RADIUS := 450.0
const BLAST_REF_SIZE := 30.0
## Seconds between a body running empty and its blast: a countdown nothing
## can stop, so ships get the chance to flee.
const DOOM_SECONDS := 10.0

## Mining Station: a cheap, lightly armed drop-off built on site by a
## Constructor. Harvesters unload here instead of flying home, which is what
## makes a distant belt worth working. It builds nothing, and losing one
## never loses the match.
## Frontier Outpost: half a starbase's guns and layers on a cheaper site — a
## laser fort for holding ground. Builds nothing, takes no deliveries, and is
## not a starbase for winning or losing.
const FRONTIER_OUTPOST := {
	"name": "Frontier Outpost", "requires": "outposts", "hp": 632.0, "armor": 1210.0, "shield": 908.0, "radius": 20.0,
	"weapon": "laser", "guns": 3, "range": 260.0,
	"cost": {"minerals": 535}, "build_time": 30.0,
	"upkeep": 1.65,
}

## Warp Gate: no gun. Ships garrison inside (no limit; still pay upkeep, and
## die with the gate), then the gate flings them all at a point warp_min to
## warp_max px away at warp_speed_mult x their speed, every warp_cooldown s.
const WARP_GATE := {
	"name": "Warp Gate", "requires": "warp_gates", "hp": 345.0, "armor": 660.0, "shield": 495.0, "radius": 24.0,
	"cost": {"minerals": 2400}, "build_time": 60.0,
	"upkeep": 3.3,
	"warp_min": 1000.0, "warp_max": 2000.0, "warp_cooldown": 30.0, "warp_speed_mult": 10.0,
}

## Every construct keeps a clear ring around it, sized by how big it is:
## radius x PLACEMENT_RING. Two constructs may not overlap rings, so a
## starbase needs more room than a Mining Station without a special case,
## and any new construct gets sensible spacing for free.
const PLACEMENT_RING := 6.0

const MINING_STATION := {
	"name": "Mining Station", "hp": 161.0, "armor": 308.0, "shield": 231.0, "radius": 16.0,
	"weapon": "laser", "guns": 1, "range": 190.0,
	"cost": {"minerals": 150}, "build_time": 20.0,
	"upkeep": 1.0,
}

## What a rock holds goes by its size class, not what it is: a small rock
## holds the same minerals or spice, and so does a large one.
const ROCK_SMALL := 410
const ROCK_LARGE := 1080

## Whether a rock of this art and draw scale is a large one.
static func rock_is_large(variant: String, scale: float) -> bool:
	return variant.begins_with("asteroid_big") or (variant.begins_with("spice") and scale > 1.01)

## No hard caps: ALL energy upkeep (ships of every kind and constructs) is
## multiplied by one empire-wide factor, the product of every unit's weight
## below - so each unit you own makes every unit dearer to run, big ones
## most. E.g. 20 corvettes alone: 1.02^20 = x1.49.
const UPKEEP_WEIGHT := {"starbase": 1.06, "carrier": 1.05, "cruiser": 1.04, "destroyer": 1.03}
## Everything else: corvettes, harvesters, support ships, depots, Mining Stations.
## (Frontier Outposts weigh as a cruiser, Warp Gates as a starbase.)
const UPKEEP_WEIGHT_SMALL := 1.02
## With no energy in the stockpile, ships move and fire at this fraction of
## normal speed, and starbases can't produce ships. In a Blackout, buildings
## that draw energy run at this same fraction (Planet.power_factor).
const ENERGY_STARVED_FACTOR := 0.25
## Spice cover: one spice pays this much of a food/minerals/energy shortfall.
const SPICE_COVER_RATIO := 2.0

## Planet types. A planet's size = its number of fields, and its base
## population cap is size * POP_PER_SIZE (a size 19 world: 19 fields, 19k pops).
## fertility multiplies what a Farm grows there: a lush Terran world feeds
## its farms in full, a Molten one barely at all.
## spice_reserve: spice stored underground per size (field) for Spice
## Extractors; never refills. Barren worlds hold the most (desert above all);
## lush worlds very little.
## energy_mult: how much a Power Plant here makes, against the same plant
## elsewhere. A Molten world runs hot, which is the one thing it is good for:
## its fertility is the worst in the game.
const PLANET_TYPES := {
	"planet_terran": {"label": "Terran", "fertility": 1.0, "energy_mult": 1.0, "spice_reserve": 7},
	"planet_desert": {"label": "Desert", "fertility": 0.45, "energy_mult": 1.0, "spice_reserve": 75},
	"planet_ice": {"label": "Arctic", "fertility": 0.6, "energy_mult": 1.0, "spice_reserve": 18},
	"planet_lava": {"label": "Molten", "fertility": 0.15, "energy_mult": 1.15, "spice_reserve": 30},
	"planet_gas": {"label": "Gas Giant", "habitable": false, "fertility": 0.0, "energy_mult": 1.0},
	"planet_moon": {"label": "Barren Moon", "fertility": 0.2, "energy_mult": 1.0, "spice_reserve": 45},
}
## What a planet type does differently from the rest, as short lines for
## any description of it: every multiplier that is not 1.0, positive or
## negative, read straight from PLANET_TYPES so a new one shows up without
## touching the UI.
const PLANET_TRAIT_LABELS := {"fertility": "Food production", "energy_mult": "Energy production"}

static func planet_traits(kind: String) -> Array:
	var out: Array = []
	var t: Dictionary = PLANET_TYPES.get(kind, {})
	if not t.get("habitable", true):
		return out  # nothing is built on a gas giant
	for key in PLANET_TRAIT_LABELS:
		var m: float = float(t.get(key, 1.0))
		if absf(m - 1.0) > 0.001:
			out.append("%s: x%s" % [PLANET_TRAIT_LABELS[key], str(snappedf(m, 0.01))])
	return out

const POP_PER_SIZE := 1000
const START_POP := 100.0
## Worlds owned at match start (home planets) begin with this many pops.
const HOME_START_POP := 300.0
## 1 new pop per minute for every 2 pop (a "pop pair").
const GROWTH_PER_PAIR_PER_MIN := 1.0
## Every pop eats FOOD_PER_POP_PER_MIN food a minute, from food or,
## failing that, spice. One Farm feeds 2,000 pops.
const FOOD_PER_POP_PER_MIN := 0.01
## Hands on the job: a world's population multiplies what its Farms, Power
## Plants, Mining Complexes and Spice Extractors produce, with diminishing
## returns: 1 + OUTPUT_POP_BONUS x (1 - e^(-pops / OUTPUT_POP_SCALE)). The
## first pops count most; the bonus levels off toward +175% (about x2.1 at
## 10,000, x2.5 at 20,000, x2.66 at 30,000). A building needs no headcount to
## run at all, so this is the reason to grow a world rather than merely hold it.
const OUTPUT_POP_BONUS := 1.75
const OUTPUT_POP_SCALE := 10000.0
## Raised by the population cap techs and by each Habitat on the world
## ("pop_bonus" in their effects): see Planet.pop_output_mult.

## A shortage ends only once the world has been fed continuously for this
## long; until then it neither grows nor stops losing pops.
const REGROW_SECONDS := 5.0
## Food comes only from Farms (see BUILDINGS), scaled by planet fertility
## (PLANET_TYPES) and by population (OUTPUT_POP_BONUS).
## Planets and pops produce and consume no energy on their own; only Power
## Plants (and starbase reactors) make it.

## Planet fields: 3 on the smallest world up to 30 on the largest, by
## sprite diameter (moon 28px .. gas giant 104px).
const MIN_FIELDS := 3
const MAX_FIELDS := 30
const FIELD_SIZE_MIN_PX := 28.0
const FIELD_SIZE_MAX_PX := 104.0

static func field_count(planet_diameter_px: float) -> int:
	var t := clampf((planet_diameter_px - FIELD_SIZE_MIN_PX) / (FIELD_SIZE_MAX_PX - FIELD_SIZE_MIN_PX), 0.0, 1.0)
	return int(round(lerpf(MIN_FIELDS, MAX_FIELDS, t)))

## Buildings placed on planet fields. Costs are paid over build time like
## ships. output: every resource per MINUTE (the tick maths divides by
## Defs.PER_MIN).
## only: planet kinds it can be built on (empty = any).
const BUILDINGS := {
	"farm": {"energy_upkeep": 2, "name": "Farm", "cost": {"minerals": 60}, "time": 30.0, "output": {"food": 20.0}, "only": [],
		"desc": "+20 food/min at base on a fertile world (x0.15 to x1.0 by world type), more with population. Feeds 2,000 pops at full fertility (boosted by Hydroponics). Upkeep: 2 energy/min (25% output in a Blackout)."},
	"generator": {"energy_upkeep": 0, "name": "Power Plant", "cost": {"minerals": 80}, "time": 30.0, "output": {"energy": 20.0}, "only": [],
		"desc": "+20 energy/min at base, more with population, and x1.15 on a Molten world. Burns 1 mineral per 10 energy it makes (from the mineral stockpile only; with no minerals to burn it makes nothing). Needs no energy upkeep. Pause power in the world panel."},
	"mine": {"energy_upkeep": 4, "name": "Mining Complex", "cost": {"minerals": 70}, "time": 35.0, "output": {"minerals": 20.0}, "only": [],
		"desc": "+20 minerals/min at base, more with population. Digs out the world's finite crust (300 per size): at 0 the world implodes. Pause mining in the world panel. Upkeep: 4 energy/min (none while paused; 25% output in a Blackout)."},
	"habitat": {"energy_upkeep": 0, "name": "Habitat", "cost": {"minerals": 110}, "time": 40.0, "output": {}, "max_pop": 1500, "pop_bonus": 0.1, "only": [],
		"desc": "+1,500 population cap, and population's output bonus on this world can rise 0.1x higher. Needs no energy upkeep, and a Blackout does not affect it."},
	"battery": {"energy_upkeep": 3, "name": "Defense Battery", "cost": {"minerals": 140}, "time": 45.0, "output": {}, "only": [],
		"desc": "+1,200 planetary shield and a gun that fires on besieging ships (250 px). Upkeep: 3 energy/min (shield bonus and gun at 25% in a Blackout)."},
	"spice_extractor": {"energy_upkeep": 5, "name": "Spice Extractor", "cost": {"minerals": 150}, "time": 60.0, "output": {"spice": 20.0}, "only": [],
		"desc": "+20 spice/min at base, more with population. Drains the planet's spice reserve (large on barren worlds, tiny on lush ones). Upkeep: 5 energy/min (25% output in a Blackout)."},
}
## energy_upkeep: flat energy per MINUTE each finished, unpaused building
## draws (never scaled by the empire upkeep multiplier). Power Plants draw
## none: they burn minerals instead. If the empire cannot pay it, a Blackout
## (Game.blackout) puts every building that draws energy on LOW POWER
## (ENERGY_STARVED_FACTOR of its output/shield/gun, no upkeep drawn) until the
## energy stockpile has stayed above 0 for BLACKOUT_RESUME_SECS (game time)
## in a row; any return to 0 restarts the count.
const BLACKOUT_RESUME_SECS := 5.0
const BUILDING_ORDER: Array[String] = ["farm", "generator", "mine", "habitat", "spice_extractor", "battery"]
## Defense Battery: shield added per battery, and its gun.
const BATTERY_SHIELD := 1200.0
const BATTERY := {"weapon": "laser", "damage": 18.0, "cooldown": 1.2, "range": 250.0}
const SHIELD_REGEN_DELAY := 4.0
const SHIELD_REGEN_PER_SEC := 0.025 # fraction of max shield
## Energy spent per shield point regenerated (spice covers shortfalls).
const SHIELD_ENERGY_PER_POINT := 0.0055

## Tech tree. tier sets the column in the tree view; requires lists
## prerequisite techs (all needed). effects are multiplier bonuses summed
## per key (e.g. "damage": 0.2 = +20%); "unlock" names are flags.
const TECHS := {
	"ion_cannons": {"name": "Ion Cannons", "group": "weapons", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 60.0,
		"effects": {"damage": 0.20}, "desc": "+20% weapon damage: ships, constructs, worlds."},
	"hydroponics": {"name": "Hydroponics", "group": "worlds", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 40.0,
		"effects": {"food": 0.30}, "desc": "+30% food production."},
	"deep_drills": {"name": "Deep-Core Drills", "group": "logistics", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 40.0,
		"effects": {"cargo": 0.40}, "desc": "Harvesters carry +40% per load."},
	"bulk_holds": {"name": "Bulk Holds", "group": "logistics", "tier": 2, "requires": ["deep_drills"], "cost": {"spice": 60}, "time": 75.0,
		"effects": {"cargo": 0.50}, "desc": "Harvesters carry +50% per load."},
	"cutting_lasers": {"name": "Cutting Lasers", "group": "logistics", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 45.0,
		"effects": {"harvest": 0.30}, "desc": "Harvesters gather 30% faster."},
	"resonance_drills": {"name": "Resonance Drills", "group": "logistics", "tier": 2, "requires": ["cutting_lasers"], "cost": {"spice": 60}, "time": 80.0,
		"effects": {"harvest": 0.40}, "desc": "Harvesters gather 40% faster."},
	"fusion_drives": {"name": "Fusion Drives", "group": "logistics", "tier": 2, "requires": ["ion_thrusters"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {"speed": 0.25}, "desc": "+25% ship speed."},
	"gas_skimming": {"name": "Gas Skimming", "group": "logistics", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 50.0,
		"effects": {}, "desc": "Unlocks the Gas Skimmer: mines gas giants and nebulae."},
	"particle_lances": {"name": "Particle Lances", "group": "weapons", "tier": 2, "requires": ["ion_cannons"], "cost": {"spice": 60}, "time": 90.0,
		"effects": {"damage": 0.25}, "desc": "+25% weapon damage: ships, constructs, worlds."},
	"ion_thrusters": {"name": "Ion Thrusters", "group": "logistics", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 60.0,
		"effects": {"speed": 0.15}, "desc": "+15% ship speed."},
	# --- Logistics: Maneuvers. Ships fly nose-first; these add turn and
	# thrust on the other axes (Ship._steer).
	"vectored_thrusters": {"name": "Vectored Thrusters", "group": "logistics", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 60.0,
		"effects": {"turn_rate": 0.50}, "desc": "+50% ship turn and turret traverse."},
	"strafing_thrusters": {"name": "Strafing Thrusters", "group": "logistics", "tier": 2, "requires": ["vectored_thrusters"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {}, "desc": "Ships can move sideways at half speed."},
	"reverse_thrusters": {"name": "Reverse Thrusters", "group": "logistics", "tier": 3, "requires": ["strafing_thrusters"], "cost": {"spice": 240}, "time": 215.0,
		"effects": {}, "desc": "Ships can move backward at half speed."},
	"gene_clinics": {"name": "Gene Clinics", "group": "worlds", "tier": 2, "requires": ["rationing"], "cost": {"spice": 60}, "time": 75.0,
		"effects": {"growth": 0.50}, "desc": "+50% population growth."},
	"arcologies": {"name": "Arcologies", "group": "worlds", "tier": 2, "requires": ["habitat_modules"], "cost": {"spice": 60}, "time": 80.0,
		"effects": {"max_pop": 0.30, "pop_bonus": 0.20}, "desc": "+30% pop cap; pop output bonus cap +0.20x."},
	# --- Weapons: reach and rate of fire, alongside the damage line.
	"targeting_arrays": {"name": "Quantum Lenses", "group": "weapons", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 50.0,
		"effects": {"range": 0.15}, "desc": "+15% weapon range: ships, starbases, outposts."},
	"autoloaders": {"name": "Autoloaders", "group": "weapons", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 55.0,
		"effects": {"fire_rate": 0.15}, "desc": "+15% rate of fire: ships and starbases."},
	"beam_focusing": {"name": "Beam Focusing", "group": "weapons", "tier": 2, "requires": ["targeting_arrays"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {"range": 0.20}, "desc": "+20% weapon range: ships, starbases, outposts."},
	"heavy_mounts": {"name": "Heavy Mounts", "group": "weapons", "tier": 2, "requires": ["autoloaders"], "cost": {"spice": 60}, "time": 90.0,
		"effects": {"fire_rate": 0.20}, "desc": "+20% rate of fire: ships and starbases."},
	"capital_batteries": {"name": "Capital Batteries", "group": "weapons", "tier": 3, "requires": ["beam_focusing"], "cost": {"spice": 240}, "time": 235.0,
		"effects": {"range": 0.35}, "desc": "+35% weapon range: ships, starbases, outposts."},

	# --- Constructs: what you build rather than fly.
	"garrison_guns": {"name": "Garrison Guns", "group": "constructs", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 50.0,
		"effects": {"structure_damage": 0.50}, "desc": "+50% construct weapon damage."},
	"orbital_yards": {"name": "Orbital Yards", "group": "constructs", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 60.0,
		"effects": {"build_speed": 0.20}, "desc": "Starbases build ships 20% faster."},
	"modular_frames": {"name": "Modular Frames", "group": "constructs", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 50.0,
		"effects": {"construct_speed": 0.35}, "desc": "Constructs are built 35% faster."},
	"reinforced_docks": {"name": "Reinforced Docks", "group": "constructs", "tier": 2, "requires": ["garrison_guns"], "cost": {"spice": 60}, "time": 95.0,
		"effects": {"structure": 0.30}, "desc": "+30% construct hull and armor."},
	"forward_bases": {"name": "Forward Bases", "group": "constructs", "tier": 2, "requires": ["orbital_yards"], "cost": {"spice": 60}, "time": 100.0,
		"effects": {"build_speed": 0.15, "construct_speed": 0.15}, "desc": "Ships and constructs are built 15% faster."},
	"citadel_protocols": {"name": "Citadel Protocols", "group": "constructs", "tier": 3, "requires": ["reinforced_docks"], "cost": {"spice": 240}, "time": 245.0,
		"effects": {"structure_shield": 0.50, "structure_range": 0.15}, "desc": "+50% construct shields, +15% construct weapon range."},

	# --- Worlds: feeding, growing and holding colonies.
	"colony_pods": {"name": "Colony Pods", "group": "worlds", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 40.0,
		"effects": {"colony_pop": 1.0}, "desc": "New colonies start with double population."},
	"orbital_farms": {"name": "Orbital Farms", "group": "worlds", "tier": 2, "requires": ["hydroponics"], "cost": {"spice": 60}, "time": 80.0,
		"effects": {"food": 0.35}, "desc": "+35% food production."},
	"planetary_shields": {"name": "Planetary Shields", "group": "worlds", "tier": 2, "requires": ["colony_pods"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {"planet_shield": 0.40}, "desc": "+40% planetary shield."},
	"terraforming": {"name": "Terraforming", "group": "worlds", "tier": 3, "requires": ["orbital_farms"], "cost": {"spice": 240}, "time": 225.0,
		"effects": {"food": 0.40, "max_pop": 0.20}, "desc": "+40% food production, +20% population cap."},
	"deep_vaults": {"name": "Deep Vaults", "group": "worlds", "tier": 3, "requires": ["arcologies"], "cost": {"spice": 240}, "time": 235.0,
		"effects": {"max_pop": 0.40, "growth": 0.25, "pop_bonus": 0.25}, "desc": "+40% pop cap, +25% growth; pop output bonus cap +0.25x."},

	# --- Weapons: every step up the line costs something. The two tier 3
	# projects are a fork, not a sequence: heavy slow guns or light fast ones.
	"overcharged_coils": {"name": "Overcharged Coils", "group": "weapons", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 55.0,
		"effects": {"shield_pierce": 0.25}, "desc": "25% of each hit skips enemy shields."},
	"burst_cyclers": {"name": "Burst Cyclers", "group": "weapons", "tier": 2, "requires": ["overcharged_coils"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {"armor_pierce": 0.25}, "desc": "25% of each hit skips enemy armor."},
	"starfire_batteries": {"name": "Starfire Batteries", "group": "weapons", "tier": 3, "requires": ["particle_lances"], "cost": {"spice": 240}, "time": 245.0,
		"effects": {"damage": 0.30}, "desc": "+30% weapon damage: ships, constructs, worlds."},
	"scatter_arrays": {"name": "Scatter Arrays", "group": "weapons", "tier": 3, "requires": ["heavy_mounts"], "cost": {"spice": 240}, "time": 245.0,
		"effects": {"fire_rate": 0.30}, "desc": "+30% rate of fire: ships and starbases."},
	# TARGETING row (Ship/Projectile read these with Game.has_tech).
	"target_prediction": {"name": "Target Prediction", "group": "weapons", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 55.0,
		"effects": {}, "desc": "Shots aim where a moving target is going."},
	"gyro_stabilizers": {"name": "Gyro-Stabilizers", "group": "weapons", "tier": 2, "requires": ["target_prediction"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {}, "desc": "No accuracy loss when firing on the move."},
	"overkill_awareness": {"name": "Overkill Awareness", "group": "weapons", "tier": 3, "requires": ["gyro_stabilizers"], "cost": {"spice": 240}, "time": 245.0,
		"effects": {}, "desc": "Guns skip enemies your shots in flight will kill."},
	"hullbreaker_rounds": {"name": "Rupture Charges", "group": "weapons", "tier": 3, "requires": ["burst_cyclers"], "cost": {"spice": 240}, "time": 245.0,
		"effects": {"hull_damage": 0.25}, "desc": "+25% damage to enemy hulls."},

	# --- Constructs: tier 3 forks into a defensive posture or an industrial one.
	"outposts": {"name": "Outposts", "group": "constructs", "tier": 2, "requires": ["depots"], "cost": {"spice": 60}, "time": 90.0,
		"effects": {"unlock_outpost": 1.0}, "desc": "Unlocks the Frontier Outpost."},
	"rapid_assembly": {"name": "Rapid Assembly", "group": "constructs", "tier": 2, "requires": ["modular_frames"], "cost": {"spice": 60}, "time": 85.0,
		"effects": {"construct_start": 1.0, "construct_progress": 0.2}, "desc": "New constructs start 20% built, with 20% hull instead of 10%."},
	"warp_gates": {"name": "Warp Gates", "group": "constructs", "tier": 3, "requires": ["outposts"], "cost": {"spice": 240}, "time": 235.0,
		"effects": {"unlock_warp_gate": 1.0}, "desc": "Unlocks the Warp Gate."},
	"shipyard_networks": {"name": "Shipyard Networks", "group": "constructs", "tier": 3, "requires": ["forward_bases"], "cost": {"spice": 240}, "time": 235.0,
		"effects": {"build_speed": 0.25}, "desc": "Starbases build ships 25% faster."},
	"orbital_elevators": {"name": "Orbital Elevators", "group": "constructs", "tier": 3, "requires": ["rapid_assembly"], "cost": {"spice": 240}, "time": 215.0,
		"effects": {"construct_speed": 0.50, "upkeep": -0.10}, "desc": "Constructs build 50% faster, -10% empire upkeep multiplier."},

	# --- Worlds: feeding a population you chose to grow.
	"rationing": {"name": "Rationing", "group": "worlds", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 40.0,
		"effects": {"growth": 0.10}, "desc": "+10% population growth."},
	"habitat_modules": {"name": "Habitat Modules", "group": "worlds", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 45.0,
		"effects": {"max_pop": 0.20, "pop_bonus": 0.15}, "desc": "+20% population cap; population's output bonus can rise 0.15x higher."},
	"gene_forges": {"name": "Gene Forges", "group": "worlds", "tier": 3, "requires": ["gene_clinics"], "cost": {"spice": 240}, "time": 215.0,
		"effects": {"growth": 0.80, "max_pop": 0.10}, "desc": "+80% population growth, +10% population cap."},
	"planetary_citadels": {"name": "Planetary Citadels", "group": "worlds", "tier": 3, "requires": ["planetary_shields"], "cost": {"spice": 240}, "time": 235.0,
		"effects": {"planet_shield": 0.60, "planet_damage": 0.25}, "desc": "+60% planetary shield, +25% battery damage."},

	# --- Logistics: tier 3 is a choice of what a harvester is good at.
	"convoy_protocols": {"name": "Convoy Protocols", "group": "logistics", "tier": 2, "requires": [], "cost": {"spice": 60}, "time": 85.0,
		"effects": {}, "desc": "Harvesters gain shields and armor equal to their hull."},
	"jump_drives": {"name": "Jump Drives", "group": "logistics", "tier": 3, "requires": ["fusion_drives"], "cost": {"spice": 240}, "time": 215.0,
		"effects": {"speed": 0.40, "upkeep": -0.10}, "desc": "+40% ship speed, -10% empire upkeep multiplier."},
	"mass_drivers": {"name": "Mass Drivers", "group": "logistics", "tier": 3, "requires": ["resonance_drills"], "cost": {"spice": 240}, "time": 215.0,
		"effects": {"harvest": 0.60}, "desc": "Harvesters gather 60% faster."},
	"logistics_command": {"name": "Logistics Command", "group": "logistics", "tier": 3, "requires": ["bulk_holds"], "cost": {"spice": 240}, "time": 225.0,
		"effects": {"harvest": 0.25, "cargo": 0.25}, "desc": "Harvesters gather 25% faster, carry +25% per load."},

	# --- Defense: the Deflectors line (id "deflectors"), soaking damage before the layers see it.
	"glance_plates": {"name": "Glance Plates", "group": "defense", "line": "deflectors", "tier": 1, "requires": [], "cost": {"spice": 40}, "time": 160.0,
		"effects": {"damage_taken": 0.06}, "desc": "-6% damage taken: ships and constructs."},
	"graviton_shunts": {"name": "Graviton Shunts", "group": "defense", "line": "deflectors", "tier": 2, "requires": ["glance_plates"], "cost": {"spice": 120}, "time": 240.0,
		"effects": {"damage_taken": 0.07}, "desc": "-7% damage taken: ships and constructs."},
	"iron_umbrella": {"name": "Iron Umbrella", "group": "defense", "line": "deflectors", "tier": 3, "requires": ["graviton_shunts"], "cost": {"spice": 360}, "time": 310.0,
		"effects": {"damage_taken": 0.10}, "desc": "-10% damage taken: ships and constructs."},

	# Hull line: the warship classes unlock one after the other.
	"depots": {"name": "Depots", "group": "constructs", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 60.0,
		"effects": {"unlock_depot": 1.0}, "desc": "Unlocks the Weapons Depot (variant refits)."},
	"carriers": {"name": "Carriers", "group": "warships", "tier": 2, "requires": ["cruisers"], "cost": {"spice": 90}, "time": 100.0,
		"effects": {"unlock_carrier": 1.0}, "desc": "Unlocks the Carrier."},
	"carrier_mk2": {"name": "Mk II Carrier", "group": "warships", "class": "carrier", "tier": 2, "requires": ["carriers"], "cost": {"spice": 30}, "time": 85.0,
		"effects": {"mark_carrier": 1.0}, "desc": "+12% damage, hull, armor and shields (of Mk I stats)."},
	"carrier_mk3": {"name": "Mk III Carrier", "group": "warships", "class": "carrier", "tier": 3, "requires": ["carrier_mk2"], "cost": {"spice": 95}, "time": 205.0,
		"effects": {"mark_carrier": 1.0}, "desc": "+25% damage, hull, armor and shields (of Mk I stats)."},
	"carrier_mk4": {"name": "Mk IV Carrier", "group": "warships", "class": "carrier", "tier": 3, "requires": ["carrier_mk3"], "cost": {"spice": 385}, "time": 260.0,
		"effects": {"mark_carrier": 1.0}, "desc": "+68% damage, hull, armor and shields (of Mk I stats)."},
	"destroyers": {"name": "Destroyers", "group": "warships", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 60.0,
		"effects": {"unlock_destroyer": 1.0}, "desc": "Unlocks the Destroyer."},
	"cruisers": {"name": "Cruisers", "group": "warships", "tier": 2, "requires": ["destroyers"], "cost": {"spice": 60}, "time": 80.0,
		"effects": {"unlock_cruiser": 1.0}, "desc": "Unlocks the Cruiser."},
	# Hull mark lines: one per warship class, three upgrades each (the class
	# starts Mk I). Each mark lifts only that class, so investing in
	# corvettes and investing in cruisers are different strategies.
	"corvette_mk2": {"name": "Mk II Corvette", "group": "warships", "class": "corvette", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 55.0,
		"effects": {"mark_corvette": 1.0}, "desc": "+7% damage, hull, armor and shields (of Mk I stats)."},
	"corvette_mk3": {"name": "Mk III Corvette", "group": "warships", "class": "corvette", "tier": 2, "requires": ["corvette_mk2"], "cost": {"spice": 60}, "time": 90.0,
		"effects": {"mark_corvette": 1.0}, "desc": "+15% damage, hull, armor and shields (of Mk I stats)."},
	"corvette_mk4": {"name": "Mk IV Corvette", "group": "warships", "class": "corvette", "tier": 3, "requires": ["corvette_mk3"], "cost": {"spice": 240}, "time": 235.0,
		"effects": {"mark_corvette": 1.0}, "desc": "+38% damage, hull, armor and shields (of Mk I stats)."},
	"destroyer_mk2": {"name": "Mk II Destroyer", "group": "warships", "class": "destroyer", "tier": 1, "requires": ["destroyers"], "cost": {"spice": 25}, "time": 65.0,
		"effects": {"mark_destroyer": 1.0}, "desc": "+8% damage, hull, armor and shields (of Mk I stats)."},
	"destroyer_mk3": {"name": "Mk III Destroyer", "group": "warships", "class": "destroyer", "tier": 2, "requires": ["destroyer_mk2"], "cost": {"spice": 70}, "time": 100.0,
		"effects": {"mark_destroyer": 1.0}, "desc": "+18% damage, hull, armor and shields (of Mk I stats)."},
	"destroyer_mk4": {"name": "Mk IV Destroyer", "group": "warships", "class": "destroyer", "tier": 3, "requires": ["destroyer_mk3"], "cost": {"spice": 275}, "time": 250.0,
		"effects": {"mark_destroyer": 1.0}, "desc": "+42% damage, hull, armor and shields (of Mk I stats)."},
	"cruiser_mk2": {"name": "Mk II Cruiser", "group": "warships", "class": "cruiser", "tier": 2, "requires": ["cruisers"], "cost": {"spice": 25}, "time": 80.0,
		"effects": {"mark_cruiser": 1.0}, "desc": "+10% damage, hull, armor and shields (of Mk I stats)."},
	"cruiser_mk3": {"name": "Mk III Cruiser", "group": "warships", "class": "cruiser", "tier": 3, "requires": ["cruiser_mk2"], "cost": {"spice": 80}, "time": 205.0,
		"effects": {"mark_cruiser": 1.0}, "desc": "+21% damage, hull, armor and shields (of Mk I stats)."},
	"cruiser_mk4": {"name": "Mk IV Cruiser", "group": "warships", "class": "cruiser", "tier": 3, "requires": ["cruiser_mk3"], "cost": {"spice": 325}, "time": 260.0,
		"effects": {"mark_cruiser": 1.0}, "desc": "+53% damage, hull, armor and shields (of Mk I stats)."},
	# Defense lines (research screen's Defenses tab): shields, armor, hull. Each
	# is three tiers of big, expensive upgrades for every ship and starbase,
	# so which layer to invest in is a real strategic choice.
	"phase_shields": {"name": "Phase Shields", "group": "defense", "line": "shields", "tier": 1, "requires": [], "cost": {"spice": 30}, "time": 120.0,
		"effects": {"shield_total": 0.07}, "desc": "+7% of total HP as shields on ships and constructs."},
	"crystal_prisms": {"name": "Crystal Prisms", "group": "defense", "line": "shields", "tier": 2, "requires": ["phase_shields"], "cost": {"spice": 90}, "time": 180.0,
		"effects": {"shield_total": 0.08}, "desc": "+8% of total HP as shields on ships and constructs."},
	"aegis_matrix": {"name": "Aegis Matrix", "group": "defense", "line": "shields", "tier": 3, "requires": ["crystal_prisms"], "cost": {"spice": 300}, "time": 260.0,
		"effects": {"shield_total": 0.15}, "desc": "+15% of total HP as shields on ships and constructs."},
	"composite_plating": {"name": "Composite Plating", "group": "defense", "line": "armor", "tier": 1, "requires": [], "cost": {"spice": 30}, "time": 120.0,
		"effects": {"armor_total": 0.07}, "desc": "+7% of total HP as armor: ships and constructs."},
	"reactive_armor": {"name": "Reactive Armor", "group": "defense", "line": "armor", "tier": 2, "requires": ["composite_plating"], "cost": {"spice": 90}, "time": 180.0,
		"effects": {"armor_total": 0.08}, "desc": "+8% of total HP as armor: ships and constructs."},
	"neutronium_armor": {"name": "Neutronium Armor", "group": "defense", "line": "armor", "tier": 3, "requires": ["reactive_armor"], "cost": {"spice": 300}, "time": 260.0,
		"effects": {"armor_total": 0.15}, "desc": "+15% of total HP as armor: ships and constructs."},
	"reinforced_frames": {"name": "Reinforced Frames", "group": "defense", "line": "hull", "tier": 1, "requires": [], "cost": {"spice": 30}, "time": 120.0,
		"effects": {"hull_total": 0.07}, "desc": "+7% of total HP as hull: ships and constructs."},
	"living_metals": {"name": "Living Metals", "group": "defense", "line": "hull", "tier": 2, "requires": ["reinforced_frames"], "cost": {"spice": 90}, "time": 180.0,
		"effects": {"hull_total": 0.08}, "desc": "+8% of total HP as hull: ships and constructs."},
	"adaptive_hulls": {"name": "Adaptive Hulls", "group": "defense", "line": "hull", "tier": 3, "requires": ["living_metals"], "cost": {"spice": 300}, "time": 260.0,
		"effects": {"hull_total": 0.15}, "desc": "+15% of total HP as hull: ships and constructs."},
	"solar_collectors": {"name": "Solar Collectors", "group": "worlds", "tier": 1, "requires": [], "cost": {"spice": 20}, "time": 45.0,
		"effects": {"energy": 0.15}, "desc": "+15% energy from Power Plants and Sail Arrays; the extra burns no fuel."},
	"plasma_reactors": {"name": "Plasma Reactors", "group": "worlds", "tier": 2, "requires": ["solar_collectors"], "cost": {"spice": 60}, "time": 80.0,
		"effects": {"energy": 0.25}, "desc": "+25% energy from Power Plants and Sail Arrays; the extra burns no fuel."},
	"dark_matter": {"name": "Dark Matter Reactors", "group": "worlds", "tier": 3, "requires": ["plasma_reactors"], "cost": {"spice": 240}, "time": 215.0,
		"effects": {"energy": 0.50}, "desc": "+50% energy from Power Plants and Sail Arrays; the extra burns no fuel."},
	"spice_navigation": {"name": "Spice Navigation", "group": "logistics", "tier": 3, "requires": ["gas_skimming", "convoy_protocols"], "requires_any": true, "requires_label": "Skimming or Convoy", "cost": {"spice": 240}, "time": 180.0,
		"effects": {}, "desc": "Ships resist 75% of nebula radiation."},
	# Mods (research screen's Mods tab): one per ship class at a time - a
	# row's three are exclusive (see Game._on_tech_done), and an active one
	# can be switched off and on for free (Game.mods_disabled). "mod" names
	# the class; "tier" is only the column on the tab. Equal costs per row are final (round-robin balanced).
	# The weapons themselves come next (docs/MODS.md).
	"mod_proton_torpedoes": {"name": "Proton Torpedoes", "group": "mods", "mod": "corvette", "tier": 1, "requires": [], "cost": {"spice": 50}, "time": 60.0,
		"effects": {"mod_corvette": 1.0}, "desc": "Heavy torpedoes; x2-4 vs big hulls."},
	"mod_kinetic_repeaters": {"name": "Kinetic Repeaters", "group": "mods", "mod": "corvette", "tier": 2, "requires": [], "cost": {"spice": 50}, "time": 60.0,
		"effects": {"mod_corvette": 1.0}, "desc": "3x fire rate, 46% damage per slug, -25% range."},
	"mod_arc_emitters": {"name": "Arc Emitters", "group": "mods", "mod": "corvette", "tier": 3, "requires": [], "cost": {"spice": 50}, "time": 60.0,
		"effects": {"mod_corvette": 1.0}, "desc": "Chains to 2 more enemies (74/26/26%)."},
	"mod_flak_cannons": {"name": "Flak Cannons", "group": "mods", "mod": "destroyer", "tier": 1, "requires": ["destroyers"], "cost": {"spice": 60}, "time": 75.0,
		"effects": {"mod_destroyer": 1.0}, "desc": "Shells burst, hitting all enemies within 20."},
	"mod_cluster_bombs": {"name": "Cluster Bombs", "group": "mods", "mod": "destroyer", "tier": 2, "requires": ["destroyers"], "cost": {"spice": 60}, "time": 75.0,
		"effects": {"mod_destroyer": 1.0}, "desc": "A spread of unguided bomblets."},
	"mod_homing_missiles": {"name": "Homing Missiles", "group": "mods", "mod": "destroyer", "tier": 3, "requires": ["destroyers"], "cost": {"spice": 60}, "time": 75.0,
		"effects": {"mod_destroyer": 1.0}, "desc": "4-missile homing volleys, +20% range."},
	"mod_ion_lance": {"name": "Ion Lance", "group": "mods", "mod": "cruiser", "tier": 1, "requires": ["cruisers"], "cost": {"spice": 70}, "time": 90.0,
		"effects": {"mod_cruiser": 1.0}, "desc": "Beam ramps up on one target; weak vs swarms."},
	"mod_rail_cannons": {"name": "Rail Cannons", "group": "mods", "mod": "cruiser", "tier": 2, "requires": ["cruisers"], "cost": {"spice": 70}, "time": 90.0,
		"effects": {"mod_cruiser": 1.0}, "desc": "+40% range, a heavy slug every 4 s: best vs big hulls."},
	"mod_point_defense_lattice": {"name": "Point-Defense Lattice", "group": "mods", "mod": "cruiser", "tier": 3, "requires": ["cruisers"], "cost": {"spice": 70}, "time": 90.0,
		"effects": {"mod_cruiser": 1.0}, "desc": "Needles shoot down ordnance, bouncing to 3 more; drones x2."},
	"mod_interceptor_drones": {"name": "Interceptor Drones", "group": "mods", "mod": "carrier", "tier": 1, "requires": ["carriers"], "cost": {"spice": 80}, "time": 105.0,
		"effects": {"mod_carrier": 1.0}, "desc": "4 drones attack enemies within 300."},
	"mod_tractor_beams": {"name": "Tractor Beams", "group": "mods", "mod": "carrier", "tier": 2, "requires": ["carriers"], "cost": {"spice": 80}, "time": 105.0,
		"effects": {"mod_carrier": 1.0}, "desc": "Each turret's beam pulls its target in."},
	"mod_missile_barrage": {"name": "Missile Barrage", "group": "mods", "mod": "carrier", "tier": 3, "requires": ["carriers"], "cost": {"spice": 80}, "time": 105.0,
		"effects": {"mod_carrier": 1.0}, "desc": "20-missile salvo every 8 s, longest range."},
}

static func tex(name: String) -> Texture2D:
	return load(PIXEL + name + ".png")

static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for r in RESOURCES:
		if cost.has(r):
			parts.append("%d %s" % [cost[r], RESOURCE_NAMES[r]])
	return ", ".join(parts)

## What each research group is for, shown under the tabs (HUD._build_research).
const TECH_GROUP_DESC := {
	"warships": "Unlock each warship class and raise its mark, Mk I through Mk IV. Every class is its own line.",
	"weapons": "Weapon output for everything you own, warship and starbase alike.",
	"defense": "The three damage layers (shields, armor, hull), plus deflectors, which soak a slice of every hit first. Pick a line and commit.",
	"constructs": "Starbases, depots and the other things you build rather than fly.",
	"worlds": "Feeding and growing your colonies: food, population and the cap on both.",
	"logistics": "Hauling, skimming and fleet movement: how fast cargo and ships get there.",
	"mods": "Change what a ship class fires. One Mod per class: researching another replaces it. Click an active Mod to switch it off.",
}

## Star types (set per system; see Star.set_type and SystemGen). core: glowing
## surface radius (px); zone: outer edge of the radiation zone; dps: damage per
## second on contact with the surface; tint: minimap / UI color.
const STAR_TYPES := {
	"red_dwarf": {"label": "Red Dwarf", "tex": "star_red", "core": 24.0, "zone": 130.0, "dps": 40.0, "tint": Color("ff6a4a")},
	"white": {"label": "White Star", "tex": "star_white", "core": 30.0, "zone": 165.0, "dps": 55.0, "tint": Color("e8eef8")},
	"yellow": {"label": "Yellow Star", "tex": "star", "core": 34.0, "zone": 180.0, "dps": 60.0, "tint": Color("ffb347")},
	"orange": {"label": "Orange Star", "tex": "star_orange", "core": 36.0, "zone": 195.0, "dps": 65.0, "tint": Color("ff8a2a")},
	"blue_giant": {"label": "Blue Giant", "tex": "star_blue", "core": 46.0, "zone": 260.0, "dps": 95.0, "tint": Color("7ab0ff")},
}

## Every buildable ship: the base designs plus their specialist variants
## (see VARIANTS), e.g. "disruptor_corvette".
static var SHIPS: Dictionary = _with_variants()

## Hull marks: every warship class starts Mk I and is upgraded a mark at
## a time by its own research line (Defs.TECHS, "mark_<class>" effects). Each
## mark makes that class alone tougher and harder-hitting, so late-game
## corvettes are a different animal from the ones built in minute one.
## A harvester fills its hold at "harvest" units a second while parked on a
## node, then hauls the load home. Spice and nebula gas fill at the same rate
## as ore (a Mining Barge 36/min on any rock, a Gas Skimmer 18/min on a gas
## giant or in a nebula); these stay as knobs.
const HARVEST_SPICE_MULT := 1.0
const HARVEST_NEBULA_MULT := 1.0

## Which classes have a mark line (see HULL_MARKS).
const MARK_LINES := ["corvette", "destroyer", "cruiser", "carrier"]

## The glass hold cut into each harvester's hull (see _cargo_tank in
## tools/gen_art.gd), as a rect in the ship's own space: x from the stern
## end to the bow end, then half-height. The game paints the load inside it,
## so these must match the art.
const CARGO_TANK := {
	"miner": [-4.0, 1.5, 2.2],
	"skimmer": [-6.0, 0.0, 2.2],
}

## A mark is rank, not shape. Each class is built in one letterform for life
## (see CLASS_SHAPE in tools/gen_art.gd): a corvette is an A, a destroyer a
## Y, a cruiser an X, a carrier an H. Research refines a ship within that
## shape, and shows as chevrons at the nose. A ship starts at Mk I and works
## up to Mk IV, the finest of its line.
const HULL_MARKS := ["Mk I", "Mk II", "Mk III", "Mk IV"]
## What one mark adds to its class, per step.
## Hull marks: the total bonus to damage, hull, armor and shields at Mk I-IV,
## per class. Each step grows with the mark and with the class: Mk II
## corvette is the smallest (+7%), Mk IV carrier the largest (+68%).
const MARK_BONUS := {
	"corvette": [0.0, 0.07, 0.22, 0.60],
	"destroyer": [0.0, 0.08, 0.26, 0.68],
	"cruiser": [0.0, 0.10, 0.31, 0.84],
	"carrier": [0.0, 0.12, 0.37, 1.05],
}

## Multiplier a ship type gets at mark `level` (0 = Mk I).
static func mark_mult(ship_type: String, level: int) -> float:
	var cls: String = SHIPS.get(ship_type, {}).get("base", ship_type)
	var b: Array = MARK_BONUS.get(cls, [0.0])
	return 1.0 + float(b[clampi(level, 0, b.size() - 1)])

## The mark name for a class at `level` (0 = Mk I), e.g. "Mk II Corvette".
static func marked_name(ship_type: String, level: int) -> String:
	var d: Dictionary = SHIPS.get(ship_type, {})
	if d.is_empty() or not MARK_LINES.has(d.get("base", ship_type)):
		return d.get("name", ship_type)
	return "%s %s" % [HULL_MARKS[clampi(level, 0, HULL_MARKS.size() - 1)], d["name"]]

## Damage vs the defense layers. Generalists deal their full base damage to
## shields, armor and hull alike. Specialists are variants of a generalist:
##   bonus  - 80% base damage, x2.5-3.0 against one layer (x2.2 for hull, the
##            biggest layer on most ships)
##   pierce - skip layers entirely: 2 = shields and armor (Disruptor, 35% base
##            damage)
##   emp    - Inhibitor (80% base damage): hits switch the target's shields
##            off for Abilities.EMP_TIME (see Abilities.emp_try)
## All variants cost the same as their generalist. Balance: vs the
## generalists' distinct profiles (corvette hull-heavy, destroyer
## shield-heavy, cruiser armor-heavy) each specialist kills its favored
## targets 7-18% faster and the others 5-46% slower (see tools notes).
## color: the variant's markings and shot color.
## Radiation Sail Array bubble radius: 80% of the size that held three
## carriers (140).
const SAIL_RADIUS := 112.0
## Share of a solar shield's maximum that each energy harvested recharges.
const SAIL_SHIELD_FRAC_PER_ENERGY := 0.10

## Mark chevrons on a ship that has no variant.
const GENERALIST_COLOR := Color("fff06a")

const VARIANTS := {
	"plasma": {"label": "Plasma", "vs": {"shield": 3.0}, "pierce": 0, "damage": 0.79, "cost": 1.0, "color": Color("7fd8ff"),
		"desc": "79% base damage, x3.0 against shields."},
	"breacher": {"label": "Breacher", "vs": {"armor": 2.5}, "pierce": 0, "damage": 0.81, "cost": 1.0, "color": Color("ff4a4a"),
		"desc": "81% base damage, x2.5 against armor."},
	"reaver": {"label": "Ravager", "vs": {"hull": 2.2}, "pierce": 0, "damage": 0.83, "cost": 1.0, "color": Color("58e07a"),
		"desc": "83% base damage, x2.2 against hull."},
	"disruptor": {"label": "Disruptor", "vs": {}, "pierce": 2, "damage": 0.36, "cost": 1.0, "color": Color("ff7a14"),
		"desc": "Shots skip shields and armor and hit the hull, at 36% base damage."},
	"inhibitor": {"label": "Inhibitor", "vs": {}, "pierce": 0, "damage": 0.83, "emp": true, "cost": 1.0, "color": Color("b06cff"),
		"desc": "83% base damage. Each hit EMPs the target: its shields go down for 5 s (they block nothing and don't recharge), then come back at the value they had. A ship can EMP once per 4 s divided by its gun count (corvette 4 s, carrier 1 s)."},
}
## Which variants each generalist has so far.
const VARIANTS_OF := {
	"corvette": ["plasma", "breacher", "reaver", "disruptor", "inhibitor"],
	"destroyer": ["plasma", "breacher", "reaver", "disruptor", "inhibitor"],
	"cruiser": ["plasma", "breacher", "reaver", "disruptor", "inhibitor"],
	"carrier": ["plasma", "breacher", "reaver", "disruptor", "inhibitor"],
}

static func _with_variants() -> Dictionary:
	var out := BASE_SHIPS.duplicate(true)
	for base in VARIANTS_OF:
		for v in VARIANTS_OF[base]:
			var vd: Dictionary = VARIANTS[v]
			var d: Dictionary = BASE_SHIPS[base].duplicate(true)
			d["name"] = "%s %s" % [vd["label"], d["name"]]
			d["variant"] = v
			d["base"] = base
			d.erase("hotkey")
			d["damage"] = d["damage"] * vd["damage"]
			for r in d["cost"]:
				d["cost"][r] = int(round(d["cost"][r] * vd["cost"]))
			out["%s_%s" % [v, base]] = d
	return out

## A ship def's damage profile: {"vs": layer multipliers, "pierce": 0-2}.
## Blast radius of every exploding shot: each deals AOE_SHARE (all) of its damage
## to every enemy within the radius, the target included.
const AOE_RADIUS := {"flak": 20.0, "missile": 25.0, "proton": 30.0, "torpedo": 30.0, "bomblet": 25.0}
const AOE_SHARE := 1.0

## How a Mod (Game.active_mod) changes its class's weapon. dmg / cd / range
## multiply damage per shot, cooldown and range; same damage per second as the
## laser unless noted (docs/MODS.md).
##   weapon - what is fired (Projectile / Game.arc_strike)
##   chain  - Arc: shares of the damage for the target, then each extra jump
const MOD_WEAPONS := {
	# Tuned (10% steps) to lose slightly to laser corvettes, then hit bigger
	# hulls harder: vs_class multiplies damage against those classes.
	"mod_proton_torpedoes": {"weapon": "proton", "dmg": 0.75, "vs_class": {"destroyer": 2.0, "cruiser": 3.0, "carrier": 4.0, "starbase": 4.0, "world": 4.0, "construct": 2.0}, "cd": 3.093},
	"mod_kinetic_repeaters": {"weapon": "kinetic", "dmg": 0.46, "cd": 0.3436, "range": 0.75},
	"mod_arc_emitters": {"weapon": "arc", "cd": 1.031, "chain": [0.74, 0.26, 0.26], "jump": 120.0},
	#   count  - projectiles per turret shot; spread - their fan, radians;
	#   fan    - [min, max] total fan width in degrees, rolled fresh each launch
	#   beam   - Ion Lance: [start, end, seconds] - a continuous beam whose damage
	#            ramps from start to end x the laser's over that long on one target
	#   pd     - Point-Defense: radius in which each turret shoots down enemy
	#            missiles, torpedoes and bomblets before firing at ships
	#   drones - Interceptor Drones: [count, reach from the carrier]
	#   tractor- Tractor Beams: [pull/s, reach x weapon range, damage at full reach, damage once pulled in to 52% of range]
	# Exploding shots (flak, missile, proton, bomblet) hit every enemy within
	# AOE_RADIUS[weapon] for AOE_SHARE of the damage (see Game.splash).
	"mod_flak_cannons": {"dmg": 0.67, "cd": 1.030, "weapon": "flak"},
	# Each bomblet = one laser shot: 3 per turret every 3 reloads = lasers'
	# total on a lone ship; the 40 blasts make it far more against a group.
	"mod_cluster_bombs": {"dmg": 0.45, "weapon": "bomblet", "cd": 3.092, "count": 3, "fan": [10.0, 20.0]},
	"mod_ion_lance": {"weapon": "beam", "dmg": 0.58, "beam": [0.15, 1.85, 4.0]},
	"mod_rail_cannons": {"weapon": "rail", "dmg": 3.6, "cd": 4.0, "range": 1.4},
	# pd: shoots down ordnance within 220 first, then enemy drones in weapon
	# range (x2 damage to them, Ship.PD_DRONE_MULT), then ships.
	"mod_point_defense_lattice": {"dmg": 0.91, "pd": 220.0},
	"mod_homing_missiles": {"weapon": "missile", "cd": 2.577, "dmg": 0.54, "count": 2, "range": 1.2},
	# Carrier. drones: [count, reach from the carrier]; the turrets stand down
	# and the drones fly out and shoot instead (vs_class: weak vs heavy armor).
	"mod_interceptor_drones": {"drones": [4, 300.0], "dmg": 2.45, "vs_class": {"destroyer": 0.7, "cruiser": 0.6, "carrier": 0.5}},
	# No lasers: each turret holds a beam that pulls and burns at dmg x a laser's DPS
	# x a factor: [pull/s, reach x range, factor at full reach, factor once pulled in].
	"mod_tractor_beams": {"tractor": [60.0, 2.0, 0.5, 1.5], "dmg": 0.51},
	"mod_missile_barrage": {"weapon": "missile", "dmg": 0.27, "count": 5, "cd": 8.0, "range": 1.6, "spread": 0.5},
}

static func damage_profile(d: Dictionary) -> Dictionary:
	if not d.has("variant"):
		return {"vs": {}, "pierce": 0}
	var v: Dictionary = VARIANTS[d["variant"]]
	return {"vs": v["vs"], "pierce": v["pierce"], "emp": v.get("emp", false)}

## Ship jobs (see Abilities): what each ship is good at. Passive jobs always
## work; active ones are triggered with Q (or the ship panel's button) and
## then need `cooldown` seconds; `duration` is how long an active effect
## lasts. `color` is the job's accent (sprites and effects share it).
const JOBS := {
	"beacon": {"name": "Deep Sensors", "active": true, "cooldown": 45.0, "duration": 90.0, "color": Color("7fe8ff"),
		"desc": "Sees far, into spice nebulae and through ion storms. [Q] Drop a sensor beacon that watches the spot for 90 s."},
	"radiation_sail": {"name": "Radiation Sail", "active": false, "color": Color("c9a0ff"),
		"desc": "In Radiation (a star's zone or a spice nebula), harvests 15 energy a minute: first into a solar shield (100; 1 energy charges 10% of it; starts full, charges even under fire), the rest to your energy pool. The shield is a bubble nearly two carriers wide. It soaks enemy fire on every friendly ship, construct and world inside, and blocks Radiation for everything inside, friend or foe. Touching bubbles merge into one pooled mega shield."},
	"field_repair": {"name": "Field Repair", "active": true, "cooldown": 60.0, "color": Color("6fe07a"),
		"desc": "Repairs up to 4 ships within 180 px (5 points/s each: hull first, then armor; only tenders restore armor) once out of combat. [Q] Emergency repair: +35% of hull and armor to ships within 200 px."},
}

## Visual language for the defense layers: bars, research lines, and the
## lasers of specialists that hit a layer harder all use these colors.
const LAYER_COLORS := {"shield": Color("7fd8ff"), "armor": Color("ff4a4a"), "hull": Color("58e07a")}
## Generalists (and starbases) fire yellow lasers.
const GENERALIST_SHOT := GENERALIST_COLOR

## Base damage a ship with `variant` ("" = generalist) needs to destroy a
## target with these defenses — the same layer maths as
## SpaceEntity.take_damage. The Codex uses it for its matchup table, so the
## numbers always follow the current stats.
static func kill_cost(shield: float, armor_v: float, hull: float, variant: String) -> float:
	var vd: Dictionary = VARIANTS.get(variant, {"vs": {}, "pierce": 0, "damage": 1.0})
	var vs: Dictionary = vd["vs"]
	var need := hull / float(vs.get("hull", 1.0))
	# Inhibitor: after its first hit the EMP keeps the shields off, so (as an
	# approximation) its fire goes to armor and hull as if shields were skipped.
	var pr := int(vd["pierce"])
	if vd.get("emp", false):
		pr = maxi(pr, 1)
	if pr < 2:
		need += armor_v / float(vs.get("armor", 1.0))
	if pr < 1:
		need += shield / float(vs.get("shield", 1.0))
	return need / float(vd["damage"])

## kill_cost relative to a generalist attacking the same target (1.0 = the
## same, below 1.0 = kills faster).
static func kill_ratio(target: Dictionary, variant: String) -> float:
	var s: float = target.get("shield", 0.0)
	var a: float = target.get("armor", 0.0)
	var h: float = target.get("hp", 1.0)
	return kill_cost(s, a, h, variant) / maxf(kill_cost(s, a, h, ""), 0.001)

## Rebindable controls (Options > Hotkeys). Panel keys 1-12 are the grid the
## selection panel's buttons use, in order: Q W E / A S D / Z X C / V B N.
## The player's own bindings live in GameState.hotkeys; key_for() reads them.
const HOTKEYS := [
	["panel1", "Panel button 1", KEY_Q], ["panel2", "Panel button 2", KEY_W], ["panel3", "Panel button 3", KEY_E],
	["panel4", "Panel button 4", KEY_A], ["panel5", "Panel button 5", KEY_S], ["panel6", "Panel button 6", KEY_D],
	["panel7", "Panel button 7", KEY_Z], ["panel8", "Panel button 8", KEY_X], ["panel9", "Panel button 9", KEY_C],
	["panel10", "Panel button 10", KEY_V], ["panel11", "Panel button 11", KEY_G], ["panel12", "Panel button 12", KEY_H],
	["stop", "Stop", KEY_T], ["warships", "Select all warships", KEY_TAB], ["corvettes", "Select all corvettes", KEY_QUOTELEFT], ["home", "Go to starbase", KEY_B],
	["next_world", "Next world", KEY_SPACE], ["build_here", "Build on this world", KEY_F], ["research", "Research", KEY_R],
	["pause", "Pause / play", KEY_P], ["speed_down", "Slower", KEY_MINUS], ["speed_up", "Faster", KEY_EQUAL],
	["speed_normal", "Normal speed", KEY_BACKSPACE],
]

static func default_hotkeys() -> Dictionary:
	var out := {}
	for h in HOTKEYS:
		out[h[0]] = h[2]
	return out

## The key bound to an action id, falling back to its default.
static func key_for(id: String) -> Key:
	var v = GameState.hotkeys.get(id, null)
	if v == null:
		for h in HOTKEYS:
			if h[0] == id:
				return h[2]
		return KEY_NONE
	# Pause used to default to the Pause/Break key, missing on most laptops;
	# a binding saved with that old default moves to P.
	if id == "pause" and int(v) == KEY_PAUSE:
		return KEY_P
	return v as Key

## Which action a pressed key runs ("" if none).
static func action_for_key(k: Key) -> String:
	for h in HOTKEYS:
		if key_for(h[0]) == k:
			return h[0]
	return ""

## The def for anything a Constructor builds ("starbase", "depot", "station",
## "outpost", "gate").
static func construct_def(kind: String) -> Dictionary:
	match kind:
		"depot": return WEAPONS_DEPOT
		"station": return MINING_STATION
		"outpost": return FRONTIER_OUTPOST
		"gate": return WARP_GATE
		_: return STARBASE

## How much open space this construct needs around itself (see PLACEMENT_RING).
static func placement_ring(kind: String) -> float:
	return float(construct_def(kind)["radius"]) * PLACEMENT_RING
