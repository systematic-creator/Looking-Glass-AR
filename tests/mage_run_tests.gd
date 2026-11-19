extends "res://tests/surface_tests.gd"
## Mage Run (M4-M6): units, lanes and arcane rows, the swipe move set with
## buffering and coyote grace, collisions and stumbles, power-ups, scoring,
## chunk templates and generated-track fairness, then the game in the host:
## swipes routed through the host, pause (button, rotate, app) with the
## resume countdown, game over / restart / session best, the first-run hint,
## the HUD in portrait and landscape, everything inside the play box, and
## the triangle budget.
## Run: godot --headless --path . res://tests/mage_run_tests.tscn

const DT: float = 1.0 / 60.0
const LANDSCAPE_WINDOW := Vector2i(2340, 1080)
const PORTRAIT_WINDOW := Vector2i(1080, 2340)
const HINT_CFG: String = "user://mage_run_test.cfg"

var _saved_window: Vector2i


func run_tests() -> void:
	_saved_window = get_tree().root.size
	MageRunGame.settings_path = HINT_CFG
	MageRunGame.next_seed = 7
	MageRunGame.session_best = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINT_CFG))
	_test_units()
	_test_manifest()
	_test_lanes_and_swipes()
	_test_jump_buffer_and_coyote()
	_test_slide_slam_drop()
	_test_collisions()
	_test_stumble()
	_test_arcane_rows()
	_test_cracked_and_ramps()
	_test_scoring()
	_test_power_ups()
	_test_templates()
	_test_generator()
	await _test_game_flow()
	await _test_host_swipes()
	await _test_pause_and_rotate()
	await _test_hud_layouts()
	await _test_first_run_hint()
	await _test_containment()
	await _test_budget()
	await _set_window(_saved_window)
	MageRunGame.next_seed = -1
	MageRunGame.session_best = 0
	MageRunGame.settings_path = "user://mage_run.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINT_CFG))


# --- Helpers ------------------------------------------------------------------------

## A sim on a hand-made track (no generation): `items` in template form,
## placed from run metre 0.
func _sim(items: Array, at: float = 0.0) -> MageRunSim:
	var sim := MageRunSim.new(1, at)
	sim.track = MageChunks.instantiate({"name": "test", "length": 8.0, "items": items}, at, false, [1000])
	sim.generator.end_s = 1.0e9
	return sim


