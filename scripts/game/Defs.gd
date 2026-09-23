class_name Defs
## Static data for Star Lords: resources, ship classes, stations, planet
## types, and the tech tree. Ranges/speeds are in world pixels.
##
## Economy rules (see Game.pay_over_time): ship/starbase construction and
## research costs are paid gradually over their build/research time.
## Progress only advances while the resources are there; any shortfall in
## food, minerals or energy is covered 1:1 from spice automatically.

const PIXEL := "res://assets/pixel/"

const RESOURCES: Array[String] = ["food", "minerals", "energy", "spice"]
const RESOURCE_NAMES := {"food": "Food", "minerals": "Minerals", "energy": "Energy", "spice": "Spice"}
const RESOURCE_COLORS := {"food": Color("8fe060"), "minerals": Color("3fd6b0"), "energy": Color("ffd46b"), "spice": Color("ff9a2e")}

const START := {"food": 75.0, "minerals": 300.0, "energy": 250.0, "spice": 50.0}

const TEAM_COLORS: Array[Color] = [
	Color("9aa0b0"), # 0: neutral
	Color("4fb4ff"), Color("ff4f5e"), Color("ffc93d"), Color("6fe07a"),
	Color("c77dff"), Color("ff8c3a"), Color("3de0d0"), Color("f2f2f2"),
]

static func team_color(owner_id: int) -> Color:
	return TEAM_COLORS[clampi(owner_id, 0, TEAM_COLORS.size() - 1)]

