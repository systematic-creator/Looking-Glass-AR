class_name CDDefs
extends RefCounted
## Crystal Defense data: towers, barriers, enemies, units, the Cryptid world
## and Normal difficulty, straight from docs/crystal-defense.md (M2 subset).
## Distances are in CELLS, speeds in cells/s, times in seconds.

const GRID_N: int = 12
const START_MANA: int = 20
const CRYSTAL_HP: int = 100
const CRYSTAL_REGEN: int = 5
const REPAIR_COST: int = 15
const REPAIR_HP: int = 10
const STORM_PERIOD: float = 2.0
const STORM_RANGE: float = 1.5
const STORM_DAMAGE: float = 2.0
const MAX_ALIVE: int = 60
const CONDENSE_THRESHOLD: float = 54.0
const MIDWAVE_MARKUP: float = 1.5
const SELL_PREP: float = 0.7
const SELL_WAVE: float = 0.5
const DISMISS_PREP: float = 0.5
const DISMISS_WAVE: float = 0.25
const TELEGRAPH: float = 3.0
const GROUP_SPACING: float = 0.5
const INTRO_TIME: float = 2.0
const CLEAR_TIME: float = 1.5
const AUTOSTART_DELAY: float = 3.0
const AUTO_STEP: float = 0.05
const AUTO_BOSS_STEP: float = 0.10
const AUTO_CAP: float = 1.5
const NO_LEAK_BONUS: int = 3
const MAX_SQUADS: int = 6
const REDEPLOY_TIME: float = 3.0
const REDEPLOY_COOLDOWN: float = 15.0

## Towers and barriers. Level entries: "cost" is the price of reaching that
## level (level 1 = build price).
const STRUCTURES: Dictionary = {
	&"arrow": {
		"title": "Arrow Tower", "tab": &"attack", "kind": &"tower", "shape": &"single", "air": true,
		"blurb": "Single target · hits air",
		"levels": [
			{"cost": 10, "damage": 2.0, "rate": 1.0, "range": 2.5},
			{"cost": 15, "damage": 3.0, "rate": 1.25, "range": 2.75},
			{"cost": 25, "damage": 5.0, "rate": 1.5, "range": 3.0, "double_every": 4},
		],
	},
	&"bombard": {
		"title": "Bombard", "tab": &"attack", "kind": &"tower", "shape": &"splash", "air": false,
		"blurb": "Splash area · ground",
		"levels": [
			{"cost": 18, "damage": 4.0, "rate": 0.5, "range": 2.25, "splash": 0.75},
			{"cost": 20, "damage": 6.0, "rate": 0.55, "range": 2.5, "splash": 0.9},
			{"cost": 35, "damage": 9.0, "rate": 0.6, "range": 2.75, "splash": 1.0, "burn_dps": 1.0, "burn_time": 2.0},
		],
	},
	&"palisade": {
		"title": "Palisade", "tab": &"barriers", "kind": &"barrier", "shape": &"wall",
		"blurb": "Cheap path-shaper",
		"levels": [
			{"cost": 5, "hp": 40.0, "armor": 0},
			{"cost": 8, "hp": 80.0, "armor": 0},
			{"cost": 15, "hp": 140.0, "armor": 0, "braced": true},
		],
	},
	&"stone_wall": {
		"title": "Stone Wall", "tab": &"barriers", "kind": &"barrier", "shape": &"wall",
		"blurb": "High-HP blocker",
		"levels": [
			{"cost": 8, "hp": 100.0, "armor": 1},
			{"cost": 10, "hp": 180.0, "armor": 2},
			{"cost": 18, "hp": 300.0, "armor": 3},
		],
	},
}
const BUILD_ORDER: Array[StringName] = [&"arrow", &"bombard", &"palisade", &"stone_wall"]

const ENEMIES: Dictionary = {
	&"stalker": {
		"title": "Pale Stalker", "hp": 6.0, "speed": 0.75, "armor": 0, "crystal_damage": 2.0,
		"mana": 1, "exp": 2, "melee_dps": 1.0, "points": 1,
	},
}

## Condensing (doc 12.1): bodies replaced, HP x, crystal damage x, mana/EXP x, scale.
const CONDENSE: Array[Dictionary] = [
	{"bodies": 1, "hp": 1.0, "crystal": 1.0, "reward": 1, "scale": 1.0},
	{"bodies": 2, "hp": 1.8, "crystal": 1.5, "reward": 2, "scale": 1.15},
	{"bodies": 4, "hp": 3.4, "crystal": 2.5, "reward": 4, "scale": 1.3},
]

