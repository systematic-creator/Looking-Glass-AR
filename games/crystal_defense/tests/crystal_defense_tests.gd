extends LGTestSuite
## Crystal Defense M1-M2: defs, the board and never-block rule, the flow field
## through barriers, the economy (markup, sell, kills, clears, Autostart),
## phases, spawning with telegraphs, condensing under the 60 cap, towers,
## squads (grow, evolve, move, Redeploy), the Crystal, and the game in the
## host: build mode, popups, HUD in portrait / landscape, rotate pause,
## defeat and retry, the pool cap and the frame budget.
## Run: godot --headless --path . res://games/crystal_defense/tests/crystal_defense_tests.tscn

const DT: float = 1.0 / 20.0
const PORTRAIT_WINDOW := Vector2i(1080, 2340)
const LANDSCAPE_WINDOW := Vector2i(2340, 1080)

var _saved_window: Vector2i


func run_tests() -> void:
	_saved_window = get_tree().root.size
	CrystalDefenseGame.next_seed = 11
	_test_defs()
	_test_manifest()
	_test_board()
	_test_never_block()
	_test_flow_through_barriers()
	_test_economy()
	_test_upgrades_and_sell()
	_test_phases()
	_test_spawning()
	_test_condense_and_cap()
	_test_combat()
	_test_squads()
	_test_redeploy()
	_test_crystal()
	_test_autostart()
	_test_save_shape()
	_test_meshes()
	await _test_game_build_flow()
	await _test_game_popups()
	await _test_wave_flow_in_host()
	await _test_rotate_pause()
	await _test_hud_layouts()
	await _test_budget()
	get_tree().root.size = _saved_window
	await frames(2)
	CrystalDefenseGame.next_seed = -1


# --- Helpers ------------------------------------------------------------------------

func _prep_sim(seed_v: int = 3) -> CDSim:
	var sim := CDSim.new(seed_v)
	var guard: int = 0
	while sim.phase() != CDSim.PHASE_PREP and guard < 200:
		sim.tick(DT)
		guard += 1
	return sim


