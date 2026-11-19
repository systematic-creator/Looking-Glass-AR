class_name MageValidator
extends RefCounted
## Fairness for Mage Run's generated track (doc section 6):
##   1. a safe path always exists, through a chunk and across chunk joins
##      (a search over the wizard's real move set and physics, MageTrack);
##   2. reaction time: everything is in view REACTION_TIME s before it
##      arrives (a property of the board layout, reaction_ok());
##   3. at most two forced inputs (walls across all three lanes) within 0.35 s;
##   4. arcane-row segments end over clear ground (at least 0.25 s, or the
##      fall time, of it);
##   5. cracked tiles always have an intact tile one lane over;
##   6. coin lines are reachable (no coin in an obstacle or out of jump reach);
## plus shape rules: a 0.3 m lead-in at every chunk start (so joins work),
## items fit behind the castle gate, ramps lead onto tiles, nothing pokes up
## through a row, and a rolling cart's lane is clear of anything it would
## roll through.

## Search resolution (run m) and the slack the search gives itself: it tests
## obstacles a little longer and taller than they are, so a path it finds is
## a path the frame-stepped game also allows.
const DS: float = 0.05
const S_MARGIN: float = 0.025
const Y_MARGIN: float = 0.003
const LEAD: float = 0.3
const SEGMENT_CLEAR_TIME: float = 0.25
const FORCED_WINDOW: float = 0.35
## Walking: largest rise per search step (ramps) and the down-snap.
const WALK_RISE: float = 0.035
const WALK_SNAP: float = 0.005


static func reaction_ok() -> bool:
	return MageTrack.reaction_time(MageTrack.MAX_SPEED, MageTrack.CART_SPEED) >= MageTrack.REACTION_TIME


## Vertical answers to one obstacle of `kind` standing alone in a lane, at
## `speed`: which of "jump", "slide", "run" get past it without a lane change.
## The design wants exactly one answer per shape (lane change aside).
static func answers(kind: StringName, speed: float) -> PackedStringArray:
	var out := PackedStringArray()
	var template: Dictionary = {"name": "probe", "length": 2.0, "items": [{"k": String(kind), "lane": 1, "s": 1.0, "len": MageTrack.CRATE_MIN_LEN}]}
	var items: Dictionary = MageChunks.instantiate(template, 0.0, false, [0])
	var entry: Array[Vector2i] = [Vector2i(1, 0)]
	for move: String in ["run", "jump", "slide"]:
		var r: Dictionary = search(items, 0.0, 2.0, entry, speed, -1.0, PackedStringArray(["run", move]), true)
		if bool(r["ok"]):
			out.append(move)
	return out


# --- Search -------------------------------------------------------------------------