func _steps(sim: MageRunSim, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds - 0.00001 and sim.alive:
		sim.step(DT)
		t += DT


## Step until distance >= s (or the run ends).
func _run_to(sim: MageRunSim, s: float) -> void:
	var guard: int = 0
	while sim.distance < s and sim.alive and guard < 10000:
		sim.step(DT)
		guard += 1


func _until_grounded(sim: MageRunSim, max_seconds: float = 2.0) -> void:
	var t: float = 0.0
	while not sim.grounded and t < max_seconds and sim.alive:
		sim.step(DT)
		t += DT


func _kinds(events: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in events:
		out.append(e["kind"] as StringName)
	return out


func _put_on_tile(sim: MageRunSim, lane: int, row: int) -> void:
	sim.lane = lane
	sim.from_lane = lane
	sim.lane_t = 1.0
	sim.x = MageTrack.lane_x(lane)
	sim.y = MageTrack.row_y(row)
	sim.grounded = true
	sim.vy = 0.0
	sim.support = &"tile"


func _game(host: GameHost) -> MageRunGame:
	return host.game as MageRunGame


func _tick(game: MageRunGame, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds - 0.00001:
		game._process(DT)
		t += DT


func _set_window(size: Vector2i) -> void:
	get_tree().root.size = size
	await frames(3)


func _view() -> Rect2:
	return get_viewport().get_visible_rect()


static func _contains(outer: Rect2, inner: Rect2, margin: float = 4.0) -> bool:
	return outer.grow(-margin).encloses(inner)


static func _overlap(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b)


func _swipe(host: GameHost, from: Vector2, to: Vector2) -> void:
	var mid: Vector2 = from.lerp(to, 0.5)
	host._input(touch(0, from, true))
	host._input(drag(0, mid, mid - from))
	host._input(drag(0, to, to - mid))
	host._input(touch(0, to, false))


func _running_host() -> GameHost:
	var host: GameHost = await make_host(&"mage_run")
	var game: MageRunGame = _game(host)
	game._hide_hint()
	game.sim.grace_t = 1.0e6
	_tick(game, MageRunGame.COUNTDOWN + 0.05)
	return host


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


# --- Units --------------------------------------------------------------------------

func _test_units() -> void:
	check("lanes: 3 ground lanes 7.5 cm apart, centred", MageTrack.LANES == 3 and is_equal_approx(MageTrack.lane_x(0), -0.075) and MageTrack.lane_x(1) == 0.0 and is_equal_approx(MageTrack.lane_x(2), 0.075))
	check("rows: ground + 2 arcane rows at 10 and 20 cm", MageTrack.TOP_ROW == 2 and MageTrack.row_y(0) == 0.0 and is_equal_approx(MageTrack.row_y(1), 0.1) and is_equal_approx(MageTrack.row_y(2), 0.2))
	check("lanes: lane_at maps x back to the nearest lane", MageTrack.lane_at(-0.07) == 0 and MageTrack.lane_at(0.01) == 1 and MageTrack.lane_at(0.2) == 2)
	check("unlocks: row 1 at 150 m, row 2 at 400 m", MageTrack.rows_unlocked(149.0) == 0 and MageTrack.rows_unlocked(150.0) == 1 and MageTrack.rows_unlocked(399.0) == 1 and MageTrack.rows_unlocked(400.0) == 2)
	var monotonic: bool = true
	var prev: float = 0.0
	for d: int in range(0, 5000, 50):
		var v: float = MageTrack.speed_at(float(d))
		monotonic = monotonic and v >= prev
		prev = v
	check("speed: starts at 1.2 run m/s, rises smoothly, never past 2.6", is_equal_approx(MageTrack.speed_at(0.0), 1.2) and monotonic and MageTrack.speed_at(1.0e6) <= MageTrack.MAX_SPEED + 0.0001 and MageTrack.speed_at(900.0) > 2.0)
	check("jump: 11 cm apex, 0.55 s airtime", is_equal_approx(MageTrack.jump_height(MageTrack.JUMP_TIME * 0.5), MageTrack.JUMP_APEX) and absf(MageTrack.jump_height(MageTrack.JUMP_TIME)) < 0.0001)
	check("reaction: every item is visible >= 0.75 s before it reaches the wizard at top speed (carts closing)", MageValidator.reaction_ok() and MageTrack.reaction_time(MageTrack.MAX_SPEED, MageTrack.CART_SPEED) >= MageTrack.REACTION_TIME)
	check("box: the longest item fits hidden inside the castle behind the gate", (MageTrack.GATE_Z - MageTrack.FAR_Z) / MageTrack.RUN_TO_BOARD >= MageTrack.MAX_ITEM_LEN)
	check("box: the board ends are inside the 60 cm board", MageTrack.NEAR_Z < 0.3 and MageTrack.FAR_Z > -0.3 and MageTrack.WIZARD_Z > 0.0)


func _test_manifest() -> void:
	var catalog := GameCatalog.new()
	catalog.scan()
	var m: LGGameManifest = catalog.get_manifest(&"mage_run")
	check("catalog: Mage Run is registered with the other games, no errors", m != null and catalog.has_game(&"stack_tower") and catalog.has_game(&"tic_tac_toe") and catalog.errors.is_empty())
	if m == null:
		return
	check("manifest: one player, 30 x 60 cm board, icon", m.max_players == 1 and m.board_size == Vector2(0.3, 0.6) and m.icon != null)
	check("manifest: orientation \"either\" (portrait recommended by the hint, not forced)", m.orientation == "either")
	var box: PlayBox = PlayBox.from_manifest(m)
	check("manifest: tall box 40 cm default, adjustable 40-70 cm", m.tall_box and is_equal_approx(box.height(), 0.4) and is_equal_approx(box.min_height, 0.4) and is_equal_approx(box.max_height, 0.7) and box.is_adjustable())
	var top: float = MageTrack.row_y(MageTrack.TOP_ROW) + MageTrack.JUMP_APEX + 0.072 + MageRunGame.BASE_HEIGHT
	check("box: a jump from Arcane II with the hat on still fits the minimum box", top <= box.min_height)


# --- Swipes -------------------------------------------------------------------------

func _test_lanes_and_swipes() -> void:
	var sim: MageRunSim = _sim([])
	check("swipe: right moves one lane right", sim.swipe(Vector2i.RIGHT) == &"lane" and sim.lane == 2 and sim.from_lane == 1)
	_steps(sim, MageTrack.LANE_TIME * 0.5)
	check("lane change: eased, halfway after half the time", sim.x > 0.0 and sim.x < MageTrack.lane_x(2))
	check("swipe: the opposite way mid-change reverses at once", sim.swipe(Vector2i.LEFT) == &"reverse" and sim.lane == 1)
	_steps(sim, MageTrack.LANE_TIME + DT)
	check("lane change: done in 0.12 s, back in the middle", is_equal_approx(sim.x, 0.0) and not sim.changing_lane())
	sim.swipe(Vector2i.LEFT)
	_steps(sim, MageTrack.LANE_TIME + DT)
	check("swipe: left at the edge bumps (stays in lane 0)", sim.swipe(Vector2i.LEFT) == &"bump" and sim.lane == 0)
	check("swipe: right mid-change (same way) is buffered", sim.swipe(Vector2i.RIGHT) == &"lane" and sim.swipe(Vector2i.RIGHT) == &"buffered")
	_steps(sim, MageTrack.LANE_TIME * 2.0 + DT * 2.0)
	check("buffer: the buffered right runs when the first change ends (lane 2)", sim.lane == 2 and is_equal_approx(sim.x, MageTrack.lane_x(2)))
	sim.swipe(Vector2i.LEFT)
	sim.swipe(Vector2i.LEFT)
	_steps(sim, MageTrack.LANE_TIME * 0.2)
	_steps(sim, MageTrack.BUFFER_TIME + 0.2)
	check("buffer: a buffered swipe expires after 0.15 s if it cannot run", sim.lane == 0 or sim.lane == 1)
	var s2: MageRunSim = _sim([])
	check("swipe: up jumps", s2.swipe(Vector2i.UP) == &"jump" and not s2.grounded and s2.vy > 0.0)


func _test_jump_buffer_and_coyote() -> void:
	var sim: MageRunSim = _sim([])
	sim.swipe(Vector2i.UP)
	var apex: float = 0.0
	var t: float = 0.0
	while not sim.grounded and t < 1.0:
		sim.step(DT)
		t += DT
		apex = maxf(apex, sim.y)
	check("jump: ~11 cm high, lands after ~0.55 s", absf(apex - MageTrack.JUMP_APEX) < 0.004 and absf(t - MageTrack.JUMP_TIME) < 0.04)
	sim.swipe(Vector2i.UP)
	while sim.vy > -0.6:
		sim.step(DT)
	var early: StringName = sim.swipe(Vector2i.UP)
	sim.take_events()
	var seen: Array[StringName] = []
	var guard: int = 0
	while not seen.has(&"land") and guard < 60:
		sim.step(DT)
		seen.append_array(_kinds(sim.take_events()))
		guard += 1
	_steps(sim, DT * 2)
	check("buffer: up just before landing is buffered and jumps on touchdown", early == &"buffered" and seen.has(&"jump") and seen.find(&"jump") >= seen.find(&"land") and not sim.grounded and sim.vy > 0.0)
	# Coyote grace: run off the end of an arcane tile.
	var c: MageRunSim = _sim([{"k": "tiles", "lane": 1, "row": 1, "s": 0.0, "len": 0.6}])
	_put_on_tile(c, 1, 1)
	_run_to(c, 0.6)
	while c.grounded:
		c.step(DT)
	_steps(c, 0.05)
	check("coyote: up 0.05 s after running off an edge still jumps", c.swipe(Vector2i.UP) == &"jump" and c.vy > 0.0)
	var late: MageRunSim = _sim([{"k": "tiles", "lane": 1, "row": 1, "s": 0.0, "len": 0.6}])
	_put_on_tile(late, 1, 1)
	_run_to(late, 0.6)
	while late.grounded:
		late.step(DT)
	_steps(late, 0.12)
	check("coyote: ... but 0.12 s after, it is too late (buffered, falling)", late.swipe(Vector2i.UP) == &"buffered" and late.vy < 0.0)


func _test_slide_slam_drop() -> void:
	var sim: MageRunSim = _sim([])
	check("swipe: down on the ground slides", sim.swipe(Vector2i.DOWN) == &"slide" and sim.sliding() and is_equal_approx(sim.body_height(), MageTrack.SLIDE_HEIGHT))
	_steps(sim, MageTrack.SLIDE_TIME + DT)
	check("slide: ends after 0.6 s", not sim.sliding() and is_equal_approx(sim.body_height(), MageTrack.BODY_HEIGHT))
	sim.swipe(Vector2i.UP)
	_steps(sim, 0.1)
	check("swipe: down mid-air slams", sim.swipe(Vector2i.DOWN) == &"slam" and sim.vy <= -MageTrack.SLAM_SPEED)
	var t: float = 0.0
	while not sim.grounded and t < 1.0:
		sim.step(DT)
		t += DT
	check("slam: lands fast and goes straight into a slide", t < 0.2 and sim.sliding())
	var d: MageRunSim = _sim([{"k": "tiles", "lane": 1, "row": 1, "s": 0.0, "len": 1.8}])
	_put_on_tile(d, 1, 1)
	_steps(d, 0.1)
	check("swipe: down on an arcane row drops", d.on_arcane_row() and d.swipe(Vector2i.DOWN) == &"drop")
	_until_grounded(d)
	check("drop: falls through to the ground", d.grounded and d.y == 0.0 and d.support == &"ground" and d.row() == 0)


# --- Collisions ---------------------------------------------------------------------

func _test_collisions() -> void:
	var sim: MageRunSim = _sim([{"k": "fence", "lane": 1, "s": 1.0}])
	_run_to(sim, 2.0)
	check("fence: running into it ends the run", not sim.alive and sim.crash_kind == &"fence" and _kinds(sim.take_events()).has(&"crash"))
	sim = _sim([{"k": "fence", "lane": 1, "s": 1.0}])
	_run_to(sim, 1.06 - MageTrack.JUMP_TIME * 0.5 * MageTrack.speed_at(0.0))
	sim.swipe(Vector2i.UP)
	_run_to(sim, 2.0)
	check("fence: jumping clears it", sim.alive and sim.distance >= 2.0)
	sim = _sim([{"k": "fence", "lane": 1, "s": 1.0}])
	_run_to(sim, 0.8)
	sim.swipe(Vector2i.DOWN)
	_run_to(sim, 2.0)
	check("fence: sliding does not get under it", not sim.alive)
	sim = _sim([{"k": "beam", "lane": 1, "s": 1.0}])
	_run_to(sim, 2.0)
	check("beam: running into the banner beam ends the run", not sim.alive and sim.crash_kind == &"beam")
	sim = _sim([{"k": "beam", "lane": 1, "s": 1.0}])
	_run_to(sim, 0.75)
	sim.swipe(Vector2i.DOWN)
	_run_to(sim, 2.0)
	check("beam: sliding under it is safe", sim.alive)
	sim = _sim([{"k": "beam", "lane": 1, "s": 1.0}])
	_run_to(sim, 1.05 - MageTrack.JUMP_TIME * 0.5 * MageTrack.speed_at(0.0))
	sim.swipe(Vector2i.UP)
	_run_to(sim, 2.0)
	check("beam: jumping into it ends the run", not sim.alive)
	sim = _sim([{"k": "crates", "lane": 1, "s": 1.0, "len": 0.6}])
	_run_to(sim, 0.6)
	sim.swipe(Vector2i.LEFT)
	_run_to(sim, 2.2)
	check("crates: a lane change gets round them", sim.alive)
	check("answers: one vertical answer each (fence jump, beam slide), crates and carts dodge only", (
		MageValidator.answers(&"fence", 1.2) == PackedStringArray(["jump"]) and MageValidator.answers(&"fence", 2.6) == PackedStringArray(["jump"])
		and MageValidator.answers(&"beam", 1.2) == PackedStringArray(["slide"]) and MageValidator.answers(&"beam", 2.6) == PackedStringArray(["slide"])
		and MageValidator.answers(&"crates", 2.6).is_empty() and MageValidator.answers(&"cart", 2.6).is_empty()
	))
	sim = _sim([{"k": "cart", "lane": 1, "s": 4.0}])
	var s0: float = sim.obstacles[0].s0
	_steps(sim, 0.2)
	var parked: bool = is_equal_approx(sim.obstacles[0].s0, s0)
	_run_to(sim, 4.0 - MageTrack.VISIBLE_AHEAD + 0.2)
	var before: float = sim.obstacles[0].s0
	_steps(sim, 0.5)
	check("cart: waits hidden in the castle, then rolls toward the wizard at 0.4 m/s once out of the gate", parked and is_equal_approx(before - sim.obstacles[0].s0, MageTrack.CART_SPEED * 0.5))
	sim = _sim([{"k": "carriage", "lane": 0, "s": 1.0}])
	_run_to(sim, 2.0)
	check("carriage: blocks two lanes", not sim.alive and sim.crash_kind == &"carriage" and sim.obstacles[0].lanes == PackedInt32Array([0, 1]))
	sim = _sim([{"k": "carriage", "lane": 0, "s": 1.0}])
	_run_to(sim, 1.0 - MageTrack.JUMP_TIME * 0.4 * MageTrack.speed_at(0.0))
	sim.swipe(Vector2i.UP)
	_until_grounded(sim)
	var roof: bool = sim.support == &"roof" and is_equal_approx(sim.y, MageTrack.CARRIAGE_ROOF)
	_run_to(sim, 2.2)
	check("carriage: its roof is walkable (jump on, run along, drop off the end)", roof and sim.alive)


func _test_stumble() -> void:
	var sim: MageRunSim = _sim([{"k": "crates", "lane": 2, "s": 0.4, "len": 0.6}, {"k": "crates", "lane": 2, "s": 1.6, "len": 0.6}])
	_run_to(sim, 0.6)
	sim.swipe(Vector2i.RIGHT)
	_steps(sim, 0.1)
	var kinds: Array[StringName] = _kinds(sim.take_events())
	check("stumble: changing lane into the side of crates bounces back (no crash)", sim.alive and kinds.has(&"stumble") and sim.lane == 1)
	check("stumble: slows the wizard for 0.8 s and breaks the coin streak", sim.slow_t > 0.0 and is_equal_approx(sim.speed(), MageTrack.speed_at(sim.distance) * MageRunSim.STUMBLE_FACTOR) and sim.coin_streak == 0)
	_steps(sim, MageRunSim.STUMBLE_SLOW + DT)
	check("stumble: full speed again afterwards", is_equal_approx(sim.speed(), MageTrack.speed_at(sim.distance)))
	_run_to(sim, 1.8)
	sim.swipe(Vector2i.RIGHT)
	_steps(sim, 0.1)
	check("stumble: a second one within 3 s ends the run", not sim.alive and sim.crash_kind == &"crates")


# --- Arcane rows --------------------------------------------------------------------

func _test_arcane_rows() -> void:
	var items: Array = [
		{"k": "tiles", "lane": 1, "row": 1, "s": 0.6, "len": 1.8},
		{"k": "coins", "shape": "surface", "lane": 1, "row": 0, "s": 1.2, "n": 3, "step": 0.2},
	]
	var sim: MageRunSim = _sim(items)
	_run_to(sim, 0.45)
	sim.swipe(Vector2i.UP)
	_until_grounded(sim)
	check("rows: jumping under an Arcane I tile lands on it", sim.alive and sim.support == &"tile" and is_equal_approx(sim.y, 0.1) and sim.row() == 1 and sim.on_arcane_row())
	check("rows: coins on a tile sit on the row and are worth x2", sim.coin_items.size() >= 3 and sim.coin_items[0].row == 1 and sim.coin_items[0].value() == 2)
	_run_to(sim, 1.75)
	check("rows: running along it collects its coins at x2 (3 coins = 6, 60 points)", sim.coins == 6 and sim.score_f >= 60.0)
	check("rows: no tile beside you up here: a lane change bumps", sim.swipe(Vector2i.RIGHT) == &"bump" and sim.lane == 1)
	_run_to(sim, 2.45)
	_until_grounded(sim)
	check("rows: running off the end drops to the road", sim.alive and sim.row() == 0 and sim.support == &"ground")
	# Lane change along a row onto a neighbouring tile.
	var two: MageRunSim = _sim([{"k": "tiles", "lane": 1, "row": 1, "s": 0.0, "len": 1.8}, {"k": "tiles", "lane": 2, "row": 1, "s": 0.0, "len": 1.8}])
	_put_on_tile(two, 1, 1)
	check("rows: 3 lanes up there too: a lane change onto a tile works", two.swipe(Vector2i.RIGHT) == &"lane")
	_steps(two, MageTrack.LANE_TIME + 0.05)
	check("rows: ... and stays on the row", two.grounded and two.row() == 1 and two.lane == 2)
	# Row 2 from row 1.
	var climb: MageRunSim = _sim([{"k": "tiles", "lane": 1, "row": 1, "s": 0.0, "len": 1.8}, {"k": "tiles", "lane": 1, "row": 2, "s": 0.8, "len": 1.2},
		{"k": "coins", "shape": "surface", "lane": 1, "row": 0, "s": 1.2, "n": 1, "step": 0.2}])
	_put_on_tile(climb, 1, 1)
	_run_to(climb, 0.55)
	climb.swipe(Vector2i.UP)
	_until_grounded(climb)
	check("rows: a jump from Arcane I lands on Arcane II (20 cm)", climb.row() == 2 and is_equal_approx(climb.y, 0.2) and climb.support == &"tile")
	_run_to(climb, 1.3)
	check("rows: Arcane II coins are worth x3", climb.coins == 3)
	check("rows: the HUD-facing row() and on_arcane_row() agree", climb.on_arcane_row() and climb.rows_unlocked() == 0)


func _test_cracked_and_ramps() -> void:
	var sim: MageRunSim = _sim([{"k": "tiles", "lane": 1, "row": 1, "s": 0.0, "len": 0.6, "cracked": true}, {"k": "tiles", "lane": 0, "row": 1, "s": 0.0, "len": 1.8}])
	_put_on_tile(sim, 1, 1)
	_steps(sim, DT * 2)
	check("cracked: standing on a cracked tile starts it crumbling", sim.tiles[0].crumble >= 0.0 and _kinds(sim.take_events()).has(&"crack"))
	_steps(sim, MageTrack.CRACK_TIME + DT * 2)
	check("cracked: gone after 0.4 s, the wizard falls", sim.tiles[0].gone and not sim.grounded and sim.y < 0.1)
	var r: MageRunSim = _sim([{"k": "ramp", "lane": 1, "row": 0, "s": 0.3, "len": 0.6}, {"k": "tiles", "lane": 1, "row": 1, "s": 0.9, "len": 0.6}])
	_run_to(r, 0.6)
	var mid: float = r.y
	_run_to(r, 1.1)
	check("ramp: running up a rune ramp climbs to the row without a swipe", mid > 0.03 and mid < 0.07 and is_equal_approx(r.y, 0.1) and r.support == &"tile")


# --- Scoring ------------------------------------------------------------------------

func _test_scoring() -> void:
	var sim: MageRunSim = _sim([{"k": "coins", "shape": "line", "lane": 1, "row": 0, "s": 0.5, "n": 25, "step": 0.1}])
	_run_to(sim, 1.0)
	check("score: distance adds 1 point per run metre at x1", absf(sim.score_f - 10.0 * float(sim.coins) - sim.distance) < 0.05)
	_run_to(sim, 2.4)
	check("score: a coin is 10 points; 20 in a row raises the multiplier to x2", sim.coins == 20 and sim.multiplier == 2 and sim.coin_streak == 0)
	var before: float = sim.score_f
	var d0: float = sim.distance
	_run_to(sim, 3.2)
	var coins_after: int = sim.coins - 20
	check("score: distance points are multiplied", absf((sim.score_f - before) - (sim.distance - d0) * 2.0 - 10.0 * float(coins_after)) < 0.05)
	check("staff: each coin charges the staff meter", sim.meter == 25)
	var cap: MageRunSim = _sim([])
	for i: int in 30:
		var c := MageTrack.Coin.new()
		c.lane = 1
		c.s = 0.5 + 0.05 * float(i)
		c.y = 0.02
		cap.coin_items.append(c)
	cap.multiplier = MageRunSim.MAX_MULTIPLIER
	cap.coin_streak = MageRunSim.STREAK_COINS - 1
	_run_to(cap, 0.6)
	check("score: the multiplier caps at x5", cap.multiplier == MageRunSim.MAX_MULTIPLIER)
	# A perfect dodge: a lane change out of the way just before an obstacle.
	var dodge: MageRunSim = _sim([{"k": "fence", "lane": 1, "s": 1.0}])
	_run_to(dodge, 0.74)
	dodge.swipe(Vector2i.LEFT)
	_run_to(dodge, 1.3)
	check("staff: a last-moment dodge adds a staff bonus", dodge.alive and dodge.perfect_dodges == 1 and dodge.meter == MageRunSim.DODGE_BONUS)


func _test_power_ups() -> void:
	var sim: MageRunSim = _sim([{"k": "fence", "lane": 1, "s": 1.0}, {"k": "fence", "lane": 1, "s": 2.0}])
	check("staff: nothing to cast until the meter is full", sim.cast() == -1)
	sim.meter = MageRunSim.METER_FULL
	check("staff: before the rows unlock, Levitation is skipped (Shield first)", sim.cast() == MageRunSim.Power.SHIELD and sim.shield_t > 0.0 and sim.meter == 0)
	_run_to(sim, 1.4)
	check("shield: smashes the first obstacle and is used up", sim.alive and sim.obstacles[0].broken and sim.shield_t == 0.0)
	_run_to(sim, 2.5)
	check("shield: ... the next one hits as usual", not sim.alive)
	var m: MageRunSim = _sim([{"k": "coins", "shape": "line", "lane": 0, "row": 0, "s": 0.4, "n": 4, "step": 0.15}, {"k": "coins", "shape": "line", "lane": 2, "row": 0, "s": 0.4, "n": 4, "step": 0.15}])
	m.meter = MageRunSim.METER_FULL
	m.next_power = MageRunSim.Power.MAGNET
	check("staff: casts in turn (Magnet)", m.cast() == MageRunSim.Power.MAGNET and m.magnet_t > 0.0)
	_run_to(m, 1.2)
	check("magnet: pulls in coins from the side lanes", m.coins == 8)
	var lev: MageRunSim = _sim([{"k": "crates", "lane": 1, "s": 1.0, "len": 0.6}, {"k": "fence", "lane": 1, "s": 2.0}], 200.0)
	lev.meter = MageRunSim.METER_FULL
	lev.next_power = MageRunSim.Power.LEVITATION
	check("staff: Levitation once a row is unlocked", lev.cast() == MageRunSim.Power.LEVITATION and lev.levitating())
	_run_to(lev, 202.5)
	check("levitation: floats at Arcane I height over everything", lev.alive and is_equal_approx(lev.y, 0.1) and lev.support == &"levitation")
	check("levitation: swipes up / down do nothing while floating", lev.swipe(Vector2i.UP) == &"ignored" and lev.swipe(Vector2i.DOWN) == &"ignored")
	_steps(lev, MageRunSim.LEVITATION_TIME)
	_until_grounded(lev)
	check("levitation: ends after 8 s with a soft landing (grace)", not lev.levitating() and lev.grounded and lev.alive)


# --- Templates and the generator ----------------------------------------------------

func _test_templates() -> void:
	var bad: PackedStringArray = []
	var names: Dictionary = {}
	for t: Dictionary in MageChunks.TEMPLATES:
		names[t["name"]] = true
		bad.append_array(MageValidator.template_errors(t))
	check("templates: %d hand-made chunks" % MageChunks.TEMPLATES.size(), MageChunks.TEMPLATES.size() >= 15 and names.size() == MageChunks.TEMPLATES.size())
	check("templates: every one is fair (both mirrors, slowest and top speed, every entry lane)", bad.is_empty())
	if not bad.is_empty():
		print("    ", bad)
	# The validator rejects unfair shapes.
	var wall: Dictionary = {"name": "unfair_wall", "length": 2.0, "items": [
		{"k": "crates", "lane": 0, "s": 0.8, "len": 0.6}, {"k": "crates", "lane": 1, "s": 0.8, "len": 0.6}, {"k": "crates", "lane": 2, "s": 0.8, "len": 0.6}]}
	check("validator: a wall of crates across all lanes is rejected", not MageValidator.template_errors(wall).is_empty())
	var tight: Dictionary = {"name": "too_tight", "length": 2.0, "items": [
		{"k": "fence", "lane": 0, "s": 0.8}, {"k": "fence", "lane": 1, "s": 0.8}, {"k": "fence", "lane": 2, "s": 0.8},
		{"k": "beam", "lane": 0, "s": 1.0}, {"k": "beam", "lane": 1, "s": 1.0}, {"k": "beam", "lane": 2, "s": 1.0}]}
	check("validator: a fence wall right before a beam wall (no time to land) is rejected", not MageValidator.template_errors(tight).is_empty())
	var lead: Dictionary = {"name": "no_lead_in", "length": 2.0, "items": [{"k": "fence", "lane": 1, "s": 0.1}]}
	check("validator: an obstacle in the 0.3 m lead-in is rejected", not MageValidator.template_errors(lead).is_empty())
	var lonely: Dictionary = {"name": "lonely_crack", "length": 3.0, "items": [
		{"k": "ramp", "lane": 1, "row": 0, "s": 0.4, "len": 0.6}, {"k": "tiles", "lane": 1, "row": 1, "s": 1.0, "len": 0.6, "cracked": true}]}
	check("validator: a cracked tile with no intact neighbour is rejected", not MageValidator.template_errors(lonely).is_empty())
	var floating: Dictionary = {"name": "coin_in_crate", "length": 2.0, "items": [
		{"k": "crates", "lane": 1, "s": 0.8, "len": 0.6}, {"k": "coins", "shape": "line", "lane": 1, "row": 0, "s": 1.0, "n": 1, "step": 0.1}]}
	check("validator: a coin inside an obstacle is rejected", not MageValidator.template_errors(floating).is_empty())


func _test_generator() -> void:
	var a := MageGenerator.new(99)
	var b := MageGenerator.new(99)
	var ta: Dictionary = MageChunks.empty_items()
	var tb: Dictionary = MageChunks.empty_items()
	var same: bool = true
	for i: int in 40:
		same = same and String(a.next_chunk(ta)["name"]) == String(b.next_chunk(tb)["name"])
	check("generator: the same seed gives the same track", same and ta["obstacles"].size() == tb["obstacles"].size())
	# Long tracks for a few seeds: every chunk passes the rules and joins its
	# neighbour fairly at its speed; rows and cracked tiles only after unlock.
	var ok: bool = true
	var early_rows: bool = false
	var row1_seen: bool = false
	var row2_seen: bool = false
	var cracked_seen: bool = false
	var t0: int = Time.get_ticks_msec()
	var count: int = 0
	var slowest: int = 0
	for seed_value: int in [3, 1234]:
		var g := MageGenerator.new(seed_value)
		var track: Dictionary = MageChunks.empty_items()
		var prev: Dictionary = {}
		while g.end_s < 1000.0:
			var c0: int = Time.get_ticks_usec()
			var c: Dictionary = g.next_chunk(track)
			slowest = maxi(slowest, Time.get_ticks_usec() - c0)
			count += 1
			var items: Dictionary = c["items"]
			var s0: float = float(c["s0"])
			var v: float = float(c["speed"])
			if not MageValidator.rule_errors(items, s0, float(c["length"]), v).is_empty():
				ok = false
			if not prev.is_empty():
				var field: Dictionary = MageChunks.empty_items()
				MageChunks.merge(field, prev["items"] as Dictionary)
				MageChunks.merge(field, items)
				var r: Dictionary = MageValidator.search(field, float(prev["s0"]), s0 + float(c["length"]), prev["entry"] as Array[Vector2i], v, s0)
				ok = ok and bool(r["ok"])
			for t: MageTrack.Tile in items["tiles"] as Array[MageTrack.Tile]:
				if t.row >= 1 and t.s0 < MageTrack.ROW1_AT:
					early_rows = true
				if t.row >= 2 and t.s0 < MageTrack.ROW2_AT:
					early_rows = true
				if t.cracked and t.s0 < MageTrack.COLLAPSE_AT:
					early_rows = true
				row1_seen = row1_seen or t.row == 1
				row2_seen = row2_seen or t.row == 2
				cracked_seen = cracked_seen or t.cracked
			prev = c
	check("generator: 2 x 1000 m of generated track, every chunk and every join fair (%d chunks)" % count, ok and count > 500)
	check("generator: arcane rows only from 150 m (row 2 from 400 m, cracked tiles from 800 m)", not early_rows)
	check("generator: ... and they do appear (row 1, row 2, cracked tiles)", row1_seen and row2_seen and cracked_seen)
	print("    generator: %d chunks in %d ms, slowest chunk %.1f ms" % [count, Time.get_ticks_msec() - t0, float(slowest) / 1000.0])
	var reaction: bool = true
	for t: Dictionary in MageChunks.TEMPLATES:
		reaction = reaction and float(t["length"]) * 0.0 + MageTrack.VISIBLE_AHEAD / MageTrack.MAX_SPEED >= MageTrack.REACTION_TIME
	check("generator: obstacles emerge from the gate at least 0.75 s away even at top speed", reaction)
	var sim := MageRunSim.new(5)
	var lead_clear: bool = true
	for o: MageTrack.Obstacle in sim.obstacles:
		lead_clear = lead_clear and o.s0 >= 0.3
	check("generator: the run starts on a clear road", lead_clear)
	sim.threaded = true
	_steps(sim, 3.0)
	sim.finish_tasks()
	check("generator: threaded generation keeps the track ahead filled", sim.generator.end_s >= sim.distance + MageRunSim.GENERATE_AHEAD)


# --- The game in the host -----------------------------------------------------------

func _test_game_flow() -> void:
	await _set_window(PORTRAIT_WINDOW)
	MageRunGame.session_best = 0
	var host: GameHost = await make_host(&"mage_run")
	var game: MageRunGame = _game(host)
	check("game: loads with a sim and starts with a 3-2-1 countdown", game != null and game.sim != null and game.state == MageRunGame.State.COUNTDOWN)
	check("game: swipes are captured (no camera orbit)", game.captures_swipes())
	game.sim.grace_t = 1.0e6
	var d0: float = game.sim.distance
	_tick(game, 1.0)
	check("countdown: the world waits during the countdown", game.sim.distance == d0 and game._countdown_label.visible and game._countdown_label.text == "2")
	_tick(game, MageRunGame.COUNTDOWN)
	check("countdown: then the run starts", game.state == MageRunGame.State.RUNNING and game.sim.distance > d0)
	check("hud: score line shows the score, distance, coins, multiplier and best", game.hud_text().contains("m") and game.hud_text().contains("Best"))
	game.sim._crash(&"fence")
	_tick(game, DT)
	check("game over: crash shows the game-over panel", game.state == MageRunGame.State.OVER and game._over_panel.visible)
	var score: int = game.sim.score()
	check("best: the session best updates on game over", MageRunGame.session_best == score and score > 0 and game.best_this_run)
	check("status: tells how to start again", host.get_status_text().contains("Run again"))
	game.restart_button.pressed.emit()
	await frames(1)
	check("restart: Run again starts a fresh run (countdown, score 0), best kept", game.state == MageRunGame.State.COUNTDOWN and game.sim.score() == 0 and game.sim.distance == 0.0 and MageRunGame.session_best == score and not game._over_panel.visible)
	_tick(game, MageRunGame.COUNTDOWN + 0.1)
	game.sim.score_f = 0.0
	game.sim._crash(&"beam")
	_tick(game, DT)
	check("best: a lower score keeps the best", MageRunGame.session_best == score and not game.best_this_run)
	await free_host(host)
	host = await make_host(&"mage_run")
	check("best: the session best survives leaving and coming back", _game(host).hud_text().contains("Best %d" % score))
	await free_host(host)


func _test_host_swipes() -> void:
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await _running_host()
	var game: MageRunGame = _game(host)
	host._swipes.threshold_px = 48.0
	var yaw: float = host.orbit_camera.yaw
	_swipe(host, Vector2(360, 900), Vector2(200, 900))
	check("host: a left swipe on screen changes to the wizard's left lane", game.sim.lane == 0 and is_equal_approx(host.orbit_camera.yaw, yaw))
	_tick(game, 0.2)
	_swipe(host, Vector2(360, 900), Vector2(360, 760))
	check("host: a swipe up jumps", not game.sim.grounded and game.sim.vy > 0.0)
	_tick(game, 0.8)
	_swipe(host, Vector2(360, 700), Vector2(360, 860))
	check("host: a swipe down slides", game.sim.sliding())
	_tick(game, 0.7)
	game._hide_hint()
	# Seen from the castle end (walked round the board), screen left is his right.
	host.orbit_camera.yaw = PI
	host.orbit_camera.orbit(Vector2.ZERO)
	await frames(1)
	check("lanes: from the far end, left / right flip to match the screen", game.lane_sign() == -1)
	host.orbit_camera.yaw = 0.0
	host.orbit_camera.orbit(Vector2.ZERO)
	await frames(1)
	check("lanes: from behind the wizard, screen right is his right", game.lane_sign() == 1)
	# Double tap casts.
	game.sim.meter = MageRunSim.METER_FULL
	game._on_box_ray(Vector3.ZERO, Vector3.DOWN)
	_tick(game, 0.1)
	game._on_box_ray(Vector3.ZERO, Vector3.DOWN)
	check("staff: a double tap casts the staff", game.sim.meter == 0 and game.sim.shield_t > 0.0)
	game.sim.meter = MageRunSim.METER_FULL
	await frames(1)
	var cast_rect: Rect2 = game.cast_button.get_global_rect()
	check("staff: the Cast button is game UI (touches there are not swipes or taps)", game.is_over_game_ui(cast_rect.get_center()) and not game.is_over_game_ui(_view().get_center()))
	game.cast_button.pressed.emit()
	check("staff: the Cast button casts too (Magnet next)", game.sim.magnet_t > 0.0)
	await free_host(host)


func _test_pause_and_rotate() -> void:
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await _running_host()
	var game: MageRunGame = _game(host)
	game.pause_button.pressed.emit()
	var d: float = game.sim.distance
	_tick(game, 1.0)
	check("pause: the Pause button stops the run", game.state == MageRunGame.State.PAUSED and game.sim.distance == d and game._pause_panel.visible)
	game.resume_button.pressed.emit()
	check("resume: counts down 3-2-1 first", game.state == MageRunGame.State.COUNTDOWN and not game._pause_panel.visible)
	_tick(game, MageRunGame.COUNTDOWN + 0.05)
	check("resume: then runs on from where it was", game.state == MageRunGame.State.RUNNING and game.sim.distance > d)
	# Buffered input never fires after a pause.
	game.sim.buffer.push(Vector2i.UP, game.sim.time)
	await _set_window(LANDSCAPE_WINDOW)
	check("rotate: turning the phone pauses the run", game.state == MageRunGame.State.PAUSED and game.pause_reason == &"rotate")
	check("rotate: ... and drops any buffered swipe", not game.sim.buffer.has_pending(game.sim.time))
	d = game.sim.distance
	_tick(game, 0.5)
	check("rotate: nothing moves while paused", game.sim.distance == d)
	check("rotate: the pause panel says why", game._pause_label.text.to_lower().contains("turn") or game._pause_label.text.to_lower().contains("rotat"))
	game.resume_button.pressed.emit()
	_tick(game, MageRunGame.COUNTDOWN + 0.05)
	check("rotate: resumes in landscape after the countdown", game.state == MageRunGame.State.RUNNING and not game.is_portrait())
	await _set_window(PORTRAIT_WINDOW)
	check("rotate: back to portrait pauses again", game.state == MageRunGame.State.PAUSED)
	game.resume()
	_tick(game, 1.0)
	await _set_window(LANDSCAPE_WINDOW)
	check("rotate: during the countdown it pauses too", game.state == MageRunGame.State.PAUSED)
	game.lg_set_app_paused(true)
	game.lg_set_app_paused(false)
	check("app: leaving the app keeps the run paused until Resume", game.state == MageRunGame.State.PAUSED)
	await free_host(host)
	# Game over is not overridden by a turn.
	host = await _running_host()
	game = _game(host)
	game.sim._crash(&"fence")
	_tick(game, DT)
	await _set_window(PORTRAIT_WINDOW)
	check("rotate: after game over the result stays up", game.state == MageRunGame.State.OVER and game._over_panel.visible)
	await free_host(host)


func _check_hud(host: GameHost, label: String) -> void:
	var game: MageRunGame = _game(host)
	var view: Rect2 = _view()
	await frames(2)
	var score: Rect2 = game._score_box.get_global_rect()
	var staff: Rect2 = game._staff_panel.get_global_rect()
	var pause_r: Rect2 = game.pause_button.get_global_rect()
	var status: Rect2 = host._status_label.get_global_rect()
	var back: Rect2 = host._back_button.get_global_rect()
	check("%s: score, staff meter and Pause inside the screen" % label, _contains(view, score) and _contains(view, staff) and _contains(view, pause_r))
	check("%s: score clear of the back button and status line" % label, not _overlap(score, back) and (host._status_label.text == "" or not _overlap(score, status)))
	check("%s: staff panel and Pause apart, at the bottom" % label, not _overlap(staff, pause_r) and staff.position.y > view.size.y * 0.6 and pause_r.position.y > view.size.y * 0.6)
	check("%s: Pause button is a comfortable touch target (>= 88 px)" % label, pause_r.size.x >= 88.0 and pause_r.size.y >= 88.0)
	for panel: Control in [game._pause_panel, game._over_panel, game._hint_panel]:
		panel.visible = true
	await frames(2)
	check("%s: pause, game-over and hint panels inside the screen" % label, _contains(view, game._pause_panel.get_global_rect()) and _contains(view, game._over_panel.get_global_rect()) and _contains(view, game._hint_panel.get_global_rect()))
	check("%s: panels clear of the staff and Pause buttons" % label, not _overlap(game._over_panel.get_global_rect(), pause_r) and not _overlap(game._over_panel.get_global_rect(), staff))
	for panel: Control in [game._pause_panel, game._over_panel, game._hint_panel]:
		panel.visible = false


func _test_hud_layouts() -> void:
	for window: Vector2i in [PORTRAIT_WINDOW, LANDSCAPE_WINDOW]:
		await _set_window(window)
		var host: GameHost = await _running_host()
		await _check_hud(host, "hud %dx%d" % [window.x, window.y])
		await free_host(host)
	# Rotating mid-game re-lays the HUD out.
	await _set_window(PORTRAIT_WINDOW)
	var h: GameHost = await _running_host()
	await _set_window(LANDSCAPE_WINDOW)
	await _check_hud(h, "hud after rotate to landscape")
	await free_host(h)


func _test_first_run_hint() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINT_CFG))
	await _set_window(PORTRAIT_WINDOW)
	var host: GameHost = await make_host(&"mage_run")
	var game: MageRunGame = _game(host)
	game.sim.grace_t = 1.0e6
	check("hint: the first run shows the hold-upright hint", game.hint_visible() and game._hint_label.text.contains("upright"))
	_tick(game, MageRunGame.COUNTDOWN + MageRunGame.HINT_TIME + 0.2)
	check("hint: it goes away by itself", not game.hint_visible())
	await free_host(host)
	host = await make_host(&"mage_run")
	check("hint: not shown again", not _game(host).hint_visible())
	await free_host(host)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINT_CFG))
	await _set_window(LANDSCAPE_WINDOW)
	host = await make_host(&"mage_run")
	game = _game(host)
	check("hint: in landscape it suggests turning the phone upright", game.hint_visible() and game._hint_label.text.contains("upright"))
	_tick(game, MageRunGame.COUNTDOWN + 0.1)
	_swipe(host, Vector2(900, 500), Vector2(700, 500))
	check("hint: the first swipe hides it", not game.hint_visible())
	await free_host(host)