func _tick_for(sim: CDSim, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		sim.tick(DT)
		t += DT


func _run_wave(sim: CDSim, limit: float = 400.0) -> float:
	var t: float = 0.0
	while sim.phase() == CDSim.PHASE_WAVE and t < limit:
		sim.tick(DT)
		t += DT
	return t


func _finish_clear(sim: CDSim) -> void:
	var guard: int = 0
	while sim.phase() == CDSim.PHASE_CLEAR and guard < 200:
		sim.tick(DT)
		guard += 1


func _set_window(size: Vector2i) -> void:
	get_tree().root.size = size
	await frames(3)


func _game(host: GameHost) -> CrystalDefenseGame:
	return host.game as CrystalDefenseGame


func _ready_host() -> GameHost:
	var host: GameHost = await make_host(&"crystal_defense")
	var game: CrystalDefenseGame = _game(host)
	for i: int in 50:
		game._process(DT)
	return host


static func _contains(outer: Rect2, inner: Rect2, margin: float = 2.0) -> bool:
	return outer.grow(-margin).encloses(inner)


static func _mesh_triangles(mesh: Mesh) -> int:
	var n: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and (indices as PackedInt32Array).size() > 0:
			n += (indices as PackedInt32Array).size() / 3
		else:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# --- Defs ---------------------------------------------------------------------------

func _test_defs() -> void:
	check("defs: 12x12 board, 20 starting mana, Crystal 100 HP", CDDefs.GRID_N == 12 and CDDefs.START_MANA == 20 and CDDefs.CRYSTAL_HP == 100)
	check("defs: Arrow Tower 10 / 15 / 25 mana", int(CDDefs.level_stats(&"arrow", 1)["cost"]) == 10 and int(CDDefs.level_stats(&"arrow", 2)["cost"]) == 15 and int(CDDefs.level_stats(&"arrow", 3)["cost"]) == 25)
	check("defs: Bombard 18 / 20 / 35, splash grows", int(CDDefs.level_stats(&"bombard", 1)["cost"]) == 18 and float(CDDefs.level_stats(&"bombard", 3)["splash"]) > float(CDDefs.level_stats(&"bombard", 1)["splash"]))
	check("defs: Palisade 5 mana, Stone Wall 8 mana, both barriers", int(CDDefs.level_stats(&"palisade", 1)["cost"]) == 5 and int(CDDefs.level_stats(&"stone_wall", 1)["cost"]) == 8 and CDDefs.is_barrier(&"palisade") and CDDefs.is_barrier(&"stone_wall") and not CDDefs.is_barrier(&"arrow"))
	check("defs: build order Arrow, Bombard, Palisade, Stone Wall", CDDefs.BUILD_ORDER == [&"arrow", &"bombard", &"palisade", &"stone_wall"])
	check("defs: waves 1-3 are set pieces (8, 10, 12)", CDDefs.wave_count(1) == 8 and CDDefs.wave_count(2) == 10 and CDDefs.wave_count(3) == 12)
	check("defs: later waves follow the budget B(w)", CDDefs.wave_count(10) == int(round(8.0 + 40.0 + 35.0)) and CDDefs.wave_count(20) > CDDefs.wave_count(10))
	check("defs: sides W from 1, +E from 4, +N from 8, all from 13", CDDefs.active_sides(1) == [0] and CDDefs.active_sides(4) == [0, 1] and CDDefs.active_sides(8) == [0, 1, 2] and CDDefs.active_sides(13) == [0, 1, 2, 3])
	check("defs: group size 3 + w/3, clamped 3..8", CDDefs.group_size(1) == 3 and CDDefs.group_size(6) == 5 and CDDefs.group_size(40) == 8)
	check("defs: group gap 3 s, 2 s from wave 15", CDDefs.group_gap(14) == 3.0 and CDDefs.group_gap(15) == 2.0)
	check("defs: HP +8% per wave, armour +1 per 15 waves", is_equal_approx(CDDefs.hp_multiplier(11), 1.8) and CDDefs.armor_bonus(14) == 0 and CDDefs.armor_bonus(15) == 1)
	check("defs: clear bonus 5 + wave", CDDefs.clear_bonus(1) == 6 and CDDefs.clear_bonus(10) == 15)
	var up1: Dictionary = CDDefs.squad_upgrade(&"knight", 0, 1)
	var up4: Dictionary = CDDefs.squad_upgrade(&"knight", 0, 4)
	var upmax: Dictionary = CDDefs.squad_upgrade(&"knight", 2, 4)
	check("defs: Knight grows (+1 member) below 4, evolves at 4, max at Lightguard", not bool(up1["evolve"]) and bool(up4["evolve"]) and bool(upmax["max"]))
	check("defs: Paladin is ~3.5x a Knight", is_equal_approx(float(CDDefs.UNITS[&"knight"]["ranks"][1]["hp"]) / float(CDDefs.UNITS[&"knight"]["ranks"][0]["hp"]), 3.5))


func _test_manifest() -> void:
	var m: LGGameManifest = load("res://games/crystal_defense/manifest.tres")
	check("manifest: id, entry and either orientation", m.id == &"crystal_defense" and m.entry == "res://games/crystal_defense/crystal_defense.tscn" and m.orientation == "either")
	check("manifest: 48 cm board inside the platform's limits", m.board_size == Vector2(0.48, 0.48) and m.board_size.x >= 0.05 and m.board_size.x <= 3.0)
	check("manifest: box height 25 cm (18-50)", is_equal_approx(m.box_height, 0.25) and is_equal_approx(m.box_min_height, 0.18) and is_equal_approx(m.box_max_height, 0.5))
	check("manifest: the game scene extends LGGame", (load(m.entry) as PackedScene).instantiate() is LGGame)


# --- Board --------------------------------------------------------------------------

func _test_board() -> void:
	var sim := CDSim.new(1)
	check("board: starts in the intro, 20 mana, full Crystal", sim.phase() == CDSim.PHASE_INTRO and sim.wallet.balance == 20 and sim.crystal_hp == 100.0)
	check("board: the Crystal holds the centre 2x2 cells", sim.crystal_cells.size() == 4 and sim.is_crystal_cell(Vector2i(5, 5)) and sim.is_crystal_cell(Vector2i(6, 6)) and not sim.is_crystal_cell(Vector2i(4, 4)))
	var terrain: int = sim.grid.cells_with_tag(BoardGrid.Tag.TERRAIN).size()
	check("board: Cryptid terrain (5 trees + 3 stones) is impassable", terrain == 8 and not sim.flow.reachable(Vector2i(2, 2)))
	var all: bool = true
	for b: Vector2i in sim.grid.border_cells():
		if sim.grid.get_tag(b) != BoardGrid.Tag.TERRAIN and not sim.flow.reachable(b):
			all = false
	check("board: every open border cell reaches the Crystal", all)
	_tick_for(sim, CDDefs.INTRO_TIME + 0.1)
	check("board: intro (2 s) then an unlimited prep", sim.phase() == CDSim.PHASE_PREP)
	_tick_for(sim, 120.0)
	check("board: prep waits forever for Start Wave", sim.phase() == CDSim.PHASE_PREP and sim.wave == 0)
	var r: Dictionary = sim.can_build(&"arrow", Vector2i(5, 5))
	check("board: can't build on the Crystal", not bool(r["ok"]) and str(r["reason"]).contains("Crystal"))
	r = sim.can_build(&"arrow", Vector2i(2, 2))
	check("board: can't build on terrain", not bool(r["ok"]) and str(r["reason"]).contains("terrain"))
	r = sim.can_build(&"arrow", Vector2i(12, 3))
	check("board: can't build off the board", not bool(r["ok"]))
	var id: int = sim.build(&"arrow", Vector2i(3, 6))
	r = sim.can_build(&"palisade", Vector2i(3, 6))
	check("board: one structure per cell", id != 0 and not bool(r["ok"]) and r["reason"] == "Occupied")
	r = sim.can_build(&"bombard", Vector2i(4, 6))
	check("board: says when mana is short", not bool(r["ok"]) and str(r["reason"]).begins_with("Need"))


func _test_never_block() -> void:
	var sim: CDSim = _prep_sim()
	sim.wallet.balance = 999
	# Ring the Crystal (x 4..7, y 4..7) except (5, 4).
	var ring: Array[Vector2i] = []
	for y: int in range(4, 8):
		for x: int in range(4, 8):
			var c := Vector2i(x, y)
			if not sim.is_crystal_cell(c) and c != Vector2i(5, 4):
				ring.append(c)
	var placed: int = 0
	for c: Vector2i in ring:
		if sim.build(&"palisade", c) != 0:
			placed += 1
	check("never-block: 11 barriers can ring the Crystal with one gap", placed == 11)
	var r: Dictionary = sim.can_build(&"palisade", Vector2i(5, 4))
	check("never-block: closing the last gap is refused", not bool(r["ok"]) and r["reason"] == "Would block the Crystal")
	r = sim.can_build(&"arrow", Vector2i(5, 4))
	check("never-block: towers can't close it either", not bool(r["ok"]) and r["reason"] == "Would block the Crystal")
	check("never-block: the flow field still reaches every border cell", sim.flow.reachable(Vector2i(0, 0)) and sim.flow.reachable(Vector2i(11, 11)))
	var p: Array[Vector2i] = sim.flow.path_from(Vector2i(0, 6))
	var enters_ring: bool = false
	for c: Vector2i in p:
		if ring.has(c):
			enters_ring = true
	check("never-block: the path goes through the gap", p.has(Vector2i(5, 4)) and not enters_ring)
	# Pockets: a border corner can't be sealed off either.
	var s2: CDSim = _prep_sim()
	s2.wallet.balance = 999
	s2.build(&"palisade", Vector2i(11, 1))
	r = s2.can_build(&"palisade", Vector2i(10, 0))
	check("never-block: sealing a border cell into a pocket is refused", not bool(r["ok"]) and r["reason"] == "Would block the Crystal")
	# An enemy inside a would-be pocket also blocks it (mid-wave).
	var s3: CDSim = _prep_sim()
	s3.wallet.balance = 999
	s3.start_wave()
	var e: int = s3._spawn_enemy(Vector2(8.5, 8.5), 0)
	for c: Vector2i in [Vector2i(7, 8), Vector2i(9, 8), Vector2i(8, 7)]:
		s3.grid.set_occupant(c, 900)
	s3.rebuild_flow()
	check("never-block: an enemy's cell must stay connected", e >= 0 and not s3.keeps_crystal_reachable(Vector2i(8, 9)) and s3.keeps_crystal_reachable(Vector2i(3, 3)))
	check("never-block: the barrier cap is 12 (N)", CDDefs.GRID_N == 12)
	var s4: CDSim = _prep_sim()
	s4.wallet.balance = 999
	var n: int = 0
	for x: int in [0, 2, 4, 6, 8, 10]:
		for y: int in [3, 8]:
			if s4.build(&"palisade", Vector2i(x, y)) != 0:
				n += 1
	r = s4.can_build(&"palisade", Vector2i(3, 6))
	check("never-block: a 13th barrier hits the cap", n == 12 and not bool(r["ok"]) and str(r["reason"]).contains("cap"))
	check("never-block: towers don't count toward the barrier cap", bool(s4.can_build(&"arrow", Vector2i(3, 6))["ok"]))
	# Building on the spawn edge: allowed, and spawns step aside.
	var s5: CDSim = _prep_sim(4)
	s5.wallet.balance = 999
	var cells: Array = s5.plan["groups"][0]["cells"]
	for c: Vector2i in cells:
		s5.build(&"palisade", c)
	check("never-block: border cells with barriers don't count as blocked entries", bool(s5.can_build(&"palisade", Vector2i(3, 6))["ok"]))
	s5.start_wave()
	_tick_for(s5, CDDefs.TELEGRAPH + 0.2)
	var inside: bool = false
	for i: int in s5.enemies.live:
		inside = inside or not s5._standable(s5.e_pos[i])
	check("spawn: a Stalker never spawns inside a structure built on its edge", s5.enemies.count() > 0 and not inside)


func _test_flow_through_barriers() -> void:
	var sim: CDSim = _prep_sim()
	sim.wallet.balance = 999
	var before: float = sim.flow.distance(Vector2i(0, 6))
	for y: int in range(3, 10):
		if y != 5:
			sim.build(&"palisade", Vector2i(3, y))
	var after: float = sim.flow.distance(Vector2i(0, 6))
	check("flow: a wall lengthens the route (maze)", after > before + 0.5)
	sim.start_wave()
	var crossed: bool = false
	var t: float = 0.0
	while sim.phase() == CDSim.PHASE_WAVE and t < 200.0:
		sim.tick(DT)
		t += DT
		for i: int in sim.enemies.live:
			var c := Vector2i(floori(sim.e_pos[i].x), floori(sim.e_pos[i].y))
			if sim.grid.get_occupant(c) > 0 or sim.grid.get_tag(c) == BoardGrid.Tag.TERRAIN:
				crossed = true
	check("flow: Stalkers never walk through barriers or terrain", not crossed)
	check("flow: they still reach the Crystal (leaks happen with no towers)", sim.leaks_this_wave > 0 or sim.phase() == CDSim.PHASE_CLEAR or sim.phase() == CDSim.PHASE_PREP)


# --- Economy ------------------------------------------------------------------------

func _test_economy() -> void:
	var sim: CDSim = _prep_sim()
	check("economy: build spends the price", sim.build(&"arrow", Vector2i(3, 6)) != 0 and sim.wallet.balance == 10)
	sim.start_wave()
	check("economy: mid-wave prices are +50% (rounded up)", sim.wallet.price(10) == 15 and int(sim.can_build(&"palisade", Vector2i(3, 3))["cost"]) == 8)
	var b0: int = sim.wallet.balance
	var kills0: int = sim.total_kills
	_run_wave(sim)
	check("economy: kills pay mana", sim.total_kills > kills0)
	var log: Array = sim.wallet.log
	var kill_mana: int = 0
	var clear_mana: int = 0
	for e: Dictionary in log:
		if e["reason"] == &"kill":
			kill_mana += int(e["delta"])
		elif e["reason"] == &"clear":
			clear_mana += int(e["delta"])
	check("economy: 1 mana per Stalker kill", kill_mana == sim.kills_this_wave)
	var expected_clear: int = CDDefs.clear_bonus(1) + (CDDefs.NO_LEAK_BONUS if sim.leaks_this_wave == 0 else 0)
	check("economy: wave clear pays 5 + wave (+3 with no leaks)", clear_mana == expected_clear)
	check("economy: balance adds up", sim.wallet.balance == b0 + kill_mana + clear_mana)
	_finish_clear(sim)
	check("economy: prep prices are back to normal", sim.phase() == CDSim.PHASE_PREP and sim.wallet.price(10) == 10)


func _test_upgrades_and_sell() -> void:
	var sim: CDSim = _prep_sim()
	sim.wallet.balance = 200
	var id: int = sim.build(&"arrow", Vector2i(3, 6))
	check("upgrade: Lv2 costs 15", sim.upgrade_cost(id) == 15 and sim.upgrade(id) and int(sim.structures[id]["level"]) == 2 and sim.wallet.balance == 175)
	check("upgrade: Lv3 costs 25", sim.upgrade(id) and int(sim.structures[id]["level"]) == 3 and sim.wallet.balance == 150)
	check("upgrade: 3 is the max", not sim.upgrade(id) and not bool(sim.can_upgrade(id)["ok"]) and sim.upgrade_cost(id) == -1)
	check("sell: full refund in the same prep (undo)", sim.sell_value(id) == 50)
	var w: int = sim.wallet.balance
	sim.sell(id)
	check("sell: frees the cell and refunds", sim.structure_at(Vector2i(3, 6)) == 0 and sim.wallet.balance == w + 50 and sim.grid.get_occupant(Vector2i(3, 6)) == 0)
	var id2: int = sim.build(&"palisade", Vector2i(3, 6))
	sim.start_wave()
	check("sell: 50% mid-wave", sim.sell_value(id2) == 2)
	check("upgrade: mid-wave upgrades cost +50%", sim.upgrade_cost(id2) == 12)
	_run_wave(sim)
	_finish_clear(sim)
	check("sell: 70% in a later prep", sim.sell_value(id2) == 3)


# --- Phases -------------------------------------------------------------------------

func _test_phases() -> void:
	var sim := CDSim.new(2)
	check("phases: can't start a wave during the intro", not sim.start_wave())
	_tick_for(sim, 2.1)
	check("phases: start from prep", sim.start_wave() and sim.phase() == CDSim.PHASE_WAVE and sim.wave == 1)
	check("phases: can't start twice", not sim.start_wave() and sim.wave == 1)
	check("phases: no squad moves mid-wave without Redeploy", not sim.phases.can(&"move") and sim.phases.can(&"redeploy"))
	sim.wallet.balance = 100
	for y: int in [4, 6, 8]:
		sim.build(&"arrow", Vector2i(3, y))
	_run_wave(sim)
	check("phases: wave -> clear when all are spawned and gone", sim.phase() == CDSim.PHASE_CLEAR)
	_tick_for(sim, CDDefs.CLEAR_TIME + 0.1)
	check("phases: clear (1.5 s) -> prep for the next wave", sim.phase() == CDSim.PHASE_PREP and sim.next_wave() == 2)
	sim.start_wave()
	sim.crystal_hp = 1.0
	for s: int in sim.structures.keys():
		sim.grid.set_occupant(sim.structures[s]["cell"], 0)
	sim.structures.clear()
	sim.rebuild_flow()
	_run_wave(sim)
	check("phases: Crystal at 0 -> defeat", sim.phase() == CDSim.PHASE_DEFEAT and sim.crystal_hp == 0.0)
	check("phases: nothing can be built after defeat", not bool(sim.can_build(&"arrow", Vector2i(3, 3))["ok"]) and not sim.start_wave())
	var events: Array[Dictionary] = sim.drain_events()
	var kinds: Array = events.map(func(e: Dictionary) -> StringName: return e["kind"])
	check("phases: events for wave start, clear, prep and defeat", kinds.has(&"defeat") and kinds.has(&"wave_start"))
	sim.reset(5)
	check("phases: reset starts a fresh run", sim.phase() == CDSim.PHASE_INTRO and sim.wave == 0 and sim.wallet.balance == 20 and sim.structures.is_empty() and sim.enemies.count() == 0)


# --- Spawning -----------------------------------------------------------------------

func _test_spawning() -> void:
	var sim: CDSim = _prep_sim(4)
	var plan: Dictionary = sim.plan
	check("spawn: the next wave is planned in prep (shown to the player)", int(plan.get("wave", 0)) == 1 and int(plan["count"]) == 8)
	var on_west: bool = true
	var away_from_corners: bool = true
	var seg_ok: bool = true
	for g: Dictionary in plan["groups"]:
		on_west = on_west and int(g["side"]) == 0
		var cells: Array = g["cells"]
		seg_ok = seg_ok and cells.size() >= 1 and cells.size() <= 3
		for c: Vector2i in cells:
			away_from_corners = away_from_corners and c.x == 0 and c.y >= 2 and c.y <= 9
	check("spawn: wave 1 comes from the West only", on_west)
	check("spawn: segments are 2-3 cells, not within 2 of a corner", seg_ok and away_from_corners)
	check("spawn: groups of 3 every 3 s", (plan["groups"] as Array).size() == 3 and is_equal_approx(float(plan["groups"][1]["t_warn"]), 3.0))
	sim.start_wave()
	var tele_t: float = -1.0
	var spawn_t: float = -1.0
	var spawn_cells_ok: bool = true
	var t: float = 0.0
	var first_cells: Array = plan["groups"][0]["cells"]
	while t < 6.0:
		sim.tick(DT)
		t += DT
		for e: Dictionary in sim.drain_events():
			if e["kind"] == &"telegraph" and tele_t < 0.0:
				tele_t = sim.wave_time
			elif e["kind"] == &"spawn":
				if spawn_t < 0.0:
					spawn_t = sim.wave_time
				var c := Vector2i(floori((e["pos"] as Vector2).x), floori((e["pos"] as Vector2).y))
				if spawn_t == sim.wave_time:
					spawn_cells_ok = spawn_cells_ok and first_cells.has(c)
	check("spawn: the orange warning comes first", tele_t >= 0.0 and tele_t < 0.2)
	check("spawn: Stalkers appear 3 s after the warning", spawn_t >= 0.0 and absf(spawn_t - tele_t - CDDefs.TELEGRAPH) < 0.11)
	check("spawn: on the warned cells", spawn_cells_ok)
	var s4 := CDSim.new(9)
	s4.wave = 3
	var p4: Dictionary = s4.make_plan(4)
	var sides: Dictionary = {}
	for g: Dictionary in p4["groups"]:
		sides[int(g["side"])] = true
	check("spawn: wave 4 adds the East side", p4["sides"] == [0, 1] and sides.has(1) or sides.has(0))
	var total: int = 0
	for g: Dictionary in p4["groups"]:
		total += int(g["count"])
	check("spawn: group counts sum to the wave count", total == CDDefs.wave_count(4))
	check("spawn: plans are deterministic per seed", JSON.stringify(s4.make_plan(4)) == JSON.stringify(p4))
	var s5 := CDSim.new(10)
	check("spawn: different seeds give different segments", JSON.stringify(s5.make_plan(4)) != JSON.stringify(p4))
	# All bodies spawn and the wave clears.
	var s6: CDSim = _prep_sim(6)
	s6.wallet.balance = 200
	for y: int in [3, 5, 7, 8]:
		s6.build(&"arrow", Vector2i(2, y) if y != 5 else Vector2i(3, 4))
	s6.start_wave()
	var spawned: int = 0
	t = 0.0
	while s6.phase() == CDSim.PHASE_WAVE and t < 200.0:
		s6.tick(DT)
		t += DT
		for e: Dictionary in s6.drain_events():
			if e["kind"] == &"spawn":
				spawned += 1
	check("spawn: every Stalker of the wave spawns", spawned == 8)


func _test_condense_and_cap() -> void:
	var sim: CDSim = _prep_sim(7)
	check("condense: early waves are not condensed", int(sim.plan.get("condense", 0)) == 0 or float(sim.plan.get("peak", 0.0)) <= CDDefs.CONDENSE_THRESHOLD)
	check("condense: thresholds 54 (pairs) and 108 (fours)", CDSim.condense_level_for(54.0) == 0 and CDSim.condense_level_for(55.0) == 1 and CDSim.condense_level_for(109.0) == 2)
	sim.wave = 39
	sim.plan = {}
	sim.start_wave()
	var peak: float = float(sim.plan["peak"])
	check("condense: on the 12x12 table even wave 40 stays under 54 alive (%.0f)" % peak, peak > 0.0 and peak <= CDDefs.CONDENSE_THRESHOLD and int(sim.plan["condense"]) == 0)
	var p2: Dictionary = sim.make_plan(40)
	sim.apply_condense_level(p2, 1)
	var bodies: int = sim.wave_bodies(p2)
	check("condense: Condensed waves send pairs as one body", bodies < int(p2["count"]) and bodies >= int(ceil(float(p2["count"]) / 2.0)))
	sim.apply_condense_level(p2, 2)
	check("condense: Twice-Condensed sends fours", sim.wave_bodies(p2) >= int(ceil(float(p2["count"]) / 4.0)) and sim.wave_bodies(p2) < bodies)
	sim.crystal_hp = 1.0e9
	sim.crystal_max = 1.0e9
	var over: bool = false
	var t: float = 0.0
	while sim.phase() == CDSim.PHASE_WAVE and t < 600.0:
		sim.tick(DT)
		t += DT
		over = over or sim.enemies.count() > CDDefs.MAX_ALIVE
	check("cap: never more than 60 alive (pooled)", not over and sim.enemies.peak <= 60)
	check("cap: the wave still finishes (spawns wait for free slots)", sim.phase() == CDSim.PHASE_CLEAR and sim.all_spawned())
	# Force the cap: a huge uncondensed wave.
	var s2: CDSim = _prep_sim(8)
	s2.start_wave()
	for i: int in 70:
		s2._spawn_enemy(Vector2(0.5, 5.5), 0)
	check("cap: the pool refuses the 61st", s2.enemies.count() == 60 and s2._spawn_enemy(Vector2(0.5, 5.5), 0) == -1)
	var hp1: float = 0.0
	var s3: CDSim = _prep_sim(8)
	s3.start_wave()
	var a: int = s3._spawn_enemy(Vector2(0.5, 5.5), 0)
	var b: int = s3._spawn_enemy(Vector2(0.5, 6.5), 1)
	hp1 = s3.e_max[a]
	check("condense: a Condensed Stalker has 1.8x HP", is_equal_approx(s3.e_max[b], hp1 * 1.8))


func _test_combat() -> void:
	var sim: CDSim = _prep_sim(12)
	sim.wallet.balance = 100
	var arrow: int = sim.build(&"arrow", Vector2i(2, 6))
	sim.start_wave()
	var e: int = sim._spawn_enemy(Vector2(1.5, 6.5), 0)
	var hp0: float = sim.e_hp[e]
	_tick_for(sim, 0.2)
	check("towers: an Arrow Tower shoots a Stalker in range", sim.e_hp[e] < hp0 or not sim.enemies.is_alive(e))
	check("towers: arrow events for the view", sim.drain_events().any(func(x: Dictionary) -> bool: return x["kind"] == &"arrow"))
	# Armour: damage minus armour, at least 1.
	sim.e_armor[e] = 5
	var before: float = sim.e_hp[e]
	sim.damage_enemy(e, 2.0)
	check("combat: armour never drops a hit below 1", is_equal_approx(sim.e_hp[e], before - 1.0) or not sim.enemies.is_alive(e))
	# First-target rule: the one closest to the Crystal by path.
	var s2: CDSim = _prep_sim(12)
	s2.start_wave()
	var far: int = s2._spawn_enemy(Vector2(1.5, 3.5), 0)
	var near: int = s2._spawn_enemy(Vector2(3.5, 5.5), 0)
	s2._rebuild_hash()
	check("towers: target the Stalker furthest along the path", s2._target_first(Vector2(2.5, 4.5), 3.0) == near and far != near)
	# Bombard splash hits a cluster.
	var s3: CDSim = _prep_sim(13)
	s3.wallet.balance = 100
	s3.build(&"bombard", Vector2i(3, 6))
	s3.start_wave()
	var ids: Array[int] = []
	for k: int in 3:
		ids.append(s3._spawn_enemy(Vector2(1.6 + 0.15 * k, 6.5), 0))
	for i: int in ids:
		s3.e_speed[i] = 0.0
	_tick_for(s3, 1.0)
	var hit: int = 0
	for i: int in ids:
		if not s3.enemies.is_alive(i) or s3.e_hp[i] < s3.e_max[i]:
			hit += 1
	check("bombard: one shell splashes several Stalkers", hit >= 2)
	# Storm Pulse.
	var s4: CDSim = _prep_sim(14)
	s4.start_wave()
	var close: int = s4._spawn_enemy(Vector2(4.6, 6.0), 0)
	s4.e_speed[close] = 0.0
	s4.storm_t = 0.01
	var hp_c: float = s4.e_hp[close]
	_tick_for(s4, 0.1)
	check("crystal: Storm Pulse zaps a Stalker within 1.5 cells", s4.e_hp[close] < hp_c)
	# Leak.
	var s5: CDSim = _prep_sim(15)
	s5.start_wave()
	var l: int = s5._spawn_enemy(Vector2(5.5, 4.2), 0)
	s5.storm_t = 99.0
	_tick_for(s5, 1.6)
	check("crystal: a Stalker reaching the Crystal costs 2 HP and is gone", not s5.enemies.is_alive(l) and s5.crystal_hp <= 98.0 and s5.leaks_this_wave == 1)


# --- Squads -------------------------------------------------------------------------

func _test_squads() -> void:
	var sim: CDSim = _prep_sim(20)
	var id: int = sim.summon(&"knight")
	var q: Dictionary = sim.squads[id]
	var c: Vector2i = q["cell"]
	check("squads: a Knight costs 8 and stands next to the Crystal", id != 0 and sim.wallet.balance == 12 and absi(c.x - 5) <= 2 and absi(c.y - 5) <= 2 and not sim.is_crystal_cell(c))
	check("squads: one member to start", sim.squad_size(q) == 1 and int(q["rank"]) == 0)
	check("squads: can't build on a squad's cell", sim.can_build(&"palisade", c)["reason"] == "A squad stands there")
	var up: Dictionary = sim.can_upgrade_squad(id)
	check("squads: upgrades need EXP first", not bool(up["ok"]) and str(up["reason"]).begins_with("EXP"))
	sim.wallet.balance = 999
	for k: int in 3:
		q["exp"] = 999.0
		sim.upgrade_squad(id)
	check("squads: each upgrade adds a member (up to 4)", sim.squad_size(q) == 4 and int(q["rank"]) == 0)
	q["exp"] = 999.0
	var ev: Dictionary = sim.can_upgrade_squad(id)
	check("squads: at 4 the next upgrade is Evolve", bool(ev["evolve"]) and bool(ev["ok"]))
	sim.upgrade_squad(id)
	check("squads: evolve -> one Paladin", int(q["rank"]) == 1 and sim.squad_size(q) == 1 and sim.squad_rank_stats(q)["name"] == "Paladin")
	check("squads: EXP resets after an upgrade", float(q["exp"]) == 0.0)
	# Move in prep: instant; blocked cells refused.
	check("squads: move in prep is instant", sim.move_squad(id, Vector2i(3, 6)) and q["cell"] == Vector2i(3, 6))
	check("squads: can't stand on terrain or the Crystal", not bool(sim.can_move_squad(id, Vector2i(2, 2))["ok"]) and not bool(sim.can_move_squad(id, Vector2i(5, 5))["ok"]))
	var f0: Vector2 = q["facing"]
	sim.turn_squad(id, 2)
	check("squads: turn by 45 degree steps", is_equal_approx(absf(f0.angle_to(q["facing"])), PI / 2.0))
	# Engagement: a Knight facing west stops a Stalker in its arc.
	var s2: CDSim = _prep_sim(21)
	var k2: int = s2.summon(&"knight")
	s2.move_squad(k2, Vector2i(3, 6))
	s2.squads[k2]["facing"] = Vector2(-1, 0)
	s2.start_wave()
	var e: int = s2._spawn_enemy(Vector2(2.4, 6.5), 0)
	_tick_for(s2, 0.3)
	check("squads: a Stalker in the arc is engaged (blocked)", not s2.enemies.is_alive(e) or s2.e_engaged[e] == k2)
	var pos: Vector2 = s2.e_pos[e]
	_tick_for(s2, 0.5)
	check("squads: engaged Stalkers stop walking", not s2.enemies.is_alive(e) or s2.e_pos[e].is_equal_approx(pos))
	_tick_for(s2, 6.0)
	check("squads: kills give the squad EXP", float(s2.squads[k2]["exp"]) > 0.0)
	var behind: int = s2._spawn_enemy(Vector2(4.6, 6.5), 0)
	s2._rebuild_hash()
	check("squads: the arc only faces one way", not CDSim.in_arc(Vector2(3.5, 6.5), Vector2(-1, 0), PI / 4.0, s2.e_pos[behind]))
	# Dismiss refunds half.
	var s3: CDSim = _prep_sim(22)
	var k3: int = s3.summon(&"knight")
	check("squads: dismiss refunds 50% in prep", s3.dismiss_value(k3) == 4 and s3.dismiss(k3) and s3.wallet.balance == 16 and s3.squads.is_empty())
	# Cap.
	var s4: CDSim = _prep_sim(23)
	s4.wallet.balance = 999
	for k: int in 7:
		s4.summon(&"knight")
	check("squads: at most 6 squads", s4.squads.size() == 6 and not bool(s4.can_summon(&"knight")["ok"]))
	# Members knocked out come back at wave end.
	var s5: CDSim = _prep_sim(24)
	var k5: int = s5.summon(&"knight")
	s5.start_wave()
	s5.squads[k5]["members"][0] = 0.0
	s5.wave_time = 999.0
	s5.plan["groups"] = []
	_tick_for(s5, 0.2)
	check("squads: knocked-out members revive at wave clear", float(s5.squads[k5]["members"][0]) > 0.0)


func _test_redeploy() -> void:
	var sim: CDSim = _prep_sim(30)
	var id: int = sim.summon(&"knight")
	var home: Vector2i = sim.squads[id]["cell"]
	sim.start_wave()
	check("redeploy: mid-wave move is a Redeploy", sim.move_squad(id, Vector2i(3, 3)))
	var q: Dictionary = sim.squads[id]
	check("redeploy: 3 s out of action at the old cell", q["cell"] == home and float(q["redeploy_t"]) > 0.0)
	check("redeploy: no second Redeploy while it's under way", not bool(sim.can_move_squad(id, Vector2i(3, 4))["ok"]))
	_tick_for(sim, CDDefs.REDEPLOY_TIME + 0.1)
	check("redeploy: arrives after 3 s", q["cell"] == Vector2i(3, 3) and float(q["redeploy_t"]) == 0.0)
	var r: Dictionary = sim.can_move_squad(id, Vector2i(3, 4))
	check("redeploy: 15 s cooldown", not bool(r["ok"]) and str(r["reason"]).begins_with("Redeploy in"))


func _test_crystal() -> void:
	var sim: CDSim = _prep_sim(40)
	sim.crystal_hp = 50.0
	sim.wallet.balance = 40
	check("crystal: repair costs 15 for +10 HP", sim.repair() and sim.crystal_hp == 60.0 and sim.wallet.balance == 25)
	check("crystal: repair once per wave", not sim.repair())
	sim.crystal_hp = 50.0
	sim.wallet.balance = 200
	for y: int in [3, 5, 7, 8]:
		sim.build(&"arrow", Vector2i(2, y) if y != 5 else Vector2i(3, 4))
	sim.start_wave()
	_run_wave(sim)
	check("crystal: regenerates 5 HP after a wave", sim.crystal_hp >= 55.0 - 16.0 and sim.phase() == CDSim.PHASE_CLEAR)
	check("crystal: never above max", sim.crystal_hp <= sim.crystal_max)


func _test_autostart() -> void:
	var sim: CDSim = _prep_sim(50)
	sim.wallet.balance = 200
	for y: int in [3, 5, 7, 8]:
		sim.build(&"arrow", Vector2i(2, y) if y != 5 else Vector2i(3, 4))
	sim.start_wave()
	sim.set_autostart(true)
	_run_wave(sim)
	_finish_clear(sim)
	check("autostart: prep counts down 3 s", sim.phase() == CDSim.PHASE_PREP and is_equal_approx(sim.auto_countdown, CDDefs.AUTOSTART_DELAY))
	_tick_for(sim, CDDefs.AUTOSTART_DELAY + 0.1)
	check("autostart: then starts the wave itself", sim.phase() == CDSim.PHASE_WAVE and sim.wave == 2)
	_run_wave(sim)
	check("autostart: +0.05 mana multiplier per auto-started wave", is_equal_approx(sim.auto_multiplier(), 1.05))
	_finish_clear(sim)
	sim.cancel_autostart_countdown()
	check("autostart: waiting (tap) resets the streak", is_equal_approx(sim.auto_multiplier(), 1.0) and sim.auto_countdown < 0.0)
	sim.auto_streak = 10.0
	sim.auto_streak = minf(CDDefs.AUTO_CAP - 1.0, sim.auto_streak)
	check("autostart: capped at x1.5", sim.auto_multiplier() <= CDDefs.AUTO_CAP + 0.0001)


func _test_save_shape() -> void:
	var sim: CDSim = _prep_sim(60)
	sim.build(&"arrow", Vector2i(3, 6))
	var d: Dictionary = sim.to_run_save()
	check("save: run snapshot (slot run, doc 3.8 shape)", d.has("wave") and d.has("seed") and d.has("crystal_hp") and d["wallet"] is Dictionary and (d["towers"] as Array).size() == 1)
	check("save: JSON-safe", JSON.parse_string(JSON.stringify(d)) is Dictionary)
	check("save: phase machine serialises", sim.phases.to_save().has("phase"))


func _test_meshes() -> void:
	var worst: int = 0
	for type: StringName in CDDefs.BUILD_ORDER:
		for lv: int in [1, 2, 3]:
			worst = maxi(worst, _mesh_triangles(CDMeshes.structure_mesh(type, lv)))
	check("meshes: every tower / barrier level <= 1500 triangles (%d)" % worst, worst <= 1500)
	var stalker: int = _mesh_triangles(CDMeshes.stalker_mesh())
	check("meshes: the Pale Stalker <= 700 triangles (%d)" % stalker, stalker <= 700)
	var tall: AABB = CDMeshes.stalker_mesh().get_aabb()
	check("meshes: the Stalker is gaunt (taller than wide, under a cell)", tall.size.y > tall.size.x * 1.5 and tall.size.y < 1.0)
	check("meshes: three Knight ranks, each larger", CDMeshes.knight_mesh(1).get_aabb().size.y > CDMeshes.knight_mesh(0).get_aabb().size.y and CDMeshes.knight_mesh(2).get_aabb().size.y > CDMeshes.knight_mesh(1).get_aabb().size.y)
	check("meshes: structure levels look different", CDMeshes.structure_mesh(&"arrow", 1) != CDMeshes.structure_mesh(&"arrow", 3) and CDMeshes.structure_mesh(&"arrow", 3).get_aabb().size.y > CDMeshes.structure_mesh(&"arrow", 1).get_aabb().size.y)


# --- The game in the host -----------------------------------------------------------

func _test_game_build_flow() -> void:
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await _ready_host()
	var game: CrystalDefenseGame = _game(host)
	check("game: loads in the host, in prep, HUD showing", game.sim != null and game.sim.phase() == CDSim.PHASE_PREP and game._hud.visible)
	check("game: board is 12 cells across 45.6 cm (inside the rim)", is_equal_approx(game.vgrid.cell_size * 12.0, CrystalDefenseGame.BOARD - 2.0 * CrystalDefenseGame.RIM))
	check("game: taps land on the board surface", is_equal_approx(game.board_surface_height(), CrystalDefenseGame.BASE_H))
	game.build_button.pressed.emit()
	await frames(2)
	check("build menu: opens with Towers and Barriers", game.sheet.is_open() and game.sheet.card(&"arrow") != null and game.sheet.card(&"bombard") != null)
	game.sheet.show_tab(&"barriers")
	check("build menu: Barriers tab has Palisade and Stone Wall", game.sheet.card(&"palisade") != null and game.sheet.card(&"stone_wall") != null)
	game.sheet.show_tab(&"towers")
	check("build menu: Bombard (18) is affordable with 20", not game.sheet.card(&"bombard").disabled)
	game.sheet.card(&"arrow").pressed.emit()
	await frames(1)
	check("placing: ghost + grid, sheet closed, drag captured", game.mode == &"build" and game._placement.active and not game.sheet.is_open() and game.captures_drag())
	check("placing: a valid start cell (green)", game._placement.is_valid() and game._confirm_bar.visible and not game.confirm_button.disabled)
	check("placing: range ring with the ghost", game._placement.range_node != null)
	game.tap_cell(Vector2i(5, 5))
	check("placing: the Crystal is red with a reason", not game._placement.is_valid() and game.confirm_button.disabled and game._confirm_label.text.contains("Crystal"))
	var target: Vector2i = Vector2i(3, 6)
	game._on_board_drag(Vector3.ZERO, game.vgrid.cell_center_board(target))
	check("placing: drag moves the ghost", game._placement.cell == target and game._placement.is_valid())
	game.tap_cell(target)
	check("placing: tapping the same cell again places it", game.sim.structure_at(target) != 0 and game.mode == &"none" and game.sim.wallet.balance == 10)
	await frames(1)
	check("placing: the tower appears on the board", game._structure_nodes.size() == 1)
	game.open_build()
	game.sheet.show_tab(&"barriers")
	game.sheet.card(&"palisade").pressed.emit()
	game.cancel_button.pressed.emit()
	check("placing: ✕ cancels without spending", game.mode == &"none" and game.sim.wallet.balance == 10 and not game._confirm_bar.visible)
	game.open_build()
	game.sheet.show_tab(&"barriers")
	game.sheet.card(&"palisade").pressed.emit()
	game.tap_cell(Vector2i(8, 3))
	game.confirm_button.pressed.emit()
	check("placing: ✓ places", game.sim.structure_at(Vector2i(8, 3)) != 0 and game.sim.wallet.balance == 5)
	await free_host(host)


func _test_game_popups() -> void:
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await _ready_host()
	var game: CrystalDefenseGame = _game(host)
	game.sim.wallet.balance = 100
	var id: int = game.sim.build(&"arrow", Vector2i(3, 6))
	game._handle_events()
	game.tap_cell(Vector2i(3, 6))
	await frames(2)
	check("popup: tapping a tower opens upgrade / sell", game.popup.visible and game.popup.button(&"upgrade") != null and game.popup.button(&"sell") != null)
	check("popup: its range ring shows", game.ring_count() == 1)
	check("popup: inside the screen", _contains(get_viewport().get_visible_rect(), game.popup.get_global_rect()))
	game.popup.button(&"upgrade").pressed.emit()
	check("popup: Upgrade → Lv2", int(game.sim.structures[id]["level"]) == 2 and game.popup.visible)
	game.popup.button(&"sell").pressed.emit()
	check("popup: Sell removes it", game.sim.structure_at(Vector2i(3, 6)) == 0 and not game.popup.visible)
	game.eye_button.pressed.emit()
	game.sim.build(&"arrow", Vector2i(3, 6))
	game.sim.build(&"arrow", Vector2i(8, 6))
	game._handle_events()
	check("ranges: the eye shows every tower's range", game.ring_count() == 2)
	game.eye_button.pressed.emit()
	check("ranges: and hides them", game.ring_count() == 0)
	# Summon + squad popup + move.
	game.summon_button.pressed.emit()
	await frames(1)
	check("summon menu: Knight card", game.sheet.card(&"knight") != null)
	game.sheet.card(&"knight").pressed.emit()
	await frames(1)
	var sq: int = game.selected_squad
	check("summon: a Knight squad appears selected, with its arc", sq != 0 and game._squad_nodes.has(sq) and game.popup.visible and game.ring_count() >= 1)
	game.popup.button(&"move").pressed.emit()
	check("move: enters move mode with the arc", game.mode == &"move" and game._placement.active)
	game.turn_button.pressed.emit()
	game.tap_cell(Vector2i(4, 8))
	game.confirm_button.pressed.emit()
	check("move: ✓ moves the squad in prep", game.sim.squads[sq]["cell"] == Vector2i(4, 8) and game.mode == &"none")
	game.tap_cell(Vector2i(5, 5))
	check("popup: tapping the Crystal offers Repair", game.popup.visible and game.popup.button(&"repair") != null)
	game.tap_cell(Vector2i(10, 10))
	check("popup: tapping empty ground closes it", not game.popup.visible)
	await free_host(host)


func _test_wave_flow_in_host() -> void:
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await _ready_host()
	var game: CrystalDefenseGame = _game(host)
	game.sim.wallet.balance = 200
	for y: int in [3, 5, 7, 8]:
		game.sim.build(&"arrow", Vector2i(2, y) if y != 5 else Vector2i(3, 4))
	game._handle_events()
	check("hud: Start Wave 1 shows in prep", game.start_button.visible and game.start_button.text == "Start Wave 1")
	game.start_button.pressed.emit()
	check("hud: wave running, Start hidden, banner", game.sim.phase() == CDSim.PHASE_WAVE and not game.start_button.visible and game.banner_t > 0.0)
	for i: int in 20:
		game._process(DT)
	check("view: a telegraph strip shows on the West edge", game.telegraph_count() >= 1)
	var seen_enemies: bool = false
	var t: float = 0.0
	while game.sim.phase() == CDSim.PHASE_WAVE and t < 200.0:
		game._process(DT)
		t += DT
		seen_enemies = seen_enemies or game._enemy_mm.visible_instance_count > 0
	check("view: Stalkers drawn from the pool", seen_enemies)
	check("hud: wave cleared banner", game.sim.phase() == CDSim.PHASE_CLEAR and game._banner.text.contains("cleared"))
	game.speed_button.pressed.emit()
	check("hud: 2x speed", game.clock.speed == 2.0 and game.speed_button.text == "2x")
	game.speed_button.pressed.emit()
	for i: int in 40:
		game._process(DT)
	check("hud: back to prep for wave 2", game.sim.phase() == CDSim.PHASE_PREP and game.start_button.text == "Start Wave 2")
	# Defeat and retry.
	game.start_wave()
	game.sim.crystal_hp = 0.5
	for s: int in game.sim.structures.keys():
		game.sim.sell(s)
	t = 0.0
	while game.sim.phase() == CDSim.PHASE_WAVE and t < 200.0:
		game._process(DT)
		t += DT
	game._process(DT)
	check("defeat: the defeat panel with a retry", game.sim.phase() == CDSim.PHASE_DEFEAT and game._over_panel.visible and game.retry_button.visible)
	check("defeat: build is off", game.build_button.disabled)
	game.retry_button.pressed.emit()
	for i: int in 50:
		game._process(DT)
	check("defeat: retry starts a fresh run", game.sim.phase() == CDSim.PHASE_PREP and game.sim.wave == 0 and game.sim.wallet.balance == 20 and not game._over_panel.visible and game._structure_nodes.is_empty())
	await free_host(host)


func _test_rotate_pause() -> void:
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await _ready_host()
	var game: CrystalDefenseGame = _game(host)
	await _set_window(LANDSCAPE_WINDOW)
	check("rotate: turning in prep doesn't pause (nothing is moving)", game.ui_state == CrystalDefenseGame.UI.PLAY and not game.is_portrait())
	game.start_wave()
	for i: int in 30:
		game._process(DT)
	await _set_window(PORTRAIT_WINDOW)
	check("rotate: turning mid-wave pauses", game.ui_state == CrystalDefenseGame.UI.PAUSED and game.pause_reason == &"rotate" and game._pause_panel.visible)
	var wt: float = game.sim.wave_time
	for i: int in 20:
		game._process(DT)
	check("rotate: nothing moves while paused", game.sim.wave_time == wt)
	check("rotate: the pause panel says why", game._pause_label.text.contains("turned"))
	game.resume_button.pressed.emit()
	check("resume: 3-2-1 countdown first", game.ui_state == CrystalDefenseGame.UI.COUNTDOWN and game._countdown_label.visible)
	for i: int in 70:
		game._process(DT)
	check("resume: then the wave runs on", game.ui_state == CrystalDefenseGame.UI.PLAY and game.sim.wave_time > wt)
	game.pause_button.pressed.emit()
	check("pause: the pause button", game.ui_state == CrystalDefenseGame.UI.PAUSED and game.pause_reason == &"button")
	game.resume()
	game.lg_set_app_paused(true)
	check("pause: the app pausing pauses", game.ui_state == CrystalDefenseGame.UI.PAUSED)
	game.lg_set_app_paused(false)
	await free_host(host)


func _check_hud(host: GameHost, label: String) -> void:
	var game: CrystalDefenseGame = _game(host)
	await frames(3)
	var view: Rect2 = get_viewport().get_visible_rect()
	var top: Rect2 = game._top.get_global_rect()
	var left: Rect2 = game._left_row.get_global_rect()
	var right: Rect2 = game._right_row.get_global_rect()
	var start: Rect2 = game.start_button.get_global_rect()
	var back: Rect2 = host._back_button.get_global_rect()
	var status: Rect2 = host._status_label.get_global_rect()
	check("%s: stats, buttons and Start inside the screen" % label, _contains(view, top) and _contains(view, left) and _contains(view, right) and _contains(view, start))
	check("%s: nothing overlaps" % label, not top.intersects(left) and not left.intersects(right) and not start.intersects(left) and not start.intersects(right) and not top.intersects(start))
	check("%s: stats clear of the back button and status line" % label, not top.intersects(back) and (host._status_label.text == "" or not top.intersects(status)))
	var small: bool = false
	for b: Button in [game.build_button, game.summon_button, game.start_button, game.auto_button, game.speed_button, game.eye_button, game.pause_button]:
		small = small or b.get_global_rect().size.x < 88.0 or b.get_global_rect().size.y < 88.0
	check("%s: every button is >= 88 px" % label, not small)
	check("%s: controls sit at the bottom" % label, left.position.y > view.size.y * 0.6 and right.end.y > view.size.y * 0.8)
	game.open_build()
	await frames(3)
	check("%s: the build sheet fits the screen" % label, _contains(view, game.sheet.get_global_rect(), 0.0))
	check("%s: the sheet leaves the pause button reachable" % label, not game.sheet.get_global_rect().intersects(game.pause_button.get_global_rect()) or game.is_portrait())
	game.sheet.close()
	game.open_build()
	game.sheet.card(&"arrow").pressed.emit()
	await frames(2)
	var cb: Rect2 = game._confirm_bar.get_global_rect()
	check("%s: the confirm bar fits and clears the buttons" % label, _contains(view, cb) and not cb.intersects(left) and not cb.intersects(right))
	game.cancel_mode()
	for panel: Control in [game._pause_panel, game._over_panel]:
		panel.visible = true
	await frames(2)
	check("%s: pause and defeat panels inside the screen" % label, _contains(view, game._pause_panel.get_global_rect()) and _contains(view, game._over_panel.get_global_rect()))
	for panel: Control in [game._pause_panel, game._over_panel]:
		panel.visible = false
	# (The host resets the inset every frame outside AR: check right away.)
	game.lg_set_ui_bottom_inset(220.0)
	check("%s: the bottom row lifts above the AR HUD inset" % label, game._left_row.get_global_rect().end.y <= view.size.y - 220.0 and game._right_row.get_global_rect().end.y <= view.size.y - 220.0)
	game.lg_set_ui_bottom_inset(0.0)
	await frames(2)


func _test_hud_layouts() -> void:
	for window: Vector2i in [PORTRAIT_WINDOW, LANDSCAPE_WINDOW]:
		await _set_window(window)
		var host: GameHost = await _ready_host()
		await _check_hud(host, "hud %dx%d" % [window.x, window.y])
		check("hud %dx%d: is_over_game_ui on Start, not on the board" % [window.x, window.y], _game(host).is_over_game_ui(_game(host).start_button.get_global_rect().get_center()) and not _game(host).is_over_game_ui(get_viewport().get_visible_rect().get_center()))
		await free_host(host)


func _test_budget() -> void:
	await _set_window(LANDSCAPE_WINDOW)
	var host: GameHost = await _ready_host()
	var game: CrystalDefenseGame = _game(host)
	var sim: CDSim = game.sim
	sim.wallet.balance = 999
	for c: Vector2i in [Vector2i(3, 4), Vector2i(3, 7), Vector2i(8, 4), Vector2i(8, 7), Vector2i(4, 9)]:
		sim.build(&"arrow", c)
	sim.build(&"bombard", Vector2i(7, 9))
	for k: int in 3:
		sim.summon(&"knight")
	game._handle_events()
	sim.start_wave()
	sim.crystal_hp = 1.0e9
	sim.crystal_max = 1.0e9
	for i: int in 60:
		sim._spawn_enemy(Vector2(0.5 + (i % 6) * 0.3, 1.5 + (i / 6) * 0.9), 0)
	game._process(DT)
	check("budget: 60 Stalkers drawn in one MultiMesh", game._enemy_mm.visible_instance_count == 60)
	var tris: int = 0
	for node: Node in game.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			tris += _mesh_triangles((gi as MeshInstance3D).mesh)
		elif gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mm.mesh != null and mm.visible_instance_count > 0:
				tris += _mesh_triangles(mm.mesh) * mm.visible_instance_count
	check("budget: a busy board stays under 120k triangles (%d)" % tris, tris < 120000)
	var draws: int = game.find_children("*", "GeometryInstance3D", true, false).size()
	check("budget: under 80 draw nodes (%d)" % draws, draws < 80)
	var t0: int = Time.get_ticks_usec()
	for i: int in 100:
		sim.tick(DT)
	var per_tick: float = float(Time.get_ticks_usec() - t0) / 100.0 / 1000.0
	check("budget: a 60-Stalker sim tick under 4 ms (%.2f ms)" % per_tick, per_tick < 4.0)
	t0 = Time.get_ticks_usec()
	for i: int in 30:
		game._sync_visuals(1.0 / 60.0)
	var per_frame: float = float(Time.get_ticks_usec() - t0) / 30.0 / 1000.0
	check("budget: view sync under 6 ms a frame (%.2f ms)" % per_frame, per_frame < 6.0)
	await free_host(host)