class Field:
	extends RefCounted
	## Per lane, per search slot: blocking (base, top) pairs and walkable
	## heights (ground, ramps, intact tiles; cracked tiles count as missing and
	## roofs are not used: both conservative).
	var speed: float
	var n: int
	## Flattened [lane * (n + 2) + slot].
	var blocks: Array[PackedFloat32Array] = []
	var sups: Array[PackedFloat32Array] = []
	## Highest blocking top per lane / slot (quick "clear above" test).
	var tops: PackedFloat32Array = PackedFloat32Array()
	var stride: int = 0

	func _init(items: Dictionary, p_speed: float, s_start: float, p_n: int) -> void:
		speed = p_speed
		n = p_n
		stride = n + 2
		for k: int in MageTrack.LANES * stride:
			blocks.append(PackedFloat32Array())
			sups.append(PackedFloat32Array([0.0]))
		tops.resize(MageTrack.LANES * stride)
		tops.fill(-1.0)
		for o: MageTrack.Obstacle in items["obstacles"] as Array[MageTrack.Obstacle]:
			var b: Vector2
			if o.moving:
				b = MageTrack.cart_block(o.s0, o.length, speed)
				b = Vector2(b.x - MageValidator.S_MARGIN, b.y + MageValidator.S_MARGIN)
			else:
				b = Vector2(o.s0 - MageTrack.BODY_HALF_LEN - MageValidator.S_MARGIN, o.s1() + MageTrack.BODY_HALF_LEN + MageValidator.S_MARGIN)
			var i0: int = maxi(ceili((b.x - s_start) / MageValidator.DS), 0)
			var i1: int = mini(floori((b.y - s_start) / MageValidator.DS), n + 1)
			for lane: int in o.lanes:
				for i: int in range(i0, i1 + 1):
					var k: int = lane * stride + i
					blocks[k].append(o.base - MageValidator.Y_MARGIN)
					blocks[k].append(o.top + MageValidator.Y_MARGIN)
					tops[k] = maxf(tops[k], o.top + MageValidator.Y_MARGIN)
		for t: MageTrack.Tile in items["tiles"] as Array[MageTrack.Tile]:
			if t.cracked or t.gone:
				continue
			for i: int in range(maxi(ceili((t.s0 - s_start) / MageValidator.DS), 0), mini(floori((t.s1() - s_start) / MageValidator.DS), n + 1) + 1):
				sups[t.lane * stride + i].append(t.height())
		for r: MageTrack.Ramp in items["ramps"] as Array[MageTrack.Ramp]:
			for i: int in range(maxi(ceili((r.s0 - s_start) / MageValidator.DS), 0), mini(floori((r.s1() - s_start) / MageValidator.DS), n + 1) + 1):
				sups[r.lane * stride + i].append(r.height_at(s_start + float(i) * MageValidator.DS))

	func supports(lane: int, i: int) -> PackedFloat32Array:
		return sups[lane * stride + mini(i, n + 1)]

	func blocked(lane: int, i: int, y: float, h: float) -> bool:
		var idx: int = lane * stride + mini(i, n + 1)
		if y >= tops[idx]:
			return false
		var pairs: PackedFloat32Array = blocks[idx]
		var k: int = 0
		while k < pairs.size():
			if y < pairs[k + 1] and y + h > pairs[k]:
				return true
			k += 2
		return false

	## The support a walker at height h steps onto at slot i (or -1: it falls).
	func walk_to(lane: int, i: int, h: float) -> float:
		var best: float = -1.0
		for sh: float in supports(lane, i):
			if sh <= h + MageValidator.WALK_RISE and sh >= h - MageValidator.WALK_SNAP and sh > best:
				best = sh
		return best

	## Landing height between prev_y (above) and y (below), or -1.
	func landing(lane: int, i: int, prev_y: float, y: float) -> float:
		var best: float = -1.0
		for sh: float in supports(lane, i):
			if sh <= prev_y + 0.0001 and sh >= y and sh > best:
				best = sh
		return best