func _test_containment() -> void:
	await _set_window(PORTRAIT_WINDOW)
	for start: float in [0.0, 420.0, 820.0]:
		var host: GameHost = await _running_host()
		var game: MageRunGame = _game(host)
		game.sim.reset(11, start)
		game.sim.grace_t = 1.0e6
		var inside: bool = true
		var worst: String = ""
		var seen_rows: bool = false
		for frame: int in 900:
			game._process(DT)
			if frame % 6 != 0:
				continue
			seen_rows = seen_rows or game._tile_mm.visible_instance_count > 0
			var aabbs: Array[AABB] = game.content_aabbs()
			aabbs.append_array(game.scenery_aabbs())
			for a: AABB in aabbs:
				for i: int in 8:
					var p: Vector3 = a.get_endpoint(i)
					if not game.box_contains(p, -0.0005):
						inside = false
						worst = "%s at %.1f m" % [p, game.sim.distance]
		check("box: from %d m, 15 s of run: props, tiles, coins, wizard and scenery stay inside the play box%s" % [int(start), "" if inside else " (" + worst + ")"], inside)
		if start > 0.0:
			check("box: arcane tiles were on screen from %d m" % int(start), seen_rows)
		await free_host(host)


func _test_budget() -> void:
	var wizard: Dictionary = MageProps.wizard()
	check("budget: the wizard is <= 2.5k triangles", int(wizard["triangles"]) <= 2500)
	var worst: int = 0
	var report: Array[String] = []
	var k: float = MageTrack.RUN_TO_BOARD
	var props: Dictionary = {
		"fence": MageProps.fence(MageTrack.FENCE_LEN * k), "beam": MageProps.beam(MageTrack.BEAM_LEN * k),
		"crates": MageProps.crates(MageTrack.CRATE_MIN_LEN * k), "cart": MageProps.cart(MageTrack.CART_LEN * k),
		"carriage": MageProps.carriage(MageTrack.CARRIAGE_LEN * k),
	}
	for kind: String in props:
		var n: int = _mesh_triangles(props[kind] as Mesh)
		worst = maxi(worst, n)
		report.append("%s %d" % [kind, n])
	check("budget: every prop is <= 800 triangles (%s)" % ", ".join(report), worst <= 800)
	var host: GameHost = await _running_host()
	var game: MageRunGame = _game(host)
	game.sim.reset(11, 420.0)
	game.sim.grace_t = 1.0e6
	var peak: int = 0
	var peak_nodes: int = 0
	for frame: int in 600:
		game._process(DT)
		if frame % 30 != 0:
			continue
		var tris: int = 0
		var nodes: int = 0
		for node: Node in game.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			nodes += 1
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
				tris += _mesh_triangles((gi as MeshInstance3D).mesh)
			elif gi is MultiMeshInstance3D:
				var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
				tris += _mesh_triangles(mm.mesh) * mm.visible_instance_count
		peak = maxi(peak, tris)
		peak_nodes = maxi(peak_nodes, nodes)
	print("    budget: peak %d triangles, %d visible geometry nodes %s" % [peak, peak_nodes, report])
	check("budget: under 60k triangles on screen at peak (%d)" % peak, peak > 0 and peak <= 60000)
	check("budget: visible geometry nodes well under the 120 draw-call budget (%d)" % peak_nodes, peak_nodes <= 90)
	await free_host(host)
