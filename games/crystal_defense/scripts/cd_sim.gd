class_name CDSim
extends RefCounted
## Crystal Defense simulation (no nodes): the grid, the Crystal, mana, the
## phase machine, towers and barriers, squads, Pale Stalkers on a flow field,
## wave planning with border spawns and telegraphs, condensing under the
## 60-enemy cap. Advance it with tick(STEP) at a fixed 20 Hz (CDSim.STEP);
## the game view reads its arrays and drains `events` every frame.
##
## Coordinates are continuous cell coordinates (BoardGrid): cell (i, j) spans
## [i, i+1) x [j, j+1). Side 0 = west (x = 0), 1 = east, 2 = north (y = 0,
## far from the player), 3 = south.

const STEP: float = 1.0 / 20.0

const PHASE_INTRO: StringName = &"intro"
const PHASE_PREP: StringName = &"prep"
const PHASE_WAVE: StringName = &"wave"
const PHASE_CLEAR: StringName = &"clear"
const PHASE_DEFEAT: StringName = &"defeat"

const STALKER_RADIUS: float = 0.22
const ENGAGE_EXTRA: float = 0.35

var grid: BoardGrid
var flow: FlowField
var wallet: Wallet
var phases: PhaseMachine
var rng := RandomNumberGenerator.new()
var seed_value: int = 0

var crystal_hp: float = CDDefs.CRYSTAL_HP
var crystal_max: float = CDDefs.CRYSTAL_HP
var crystal_center := Vector2(6, 6)
var crystal_cells: Array[Vector2i] = []
var storm_t: float = CDDefs.STORM_PERIOD
var repaired_this_wave: bool = false

## Structures: id -> {id, type, level, cell, hp, cooldown, shots, spent, prep_serial}
var structures: Dictionary = {}
var _next_id: int = 1
## Squads: id -> {id, unit, rank, members (Array[float] hp), exp, upgrades,
## cell, facing (Vector2), cooldown, redeploy_t, redeploy_cd, target_cell}
var squads: Dictionary = {}

# Enemies: pooled slots with parallel arrays.
var enemies := SimPool.new(CDDefs.MAX_ALIVE)
var e_pos := PackedVector2Array()
var e_prev := PackedVector2Array()
var e_hp := PackedFloat32Array()
var e_max := PackedFloat32Array()
var e_speed := PackedFloat32Array()
var e_armor := PackedInt32Array()
var e_condense := PackedInt32Array()
var e_engaged := PackedInt32Array()
var e_flash := PackedFloat32Array()
var e_serial := PackedInt32Array()
var _spawn_serial: int = 0
var space := SpatialHash2D.new(1.0)

## Bombs in flight: {from, to, t, dur, damage, splash, burn_dps, burn_time}
var bombs: Array[Dictionary] = []
## Burning patches: {pos, radius, t, dps}
var burns: Array[Dictionary] = []

var wave: int = 0
var wave_time: float = 0.0
## Plan for `plan_wave`: {wave, count, condense, groups: [...]}
var plan: Dictionary = {}
var kills_this_wave: int = 0
var leaks_this_wave: int = 0
var mana_this_wave: int = 0
var total_kills: int = 0
var prep_serial: int = 0
var wave_started_by_auto: bool = false

var autostart: bool = false
var auto_streak: float = 0.0
## Seconds left before Autostart starts the next wave (< 0 = not counting).
var auto_countdown: float = -1.0

var events: Array[Dictionary] = []
var time: float = 0.0


func _init(p_seed: int = 1) -> void:
	_alloc_arrays()
	reset(p_seed)


func _alloc_arrays() -> void:
	var n: int = CDDefs.MAX_ALIVE
	e_pos.resize(n)
	e_prev.resize(n)
	e_hp.resize(n)
	e_max.resize(n)
	e_speed.resize(n)
	e_flash.resize(n)
	e_armor.resize(n)
	e_condense.resize(n)
	e_engaged.resize(n)
	e_serial.resize(n)


## Fresh run: wave 0, 20 mana, full Crystal, empty board, intro phase.
func reset(p_seed: int = 1) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	grid = BoardGrid.new(CDDefs.GRID_N, CDDefs.GRID_N, 1.0)
	var mid: int = CDDefs.GRID_N / 2
	crystal_cells = [Vector2i(mid - 1, mid - 1), Vector2i(mid, mid - 1), Vector2i(mid - 1, mid), Vector2i(mid, mid)]
	crystal_center = Vector2(mid, mid)
	for c: Vector2i in crystal_cells:
		grid.set_tag(c, BoardGrid.Tag.GOAL)
	for c: Vector2i in CDDefs.WORLD["trees"]:
		grid.set_tag(c, BoardGrid.Tag.TERRAIN)
	for c: Vector2i in CDDefs.WORLD["stones"]:
		grid.set_tag(c, BoardGrid.Tag.TERRAIN)
	flow = FlowField.new(grid)
	wallet = Wallet.new(CDDefs.START_MANA)
	phases = PhaseMachine.new()
	phases.allow(&"", [PHASE_INTRO])
	phases.allow(PHASE_INTRO, [PHASE_PREP])
	phases.allow(PHASE_PREP, [PHASE_WAVE])
	phases.allow(PHASE_WAVE, [PHASE_CLEAR, PHASE_DEFEAT])
	phases.allow(PHASE_CLEAR, [PHASE_PREP])
	phases.permit(PHASE_PREP, [&"build", &"upgrade", &"sell", &"summon", &"move", &"start", &"repair"])
	phases.permit(PHASE_WAVE, [&"build", &"upgrade", &"sell", &"summon", &"redeploy", &"repair"])
	crystal_max = CDDefs.CRYSTAL_HP
	crystal_hp = crystal_max
	storm_t = CDDefs.STORM_PERIOD
	structures.clear()
	squads.clear()
	_next_id = 1
	enemies.clear()
	bombs.clear()
	burns.clear()
	wave = 0
	wave_time = 0.0
	kills_this_wave = 0
	leaks_this_wave = 0
	total_kills = 0
	prep_serial = 0
	auto_streak = 0.0
	auto_countdown = -1.0
	autostart = false
	events.clear()
	time = 0.0
	rebuild_flow()
	phases.enter(PHASE_INTRO, CDDefs.INTRO_TIME)
	_emit(&"intro")