## Search for a safe path from `entry` states (lane, row) at s_start to
## s_end at a steady `speed`. Returns ok, plus `boundary`: ground lanes the
## wizard can be in (running, or landing) within LEAD after `mark` (the next
## chunk's entry set). `moves` limits the move set (tests); `stay_lane`
## forbids lane changes.
static func search(items: Dictionary, s_start: float, s_end: float, entry: Array[Vector2i], speed: float, mark: float = -1.0, moves: PackedStringArray = PackedStringArray(), stay_lane: bool = false) -> Dictionary:
	var n: int = ceili((s_end - s_start) / DS)
	var field := Field.new(items, speed, s_start, n)
	var mark_slot: int = -1 if mark < 0.0 else roundi((mark - s_start) / DS)
	var lead_slots: int = ceili(LEAD / DS)
	var all_moves: bool = moves.is_empty()
	var can_run: bool = all_moves or moves.has("run")
	var can_jump: bool = all_moves or moves.has("jump")
	var can_slide: bool = all_moves or moves.has("slide")
	var can_drop: bool = all_moves or moves.has("drop")
	var can_lane: bool = not stay_lane and (all_moves or moves.has("lane"))
	var visited: Dictionary = {}
	var queue: Array[Vector3i] = []
	var boundary: Dictionary = {}
	var ok: bool = false
	for e: Vector2i in entry:
		var h0: float = MageTrack.row_y(e.y)
		var st := Vector3i(0, e.x, _hk(h0))
		if not field.blocked(e.x, 0, h0, MageTrack.BODY_HEIGHT):
			queue.append(st)
			visited[_key(st)] = true
	var lane_slots: int = maxi(1, ceili(MageTrack.LANE_TIME * speed / DS))
	var slide_slots: int = maxi(1, ceili(MageTrack.SLIDE_TIME * speed / DS))
	var head: int = 0
	var results: Array[Vector3i] = []
	while head < queue.size():
		var st: Vector3i = queue[head]
		head += 1
		var i: int = st.x
		var lane: int = st.y
		var h: float = float(st.z) * 0.005
		if i >= n:
			ok = true
			if mark_slot < 0:
				break
			continue
		if mark_slot >= 0 and h < 0.001 and i >= mark_slot and i <= mark_slot + lead_slots:
			boundary[lane] = true
		results.clear()
		if can_run:
			var nh: float = field.walk_to(lane, i + 1, h)
			if nh >= 0.0:
				if not field.blocked(lane, i + 1, nh, MageTrack.BODY_HEIGHT):
					results.append(Vector3i(i + 1, lane, _hk(nh)))
			else:
				var f: Vector3i = _air(field, i, lane, h, 0.0)
				if f.x >= 0:
					results.append(f)
		# Jumps are tried every other slot, and always just before something.
		if can_jump and (i % 2 == 0 or field.blocked(lane, i + 2, h, MageTrack.BODY_HEIGHT) or field.blocked(lane, i + 3, h, MageTrack.BODY_HEIGHT)):
			var j: Vector3i = _air(field, i, lane, h, MageTrack.JUMP_SPEED)
			if j.x >= 0:
				results.append(j)
		if can_slide and h < 0.001:
			var good: bool = true
			for m: int in range(1, slide_slots + 1):
				if i + m > n:
					break
				var sup: PackedFloat32Array = field.supports(lane, i + m)
				if sup.size() > 1 and _max(sup) > 0.001 and _max(sup) < MageTrack.ROW_HEIGHT * 0.5:
					good = false
				elif field.blocked(lane, i + m, 0.0, MageTrack.SLIDE_HEIGHT):
					good = false
				if not good:
					break
			if good:
				results.append(Vector3i(mini(i + slide_slots, n), lane, 0))
		if can_drop and h > 0.01:
			var d: Vector3i = _air(field, i, lane, h - MageTrack.DROP_NUDGE, 0.0)
			if d.x >= 0:
				results.append(d)
		if can_lane:
			for dir: int in [-1, 1]:
				var to: int = lane + dir
				if to < 0 or to >= MageTrack.LANES:
					continue
				var good: bool = true
				for m: int in range(1, lane_slots + 1):
					if i + m > n:
						break
					if field.walk_to(to, i + m, h) < 0.0 or (h > 0.001 and field.walk_to(lane, i + m, h) < 0.0):
						good = false
					elif field.blocked(to, i + m, h, MageTrack.BODY_HEIGHT) or field.blocked(lane, i + m, h, MageTrack.BODY_HEIGHT):
						good = false
					if not good:
						break
				if good:
					var e_slot: int = mini(i + lane_slots, n)
					results.append(Vector3i(e_slot, to, _hk(maxf(field.walk_to(to, e_slot, h), 0.0))))
		for r: Vector3i in results:
			var key: int = _key(r)
			if not visited.has(key):
				visited[key] = true
				queue.append(r)
	var lanes: Array[int] = []
	for l: Variant in boundary.keys():
		lanes.append(int(l))
	lanes.sort()
	return {"ok": ok, "boundary": lanes, "states": visited.size()}


## A jump (vy0 > 0) or fall (vy0 = 0) from slot i at height h: the state it
## lands in, or x = -1 if it hits something. Past the end counts as through.
static func _air(field: Field, i: int, lane: int, h: float, vy0: float) -> Vector3i:
	var dt: float = DS / field.speed
	var y: float = h
	var vy: float = vy0
	var m: int = 0
	while m < 400:
		m += 1
		if i + m > field.n:
			return Vector3i(field.n, lane, _hk(maxf(y, 0.0)))
		var prev_y: float = y
		y += vy * dt - 0.5 * MageTrack.GRAVITY * dt * dt
		vy -= MageTrack.GRAVITY * dt
		if vy <= 0.0:
			var land: float = field.landing(lane, i + m, prev_y, y)
			if land >= 0.0:
				if field.blocked(lane, i + m, land, MageTrack.BODY_HEIGHT):
					return Vector3i(-1, 0, 0)
				return Vector3i(i + m, lane, _hk(land))
		if field.blocked(lane, i + m, maxf(y, 0.0), MageTrack.BODY_HEIGHT):
			return Vector3i(-1, 0, 0)
	return Vector3i(-1, 0, 0)