## role: miner / warship / colony / constructor.
## cost is the total, paid over build_time. upkeep is energy per second.
## requires: tech id that must be researched before it can be queued.
const BASE_SHIPS := {
	"miner": {
		"name": "Mining Barge", "role": "miner",
		"hp": 70.0, "shield": 0.0, "speed": 70.0, "radius": 8.0,
		"cost": {"minerals": 50}, "build_time": 6.0, "upkeep": 0.05,
		"cargo": 10, "harvest": 0.6,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"skimmer": {
		"name": "Gas Skimmer", "role": "skimmer", "requires": "gas_skimming",
		"hp": 90.0, "shield": 20.0, "speed": 65.0, "radius": 9.0,
		"cost": {"minerals": 90, "spice": 10}, "build_time": 12.0, "upkeep": 0.1,
		"cargo": 20, "harvest": 0.3,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"colony": {
		"name": "Colony Ship", "role": "colony",
		"hp": 100.0, "armor": 20.0, "shield": 20.0, "speed": 60.0, "radius": 9.0,
		"cost": {"minerals": 80, "spice": 10}, "build_time": 15.0, "upkeep": 0.1,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"constructor": {
		"name": "Constructor", "role": "constructor",
		"hp": 110.0, "armor": 40.0, "shield": 20.0, "speed": 65.0, "radius": 9.0,
		"cost": {"minerals": 120, "spice": 5}, "build_time": 12.0, "upkeep": 0.1,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"corvette": {
		"name": "Corvette", "role": "warship",
		"hp": 70.0, "armor": 20.0, "shield": 30.0, "speed": 125.0, "radius": 8.0,
		"cost": {"minerals": 75}, "build_time": 14.0, "upkeep": 0.1,
		"weapon": "laser", "damage": 5.0, "cooldown": 0.55, "range": 140.0, "sensor": 280.0, "job": "swarm", "refit": {"minerals": 5, "time": 15.0},
	},
	"destroyer": {
		"name": "Destroyer", "role": "warship", "requires": "destroyers",
		"hp": 120.0, "armor": 40.0, "shield": 140.0, "speed": 85.0, "radius": 11.0,
		"cost": {"minerals": 170, "spice": 5}, "build_time": 17.0, "upkeep": 0.25,
		"weapon": "laser", "damage": 13.0, "cooldown": 0.9, "range": 190.0, "sensor": 330.0, "job": "escort", "refit": {"minerals": 10, "time": 25.0},
	},
	"cruiser": {
		"name": "Cruiser", "role": "warship", "requires": "cruisers",
		"hp": 250.0, "armor": 360.0, "shield": 150.0, "speed": 55.0, "radius": 16.0,
		"cost": {"minerals": 350, "spice": 25}, "build_time": 28.0, "upkeep": 0.6,
		"weapon": "torpedo", "damage": 42.0, "cooldown": 2.2, "range": 260.0, "sensor": 420.0, "refit": {"minerals": 15, "time": 35.0},
	},
	"scout": {
		"name": "Scout", "role": "scout",
		"hp": 50.0, "shield": 10.0, "speed": 155.0, "radius": 7.0,
		"cost": {"minerals": 45}, "build_time": 6.0, "upkeep": 0.05,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0, "sensor": 600.0, "job": "beacon",
	},
	"heatshield": {
		"name": "Heat Shield Frigate", "role": "warship", "requires": "deflectors",
		"hp": 130.0, "armor": 70.0, "shield": 140.0, "speed": 80.0, "radius": 11.0,
		"cost": {"minerals": 110, "spice": 10}, "build_time": 14.0, "upkeep": 0.2,
		"weapon": "laser", "damage": 5.0, "cooldown": 0.8, "range": 150.0, "sensor": 300.0, "job": "heat_screen",
	},
	"tender": {
		"name": "Repair Tender", "role": "support", "requires": "reinforced_frames",
		"hp": 150.0, "armor": 90.0, "shield": 60.0, "speed": 75.0, "radius": 11.0,
		"cost": {"minerals": 130, "spice": 10}, "build_time": 16.0, "upkeep": 0.25,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0, "sensor": 300.0, "job": "field_repair",
	},
}

## Starbase build menu order (and G/J/K etc. hotkey lookup): economy,
## support, generalist warships. Specialist variants aren't built here: a
## generalist is refitted into one at a Weapons Depot (WEAPONS_DEPOT).
const BUILD_ORDER: Array[String] = ["miner", "skimmer", "colony", "constructor", "scout", "tender",
	"corvette", "destroyer", "cruiser", "heatshield"]

## Weapons Depot: built by a Constructor like a starbase (paid over
## build_time). Each depot is built for ONE variant (Defs.VARIANTS) and refits
## generalists into it: a Plasma Depot makes Plasma ships, a Slip Depot Slip ships.
## Ships fly in, dock (CAPACITY at a time, hidden and safe inside) and are
## refitted automatically as minerals allow; each hull has its own refit cost
## and time (see SHIPS "refit"). A specialist can never be refitted again.
## Doesn't count as a starbase (losing it doesn't lose the match).
const WEAPONS_DEPOT := {
	"name": "Weapons Depot", "requires": "depots", "hp": 900.0, "armor": 400.0, "shield": 300.0, "radius": 22.0,
	"cost": {"minerals": 250, "spice": 20}, "build_time": 30.0, "upkeep": 0.3,
	"capacity": 10, "min_spacing": 250.0,
}

const STARBASE := {
	"name": "Starbase", "hp": 4000.0, "armor": 2000.0, "shield": 2000.0, "radius": 26.0,
	"weapon": "laser", "damage": 34.0, "cooldown": 0.6, "range": 260.0,
	# Built on site by a Constructor, paid over build_time.
	"cost": {"minerals": 400, "spice": 20}, "build_time": 40.0,
	"upkeep": 0.5,
	# Station reactors and ore refineries.
	"energy_per_sec": 2.0, "minerals_per_sec": 0.5,
	"min_spacing": 500.0,
}

## Asteroid reserves scale with rock size: amount = width_px^2 * this.
## Small 16px rock ~410 minerals, large 26px ~1080; spice rocks are scarcer.
const ASTEROID_MINERALS_PER_PX2 := 1.6
const ASTEROID_SPICE_PER_PX2 := 0.5

## No hard fleet cap: each ship's energy upkeep is multiplied by
## 1 + (ship_count / UPKEEP_SCALE_SHIPS)^2, so total upkeep climbs steeply and
## fleets plateau (around 200 ships on a strong late-game economy).
const UPKEEP_SCALE_SHIPS := 100.0
## Starbases scale separately and more steeply: each one's upkeep is
## multiplied by 1 + (starbases / STARBASE_UPKEEP_SCALE)^3, so ~10 is
## sustainable and going past it gets very expensive fast (x9 at 10, x28 at 15).
const STARBASE_UPKEEP_SCALE := 5.0
## With no energy in the stockpile, ships move and fire at this fraction of
## normal speed, and starbases can't produce ships.
const ENERGY_STARVED_FACTOR := 0.25

## Planet types. A planet's size = its number of fields, and its base
## population cap is size * POP_PER_SIZE (a size 19 world: 19 fields, 19k pops).
## fertility is informational for now (farms produce a flat amount).
## spice_reserve: spice stored underground for Spice Extractors. Barren
## worlds hold the most (desert above all); lush worlds very little.
## energy: base energy/sec once colonized. spice: spice/sec once colonized.
const PLANET_TYPES := {
	"planet_terran": {"label": "Terran", "fertility": 1.0, "energy": 0.0, "spice": 0.0, "spice_reserve": 200},
	"planet_desert": {"label": "Desert", "fertility": 0.45, "energy": 0.0, "spice": 0.0, "spice_reserve": 5000},
	"planet_ice": {"label": "Arctic", "fertility": 0.6, "energy": 0.0, "spice": 0.0, "spice_reserve": 1200},
	"planet_lava": {"label": "Molten", "fertility": 0.15, "energy": 0.0, "spice": 0.08, "spice_reserve": 2000},
	"planet_gas": {"label": "Gas Giant", "habitable": false, "gas_reserve": 8000, "fertility": 0.0, "energy": 0.0, "spice": 0.0},
	"planet_moon": {"label": "Barren Moon", "fertility": 0.2, "energy": 0.0, "spice": 0.0, "spice_reserve": 3000},
}
const POP_PER_SIZE := 1000
const START_POP := 100.0
## Worlds owned at match start (home planets) begin with this many pops,
## enough to staff their starting Farm and Power Plant.
const HOME_START_POP := 200.0
## 1 new pop per minute for every 2 pop (a "pop pair").
const GROWTH_PER_PAIR_PER_MIN := 1.0
## Every pop eats FOOD_PER_POP_PER_MIN food a minute, from food or,
## failing that, spice. One Farm feeds 2,000 pops.
const FOOD_PER_POP_PER_MIN := 0.15
## A shortage ends only once the world has been fed continuously for this
## long; until then it neither grows nor stops losing pops.
const REGROW_SECONDS := 5.0
## Food comes only from Farms (see BUILDINGS), scaled by planet fertility.
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
## ships. output: food per MINUTE; energy/minerals/spice per SECOND.
## only: planet kinds it can be built on (empty = any).
const BUILDINGS := {
	"farm": {"name": "Farm", "pop": 100, "cost": {"minerals": 60}, "time": 30.0, "output": {"food": 300.0}, "only": [],
		"desc": "+300 food/min (5/s): feeds 2,000 pops (boosted by Hydroponics). Needs 100 pop."},
	"generator": {"name": "Power Plant", "pop": 100, "cost": {"minerals": 80}, "time": 30.0, "output": {"energy": 3.0}, "only": [],
		"desc": "+3 energy/s. Needs 100 pop."},
	"mine": {"name": "Mining Complex", "pop": 100, "cost": {"minerals": 70}, "time": 35.0, "output": {"minerals": 1.8}, "only": [],
		"desc": "+1.8 minerals/s. Needs 100 pop."},
	"habitat": {"name": "Habitat", "pop": 0, "cost": {"minerals": 100, "spice": 5}, "time": 40.0, "output": {}, "max_pop": 1500, "only": [],
		"desc": "+1,500 population cap. Needs no staff."},
	"battery": {"name": "Defense Battery", "pop": 100, "cost": {"minerals": 120, "spice": 10}, "time": 45.0, "output": {}, "only": [],
		"desc": "+1,200 planetary shield and a gun that fires on besieging ships (250 px). Needs 100 pop."},
	"spice_extractor": {"name": "Spice Extractor", "pop": 200, "cost": {"minerals": 150, "spice": 30}, "time": 60.0, "output": {"spice": 0.6}, "only": [],
		"desc": "+0.6 spice/s from the planet's spice reserve (large on barren worlds, tiny on lush ones). Needs 200 pop."},
}
const BUILDING_ORDER: Array[String] = ["farm", "generator", "mine", "habitat", "spice_extractor", "battery"]
## Defense Battery: shield added per battery, and its gun.
const BATTERY_SHIELD := 1200.0
const BATTERY := {"weapon": "laser", "damage": 18.0, "cooldown": 1.2, "range": 250.0}
## Buildings only operate with enough pop on the planet ("pop" above).
## Pop is assigned automatically in this order of output.
const STAFFING_PRIORITY: Array[String] = ["food", "energy", "minerals", "spice"]

const SHIELD_REGEN_DELAY := 4.0
const SHIELD_REGEN_PER_SEC := 0.08 # fraction of max shield
## Energy spent per shield point regenerated (spice covers shortfalls).
const SHIELD_ENERGY_PER_POINT := 0.05

## Tech tree. tier sets the column in the tree view; requires lists
## prerequisite techs (all needed). effects are multiplier bonuses summed
## per key (e.g. "damage": 0.2 = +20%); "unlock" names are flags.
const TECHS := {
	"ion_cannons": {"name": "Ion Cannons", "group": "weapons", "tier": 1, "requires": [], "cost": {"energy": 600}, "time": 60.0,
		"effects": {"damage": 0.20}, "desc": "+20% weapon damage."},
	"hydroponics": {"name": "Hydroponics", "group": "worlds", "tier": 1, "requires": [], "cost": {"energy": 400}, "time": 40.0,
		"effects": {"food": 0.30}, "desc": "+30% food production."},
	"deep_drills": {"name": "Deep-Core Drills", "group": "logistics", "tier": 1, "requires": [], "cost": {"energy": 400}, "time": 40.0,
		"effects": {"cargo": 0.40}, "desc": "Harvesters carry +40% per load."},
	"bulk_holds": {"name": "Bulk Holds", "group": "logistics", "tier": 2, "requires": ["deep_drills"], "cost": {"energy": 1100, "spice": 20}, "time": 75.0,
		"effects": {"cargo": 0.50}, "desc": "Harvesters carry a further +50% per load."},
	"cutting_lasers": {"name": "Cutting Lasers", "group": "logistics", "tier": 1, "requires": [], "cost": {"energy": 500}, "time": 45.0,
		"effects": {"harvest": 0.30}, "desc": "+30% gather rate at every node."},
	"resonance_drills": {"name": "Resonance Drills", "group": "logistics", "tier": 2, "requires": ["cutting_lasers"], "cost": {"energy": 1200, "spice": 20}, "time": 80.0,
		"effects": {"harvest": 0.40}, "desc": "A further +40% gather rate at every node."},
	"fusion_drives": {"name": "Fusion Drives", "group": "logistics", "tier": 2, "requires": ["ion_thrusters"], "cost": {"energy": 1300, "spice": 25}, "time": 85.0,
		"effects": {"speed": 0.25}, "desc": "A further +25% ship speed."},
	"gas_skimming": {"name": "Gas Skimming", "group": "logistics", "tier": 1, "requires": [], "cost": {"energy": 500}, "time": 50.0,
		"effects": {}, "desc": "Unlocks the Gas Skimmer, which mines minerals from gas giants."},
	"particle_lances": {"name": "Particle Lances", "group": "weapons", "tier": 2, "requires": ["ion_cannons"], "cost": {"energy": 1200, "spice": 30}, "time": 90.0,
		"effects": {"damage": 0.25}, "desc": "+25% weapon damage."},
	"ion_thrusters": {"name": "Ion Thrusters", "group": "logistics", "tier": 1, "requires": [], "cost": {"energy": 700}, "time": 60.0,
		"effects": {"speed": 0.15}, "desc": "+15% ship speed."},
	"gene_clinics": {"name": "Gene Clinics", "group": "worlds", "tier": 2, "requires": ["hydroponics"], "cost": {"energy": 900, "spice": 20}, "time": 75.0,
		"effects": {"growth": 0.50}, "desc": "+50% population growth."},
	"arcologies": {"name": "Arcologies", "group": "worlds", "tier": 2, "requires": ["hydroponics"], "cost": {"energy": 1000, "spice": 20}, "time": 80.0,
		"effects": {"max_pop": 0.30}, "desc": "+30% planet population cap."},
	# Hull line: the warship classes unlock one after the other.
	"depots": {"name": "Depots", "group": "constructs", "tier": 1, "requires": [], "cost": {"energy": 700, "spice": 10}, "time": 60.0,
		"effects": {"unlock_depot": 1.0}, "desc": "Unlocks the Weapons Depot: Plasma, Breacher, Reaver, Slip and Disruptor."},
	"destroyers": {"name": "Destroyers", "group": "warships", "tier": 1, "requires": [], "cost": {"energy": 500}, "time": 45.0,
		"effects": {"unlock_destroyer": 1.0}, "desc": "Unlocks the Destroyer."},
	"cruisers": {"name": "Cruisers", "group": "warships", "tier": 2, "requires": ["destroyers"], "cost": {"energy": 1200, "spice": 30}, "time": 85.0,
		"effects": {"unlock_cruiser": 1.0}, "desc": "Unlocks the Cruiser."},
	# Hull mark lines: one per warship class, three upgrades each (the class
	# starts as a Wisp). Each mark lifts only that class, so investing in
	# corvettes and investing in cruisers are different strategies.
	"corvette_mk2": {"name": "Specter Corvette", "group": "warships", "class": "corvette", "tier": 1, "requires": [], "cost": {"energy": 600}, "time": 55.0,
		"effects": {"mark_corvette": 1.0}, "desc": "Corvettes become Specters: +18% damage, +15% shields, armor and hull."},
	"corvette_mk3": {"name": "Wraith Corvette", "group": "warships", "class": "corvette", "tier": 2, "requires": ["corvette_mk2"], "cost": {"energy": 1400, "spice": 25}, "time": 90.0,
		"effects": {"mark_corvette": 1.0}, "desc": "Corvettes become Wraiths: another +18% damage, +15% shields, armor and hull."},
	"corvette_mk4": {"name": "Phantom Corvette", "group": "warships", "class": "corvette", "tier": 3, "requires": ["corvette_mk3"], "cost": {"energy": 2600, "spice": 70}, "time": 130.0,
		"effects": {"mark_corvette": 1.0}, "desc": "Corvettes become Phantoms: a third +18% damage, +15% shields, armor and hull."},
	"destroyer_mk2": {"name": "Specter Destroyer", "group": "warships", "class": "destroyer", "tier": 1, "requires": ["destroyers"], "cost": {"energy": 900}, "time": 65.0,
		"effects": {"mark_destroyer": 1.0}, "desc": "Destroyers become Specters: +18% damage, +15% shields, armor and hull."},
	"destroyer_mk3": {"name": "Wraith Destroyer", "group": "warships", "class": "destroyer", "tier": 2, "requires": ["destroyer_mk2"], "cost": {"energy": 1800, "spice": 35}, "time": 100.0,
		"effects": {"mark_destroyer": 1.0}, "desc": "Destroyers become Wraiths: another +18% damage, +15% shields, armor and hull."},
	"destroyer_mk4": {"name": "Phantom Destroyer", "group": "warships", "class": "destroyer", "tier": 3, "requires": ["destroyer_mk3"], "cost": {"energy": 3200, "spice": 90}, "time": 140.0,
		"effects": {"mark_destroyer": 1.0}, "desc": "Destroyers become Phantoms: a third +18% damage, +15% shields, armor and hull."},
	"cruiser_mk2": {"name": "Specter Cruiser", "group": "warships", "class": "cruiser", "tier": 2, "requires": ["cruisers"], "cost": {"energy": 1300, "spice": 20}, "time": 80.0,
		"effects": {"mark_cruiser": 1.0}, "desc": "Cruisers become Specters: +18% damage, +15% shields, armor and hull."},
	"cruiser_mk3": {"name": "Wraith Cruiser", "group": "warships", "class": "cruiser", "tier": 3, "requires": ["cruiser_mk2"], "cost": {"energy": 2400, "spice": 60}, "time": 115.0,
		"effects": {"mark_cruiser": 1.0}, "desc": "Cruisers become Wraiths: another +18% damage, +15% shields, armor and hull."},
	"cruiser_mk4": {"name": "Phantom Cruiser", "group": "warships", "class": "cruiser", "tier": 3, "requires": ["cruiser_mk3"], "cost": {"energy": 4000, "spice": 120}, "time": 160.0,
		"effects": {"mark_cruiser": 1.0}, "desc": "Cruisers become Phantoms: a third +18% damage, +15% shields, armor and hull."},
	# Defense lines (research screen's Defenses tab): shields, armor, hull. Each
	# is three tiers of big, expensive upgrades for every ship and starbase,
	# so which layer to invest in is a real strategic choice.
	"deflectors": {"name": "Deflector Arrays", "group": "defense", "line": "shields", "tier": 1, "requires": [], "cost": {"energy": 1500, "spice": 40}, "time": 120.0,
		"effects": {"shield": 0.20}, "desc": "+20% shields on all ships and starbases. Unlocks the Heat Shield Frigate."},
	"phase_shields": {"name": "Phase Shields", "group": "defense", "line": "shields", "tier": 2, "requires": ["deflectors"], "cost": {"energy": 3000, "spice": 100}, "time": 180.0,
		"effects": {"shield": 0.25}, "desc": "+25% shields."},
	"aegis_matrix": {"name": "Aegis Matrix", "group": "defense", "line": "shields", "tier": 3, "requires": ["phase_shields"], "cost": {"energy": 5000, "spice": 250}, "time": 240.0,
		"effects": {"shield": 0.35}, "desc": "+35% shields."},
	"composite_plating": {"name": "Composite Plating", "group": "defense", "line": "armor", "tier": 1, "requires": [], "cost": {"energy": 1500, "spice": 40}, "time": 120.0,
		"effects": {"armor": 0.20}, "desc": "+20% armor on all ships and starbases."},
	"reactive_armor": {"name": "Reactive Armor", "group": "defense", "line": "armor", "tier": 2, "requires": ["composite_plating"], "cost": {"energy": 3000, "spice": 100}, "time": 180.0,
		"effects": {"armor": 0.25}, "desc": "+25% armor."},
	"neutronium_armor": {"name": "Neutronium Armor", "group": "defense", "line": "armor", "tier": 3, "requires": ["reactive_armor"], "cost": {"energy": 5000, "spice": 250}, "time": 240.0,
		"effects": {"armor": 0.35}, "desc": "+35% armor."},
	"reinforced_frames": {"name": "Reinforced Frames", "group": "defense", "line": "hull", "tier": 1, "requires": [], "cost": {"energy": 1500, "spice": 40}, "time": 120.0,
		"effects": {"hull": 0.15}, "desc": "+15% hull on all ships and starbases. Unlocks the Repair Tender."},
	"nanite_plating": {"name": "Nanite Plating", "group": "defense", "line": "hull", "tier": 2, "requires": ["reinforced_frames"], "cost": {"energy": 3000, "spice": 100}, "time": 180.0,
		"effects": {"hull": 0.20}, "desc": "+20% hull."},
	"adaptive_hulls": {"name": "Adaptive Hulls", "group": "defense", "line": "hull", "tier": 3, "requires": ["nanite_plating"], "cost": {"energy": 5000, "spice": 250}, "time": 240.0,
		"effects": {"hull": 0.30}, "desc": "+30% hull."},
	"dark_matter": {"name": "Dark Matter Reactors", "group": "weapons", "tier": 3, "requires": ["particle_lances"], "cost": {"spice": 250}, "time": 120.0,
		"effects": {"energy": 0.50, "damage": 0.25}, "desc": "+50% energy output, +25% weapon damage. Paid entirely in spice."},
	"spice_navigation": {"name": "Spice Navigation", "group": "logistics", "tier": 3, "requires": ["ion_thrusters", "gene_clinics"], "cost": {"spice": 200}, "time": 100.0,
		"effects": {"speed": 0.25, "growth": 0.25}, "desc": "+25% ship speed, +25% population growth. Paid entirely in spice."},
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
	"warships": "Unlock each warship class and raise its mark: Wisp, Specter, Wraith, Phantom. Every class is its own line.",
	"weapons": "Weapon output for everything you own, warship and starbase alike.",
	"defense": "The three defense layers — shields, armor and hull — on every ship and starbase. Pick a layer and commit.",
	"constructs": "Starbases, depots and the other things you build rather than fly.",
	"worlds": "Feeding and growing your colonies: food, population and the cap on both.",
	"logistics": "Hauling, skimming and fleet movement — how fast your cargo and your ships get there.",
	"general": "Everything else.",
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
## (see VARIANTS), e.g. "slip_corvette".
static var SHIPS: Dictionary = _with_variants()

## Hull marks: every warship class starts as a Wisp and is upgraded a mark at
## a time by its own research line (Defs.TECHS, "mark_<class>" effects). Each
## mark makes that class alone tougher and harder-hitting, so late-game
## corvettes are a different animal from the ones built in minute one.
## A harvester fills its hold at "harvest" units a second while parked on a
## node, then hauls the load home. Spice fills slower than ore, nebula gas
## slower still.
const HARVEST_SPICE_MULT := 0.4
const HARVEST_NEBULA_MULT := 0.6

## Which classes have a mark line (see HULL_MARKS).
const MARK_LINES := ["corvette", "destroyer", "cruiser"]

const HULL_MARKS := ["Wisp", "Specter", "Wraith", "Phantom"]
## What one mark adds to its class, per step.
const MARK_STEP := {"damage": 0.18, "hull": 0.15, "armor": 0.15, "shield": 0.15}

## The mark name for a class at `level` (0 = Wisp), e.g. "Specter Corvette".
static func marked_name(ship_type: String, level: int) -> String:
	var d: Dictionary = SHIPS.get(ship_type, {})
	if d.is_empty() or not MARK_LINES.has(d.get("base", ship_type)):
		return d.get("name", ship_type)
	return "%s %s" % [HULL_MARKS[clampi(level, 0, HULL_MARKS.size() - 1)], d["name"]]

## Damage vs the defense layers. Generalists deal their full base damage to
## shields, armor and hull alike. Specialists are variants of a generalist:
##   bonus  - 80% base damage, x2.2 against one layer (x1.9 for hull, the
##            biggest layer on most ships)
##   pierce - skip layers entirely: 1 = shields (65% base damage),
##            2 = shields and armor (40% base damage)
## All variants cost the same as their generalist. Balance: vs the
## generalists' distinct profiles (corvette hull-heavy, destroyer
## shield-heavy, cruiser armor-heavy) each specialist kills its favored
## targets 7-18% faster and the others 5-46% slower (see tools notes).
## color: the variant's markings and shot color.
const VARIANTS := {
	"plasma": {"label": "Plasma", "vs": {"shield": 2.2}, "pierce": 0, "damage": 0.8, "cost": 1.0, "color": Color("7fd8ff"),
		"desc": "80% base damage, x2.2 against shields."},
	"breacher": {"label": "Breacher", "vs": {"armor": 2.2}, "pierce": 0, "damage": 0.8, "cost": 1.0, "color": Color("ff4a4a"),
		"desc": "80% base damage, x2.2 against armor."},
	"reaver": {"label": "Reaver", "vs": {"hull": 1.9}, "pierce": 0, "damage": 0.8, "cost": 1.0, "color": Color("58e07a"),
		"desc": "80% base damage, x1.9 against hull."},
	"slip": {"label": "Slip", "vs": {}, "pierce": 1, "damage": 0.65, "cost": 1.0, "color": Color("ffa43a"),
		"desc": "Shots slip past shields straight to armor and hull, at 65% base damage."},
	"disruptor": {"label": "Disruptor", "vs": {}, "pierce": 2, "damage": 0.4, "cost": 1.0, "color": Color("b06cff"),
		"desc": "Shots pass through shields and armor straight to the hull, at 40% base damage."},
}
## Which variants each generalist has so far.
const VARIANTS_OF := {
	"corvette": ["plasma", "breacher", "reaver", "slip", "disruptor"],
	"destroyer": ["plasma", "breacher", "reaver", "slip", "disruptor"],
	"cruiser": ["plasma", "breacher", "reaver", "slip", "disruptor"],
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
static func damage_profile(d: Dictionary) -> Dictionary:
	if not d.has("variant"):
		return {"vs": {}, "pierce": 0}
	var v: Dictionary = VARIANTS[d["variant"]]
	return {"vs": v["vs"], "pierce": v["pierce"]}

## Ship jobs (see Abilities): what each ship is good at. Passive jobs always
## work; active ones are triggered with Q (or the ship panel's button) and
## then need `cooldown` seconds; `duration` is how long an active effect
## lasts. `color` is the job's accent (sprites and effects share it).
const JOBS := {
	"swarm": {"name": "Swarm", "active": false, "color": Color("7fb2ff"),
		"desc": "+6% damage for each other corvette within 150 px (up to +36%). Strong in numbers, weak alone."},
	"escort": {"name": "Escort", "active": false, "color": Color("7fd8ff"),
		"desc": "Friendly ships within 130 px take 15% less weapon damage. Guards miners, colony ships and fleets."},
	"beacon": {"name": "Deep Sensors", "active": true, "cooldown": 45.0, "duration": 90.0, "color": Color("7fe8ff"),
		"desc": "Sees far, into spice nebulae and through ion storms. [Q] Drop a sensor beacon that watches the spot for 90 s."},
	"heat_screen": {"name": "Heat Screen", "active": false, "color": Color("ffc24a"),
		"desc": "Friendly ships within 170 px take 75% less radiation damage and keep their shields in spice nebulae."},
	"field_repair": {"name": "Field Repair", "active": true, "cooldown": 60.0, "color": Color("6fe07a"),
		"desc": "Repairs up to 4 ships within 180 px (6 points/s each: hull first, then armor, the only way to restore armor) once they're out of combat. [Q] Emergency repair: +35% of hull and armor to ships within 200 px."},
}

## Visual language for the defense layers: bars, research lines, and the
## lasers of specialists that hit a layer harder all use these colors.
const LAYER_COLORS := {"shield": Color("7fd8ff"), "armor": Color("ff4a4a"), "hull": Color("58e07a")}
## Generalists (and starbases) fire yellow lasers.
const GENERALIST_SHOT := Color("ffd84a")

## Base damage a ship with `variant` ("" = generalist) needs to destroy a
## target with these defenses — the same layer maths as
## SpaceEntity.take_damage. The Codex uses it for its matchup table, so the
## numbers always follow the current stats.
static func kill_cost(shield: float, armor_v: float, hull: float, variant: String) -> float:
	var vd: Dictionary = VARIANTS.get(variant, {"vs": {}, "pierce": 0, "damage": 1.0})
	var vs: Dictionary = vd["vs"]
	var need := hull / float(vs.get("hull", 1.0))
	if int(vd["pierce"]) < 2:
		need += armor_v / float(vs.get("armor", 1.0))
	if int(vd["pierce"]) < 1:
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
	["stop", "Stop", KEY_T], ["warships", "Select all warships", KEY_TAB], ["home", "Go to starbase", KEY_B],
	["next_world", "Next world", KEY_SPACE], ["build_here", "Build on this world", KEY_F], ["research", "Research", KEY_R],
	["pause", "Pause / play", KEY_PAUSE], ["speed_down", "Slower", KEY_MINUS], ["speed_up", "Faster", KEY_EQUAL],
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
	return v as Key

## Which action a pressed key runs ("" if none).
static func action_for_key(k: Key) -> String:
	for h in HOTKEYS:
		if key_for(h[0]) == k:
			return h[0]
	return ""
