class_name MageRunSim
extends RefCounted
## Mage Run's game logic, with no nodes: the wizard's lanes / rows, jumps,
## slides, drops and ramps, the generated track, collisions and stumbles,
## coins and multipliers, the staff meter and power-ups, speed and score.
## MageRunGame steps it every frame and draws it; tests drive it directly.
## Deterministic for a seed. Events (coin, jump, crash, ...) queue up in
## `events` for the visuals (drain with take_events()).

## Score: points per run metre (times the multiplier) and per coin (times
## its row: x1 ground, x2 Arcane I, x3 Arcane II).
const COIN_POINTS: int = 10
## Multiplier: +1 per STREAK_COINS coins without a stumble, up to MAX_MULTIPLIER.
const STREAK_COINS: int = 20
const MAX_MULTIPLIER: int = 5
## Stumble: slowed for this long; a second stumble within STUMBLE_WINDOW ends the run.
const STUMBLE_SLOW: float = 0.8
const STUMBLE_FACTOR: float = 0.7
const STUMBLE_WINDOW: float = 3.0
## Staff meter: full at METER_FULL; a coin adds 1, a perfect dodge 3.
const METER_FULL: int = 50
const DODGE_BONUS: int = 3
const DODGE_WINDOW: float = 0.5
## Power-ups (seconds).
const SHIELD_TIME: float = 12.0
const MAGNET_TIME: float = 10.0
const LEVITATION_TIME: float = 8.0
## After levitation: a safe landing (no crash) for this long.
const LANDING_GRACE: float = 1.0
const MAGNET_LANES: float = 1.5
const MAGNET_AHEAD: float = 0.7
const MAGNET_FLY_TIME: float = 0.15
const LEVITATION_RISE: float = 0.45
## Track kept generated this far ahead (run m).
const GENERATE_AHEAD: float = MageTrack.SPAWN_AHEAD + 1.5

enum Power { SHIELD, MAGNET, LEVITATION }
const POWER_NAMES: Array[String] = ["Shield", "Magnet", "Levitation"]

var seed_value: int = 0
var generator: MageGenerator
var track: Dictionary = MageChunks.empty_items()
var events: Array[Dictionary] = []

var time: float = 0.0
var distance: float = 0.0
var alive: bool = true
var score_f: float = 0.0
var coins: int = 0
var coin_streak: int = 0
var multiplier: int = 1
var meter: int = 0
var next_power: Power = Power.SHIELD
var shield_t: float = 0.0
var magnet_t: float = 0.0
var levitation_t: float = 0.0
var grace_t: float = 0.0
var crash_kind: StringName = &""
var perfect_dodges: int = 0

# The wizard.
var lane: int = 1
var from_lane: int = 1
## Lane change progress 0..1 (1 = done).
var lane_t: float = 1.0
var x: float = 0.0
var y: float = 0.0
var vy: float = 0.0
var grounded: bool = true
## The support under a grounded wizard: &"ground", &"tile", &"ramp", &"roof", &"levitation".
var support: StringName = &"ground"
var support_tile: MageTrack.Tile = null
var slide_t: float = 0.0
var slam: bool = false
var coyote_t: float = 0.0
var slow_t: float = 0.0
var last_stumble: float = -INF
var buffer := SwipeBuffer.new()
var _dodge_from: int = -1
var _dodge_time: float = -INF


func _init(p_seed: int = 1, start: float = 0.0) -> void:
	reset(p_seed, start)


## Start a run (at `start` run metres: tests and the debug start skip ahead).
func reset(p_seed: int, start: float = 0.0) -> void:
	finish_tasks()
	seed_value = p_seed
	generator = MageGenerator.new(p_seed, start)
	track = MageChunks.empty_items()
	events.clear()
	time = 0.0
	distance = start
	alive = true
	score_f = 0.0
	coins = 0
	coin_streak = 0
	multiplier = 1
	meter = 0
	next_power = Power.SHIELD
	shield_t = 0.0
	magnet_t = 0.0
	levitation_t = 0.0
	grace_t = 0.0
	crash_kind = &""
	perfect_dodges = 0
	lane = 1
	from_lane = 1
	lane_t = 1.0
	x = 0.0
	y = 0.0
	vy = 0.0
	grounded = true
	support = &"ground"
	support_tile = null
	slide_t = 0.0
	slam = false
	coyote_t = 0.0
	slow_t = 0.0
	last_stumble = -INF
	buffer = SwipeBuffer.new()
	buffer.window = MageTrack.BUFFER_TIME
	_dodge_from = -1
	_dodge_time = -INF
	_generate()


