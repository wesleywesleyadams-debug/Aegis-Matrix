class_name Defs
## Static data for Star Lords: ship classes, station stats, team colors.
## Ranges/speeds are in world pixels (sprites are 1 texel = 1 world px).

const PIXEL := "res://assets/pixel/"

const TEAM_COLORS: Array[Color] = [
	Color("9aa0b0"), # 0: neutral
	Color("4fb4ff"), # 1
	Color("ff4f5e"), # 2
	Color("ffc93d"), # 3
	Color("6fe07a"), # 4
	Color("c77dff"), # 5
	Color("ff8c3a"), # 6
	Color("3de0d0"), # 7
	Color("f2f2f2"), # 8
]

static func team_color(owner_id: int) -> Color:
	return TEAM_COLORS[clampi(owner_id, 0, TEAM_COLORS.size() - 1)]

## role: "miner" gathers minerals; "warship" fights.
## weapon: "laser" (fast, hitscan-ish bolt) or "torpedo" (slow, heavy).
const SHIPS := {
	"miner": {
		"name": "Mining Barge", "role": "miner", "hotkey": KEY_Z,
		"hp": 70.0, "shield": 0.0, "speed": 70.0, "radius": 8.0, "supply": 1,
		"cost": {"minerals": 50, "energy": 0}, "build_time": 6.0,
		"cargo": 10, "mine_time": 2.5,
		"weapon": "", "damage": 0.0, "cooldown": 1.0, "range": 0.0,
	},
	"corvette": {
		"name": "Corvette", "role": "warship", "hotkey": KEY_X,
		"hp": 90.0, "shield": 30.0, "speed": 125.0, "radius": 8.0, "supply": 1,
		"cost": {"minerals": 75, "energy": 25}, "build_time": 8.0,
		"weapon": "laser", "damage": 6.0, "cooldown": 0.55, "range": 140.0,
	},
	"destroyer": {
		"name": "Destroyer", "role": "warship", "hotkey": KEY_C,
		"hp": 220.0, "shield": 80.0, "speed": 85.0, "radius": 11.0, "supply": 2,
		"cost": {"minerals": 150, "energy": 60}, "build_time": 14.0,
		"weapon": "laser", "damage": 13.0, "cooldown": 0.9, "range": 190.0,
	},
	"cruiser": {
		"name": "Cruiser", "role": "warship", "hotkey": KEY_V,
		"hp": 560.0, "shield": 200.0, "speed": 55.0, "radius": 16.0, "supply": 4,
		"cost": {"minerals": 320, "energy": 150}, "build_time": 24.0,
		"weapon": "torpedo", "damage": 42.0, "cooldown": 2.2, "range": 260.0,
	},
}

const BUILD_ORDER: Array[String] = ["miner", "corvette", "destroyer", "cruiser"]

const STARBASE := {
	"name": "Starbase", "hp": 2400.0, "shield": 800.0, "radius": 26.0,
	"weapon": "laser", "damage": 10.0, "cooldown": 0.7, "range": 220.0,
}

const FLEET_CAP := 40
const START_MINERALS := 300
const START_ENERGY := 150
## Base income per second from each owned planet.
const PLANET_ENERGY_PER_SEC := 1.5
const STARBASE_MINERALS_PER_SEC := 0.5
const SHIELD_REGEN_DELAY := 4.0
const SHIELD_REGEN_PER_SEC := 0.08 # fraction of max shield

static func tex(name: String) -> Texture2D:
	return load(PIXEL + name + ".png")