func phase() -> StringName:
	return phases.phase


func next_wave() -> int:
	return wave + 1 if phases.phase != PHASE_WAVE else wave


# --- Board rules ------------------------------------------------------------------

func is_blocking(cell: Vector2i) -> bool:
	return grid.get_occupant(cell) > 0


## Entry cost per cell for ground enemies (doc 6.3).
func cost_array(extra_solid: Vector2i = Vector2i(-1, -1)) -> PackedFloat32Array:
	var costs := PackedFloat32Array()
	costs.resize(grid.cell_count())
	for i: int in grid.cell_count():
		var tag: int = grid.tags[i]
		if tag == BoardGrid.Tag.TERRAIN or grid.occupant[i] > 0:
			costs[i] = INF
		else:
			costs[i] = 1.0
	if grid.in_bounds(extra_solid):
		costs[grid.index(extra_solid)] = INF
	return costs


func rebuild_flow() -> void:
	flow.build(cost_array(), crystal_cells)


func _passable_mask(extra_solid: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(grid.cell_count())
	var costs: PackedFloat32Array = cost_array(extra_solid)
	for i: int in grid.cell_count():
		mask[i] = 1 if FlowField.is_passable_cost(costs[i]) else 0
	return mask


## Never-block rule (doc 6.3): with `cell` solid, every non-terrain border
## cell (all four sides) can still reach the Crystal, and so can every enemy.
func keeps_crystal_reachable(cell: Vector2i) -> bool:
	var mask: PackedByteArray = _passable_mask(cell)
	var reached: PackedByteArray = grid.flood(crystal_cells, mask)
	for b: Vector2i in grid.border_cells():
		# Solid border cells (terrain, structures, the candidate) are not entries.
		if mask[grid.index(b)] == 0:
			continue
		if reached[grid.index(b)] == 0:
			return false
	for i: int in enemies.live:
		var ec := Vector2i(floori(e_pos[i].x), floori(e_pos[i].y))
		if grid.in_bounds(ec) and reached[grid.index(ec)] == 0:
			return false
	return true


func barrier_count() -> int:
	var n: int = 0
	for s: Dictionary in structures.values():
		if CDDefs.is_barrier(s["type"]):
			n += 1
	return n


func squad_at(cell: Vector2i) -> int:
	for q: Dictionary in squads.values():
		if q["cell"] == cell or q.get("target_cell", Vector2i(-9, -9)) == cell:
			return int(q["id"])
	return 0


func _enemy_near(cell: Vector2i) -> bool:
	for i: int in enemies.live:
		var ec := Vector2i(floori(e_pos[i].x), floori(e_pos[i].y))
		if absi(ec.x - cell.x) <= 1 and absi(ec.y - cell.y) <= 1:
			return true
	return false


## Can `type` be built on `cell` now? {"ok", "reason", "cost"}.
func can_build(type: StringName, cell: Vector2i) -> Dictionary:
	var cost: int = wallet.price(int(CDDefs.level_stats(type, 1)["cost"]))
	var r := {"ok": false, "reason": "", "cost": cost}
	if not phases.can(&"build"):
		r["reason"] = "Not now"
	elif not grid.in_bounds(cell):
		r["reason"] = "Off the board"
	elif grid.get_tag(cell) == BoardGrid.Tag.GOAL:
		r["reason"] = "That's the Crystal"
	elif grid.get_tag(cell) == BoardGrid.Tag.TERRAIN:
		r["reason"] = "Blocked by terrain"
	elif grid.get_occupant(cell) != 0:
		r["reason"] = "Occupied"
	elif squad_at(cell) != 0:
		r["reason"] = "A squad stands there"
	elif CDDefs.is_barrier(type) and barrier_count() >= CDDefs.GRID_N:
		r["reason"] = "Barrier cap reached (%d)" % CDDefs.GRID_N
	elif phases.phase == PHASE_WAVE and _enemy_near(cell):
		r["reason"] = "Too close to an enemy"
	elif not keeps_crystal_reachable(cell):
		r["reason"] = "Would block the Crystal"
	elif wallet.balance < cost:
		r["reason"] = "Need %d mana" % cost
	else:
		r["ok"] = true
	return r


func build(type: StringName, cell: Vector2i) -> int:
	var check: Dictionary = can_build(type, cell)
	if not bool(check["ok"]):
		return 0
	var base: int = int(CDDefs.level_stats(type, 1)["cost"])
	var paid: int = wallet.price(base)
	wallet.spend(base, &"build")
	var id: int = _next_id
	_next_id += 1
	var stats: Dictionary = CDDefs.level_stats(type, 1)
	structures[id] = {
		"id": id, "type": type, "level": 1, "cell": cell, "hp": float(stats.get("hp", 0.0)),
		"cooldown": 0.0, "shots": 0, "spent": paid,
		"prep_serial": prep_serial if phases.phase == PHASE_PREP else -1,
	}
	grid.set_occupant(cell, id)
	rebuild_flow()
	_emit(&"build", {"id": id, "type": type, "cell": cell})
	return id


func upgrade_cost(id: int) -> int:
	var s: Dictionary = structures.get(id, {})
	if s.is_empty() or int(s["level"]) >= 3:
		return -1
	return wallet.price(int(CDDefs.level_stats(s["type"], int(s["level"]) + 1)["cost"]))


func can_upgrade(id: int) -> Dictionary:
	var cost: int = upgrade_cost(id)
	if not phases.can(&"upgrade"):
		return {"ok": false, "reason": "Not now", "cost": cost}
	if cost < 0:
		return {"ok": false, "reason": "Max level", "cost": cost}
	if wallet.balance < cost:
		return {"ok": false, "reason": "Need %d mana" % cost, "cost": cost}
	return {"ok": true, "reason": "", "cost": cost}


func upgrade(id: int) -> bool:
	if not bool(can_upgrade(id)["ok"]):
		return false
	var s: Dictionary = structures[id]
	var base: int = int(CDDefs.level_stats(s["type"], int(s["level"]) + 1)["cost"])
	var paid: int = wallet.price(base)
	wallet.spend(base, &"upgrade")
	s["level"] = int(s["level"]) + 1
	s["spent"] = int(s["spent"]) + paid
	var stats: Dictionary = CDDefs.level_stats(s["type"], s["level"])
	if stats.has("hp"):
		s["hp"] = float(stats["hp"])
	_emit(&"upgrade", {"id": id, "level": s["level"], "target": "first"})
	return true


func sell_value(id: int) -> int:
	var s: Dictionary = structures.get(id, {})
	if s.is_empty():
		return 0
	if phases.phase == PHASE_PREP and int(s["prep_serial"]) == prep_serial:
		return int(s["spent"])
	var ratio: float = CDDefs.SELL_WAVE if phases.phase == PHASE_WAVE else CDDefs.SELL_PREP
	return int(floor(int(s["spent"]) * ratio))


func sell(id: int) -> bool:
	if not structures.has(id) or not phases.can(&"sell"):
		return false
	var s: Dictionary = structures[id]
	var value: int = sell_value(id)
	wallet.refund(value, &"sell")
	grid.set_occupant(s["cell"], 0)
	structures.erase(id)
	rebuild_flow()
	_emit(&"sell", {"id": id, "cell": s["cell"], "value": value})
	return true


func structure_at(cell: Vector2i) -> int:
	var id: int = grid.get_occupant(cell)
	return id if id > 0 and structures.has(id) else 0


func is_crystal_cell(cell: Vector2i) -> bool:
	return grid.get_tag(cell) == BoardGrid.Tag.GOAL


func can_repair() -> Dictionary:
	var cost: int = CDDefs.REPAIR_COST
	if not phases.can(&"repair"):
		return {"ok": false, "reason": "Not now", "cost": cost}
	if repaired_this_wave:
		return {"ok": false, "reason": "Once per wave", "cost": cost}
	if crystal_hp >= crystal_max:
		return {"ok": false, "reason": "Crystal is whole", "cost": cost}
	if wallet.balance < cost:
		return {"ok": false, "reason": "Need %d mana" % cost, "cost": cost}
	return {"ok": true, "reason": "", "cost": cost}


func repair() -> bool:
	if not bool(can_repair()["ok"]):
		return false
	wallet.spend_exact(CDDefs.REPAIR_COST, &"repair")
	crystal_hp = minf(crystal_max, crystal_hp + CDDefs.REPAIR_HP)
	repaired_this_wave = true
	_emit(&"repair")
	return true


# --- Squads -----------------------------------------------------------------------

func summon_cost(unit: StringName) -> int:
	return wallet.price(int(CDDefs.UNITS[unit]["cost"]))


func can_squad_stand(cell: Vector2i, ignore_squad: int = 0) -> Dictionary:
	if not grid.in_bounds(cell):
		return {"ok": false, "reason": "Off the board"}
	var tag: int = grid.get_tag(cell)
	if tag == BoardGrid.Tag.TERRAIN:
		return {"ok": false, "reason": "Blocked by terrain"}
	if tag == BoardGrid.Tag.GOAL:
		return {"ok": false, "reason": "That's the Crystal"}
	if grid.get_occupant(cell) != 0:
		return {"ok": false, "reason": "Occupied"}
	var other: int = squad_at(cell)
	if other != 0 and other != ignore_squad:
		return {"ok": false, "reason": "Another squad is there"}
	return {"ok": true, "reason": ""}


func can_summon(unit: StringName) -> Dictionary:
	var cost: int = summon_cost(unit)
	if not phases.can(&"summon"):
		return {"ok": false, "reason": "Not now", "cost": cost}
	if squads.size() >= CDDefs.MAX_SQUADS:
		return {"ok": false, "reason": "Squad cap (%d)" % CDDefs.MAX_SQUADS, "cost": cost}
	if _summon_cell() == Vector2i(-1, -1):
		return {"ok": false, "reason": "No free cell by the Crystal", "cost": cost}
	if wallet.balance < cost:
		return {"ok": false, "reason": "Need %d mana" % cost, "cost": cost}
	return {"ok": true, "reason": "", "cost": cost}


## A free standable cell next to the Crystal (ring by ring outward).
func _summon_cell() -> Vector2i:
	for ring: int in range(1, 6):
		var best := Vector2i(-1, -1)
		var best_d: float = INF
		for y: int in range(int(crystal_center.y) - 1 - ring, int(crystal_center.y) + 1 + ring):
			for x: int in range(int(crystal_center.x) - 1 - ring, int(crystal_center.x) + 1 + ring):
				var c := Vector2i(x, y)
				if not bool(can_squad_stand(c)["ok"]):
					continue
				var d: float = BoardGrid.center_of(c).distance_squared_to(crystal_center + Vector2(0, 0.6))
				if d < best_d:
					best_d = d
					best = c
		if best != Vector2i(-1, -1):
			return best
	return Vector2i(-1, -1)


func summon(unit: StringName) -> int:
	if not bool(can_summon(unit)["ok"]):
		return 0
	wallet.spend(int(CDDefs.UNITS[unit]["cost"]), &"summon")
	var cell: Vector2i = _summon_cell()
	var id: int = _next_id
	_next_id += 1
	var rank0: Dictionary = (CDDefs.UNITS[unit]["ranks"] as Array)[0]
	var away: Vector2 = (BoardGrid.center_of(cell) - crystal_center)
	squads[id] = {
		"id": id, "unit": unit, "rank": 0, "members": [float(rank0["hp"])], "exp": 0.0, "upgrades": 0,
		"cell": cell, "facing": _snap8(away if away.length() > 0.01 else Vector2(0, 1)), "cooldown": 0.0,
		"redeploy_t": 0.0, "redeploy_cd": 0.0, "target_cell": Vector2i(-9, -9),
		"summon_cost": wallet.price(int(CDDefs.UNITS[unit]["cost"])),
	}
	_emit(&"summon", {"id": id, "cell": cell})
	return id


static func _snap8(v: Vector2) -> Vector2:
	var a: float = round(v.angle() / (PI / 4.0)) * (PI / 4.0)
	return Vector2(cos(a), sin(a))


func squad_rank_stats(q: Dictionary) -> Dictionary:
	return (CDDefs.UNITS[q["unit"]]["ranks"] as Array)[int(q["rank"])]


func squad_size(q: Dictionary) -> int:
	return (q["members"] as Array).size()


func squad_alive(q: Dictionary) -> int:
	var n: int = 0
	for hp: float in q["members"]:
		if hp > 0.0:
			n += 1
	return n


func squad_exp_needed(id: int) -> float:
	var q: Dictionary = squads[id]
	return CDDefs.exp_needed(q["unit"], int(q["upgrades"]))


## {"ok", "reason", "cost", "evolve", "max"} for the squad's next upgrade.
func can_upgrade_squad(id: int) -> Dictionary:
	var q: Dictionary = squads.get(id, {})
	if q.is_empty():
		return {"ok": false, "reason": "No squad", "cost": 0, "evolve": false, "max": false}
	var up: Dictionary = CDDefs.squad_upgrade(q["unit"], int(q["rank"]), squad_size(q))
	var cost: int = wallet.price(int(up["cost"]))
	var r := {"ok": false, "reason": "", "cost": cost, "evolve": up["evolve"], "max": up["max"]}
	if bool(up["max"]):
		r["reason"] = "Max rank"
	elif not phases.can(&"upgrade"):
		r["reason"] = "Not now"
	elif float(q["exp"]) < squad_exp_needed(id):
		r["reason"] = "EXP %d / %d" % [int(q["exp"]), int(ceil(squad_exp_needed(id)))]
	elif wallet.balance < cost:
		r["reason"] = "Need %d mana" % cost
	else:
		r["ok"] = true
	return r


func upgrade_squad(id: int) -> bool:
	var check: Dictionary = can_upgrade_squad(id)
	if not bool(check["ok"]):
		return false
	var q: Dictionary = squads[id]
	var up: Dictionary = CDDefs.squad_upgrade(q["unit"], int(q["rank"]), squad_size(q))
	wallet.spend(int(up["cost"]), &"squad")
	q["exp"] = 0.0
	q["upgrades"] = int(q["upgrades"]) + 1
	if bool(up["evolve"]):
		q["rank"] = int(q["rank"]) + 1
		q["members"] = [float(squad_rank_stats(q)["hp"])]
		_release_engaged(id)
		_emit(&"evolve", {"id": id, "rank": q["rank"]})
	else:
		(q["members"] as Array).append(float(squad_rank_stats(q)["hp"]))
		_emit(&"grow", {"id": id, "size": squad_size(q)})
	return true


func dismiss_value(id: int) -> int:
	var q: Dictionary = squads.get(id, {})
	if q.is_empty():
		return 0
	var ratio: float = CDDefs.DISMISS_WAVE if phases.phase == PHASE_WAVE else CDDefs.DISMISS_PREP
	return int(floor(int(CDDefs.UNITS[q["unit"]]["cost"]) * ratio))


func dismiss(id: int) -> bool:
	if not squads.has(id) or not (phases.can(&"move") or phases.can(&"redeploy")):
		return false
	wallet.refund(dismiss_value(id), &"dismiss")
	_release_engaged(id)
	squads.erase(id)
	_emit(&"dismiss", {"id": id})
	return true


## Prep: move instantly. Wave: Redeploy (3 s out of action, 15 s cooldown).
func can_move_squad(id: int, cell: Vector2i) -> Dictionary:
	var q: Dictionary = squads.get(id, {})
	if q.is_empty():
		return {"ok": false, "reason": "No squad"}
	if phases.phase == PHASE_WAVE:
		if float(q["redeploy_t"]) > 0.0:
			return {"ok": false, "reason": "Redeploying"}
		if float(q["redeploy_cd"]) > 0.0:
			return {"ok": false, "reason": "Redeploy in %ds" % int(ceil(float(q["redeploy_cd"])))}
	elif not phases.can(&"move"):
		return {"ok": false, "reason": "Not now"}
	if cell == q["cell"]:
		return {"ok": true, "reason": ""}
	return can_squad_stand(cell, id)


func move_squad(id: int, cell: Vector2i) -> bool:
	if not bool(can_move_squad(id, cell)["ok"]):
		return false
	var q: Dictionary = squads[id]
	if cell == q["cell"]:
		return true
	_release_engaged(id)
	if phases.phase == PHASE_WAVE:
		q["target_cell"] = cell
		q["redeploy_t"] = CDDefs.REDEPLOY_TIME
		q["redeploy_cd"] = CDDefs.REDEPLOY_COOLDOWN
		_emit(&"redeploy", {"id": id, "cell": cell})
	else:
		q["cell"] = cell
		_emit(&"move", {"id": id, "cell": cell})
	return true


## Turn a squad's facing by 45 degrees (cone / arc units).
func turn_squad(id: int, steps: int = 1) -> void:
	if not squads.has(id):
		return
	var q: Dictionary = squads[id]
	q["facing"] = _snap8((q["facing"] as Vector2).rotated(steps * PI / 4.0))


func _release_engaged(squad_id: int) -> void:
	for i: int in enemies.live:
		if e_engaged[i] == squad_id:
			e_engaged[i] = 0


# --- Waves ------------------------------------------------------------------------

func start_wave() -> bool:
	if phases.phase != PHASE_PREP:
		return false
	wave_started_by_auto = auto_countdown >= 0.0 and autostart
	auto_countdown = -1.0
	wave += 1
	if plan.get("wave", -1) != wave:
		plan = make_plan(wave)
	_apply_condense(plan)
	wave_time = 0.0
	kills_this_wave = 0
	leaks_this_wave = 0
	mana_this_wave = 0
	repaired_this_wave = false
	wallet.markup = CDDefs.MIDWAVE_MARKUP
	phases.enter(PHASE_WAVE)
	_emit(&"wave_start", {"wave": wave})
	return true


## Spawn groups for a wave: segments on active sides, telegraph and spawn times.
func make_plan(w: int) -> Dictionary:
	var prng := RandomNumberGenerator.new()
	prng.seed = hash_seed(w)
	var count: int = CDDefs.wave_count(w)
	var size: int = CDDefs.group_size(w)
	var gap: float = CDDefs.group_gap(w)
	var sides: Array = CDDefs.active_sides(w)
	var groups: Array[Dictionary] = []
	var left: int = count
	var t: float = 0.0
	var prev_mid := Vector2(-100, -100)
	while left > 0:
		var n: int = mini(size, left)
		left -= n
		var seg: Dictionary = _pick_segment(prng, sides, prev_mid)
		prev_mid = seg["mid"]
		groups.append({
			"side": seg["side"], "cells": seg["cells"], "count": n, "bodies": n,
			"t_warn": t, "t_spawn": t + CDDefs.TELEGRAPH, "spawned": 0, "next_t": t + CDDefs.TELEGRAPH,
		})
		t += gap
	return {"wave": w, "count": count, "condense": 0, "groups": groups, "sides": sides}


func hash_seed(w: int) -> int:
	return seed_value * 7919 + w * 104729 + 17


func _pick_segment(prng: RandomNumberGenerator, sides: Array, prev_mid: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = -1.0
	for _try: int in 4:
		var side: int = int(sides[prng.randi_range(0, sides.size() - 1)])
		var cells: Array[Vector2i] = grid.side_cells(side)
		var length: int = prng.randi_range(2, 3)
		var start: int = prng.randi_range(2, cells.size() - 3 - length)
		var seg: Array[Vector2i] = []
		for k: int in length:
			var c: Vector2i = cells[start + k]
			if grid.get_tag(c) != BoardGrid.Tag.TERRAIN:
				seg.append(c)
		if seg.is_empty():
			continue
		var mid: Vector2 = (BoardGrid.center_of(seg[0]) + BoardGrid.center_of(seg[seg.size() - 1])) * 0.5
		var d: float = mid.distance_to(prev_mid)
		if d > best_d:
			best_d = d
			best = {"side": side, "cells": seg, "mid": mid}
	return best


## Doc 12.1: projected peak alive Q = rate x average travel time x 0.6; above
## 54 merge pairs (Condensed), above 108 merge fours (Twice-Condensed).
func projected_peak(p: Dictionary) -> float:
	var groups: Array = p["groups"]
	if groups.is_empty():
		return 0.0
	var gap: float = CDDefs.group_gap(int(p["wave"]))
	var size: float = float(CDDefs.group_size(int(p["wave"])))
	var rate: float = size / gap
	var travel: float = average_travel_time()
	return minf(float(p["count"]), rate * travel * 0.6)


func average_travel_time() -> float:
	var total: float = 0.0
	var n: int = 0
	var speed: float = float(CDDefs.ENEMIES[&"stalker"]["speed"])
	for b: Vector2i in grid.border_cells():
		var d: float = flow.distance(b)
		if d < INF:
			total += d
			n += 1
	return (total / n) / speed if n > 0 else 0.0


func _apply_condense(p: Dictionary) -> void:
	var q: float = projected_peak(p)
	p["peak"] = q
	apply_condense_level(p, condense_level_for(q))


## 0 = none, 1 = pairs (Condensed) above 54, 2 = fours above 108.
static func condense_level_for(peak: float) -> int:
	if peak > CDDefs.CONDENSE_THRESHOLD * 2.0:
		return 2
	if peak > CDDefs.CONDENSE_THRESHOLD:
		return 1
	return 0


func apply_condense_level(p: Dictionary, level: int) -> void:
	p["condense"] = level
	var per: int = int(CDDefs.CONDENSE[level]["bodies"])
	for g: Dictionary in p["groups"]:
		g["bodies"] = int(ceil(float(g["count"]) / per))


func wave_bodies(p: Dictionary) -> int:
	var n: int = 0
	for g: Dictionary in p["groups"]:
		n += int(g["bodies"])
	return n


func _spawn_due() -> void:
	for g: Dictionary in plan.get("groups", []):
		if not g.has("warned") and wave_time >= float(g["t_warn"]):
			g["warned"] = true
			_emit(&"telegraph", {"side": g["side"], "cells": g["cells"], "t_spawn": g["t_spawn"]})
		while int(g["spawned"]) < int(g["bodies"]) and wave_time >= float(g["next_t"]):
			if enemies.is_full():
				break
			var cells: Array = g["cells"]
			var c: Vector2i = _free_spawn_cell(cells[int(g["spawned"]) % cells.size()], int(g["side"]))
			var jitter := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
			_spawn_enemy(BoardGrid.center_of(c) + jitter, int(plan["condense"]))
			g["spawned"] = int(g["spawned"]) + 1
			g["next_t"] = float(g["next_t"]) + CDDefs.GROUP_SPACING


## A spawn cell that is free to stand on: the planned one, or the nearest
## free cell along the same side (something was built on it after the plan).
func _free_spawn_cell(c: Vector2i, side: int) -> Vector2i:
	if _standable(BoardGrid.center_of(c)):
		return c
	var best := c
	var best_d: int = 1 << 30
	for o: Vector2i in grid.side_cells(side):
		var d: int = absi(o.x - c.x) + absi(o.y - c.y)
		if d < best_d and _standable(BoardGrid.center_of(o)) and flow.reachable(o):
			best_d = d
			best = o
	return best


func _spawn_enemy(pos: Vector2, condense: int) -> int:
	var i: int = enemies.acquire()
	if i < 0:
		return -1
	var def: Dictionary = CDDefs.ENEMIES[&"stalker"]
	var cd: Dictionary = CDDefs.CONDENSE[condense]
	var hp: float = float(def["hp"]) * CDDefs.hp_multiplier(wave) * float(cd["hp"])
	e_pos[i] = pos
	e_prev[i] = pos
	e_hp[i] = hp
	e_max[i] = hp
	e_speed[i] = float(def["speed"])
	e_armor[i] = int(def["armor"]) + CDDefs.armor_bonus(wave)
	e_condense[i] = condense
	e_engaged[i] = 0
	e_flash[i] = 0.0
	_spawn_serial += 1
	e_serial[i] = _spawn_serial
	_emit(&"spawn", {"slot": i, "pos": pos})
	return i


func all_spawned() -> bool:
	for g: Dictionary in plan.get("groups", []):
		if int(g["spawned"]) < int(g["bodies"]):
			return false
	return true


func _wave_clear() -> void:
	var bonus: int = CDDefs.clear_bonus(wave)
	if leaks_this_wave == 0:
		bonus += CDDefs.NO_LEAK_BONUS
	var got: int = wallet.earn(bonus, &"clear")
	mana_this_wave += got
	crystal_hp = minf(crystal_max, crystal_hp + CDDefs.CRYSTAL_REGEN)
	for q: Dictionary in squads.values():
		var full: float = float(squad_rank_stats(q)["hp"])
		var members: Array = q["members"]
		for k: int in members.size():
			members[k] = full
		if float(q["redeploy_t"]) > 0.0:
			q["cell"] = q["target_cell"]
		q["redeploy_t"] = 0.0
		q["redeploy_cd"] = 0.0
		q["target_cell"] = Vector2i(-9, -9)
	bombs.clear()
	burns.clear()
	# Autostart streak (doc 2.2).
	if autostart and wave_started_by_auto:
		auto_streak = minf(CDDefs.AUTO_CAP - 1.0, auto_streak + (CDDefs.AUTO_BOSS_STEP if wave % 10 == 0 else CDDefs.AUTO_STEP))
	wallet.earn_multiplier = 1.0 + (auto_streak if autostart else 0.0)
	wallet.markup = 1.0
	phases.enter(PHASE_CLEAR, CDDefs.CLEAR_TIME)
	_emit(&"wave_clear", {"wave": wave, "bonus": got, "kills": kills_this_wave, "leaks": leaks_this_wave, "mana": mana_this_wave})


func set_autostart(on: bool) -> void:
	if on == autostart:
		return
	autostart = on
	if not on:
		auto_streak = 0.0
		auto_countdown = -1.0
	elif phases.phase == PHASE_PREP and wave > 0:
		auto_countdown = CDDefs.AUTOSTART_DELAY
	wallet.earn_multiplier = 1.0 + (auto_streak if autostart else 0.0)
	_emit(&"autostart", {"on": on})


## Tap on the Autostart countdown: take a prep this wave (resets the streak).
func cancel_autostart_countdown() -> void:
	if auto_countdown >= 0.0:
		auto_countdown = -1.0
		auto_streak = 0.0
		wallet.earn_multiplier = 1.0


func auto_multiplier() -> float:
	return 1.0 + (auto_streak if autostart else 0.0)


func _enter_prep() -> void:
	prep_serial += 1
	wallet.markup = 1.0
	phases.enter(PHASE_PREP)
	plan = make_plan(wave + 1)
	plan["peak"] = projected_peak(plan)
	auto_countdown = CDDefs.AUTOSTART_DELAY if autostart and wave > 0 else -1.0
	_emit(&"prep", {"wave": wave + 1})


func _defeat() -> void:
	phases.enter(PHASE_DEFEAT)
	wallet.markup = 1.0
	_emit(&"defeat", {"wave": wave, "kills": total_kills})


# --- Tick -------------------------------------------------------------------------

func tick(dt: float = STEP) -> void:
	time += dt
	var timed_out: StringName = phases.advance(dt)
	match phases.phase:
		PHASE_INTRO:
			if timed_out == PHASE_INTRO:
				_enter_prep()
		PHASE_CLEAR:
			if timed_out == PHASE_CLEAR:
				_enter_prep()
		PHASE_PREP:
			if auto_countdown >= 0.0 and autostart:
				auto_countdown -= dt
				if auto_countdown <= 0.0:
					auto_countdown = 0.0
					start_wave()
		PHASE_WAVE:
			_tick_wave(dt)


func _tick_wave(dt: float) -> void:
	wave_time += dt
	_spawn_due()
	for i: int in enemies.live:
		e_prev[i] = e_pos[i]
		if e_flash[i] > 0.0:
			e_flash[i] = maxf(0.0, e_flash[i] - dt)
	_rebuild_hash()
	_tick_squads(dt)
	_move_enemies(dt)
	_rebuild_hash()
	_tick_towers(dt)
	_tick_bombs(dt)
	_tick_burns(dt)
	_tick_storm(dt)
	if crystal_hp <= 0.0:
		crystal_hp = 0.0
		_defeat()
		return
	if all_spawned() and enemies.count() == 0:
		_wave_clear()


func _rebuild_hash() -> void:
	space.clear()
	for i: int in enemies.live:
		space.insert(i, e_pos[i])


func _move_enemies(dt: float) -> void:
	var dead: Array[int] = []
	var def: Dictionary = CDDefs.ENEMIES[&"stalker"]
	for i: int in enemies.live:
		var sq: int = e_engaged[i]
		if sq != 0:
			if squads.has(sq) and squad_alive(squads[sq]) > 0 and float(squads[sq]["redeploy_t"]) <= 0.0:
				_enemy_hits_squad(sq, float(def["melee_dps"]) * dt)
				continue
			e_engaged[i] = 0
		var pos: Vector2 = e_pos[i]
		var cell := Vector2i(floori(pos.x), floori(pos.y))
		if grid.get_tag(cell) == BoardGrid.Tag.GOAL:
			_leak(i)
			dead.append(i)
			continue
		var dir: Vector2 = flow.direction_at(pos)
		if dir == Vector2.ZERO:
			dir = (crystal_center - pos).normalized()
		var step: Vector2 = dir * e_speed[i] * dt
		# Light separation from neighbours.
		var push := Vector2.ZERO
		for j: int in space.query(pos, 0.45):
			if j == i:
				continue
			var away: Vector2 = pos - e_pos[j]
			var d: float = away.length()
			if d > 0.0001 and d < 0.45:
				push += away / d * (0.45 - d)
			elif d <= 0.0001:
				push += Vector2(0.01 * (1 if i > j else -1), 0.0)
		step += push * 0.6 * dt
		var np: Vector2 = pos + step
		if not _standable(np):
			np = pos + dir * e_speed[i] * dt
			if not _standable(np):
				np = pos
		e_pos[i] = np
	for i: int in dead:
		enemies.release(i)


func _standable(p: Vector2) -> bool:
	var c := Vector2i(floori(p.x), floori(p.y))
	if not grid.in_bounds(c):
		return false
	var idx: int = grid.index(c)
	return grid.tags[idx] != BoardGrid.Tag.TERRAIN and grid.occupant[idx] == 0


func _leak(i: int) -> void:
	var dmg: float = float(CDDefs.ENEMIES[&"stalker"]["crystal_damage"]) * float(CDDefs.CONDENSE[e_condense[i]]["crystal"])
	crystal_hp -= dmg
	leaks_this_wave += 1
	_emit(&"crystal_hit", {"damage": dmg, "pos": e_pos[i], "slot": i})


## Damage an enemy (armor applies, minimum 1). Returns true if it died.
func damage_enemy(i: int, amount: float, source: Dictionary = {}) -> bool:
	if not enemies.is_alive(i):
		return false
	var dealt: float = maxf(1.0, amount - e_armor[i]) if amount >= 1.0 else maxf(0.0, amount)
	e_hp[i] -= dealt
	e_flash[i] = 0.12
	if e_hp[i] <= 0.0:
		_kill(i, source)
		return true
	return false


func _kill(i: int, source: Dictionary) -> void:
	var def: Dictionary = CDDefs.ENEMIES[&"stalker"]
	var reward: int = int(def["mana"]) * int(CDDefs.CONDENSE[e_condense[i]]["reward"])
	var got: int = wallet.earn(reward, &"kill")
	mana_this_wave += got
	kills_this_wave += 1
	total_kills += 1
	var sq: int = int(source.get("squad", 0))
	if sq != 0 and squads.has(sq):
		squads[sq]["exp"] = float(squads[sq]["exp"]) + float(def["exp"]) * int(CDDefs.CONDENSE[e_condense[i]]["reward"])
	_emit(&"death", {"slot": i, "pos": e_pos[i], "mana": got, "condense": e_condense[i], "serial": e_serial[i]})
	enemies.release(i)


func _target_first(center: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in space.query(center, radius):
		if not enemies.is_alive(i):
			continue
		var d: float = flow.distance(Vector2i(floori(e_pos[i].x), floori(e_pos[i].y)))
		if d < best_d or (d == best_d and best >= 0 and e_serial[i] < e_serial[best]):
			best_d = d
			best = i
	return best


func _tick_towers(dt: float) -> void:
	for s: Dictionary in structures.values():
		if CDDefs.is_barrier(s["type"]):
			continue
		s["cooldown"] = maxf(0.0, float(s["cooldown"]) - dt)
		if float(s["cooldown"]) > 0.0:
			continue
		var st: Dictionary = CDDefs.level_stats(s["type"], int(s["level"]))
		var center: Vector2 = BoardGrid.center_of(s["cell"])
		var target: int = _target_first(center, float(st["range"]))
		if target < 0:
			continue
		s["cooldown"] = 1.0 / float(st["rate"])
		s["shots"] = int(s["shots"]) + 1
		if s["type"] == &"arrow":
			var to: Vector2 = e_pos[target]
			_emit(&"arrow", {"from": center, "to": to, "id": s["id"]})
			damage_enemy(target, float(st["damage"]))
			if st.has("double_every") and int(s["shots"]) % int(st["double_every"]) == 0:
				var second: int = -1
				var best_d: float = INF
				for j: int in space.query(center, float(st["range"])):
					if j == target or not enemies.is_alive(j):
						continue
					var d: float = flow.distance(Vector2i(floori(e_pos[j].x), floori(e_pos[j].y)))
					if d < best_d:
						best_d = d
						second = j
				if second >= 0:
					_emit(&"arrow", {"from": center, "to": e_pos[second], "id": s["id"]})
					damage_enemy(second, float(st["damage"]))
		elif s["type"] == &"bombard":
			bombs.append({
				"from": center, "to": e_pos[target], "t": 0.0, "dur": 0.6, "damage": float(st["damage"]),
				"splash": float(st["splash"]), "burn_dps": float(st.get("burn_dps", 0.0)), "burn_time": float(st.get("burn_time", 0.0)),
			})
			_emit(&"bomb_launch", {"from": center, "to": e_pos[target], "id": s["id"]})


func _tick_bombs(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for b: Dictionary in bombs:
		b["t"] = float(b["t"]) + dt
		if float(b["t"]) < float(b["dur"]):
			keep.append(b)
			continue
		var at: Vector2 = b["to"]
		for i: int in space.query(at, float(b["splash"]) + STALKER_RADIUS):
			damage_enemy(i, float(b["damage"]))
		if float(b["burn_time"]) > 0.0:
			burns.append({"pos": at, "radius": float(b["splash"]), "t": float(b["burn_time"]), "dps": float(b["burn_dps"])})
		_emit(&"explode", {"pos": at, "radius": b["splash"]})
	bombs = keep


func _tick_burns(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for p: Dictionary in burns:
		p["t"] = float(p["t"]) - dt
		for i: int in space.query(p["pos"], float(p["radius"])):
			if enemies.is_alive(i):
				e_hp[i] -= float(p["dps"]) * dt
				if e_hp[i] <= 0.0:
					_kill(i, {})
		if float(p["t"]) > 0.0:
			keep.append(p)
	burns = keep


func _tick_storm(dt: float) -> void:
	storm_t -= dt
	if storm_t > 0.0:
		return
	var best: int = -1
	var best_d: float = INF
	for i: int in space.query(crystal_center, CDDefs.STORM_RANGE + 1.0):
		if not enemies.is_alive(i):
			continue
		var d: float = e_pos[i].distance_to(crystal_center) - 1.0
		if d <= CDDefs.STORM_RANGE and d < best_d:
			best_d = d
			best = i
	if best < 0:
		storm_t = 0.0
		return
	storm_t = CDDefs.STORM_PERIOD
	_emit(&"storm", {"to": e_pos[best]})
	damage_enemy(best, CDDefs.STORM_DAMAGE)


func _tick_squads(dt: float) -> void:
	for q: Dictionary in squads.values():
		var id: int = int(q["id"])
		q["redeploy_cd"] = maxf(0.0, float(q["redeploy_cd"]) - dt)
		if float(q["redeploy_t"]) > 0.0:
			q["redeploy_t"] = float(q["redeploy_t"]) - dt
			if float(q["redeploy_t"]) <= 0.0:
				q["redeploy_t"] = 0.0
				q["cell"] = q["target_cell"]
				q["target_cell"] = Vector2i(-9, -9)
				_emit(&"redeployed", {"id": id})
			continue
		var alive: int = squad_alive(q)
		if alive == 0:
			continue
		var stats: Dictionary = squad_rank_stats(q)
		var center: Vector2 = BoardGrid.center_of(q["cell"])
		var facing: Vector2 = q["facing"]
		var reach: float = float(stats["reach"]) + ENGAGE_EXTRA + 0.5
		var half_arc: float = deg_to_rad(float(CDDefs.UNITS[q["unit"]]["arc_deg"])) * 0.5
		# Engage enemies in the arc, up to one per standing member.
		var engaged: int = 0
		for i: int in enemies.live:
			if e_engaged[i] == id:
				engaged += 1
		for i: int in space.query(center, reach):
			if engaged >= alive:
				break
			if e_engaged[i] != 0:
				continue
			if in_arc(center, facing, half_arc, e_pos[i]):
				e_engaged[i] = id
				engaged += 1
		# Attack.
		q["cooldown"] = maxf(0.0, float(q["cooldown"]) - dt)
		if float(q["cooldown"]) > 0.0:
			continue
		var target: int = -1
		var low: float = INF
		for i: int in space.query(center, reach):
			if not enemies.is_alive(i):
				continue
			if e_engaged[i] == id or in_arc(center, facing, half_arc, e_pos[i]):
				if e_hp[i] < low:
					low = e_hp[i]
					target = i
		if target < 0:
			continue
		q["cooldown"] = 1.0 / float(stats["rate"])
		var dmg: float = float(stats["damage"]) * alive
		_emit(&"squad_hit", {"id": id, "to": e_pos[target]})
		damage_enemy(target, dmg, {"squad": id})
		if float(stats["lifesteal"]) > 0.0:
			_heal_squad(q, dmg * float(stats["lifesteal"]))


static func in_arc(center: Vector2, facing: Vector2, half_arc: float, p: Vector2) -> bool:
	var to: Vector2 = p - center
	if to.length() < 0.3:
		return true
	return absf(facing.angle_to(to)) <= half_arc + 0.0001


func _enemy_hits_squad(squad_id: int, amount: float) -> void:
	var q: Dictionary = squads[squad_id]
	var members: Array = q["members"]
	for k: int in members.size():
		if float(members[k]) > 0.0:
			members[k] = float(members[k]) - amount
			if float(members[k]) <= 0.0:
				members[k] = 0.0
				_emit(&"knockout", {"id": squad_id, "member": k})
				# Release enemies above the new capacity.
				var cap: int = squad_alive(q)
				var n: int = 0
				for i: int in enemies.live:
					if e_engaged[i] == squad_id:
						n += 1
						if n > cap:
							e_engaged[i] = 0
			return


func _heal_squad(q: Dictionary, amount: float) -> void:
	var full: float = float(squad_rank_stats(q)["hp"])
	var members: Array = q["members"]
	for k: int in members.size():
		if float(members[k]) > 0.0 and float(members[k]) < full:
			members[k] = minf(full, float(members[k]) + amount)
			return


func _emit(kind: StringName, data: Dictionary = {}) -> void:
	data["kind"] = kind
	events.append(data)
	if events.size() > 512:
		events.pop_front()


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


## Run snapshot for the platform save (platform-accounts doc 3.8, slot "run"),
## valid at a clean checkpoint (prep). Not persisted yet.
func to_run_save() -> Dictionary:
	var towers: Array = []
	for s: Dictionary in structures.values():
		towers.append({"kind": str(s["type"]), "cell": [s["cell"].x, s["cell"].y], "level": s["level"], "target": "first"})
	var sq: Array = []
	for q: Dictionary in squads.values():
		sq.append({"unit": str(q["unit"]), "rank": q["rank"], "size": squad_size(q), "exp": q["exp"], "upgrades": q["upgrades"], "cell": [q["cell"].x, q["cell"].y]})
	return {
		"world": "cryptid", "difficulty": "normal", "tier": "table", "grid": [grid.nx, grid.ny],
		"wave": wave, "seed": seed_value,
		"crystal_hp": crystal_hp, "wallet": wallet.to_save(), "towers": towers, "squads": sq,
		"autostart_streak": auto_streak,
	}