# --- Queries ------------------------------------------------------------------------

var obstacles: Array[MageTrack.Obstacle]:
	get:
		return track["obstacles"]
var tiles: Array[MageTrack.Tile]:
	get:
		return track["tiles"]
var ramps: Array[MageTrack.Ramp]:
	get:
		return track["ramps"]
var coin_items: Array[MageTrack.Coin]:
	get:
		return track["coins"]


func speed() -> float:
	var v: float = MageTrack.speed_at(distance)
	return v * STUMBLE_FACTOR if slow_t > 0.0 else v


func score() -> int:
	return int(score_f)


func sliding() -> bool:
	return slide_t > 0.0


func body_height() -> float:
	return MageTrack.SLIDE_HEIGHT if sliding() else MageTrack.BODY_HEIGHT


func levitating() -> bool:
	return levitation_t > 0.0


func changing_lane() -> bool:
	return lane_t < 1.0


## The row the wizard is on (or over): 0 ground, 1 Arcane I, 2 Arcane II.
func row() -> int:
	return clampi(floori((y + 0.02) / MageTrack.ROW_HEIGHT), 0, MageTrack.TOP_ROW)


func on_arcane_row() -> bool:
	return grounded and (support == &"tile" or (support == &"ramp" and y > MageTrack.ROW_HEIGHT * 0.5) or support == &"levitation") and y > MageTrack.ROW_HEIGHT * 0.5


func rows_unlocked() -> int:
	return MageTrack.rows_unlocked(distance)


func meter_full() -> bool:
	return meter >= METER_FULL


## What the staff casts next (levitation needs an unlocked row).
func power_to_cast() -> Power:
	var p: Power = next_power
	if p == Power.LEVITATION and rows_unlocked() == 0:
		p = Power.SHIELD
	return p


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events.duplicate()
	events.clear()
	return out


func _event(kind: StringName, data: Dictionary = {}) -> void:
	var e: Dictionary = data.duplicate()
	e["kind"] = kind
	e["time"] = time
	events.append(e)


# --- Input --------------------------------------------------------------------------

## A swipe in the wizard's frame: x = -1 left / +1 right (his left and right),
## y = -1 up / +1 down. Returns what it did: &"lane", &"reverse", &"bump",
## &"jump", &"slide", &"drop", &"slam", &"buffered" or &"ignored".
func swipe(dir: Vector2i) -> StringName:
	if not alive:
		return &"ignored"
	var result: StringName = _apply(dir)
	if result == &"buffered":
		buffer.push(dir, time)
	return result


func _apply(dir: Vector2i) -> StringName:
	if dir.x != 0:
		var step: int = signi(dir.x)
		if changing_lane():
			if signi(lane - from_lane) == -step:
				# Reverse mid-change (no buffer needed).
				var back: int = from_lane
				from_lane = lane
				lane = back
				lane_t = 1.0 - lane_t
				_event(&"reverse")
				return &"reverse"
			return &"buffered"
		var target: int = lane + step
		if target < 0 or target >= MageTrack.LANES:
			_event(&"bump", {"edge": true})
			return &"bump"
		if grounded and not levitating() and y > 0.001 and not _walkable(target, distance, y):
			_event(&"bump", {"edge": false})
			return &"bump"
		from_lane = lane
		lane = target
		lane_t = 0.0
		_dodge_from = from_lane
		_dodge_time = time
		_event(&"lane", {"to": lane})
		return &"lane"
	if dir.y < 0:
		if levitating():
			return &"ignored"
		if grounded or coyote_t > 0.0:
			_jump()
			return &"jump"
		return &"buffered"
	if dir.y > 0:
		if levitating():
			return &"ignored"
		if not grounded:
			slam = true
			vy = minf(vy, -MageTrack.SLAM_SPEED)
			coyote_t = 0.0
			_event(&"slam")
			return &"slam"
		if y > 0.001:
			y -= MageTrack.DROP_NUDGE
			grounded = false
			vy = 0.0
			coyote_t = 0.0
			support = &""
			support_tile = null
			_event(&"drop")
			return &"drop"
		slide_t = MageTrack.SLIDE_TIME
		_event(&"slide")
		return &"slide"
	return &"ignored"