static func _hk(h: float) -> int:
	return roundi(h / 0.005)


static func _key(st: Vector3i) -> int:
	return (st.x * MageTrack.LANES + st.y) * 1000 + st.z


static func _max(values: PackedFloat32Array) -> float:
	var m: float = -INF
	for v: float in values:
		m = maxf(m, v)
	return m


# --- Shape rules --------------------------------------------------------------------

## Rule violations for a chunk's items placed at s_start (length run m) at
## `speed`. Empty = fair. (The path search is separate: search().)
static func rule_errors(items: Dictionary, s_start: float, length: float, speed: float) -> PackedStringArray:
	var errors := PackedStringArray()
	var obstacles: Array[MageTrack.Obstacle] = items["obstacles"]
	var tiles: Array[MageTrack.Tile] = items["tiles"]
	var ramps: Array[MageTrack.Ramp] = items["ramps"]
	var coins: Array[MageTrack.Coin] = items["coins"]
	var s_end: float = s_start + length
	# Lead-in and sizes.
	for o: MageTrack.Obstacle in obstacles:
		if o.s0 < s_start + LEAD - 0.0001:
			errors.append("%s at %.2f is inside the lead-in" % [o.kind, o.s0 - s_start])
		if o.length > MageTrack.MAX_ITEM_LEN + 0.0001:
			errors.append("%s is %.2f m long (max %.2f)" % [o.kind, o.length, MageTrack.MAX_ITEM_LEN])
		if o.kind == &"crates" and o.length < MageTrack.CRATE_MIN_LEN - 0.0001:
			errors.append("crates shorter than %.2f m can be jumped" % MageTrack.CRATE_MIN_LEN)
		for l: int in o.lanes:
			if l < 0 or l >= MageTrack.LANES:
				errors.append("%s in lane %d" % [o.kind, l])
		if o.s1() > s_end + 0.0001:
			errors.append("%s runs past the chunk end" % o.kind)
	for t: MageTrack.Tile in tiles:
		if t.s0 < s_start + LEAD - 0.0001:
			errors.append("tile at %.2f is inside the lead-in" % (t.s0 - s_start))
		if t.row < 1 or t.row > MageTrack.TOP_ROW:
			errors.append("tile on row %d (rows are 1-%d)" % [t.row, MageTrack.TOP_ROW])
		if t.length > MageTrack.MAX_ITEM_LEN + 0.0001:
			errors.append("tile piece %.2f m long" % t.length)
	for r: MageTrack.Ramp in ramps:
		if r.s0 < s_start + LEAD - 0.0001:
			errors.append("ramp at %.2f is inside the lead-in" % (r.s0 - s_start))
		if r.row < 0 or r.row >= MageTrack.TOP_ROW:
			errors.append("ramp from row %d" % r.row)
		if r.length > MageTrack.MAX_ITEM_LEN + 0.0001:
			errors.append("ramp %.2f m long" % r.length)
		# 6. A ramp leads onto a tile one row up (and, above ground, continues a row).
		if _tile_starting(tiles, r.lane, r.row + 1, r.s1()) == null:
			errors.append("ramp in lane %d at %.2f leads onto nothing" % [r.lane, r.s0 - s_start])
		if r.row > 0 and _tile_ending(tiles, r.lane, r.row, r.s0) == null:
			errors.append("ramp on row %d in lane %d starts in the air" % [r.row, r.lane])
	# 4. Segment ends (and cracked tiles) over clear ground.
	for t: MageTrack.Tile in tiles:
		var ends: Array[float] = []
		if _tile_starting(tiles, t.lane, t.row, t.s1()) == null and _ramp_starting(ramps, t.lane, t.row, t.s1()) == null:
			ends.append(t.s1())
		if t.cracked:
			ends.append(t.s0)
		for e: float in ends:
			var clear: float = maxf(SEGMENT_CLEAR_TIME, MageTrack.fall_time(t.height())) * speed
			var lo: float = e - MageTrack.BODY_HALF_LEN
			var hi: float = (t.s1() if t.cracked else e) + clear + MageTrack.BODY_HALF_LEN
			if hi > s_end + 0.0001:
				errors.append("row %d segment in lane %d ends %.2f m before the chunk end (needs %.2f)" % [t.row, t.lane, s_end - e, hi - e])
			for o: MageTrack.Obstacle in obstacles:
				if o.has_lane(t.lane) and o.s1() > lo and o.s0 < hi and not _row_below_covers(tiles, t, o):
					errors.append("%s under the end of a row %d segment (lane %d)" % [o.kind, t.row, t.lane])
	# 5. Cracked tiles have an intact neighbour.
	for t: MageTrack.Tile in tiles:
		if not t.cracked:
			continue
		var safe: bool = false
		for other: MageTrack.Tile in tiles:
			if other.row == t.row and not other.cracked and absi(other.lane - t.lane) == 1 and other.s0 <= t.s0 + 0.0001 and other.s1() >= t.s1() - 0.0001:
				safe = true
		if not safe:
			errors.append("cracked tile in lane %d has no intact tile one lane over" % t.lane)
	# Nothing pokes up through a row; beams never stand under one.
	for o: MageTrack.Obstacle in obstacles:
		for t: MageTrack.Tile in tiles:
			if not o.has_lane(t.lane) or o.s1() < t.s0 - 0.1 or o.s0 > t.s1() + 0.1:
				continue
			if o.kind == &"beam":
				errors.append("beam under a row %d tile (lane %d)" % [t.row, t.lane])
			elif o.s1() > t.s0 and o.s0 < t.s1() and o.top >= t.height() - MageTrack.TILE_THICKNESS:
				errors.append("%s pokes through a row %d tile" % [o.kind, t.row])
	# Rolling carts: nothing in their lane that they would roll through.
	for o: MageTrack.Obstacle in obstacles:
		if not o.moving:
			continue
		var b: Vector2 = MageTrack.cart_block(o.s0, o.length, speed)
		var lo: float = b.x - MageTrack.BEHIND
		for other: MageTrack.Obstacle in obstacles:
			if other != o and other.lanes.has(o.lanes[0]) and other.s1() > lo and other.s0 < o.s1():
				errors.append("cart in lane %d would roll through a %s" % [o.lanes[0], other.kind])
		for c: MageTrack.Coin in coins:
			if c.lane == o.lanes[0] and c.s > lo and c.s < o.s1():
				errors.append("cart in lane %d rolls over coins" % o.lanes[0])
				break
	# 6. Coins: never inside an obstacle, always within jump reach of a surface.
	for c: MageTrack.Coin in coins:
		for o: MageTrack.Obstacle in obstacles:
			if o.moving or not o.has_lane(c.lane):
				continue
			if c.s > o.s0 - MageTrack.COIN_RADIUS and c.s < o.s1() + MageTrack.COIN_RADIUS and c.y > o.base - MageTrack.COIN_RADIUS and c.y < o.top + MageTrack.COIN_RADIUS and not (o.roof > 0.0 and c.y >= o.roof):
				errors.append("coin at %.2f inside a %s" % [c.s - s_start, o.kind])
		var surface: Vector2 = MageChunks.surface_at(items, c.lane, c.s)
		var reach: bool = false
		# A coin is in reach from any surface within half a jump of it.
		var surfaces := PackedFloat32Array()
		for off: float in [-0.35, -0.25, -0.15, -0.05, 0.0, 0.05, 0.15, 0.25, 0.35]:
			surfaces.append_array(_all_surfaces(items, c.lane, c.s + off))
		for sh: float in surfaces:
			if c.y >= sh - 0.005 and c.y <= sh + MageTrack.JUMP_APEX + MageTrack.BODY_HEIGHT:
				reach = true
		if not reach:
			errors.append("coin at %.2f (lane %d, %.3f m) is out of reach (surface %.3f)" % [c.s - s_start, c.lane, c.y, surface.x])
	# 3. Forced inputs: walls across all lanes, at most two within 0.35 s.
	var walls: Array[float] = []
	for o: MageTrack.Obstacle in obstacles:
		if o.moving:
			continue
		var covered: Dictionary = {}
		for other: MageTrack.Obstacle in obstacles:
			if not other.moving and absf(other.s0 - o.s0) < 0.15:
				for l: int in other.lanes:
					covered[l] = true
		if covered.size() == MageTrack.LANES:
			var dup: bool = false
			for w: float in walls:
				dup = dup or absf(w - o.s0) < 0.15
			if not dup:
				walls.append(o.s0)
	walls.sort()
	for k: int in range(2, walls.size()):
		if walls[k] - walls[k - 2] < FORCED_WINDOW * speed:
			errors.append("three forced inputs within %.2f s" % FORCED_WINDOW)
	return errors


