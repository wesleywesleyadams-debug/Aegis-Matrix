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

const START := {"food": 500.0, "minerals": 300.0, "energy": 250.0, "spice": 50.0}

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
const SHIPS := {
	"miner": {
		"name": "Mining Barge", "role": "miner", "hotkey": KEY_Z,
		"hp": 70.0, "shield": 0.0, "speed": 70.0, "radius": 8.0, "supply": 1,
		"cost": {"minerals": 50}, "build_time": 6.0, "upkeep": 0.05,
		"cargo": 10, "mine_time": 2.5,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"colony": {
		"name": "Colony Ship", "role": "colony", "hotkey": KEY_X,
		"hp": 120.0, "shield": 20.0, "speed": 60.0, "radius": 9.0, "supply": 2,
		"cost": {"minerals": 80, "spice": 20}, "build_time": 15.0, "upkeep": 0.1,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"constructor": {
		"name": "Constructor", "role": "constructor", "hotkey": KEY_C,
		"hp": 150.0, "shield": 20.0, "speed": 65.0, "radius": 9.0, "supply": 2,
		"cost": {"minerals": 120, "spice": 5}, "build_time": 12.0, "upkeep": 0.1,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"corvette": {
		"name": "Corvette", "role": "warship", "hotkey": KEY_V,
		"hp": 90.0, "shield": 30.0, "speed": 125.0, "radius": 8.0, "supply": 1,
		"cost": {"minerals": 60}, "build_time": 8.0, "upkeep": 0.1,
		"weapon": "laser", "damage": 6.0, "cooldown": 0.55, "range": 140.0,
	},
	"destroyer": {
		"name": "Destroyer", "role": "warship", "hotkey": KEY_B,
		"hp": 220.0, "shield": 80.0, "speed": 85.0, "radius": 11.0, "supply": 2,
		"cost": {"minerals": 140, "spice": 5}, "build_time": 14.0, "upkeep": 0.25,
		"weapon": "laser", "damage": 13.0, "cooldown": 0.9, "range": 190.0,
	},
	"cruiser": {
		"name": "Cruiser", "role": "warship", "hotkey": KEY_N, "requires": "cruiser_doctrine",
		"hp": 560.0, "shield": 200.0, "speed": 55.0, "radius": 16.0, "supply": 4,
		"cost": {"minerals": 300, "spice": 25}, "build_time": 24.0, "upkeep": 0.6,
		"weapon": "torpedo", "damage": 42.0, "cooldown": 2.2, "range": 260.0,
	},
}

const BUILD_ORDER: Array[String] = ["miner", "colony", "constructor", "corvette", "destroyer", "cruiser"]

const STARBASE := {
	"name": "Starbase", "hp": 2400.0, "shield": 800.0, "radius": 26.0,
	"weapon": "laser", "damage": 10.0, "cooldown": 0.7, "range": 220.0,
	# Built on site by a Constructor, paid over build_time.
	"cost": {"minerals": 400, "spice": 20}, "build_time": 40.0,
	"upkeep": 0.5,
	# Station reactors and ore refineries.
	"energy_per_sec": 2.0, "minerals_per_sec": 0.5,
	"min_spacing": 500.0,
}

const FLEET_CAP := 40

## Planet types. max_pop: population ceiling. fertility scales food output.
## energy: base energy/sec once colonized. spice: spice/sec once colonized.
const PLANET_TYPES := {
	"planet_terran": {"label": "Terran", "max_pop": 12000, "fertility": 1.0, "energy": 4.0, "spice": 0.0},
	"planet_desert": {"label": "Desert", "max_pop": 10000, "fertility": 0.45, "energy": 4.5, "spice": 0.0},
	"planet_ice": {"label": "Arctic", "max_pop": 8000, "fertility": 0.6, "energy": 4.0, "spice": 0.0},
	"planet_lava": {"label": "Molten", "max_pop": 4000, "fertility": 0.15, "energy": 6.0, "spice": 0.08},
	"planet_gas": {"label": "Gas Giant", "max_pop": 3000, "fertility": 0.0, "energy": 5.0, "spice": 0.15},
	"planet_moon": {"label": "Barren Moon", "max_pop": 2000, "fertility": 0.2, "energy": 2.0, "spice": 0.0},
}
const START_POP := 100.0
## 1 new pop per minute for every 2 pop (a "pop pair").
const GROWTH_PER_PAIR_PER_MIN := 1.0
## Every pop eats 1 food per minute. Pops left unfed for STARVE_SECONDS
## die; feeding them before then (food or spice) resets the clock.
const FOOD_PER_POP_PER_MIN := 1.0
const STARVE_SECONDS := 60.0
## Food comes only from Farms (see BUILDINGS), scaled by planet fertility.
## Extra energy per second from each 1,000 pop.
const ENERGY_PER_1000_POP := 1.5

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
	"farm": {"name": "Farm", "pop": 100, "cost": {"minerals": 60}, "time": 30.0, "output": {"food": 200.0}, "only": [],
		"desc": "+100 to +200 food/min depending on fertility (boosted by Hydroponics). Needs 100 pop."},
	"generator": {"name": "Power Plant", "pop": 100, "cost": {"minerals": 80}, "time": 30.0, "output": {"energy": 3.0}, "only": [],
		"desc": "+3 energy/s. Needs 100 pop."},
	"mine": {"name": "Mining Complex", "pop": 100, "cost": {"minerals": 70}, "time": 35.0, "output": {"minerals": 1.5}, "only": [],
		"desc": "+1.5 minerals/s. Needs 100 pop."},
	"habitat": {"name": "Habitat", "pop": 0, "cost": {"minerals": 100, "spice": 5}, "time": 40.0, "output": {}, "max_pop": 1500, "only": [],
		"desc": "+1,500 population cap. Needs no staff."},
	"spice_extractor": {"name": "Spice Extractor", "pop": 200, "cost": {"minerals": 150, "spice": 30}, "time": 60.0, "output": {"spice": 0.2}, "only": ["planet_gas", "planet_lava"],
		"desc": "+0.2 spice/s. Gas giants and molten worlds only. Needs 200 pop."},
}
const BUILDING_ORDER: Array[String] = ["farm", "generator", "mine", "habitat", "spice_extractor"]
## Buildings only operate with enough pop on the planet ("pop" above).
## Pop is assigned automatically in this order of output.
const STAFFING_PRIORITY: Array[String] = ["food", "energy", "minerals", "spice"]

const SHIELD_REGEN_DELAY := 4.0
const SHIELD_REGEN_PER_SEC := 0.08 # fraction of max shield

## Tech tree. tier sets the column in the tree view; requires lists
## prerequisite techs (all needed). effects are multiplier bonuses summed
## per key (e.g. "damage": 0.2 = +20%); "unlock" names are flags.
const TECHS := {
	"ion_cannons": {"name": "Ion Cannons", "tier": 1, "requires": [], "cost": {"energy": 600}, "time": 60.0,
		"effects": {"damage": 0.20}, "desc": "+20% weapon damage."},
	"deflectors": {"name": "Deflector Arrays", "tier": 1, "requires": [], "cost": {"energy": 500}, "time": 50.0,
		"effects": {"shield": 0.25}, "desc": "+25% shield strength."},
	"hydroponics": {"name": "Hydroponics", "tier": 1, "requires": [], "cost": {"energy": 400}, "time": 40.0,
		"effects": {"food": 0.30}, "desc": "+30% food production."},
	"deep_drills": {"name": "Deep-Core Drills", "tier": 1, "requires": [], "cost": {"energy": 400}, "time": 40.0,
		"effects": {"cargo": 0.40}, "desc": "Mining barges carry +40% ore."},
	"plasma_lances": {"name": "Plasma Lances", "tier": 2, "requires": ["ion_cannons"], "cost": {"energy": 1200, "spice": 30}, "time": 90.0,
		"effects": {"damage": 0.25}, "desc": "+25% weapon damage."},
	"nanite_plating": {"name": "Nanite Plating", "tier": 2, "requires": ["deflectors"], "cost": {"energy": 1000, "spice": 25}, "time": 80.0,
		"effects": {"hull": 0.30}, "desc": "+30% hull strength."},
	"ion_thrusters": {"name": "Ion Thrusters", "tier": 2, "requires": ["deflectors"], "cost": {"energy": 700}, "time": 60.0,
		"effects": {"speed": 0.15}, "desc": "+15% ship speed."},
	"gene_clinics": {"name": "Gene Clinics", "tier": 2, "requires": ["hydroponics"], "cost": {"energy": 900, "spice": 20}, "time": 75.0,
		"effects": {"growth": 0.50}, "desc": "+50% population growth."},
	"arcologies": {"name": "Arcologies", "tier": 2, "requires": ["hydroponics"], "cost": {"energy": 1000, "spice": 20}, "time": 80.0,
		"effects": {"max_pop": 0.30}, "desc": "+30% planet population cap."},
	"cruiser_doctrine": {"name": "Cruiser Doctrine", "tier": 2, "requires": ["ion_cannons", "deep_drills"], "cost": {"energy": 800, "spice": 20}, "time": 70.0,
		"effects": {"unlock_cruiser": 1.0}, "desc": "Unlocks the Cruiser."},
	"dark_matter": {"name": "Dark Matter Reactors", "tier": 3, "requires": ["plasma_lances", "nanite_plating"], "cost": {"spice": 250}, "time": 120.0,
		"effects": {"energy": 0.50, "damage": 0.25}, "desc": "+50% energy output, +25% weapon damage. Paid entirely in spice."},
	"spice_navigation": {"name": "Spice Navigation", "tier": 3, "requires": ["ion_thrusters", "gene_clinics"], "cost": {"spice": 200}, "time": 100.0,
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