func _jump() -> void:
	vy = MageTrack.JUMP_SPEED
	grounded = false
	coyote_t = 0.0
	slide_t = 0.0
	slam = false
	support = &""
	support_tile = null
	_event(&"jump")


## Cast the staff's power-up (meter full). Returns the power or -1.
func cast() -> int:
	if not alive or not meter_full():
		return -1
	var p: Power = power_to_cast()
	meter = 0
	match p:
		Power.SHIELD:
			shield_t = SHIELD_TIME
		Power.MAGNET:
			magnet_t = MAGNET_TIME
		Power.LEVITATION:
			levitation_t = LEVITATION_TIME
			slide_t = 0.0
	next_power = ((int(p) + 1) % 3) as Power
	_event(&"cast", {"power": int(p)})
	return int(p)


# --- Step ---------------------------------------------------------------------------

func step(dt: float) -> void:
	if not alive or dt <= 0.0:
		return
	time += dt
	var v: float = speed()
	distance += v * dt
	score_f += v * dt * float(multiplier)
	_generate()
	_trim()
	_move_carts(dt)
	_lateral(dt)
	_vertical(dt)
	_crumble(dt)
	if slide_t > 0.0:
		slide_t = maxf(slide_t - dt, 0.0)
	if buffer.has_pending(time):
		var dir: Vector2i = buffer.take(time)
		var r: StringName = _apply(dir)
		if r == &"buffered":
			buffer.push(dir, time - dt)
	_collide()
	_collect(dt)
	_timers(dt)


## Track generation: inline (tests, desktop) or, with `threaded`, on a
## worker thread ahead of need; the step only waits for it if content is
## actually due (never in normal play: it starts THREAD_LEAD run m early).
var threaded: bool = false
const THREAD_LEAD: float = 3.0
var _task: int = -1
var _task_result: Dictionary = {}
var _content_end: float = 0.0


func _generate() -> void:
	if _task >= 0:
		# The worker owns the generator until it is done: use the end from before.
		var done: bool = WorkerThreadPool.is_task_completed(_task)
		if not done and _content_end >= distance + GENERATE_AHEAD:
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		MageChunks.merge(track, _task_result["items"] as Dictionary)
		_task_result = {}
	while generator.end_s < distance + GENERATE_AHEAD:
		generator.next_chunk(track)
	if threaded and generator.end_s < distance + GENERATE_AHEAD + THREAD_LEAD:
		_content_end = generator.end_s
		_task = WorkerThreadPool.add_task(_make_chunk_task)


func _make_chunk_task() -> void:
	_task_result = generator.make_chunk()


## Finish any background generation (before freeing / resetting).
func finish_tasks() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_task_result = {}


func _trim() -> void:
	var behind: float = distance - MageTrack.BEHIND - 0.2
	var keep_o: Array[MageTrack.Obstacle] = []
	for o: MageTrack.Obstacle in obstacles:
		if o.s1() > behind:
			keep_o.append(o)
	var keep_t: Array[MageTrack.Tile] = []
	for t: MageTrack.Tile in tiles:
		if t.s1() > behind:
			keep_t.append(t)
	var keep_r: Array[MageTrack.Ramp] = []
	for r: MageTrack.Ramp in ramps:
		if r.s1() > behind:
			keep_r.append(r)
	var keep_c: Array[MageTrack.Coin] = []
	for c: MageTrack.Coin in coin_items:
		if c.s > behind and (c.flying or not c.taken):
			keep_c.append(c)
	track["obstacles"] = keep_o
	track["tiles"] = keep_t
	track["ramps"] = keep_r
	track["coins"] = keep_c


func _move_carts(dt: float) -> void:
	for o: MageTrack.Obstacle in obstacles:
		if not o.moving:
			continue
		if not o.active and o.s0 - distance <= MageTrack.VISIBLE_AHEAD:
			o.active = true
		if o.active:
			o.s0 -= MageTrack.CART_SPEED * dt