const UNITS: Dictionary = {
	&"knight": {
		"title": "Knight", "cost": 8, "shape": &"arc", "arc_deg": 90.0, "threshold": 4, "exp_base": 10.0,
		"blurb": "Melee arc · blocks",
		"grow_base": [5, 12, 25], "grow_step": [2, 3, 5], "evolve_cost": [15, 30],
		"ranks": [
			{"name": "Knight", "hp": 20.0, "damage": 2.0, "rate": 1.0, "reach": 0.5, "lifesteal": 0.0},
			{"name": "Paladin", "hp": 70.0, "damage": 7.0, "rate": 1.0, "reach": 0.5, "lifesteal": 0.1},
			{"name": "Lightguard", "hp": 245.0, "damage": 24.5, "rate": 1.0, "reach": 0.5, "lifesteal": 0.1},
		],
	},
}
const SUMMON_ORDER: Array[StringName] = [&"knight"]

## Cryptid world (Normal): wave budget, HP growth, group gap, side schedule.
const WORLD: Dictionary = {
	"name": "Cryptid", "b0": 8.0, "b1": 4.0, "b2": 0.35, "h": 0.08, "gap": 3.0, "gap_late": 2.0, "gap_late_from": 15,
	# [first wave, sides active from then on]
	"sides": [[1, [0]], [4, [0, 1]], [8, [0, 1, 2]], [13, [0, 1, 2, 3]]],
	"set_pieces": {1: 8, 2: 10, 3: 12},
	# Impassable terrain (dead trees, standing stones) in 12x12 cells.
	"trees": [Vector2i(2, 2), Vector2i(9, 2), Vector2i(2, 9), Vector2i(9, 9), Vector2i(1, 5)],
	"stones": [Vector2i(6, 1), Vector2i(10, 6), Vector2i(5, 10)],
}


static func structure(id: StringName) -> Dictionary:
	return STRUCTURES.get(id, {})


static func level_stats(id: StringName, level: int) -> Dictionary:
	var levels: Array = structure(id).get("levels", [])
	return levels[clampi(level - 1, 0, levels.size() - 1)] if not levels.is_empty() else {}


static func is_barrier(id: StringName) -> bool:
	return structure(id).get("kind", &"") == &"barrier"


## Total mana put into a structure to reach `level` (base prices).
static func spent_to_level(id: StringName, level: int) -> int:
	var total: int = 0
	var levels: Array = structure(id).get("levels", [])
	for i: int in mini(level, levels.size()):
		total += int((levels[i] as Dictionary)["cost"])
	return total


## Doc 9: B(w) = b0 + b1 w + b2 w^2 points (Normal, table board).
static func budget(wave: int) -> float:
	return WORLD["b0"] + WORLD["b1"] * wave + WORLD["b2"] * wave * wave


static func hp_multiplier(wave: int) -> float:
	return 1.0 + WORLD["h"] * (wave - 1)


static func armor_bonus(wave: int) -> int:
	return int(wave / 15)


static func group_gap(wave: int) -> float:
	return WORLD["gap_late"] if wave >= int(WORLD["gap_late_from"]) else WORLD["gap"]


static func group_size(wave: int) -> int:
	return clampi(3 + wave / 3, 3, 8)


static func active_sides(wave: int) -> Array:
	var sides: Array = [0]
	for entry: Array in WORLD["sides"]:
		if wave >= int(entry[0]):
			sides = entry[1]
	return sides


## Enemy count for a wave (before condensing): set pieces for 1-3, else the
## budget spent on Pale Stalkers (1 point each).
static func wave_count(wave: int) -> int:
	var sp: Dictionary = WORLD["set_pieces"]
	if sp.has(wave):
		return int(sp[wave])
	return int(round(budget(wave) / float(ENEMIES[&"stalker"]["points"])))


static func clear_bonus(wave: int) -> int:
	return 5 + wave


static func exp_needed(unit: StringName, upgrades: int) -> float:
	return float(UNITS[unit]["exp_base"]) * pow(1.35, upgrades)


## Mana for a squad's next upgrade (base price) and whether it evolves.
## Returns {"cost", "evolve", "max"}.
static func squad_upgrade(unit: StringName, rank: int, size: int) -> Dictionary:
	var u: Dictionary = UNITS[unit]
	var threshold: int = int(u["threshold"])
	if size >= threshold:
		if rank >= (u["ranks"] as Array).size() - 1:
			return {"cost": 0, "evolve": false, "max": true}
		return {"cost": int((u["evolve_cost"] as Array)[rank]), "evolve": true, "max": false}
	var cost: int = int((u["grow_base"] as Array)[rank]) + int((u["grow_step"] as Array)[rank]) * (size - 1)
	return {"cost": cost, "evolve": false, "max": false}