static func _all_surfaces(items: Dictionary, lane: int, s: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for t: MageTrack.Tile in items["tiles"] as Array[MageTrack.Tile]:
		if t.lane == lane and t.covers(s):
			out.append(t.height())
	for r: MageTrack.Ramp in items["ramps"] as Array[MageTrack.Ramp]:
		if r.lane == lane and r.covers(s):
			out.append(r.height_at(s))
	for o: MageTrack.Obstacle in items["obstacles"] as Array[MageTrack.Obstacle]:
		if o.roof > 0.0 and o.has_lane(lane) and s >= o.s0 and s <= o.s1():
			out.append(o.roof)
	return out


static func _tile_starting(tiles: Array[MageTrack.Tile], lane: int, row: int, s: float) -> MageTrack.Tile:
	for t: MageTrack.Tile in tiles:
		if t.lane == lane and t.row == row and absf(t.s0 - s) <= 0.03:
			return t
	return null


static func _tile_ending(tiles: Array[MageTrack.Tile], lane: int, row: int, s: float) -> MageTrack.Tile:
	for t: MageTrack.Tile in tiles:
		if t.lane == lane and t.row == row and absf(t.s1() - s) <= 0.03:
			return t
	return null


static func _ramp_starting(ramps: Array[MageTrack.Ramp], lane: int, row: int, s: float) -> MageTrack.Ramp:
	for r: MageTrack.Ramp in ramps:
		if r.lane == lane and r.row == row and absf(r.s0 - s) <= 0.03:
			return r
	return null


## A row-2 segment end over a row-1 tile lands on that tile, not the ground.
static func _row_below_covers(tiles: Array[MageTrack.Tile], above: MageTrack.Tile, o: MageTrack.Obstacle) -> bool:
	for t: MageTrack.Tile in tiles:
		if t.lane == above.lane and t.row < above.row and not t.cracked and t.s0 <= maxf(o.s0, above.s1()) and t.s1() >= o.s1():
			return true
	return false


## Template-level check: every rule at the slowest and fastest speed, both
## mirrors, and a path from each entry lane. Empty = the template is fair.
static func template_errors(template: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var length: float = float(template["length"])
	for mirror: bool in [false, true]:
		for speed: float in [MageTrack.BASE_SPEED, MageTrack.MAX_SPEED]:
			var items: Dictionary = MageChunks.instantiate(template, 10.0, mirror, [0])
			for e: String in rule_errors(items, 10.0, length, speed):
				errors.append("%s%s @%.1f: %s" % [template["name"], " (mirrored)" if mirror else "", speed, e])
			for lane: int in MageTrack.LANES:
				var entry: Array[Vector2i] = [Vector2i(lane, 0)]
				var r: Dictionary = search(items, 10.0, 10.0 + length, entry, speed)
				if not bool(r["ok"]):
					errors.append("%s%s @%.1f: no safe path from lane %d" % [template["name"], " (mirrored)" if mirror else "", speed, lane])
	return errors