func _lateral(dt: float) -> void:
	if lane_t < 1.0:
		lane_t = minf(lane_t + dt / MageTrack.LANE_TIME, 1.0)
	var t: float = lane_t * lane_t * (3.0 - 2.0 * lane_t)
	x = lerpf(MageTrack.lane_x(from_lane), MageTrack.lane_x(lane), t)


## Walkable surfaces at (lane, s): ground, tiles, ramps, roofs, levitation.
func supports_at(at_lane: int, s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"h": 0.0, "kind": &"ground"}]
	for t: MageTrack.Tile in tiles:
		if t.lane == at_lane and t.covers(s):
			out.append({"h": t.height(), "kind": &"tile", "tile": t})
	for r: MageTrack.Ramp in ramps:
		if r.lane == at_lane and r.covers(s):
			out.append({"h": r.height_at(s), "kind": &"ramp"})
	for o: MageTrack.Obstacle in obstacles:
		# A roof holds the wizard while any of his body is over it.
		if o.roof > 0.0 and not o.broken and o.has_lane(at_lane) and s >= o.s0 - MageTrack.BODY_HALF_LEN and s <= o.s1() + MageTrack.BODY_HALF_LEN:
			out.append({"h": o.roof, "kind": &"roof"})
	if levitating():
		out.append({"h": _levitation_height(), "kind": &"levitation"})
	return out


func _walkable(at_lane: int, s: float, h: float) -> bool:
	for sup: Dictionary in supports_at(at_lane, s):
		if absf(float(sup["h"]) - h) <= MageTrack.STEP_UP:
			return true
	return false


func _levitation_height() -> float:
	return MageTrack.row_y(maxi(rows_unlocked(), 1))


func _vertical(dt: float) -> void:
	var cur_lane: int = MageTrack.lane_at(x)
	var sups: Array[Dictionary] = supports_at(cur_lane, distance)
	if levitating():
		var target: float = _levitation_height()
		y = move_toward(y, target, LEVITATION_RISE * dt)
		vy = 0.0
		grounded = true
		support = &"levitation"
		support_tile = null
		coyote_t = 0.0
		return
	if grounded:
		var best: Dictionary = {}
		for sup: Dictionary in sups:
			var h: float = float(sup["h"])
			if h <= y + MageTrack.STEP_UP and h >= y - 0.004 and (best.is_empty() or h > float(best["h"])):
				best = sup
		if not best.is_empty():
			y = float(best["h"])
			support = best["kind"]
			support_tile = best.get("tile") as MageTrack.Tile
			return
		# Ran off the edge (or the tile crumbled): fall, with coyote grace.
		grounded = false
		vy = 0.0
		coyote_t = MageTrack.COYOTE_TIME
		support = &""
		support_tile = null
		_event(&"fall")
	coyote_t = maxf(coyote_t - dt, 0.0)
	var prev_y: float = y
	# Exact parabola per step (same apex at any frame rate as the validator).
	y += vy * dt - 0.5 * MageTrack.GRAVITY * dt * dt
	vy -= MageTrack.GRAVITY * dt
	if vy <= 0.0:
		var land: Dictionary = {}
		for sup: Dictionary in sups:
			var h: float = float(sup["h"])
			if h <= prev_y + 0.0001 and h >= y and (land.is_empty() or h > float(land["h"])):
				land = sup
		if not land.is_empty():
			y = float(land["h"])
			vy = 0.0
			grounded = true
			support = land["kind"]
			support_tile = land.get("tile") as MageTrack.Tile
			_event(&"land", {"support": support, "row": row()})
			if slam:
				slam = false
				if y < 0.001:
					slide_t = MageTrack.SLIDE_TIME
					_event(&"slide")
	y = maxf(y, 0.0)


func _crumble(dt: float) -> void:
	if grounded and support == &"tile" and support_tile != null and support_tile.cracked and support_tile.crumble < 0.0:
		support_tile.crumble = 0.0
		_event(&"crack", {"id": support_tile.id})
	for t: MageTrack.Tile in tiles:
		if t.cracked and t.crumble >= 0.0 and not t.gone:
			t.crumble += dt
			if t.crumble >= MageTrack.CRACK_TIME:
				t.gone = true
				_event(&"crumble", {"id": t.id})


func _overlaps(o: MageTrack.Obstacle) -> bool:
	if distance + MageTrack.BODY_HALF_LEN <= o.s0 or distance - MageTrack.BODY_HALF_LEN >= o.s1():
		return false
	if x + MageTrack.BODY_HALF_WIDTH <= o.min_x() or x - MageTrack.BODY_HALF_WIDTH >= o.max_x():
		return false
	if o.roof > 0.0 and y >= o.roof - 0.0005:
		return false
	return y < o.top - 0.0005 and y + body_height() > o.base + 0.0005


func _collide() -> void:
	for o: MageTrack.Obstacle in obstacles:
		if o.broken or o.grazed:
			continue
		if not o.passed and o.s1() + MageTrack.BODY_HALF_LEN < distance:
			o.passed = true
			if _dodge_from >= 0 and o.has_lane(_dodge_from) and not o.has_lane(MageTrack.lane_at(x)) and time - _dodge_time <= DODGE_WINDOW and o.base <= y + body_height() and o.top >= y:
				perfect_dodges += 1
				meter = mini(meter + DODGE_BONUS, METER_FULL)
				_event(&"dodge", {"id": o.id})
		if not _overlaps(o):
			continue
		if grace_t > 0.0 or levitating():
			continue
		if shield_t > 0.0:
			shield_t = 0.0
			o.broken = true
			grace_t = 0.4
			_event(&"smash", {"id": o.id})
			continue
		if changing_lane() and o.has_lane(lane) and not o.has_lane(from_lane):
			o.grazed = true
			_stumble()
			if not alive:
				crash_kind = o.kind
				return
			continue
		_crash(o.kind)
		return


func _stumble() -> void:
	if time - last_stumble <= STUMBLE_WINDOW:
		_crash(&"stumble")
		return
	last_stumble = time
	slow_t = STUMBLE_SLOW
	coin_streak = 0
	# Bounce back to the lane we came from.
	var back: int = from_lane
	from_lane = lane
	lane = back
	lane_t = 1.0 - lane_t
	_event(&"stumble")


func _crash(kind: StringName) -> void:
	alive = false
	crash_kind = kind
	_event(&"crash", {"obstacle": kind})


func _collect(dt: float) -> void:
	var magnet: bool = magnet_t > 0.0
	for c: MageTrack.Coin in coin_items:
		if c.taken and not c.flying:
			continue
		if c.flying:
			c.fly += dt
			if c.fly >= MAGNET_FLY_TIME:
				c.flying = false
				_take(c)
			continue
		var ds: float = c.s - distance
		var dx: float = MageTrack.lane_x(c.lane) - x
		if absf(ds) < 0.08 and absf(dx) < 0.035 and c.y >= y - 0.012 and c.y <= y + body_height() + 0.012:
			c.taken = true
			_take(c)
		elif magnet and ds > -0.05 and ds < MAGNET_AHEAD and absf(dx) <= MageTrack.LANE_PITCH * MAGNET_LANES and absf(c.y - (y + 0.03)) < 0.16:
			c.taken = true
			c.flying = true
			c.fly = 0.0


func _take(c: MageTrack.Coin) -> void:
	coins += c.value()
	score_f += float(COIN_POINTS * c.value())
	coin_streak += 1
	meter = mini(meter + 1, METER_FULL)
	if coin_streak >= STREAK_COINS:
		coin_streak = 0
		if multiplier < MAX_MULTIPLIER:
			multiplier += 1
			_event(&"multiplier", {"value": multiplier})
	_event(&"coin", {"id": c.id, "value": c.value(), "row": c.row})


func _timers(dt: float) -> void:
	slow_t = maxf(slow_t - dt, 0.0)
	grace_t = maxf(grace_t - dt, 0.0)
	shield_t = maxf(shield_t - dt, 0.0)
	magnet_t = maxf(magnet_t - dt, 0.0)
	if levitation_t > 0.0:
		levitation_t = maxf(levitation_t - dt, 0.0)
		if levitation_t == 0.0:
			grounded = false
			vy = 0.0
			support = &""
			grace_t = LANDING_GRACE
			_event(&"levitation_end")


## The coin-flight position (0..1 toward the wizard) for the visuals.
func coin_fly_t(c: MageTrack.Coin) -> float:
	return clampf(c.fly / MAGNET_FLY_TIME, 0.0, 1.0)
