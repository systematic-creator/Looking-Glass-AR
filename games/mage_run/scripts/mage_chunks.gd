class_name MageChunks
extends RefCounted
## Hand-authored chunk templates (data, not scenes) and turning one into
## track items. A template: name, min_d (run metres before it can appear),
## weight, length (run m) and items with s offsets from the chunk start:
##   fence / beam      lane, s
##   crates            lane (or lanes), s, len
##   cart              lane, s                (rolls toward the wizard)
##   carriage          lane (left of its 2 lanes), s
##   tiles             lane, row (1-2), s, len, cracked   (arcane-row platforms)
##   ramp              lane, row (from), s, len           (up to row + 1)
##   coins             shape, lane, row, s, n, step (+ lanes for "weave")
##     line     flat, row height
##     jump     an arc over an obstacle (jump apex)
##     surface  on whatever is under it: ramps, tiles, a carriage roof
##     weave    a line across lanes (lanes[i] per coin)
## Every template is checked by MageValidator (tests run all of them).

const TEMPLATES: Array[Dictionary] = [
	{"name": "breather", "min_d": 0.0, "weight": 0.25, "length": 1.2, "items": [
		{"k": "coins", "shape": "line", "lane": 1, "row": 0, "s": 0.3, "n": 5, "step": 0.18},
	]},
	{"name": "fences_side", "min_d": 0.0, "weight": 1.0, "length": 1.6, "items": [
		{"k": "fence", "lane": 0, "s": 0.7}, {"k": "fence", "lane": 2, "s": 0.7},
		{"k": "coins", "shape": "line", "lane": 1, "row": 0, "s": 0.4, "n": 6, "step": 0.18},
	]},
	{"name": "fence_wall", "min_d": 0.0, "weight": 1.0, "length": 1.8, "items": [
		{"k": "fence", "lane": 0, "s": 0.9}, {"k": "fence", "lane": 1, "s": 0.9}, {"k": "fence", "lane": 2, "s": 0.9},
		{"k": "coins", "shape": "jump", "lane": 1, "row": 0, "s": 0.6, "n": 7, "step": 0.12},
	]},
	{"name": "beam_mid", "min_d": 0.0, "weight": 1.0, "length": 1.8, "items": [
		{"k": "beam", "lane": 1, "s": 0.8}, {"k": "crates", "lane": 0, "s": 0.6, "len": 0.6},
		{"k": "coins", "shape": "line", "lane": 2, "row": 0, "s": 0.4, "n": 6, "step": 0.18},
	]},
	{"name": "crate_weave", "min_d": 0.0, "weight": 1.0, "length": 2.4, "items": [
		{"k": "crates", "lane": 0, "s": 0.5, "len": 0.6}, {"k": "crates", "lane": 2, "s": 1.5, "len": 0.6},
		{"k": "coins", "shape": "weave", "s": 0.4, "n": 10, "step": 0.2, "row": 0, "lanes": [1, 1, 1, 1, 0, 0, 0, 0, 0, 1]},
	]},
	{"name": "beam_wall", "min_d": 30.0, "weight": 0.9, "length": 1.6, "items": [
		{"k": "beam", "lane": 0, "s": 0.8}, {"k": "beam", "lane": 1, "s": 0.8}, {"k": "beam", "lane": 2, "s": 0.8},
		{"k": "coins", "shape": "line", "lane": 1, "row": 0, "s": 0.5, "n": 5, "step": 0.1},
	]},
	{"name": "carriage_roof", "min_d": 40.0, "weight": 0.9, "length": 2.2, "items": [
		{"k": "carriage", "lane": 0, "s": 0.6},
		{"k": "coins", "shape": "surface", "lane": 0, "row": 0, "s": 0.68, "n": 4, "step": 0.14},
		{"k": "fence", "lane": 2, "s": 1.0},
		{"k": "coins", "shape": "line", "lane": 2, "row": 0, "s": 1.3, "n": 4, "step": 0.2},
	]},
	{"name": "cart_lane", "min_d": 60.0, "weight": 0.9, "length": 2.2, "items": [
		{"k": "cart", "lane": 1, "s": 1.2}, {"k": "crates", "lane": 0, "s": 0.5, "len": 0.6},
		{"k": "coins", "shape": "line", "lane": 2, "row": 0, "s": 0.4, "n": 7, "step": 0.2},
	]},
	{"name": "three_way", "min_d": 100.0, "weight": 1.0, "length": 1.8, "items": [
		{"k": "fence", "lane": 0, "s": 0.8}, {"k": "beam", "lane": 1, "s": 0.8}, {"k": "crates", "lane": 2, "s": 0.6, "len": 0.6},
		{"k": "coins", "shape": "jump", "lane": 0, "row": 0, "s": 0.5, "n": 7, "step": 0.12},
	]},
	{"name": "double_fence", "min_d": 200.0, "weight": 0.8, "length": 2.4, "items": [
		{"k": "fence", "lane": 0, "s": 0.6}, {"k": "fence", "lane": 1, "s": 0.6}, {"k": "fence", "lane": 2, "s": 0.6},
		{"k": "fence", "lane": 0, "s": 1.8}, {"k": "fence", "lane": 1, "s": 1.8}, {"k": "fence", "lane": 2, "s": 1.8},
		{"k": "coins", "shape": "jump", "lane": 1, "row": 0, "s": 1.5, "n": 7, "step": 0.12},
	]},
	{"name": "cart_pair", "min_d": 300.0, "weight": 0.8, "length": 2.4, "items": [
		{"k": "cart", "lane": 0, "s": 1.0}, {"k": "cart", "lane": 2, "s": 1.3},
		{"k": "coins", "shape": "line", "lane": 1, "row": 0, "s": 0.4, "n": 8, "step": 0.2},
	]},
	# --- Arcane row 1 (from 150 m): short segments ----------------------------------
	{"name": "ramp_up", "min_d": 150.0, "weight": 1.2, "length": 3.0, "items": [
		{"k": "ramp", "lane": 1, "row": 0, "s": 0.4, "len": 0.6},
		{"k": "tiles", "lane": 1, "row": 1, "s": 1.0, "len": 1.2},
		{"k": "crates", "lane": 1, "s": 1.3, "len": 0.6},
		{"k": "fence", "lane": 0, "s": 1.5},
		{"k": "coins", "shape": "surface", "lane": 1, "row": 0, "s": 0.45, "n": 9, "step": 0.2},
	]},
	{"name": "jump_to_row", "min_d": 150.0, "weight": 1.0, "length": 3.0, "items": [
		{"k": "tiles", "lane": 0, "row": 1, "s": 0.8, "len": 1.2},
		{"k": "fence", "lane": 0, "s": 0.7},
		{"k": "crates", "lane": 1, "s": 1.0, "len": 0.6},
		{"k": "coins", "shape": "surface", "lane": 0, "row": 1, "s": 1.0, "n": 5, "step": 0.2},
	]},
	{"name": "side_row", "min_d": 150.0, "weight": 1.0, "length": 3.0, "items": [
		{"k": "ramp", "lane": 2, "row": 0, "s": 0.35, "len": 0.6},
		{"k": "tiles", "lane": 2, "row": 1, "s": 0.95, "len": 1.2},
		{"k": "crates", "lane": 0, "s": 0.9, "len": 0.6},
		{"k": "beam", "lane": 1, "s": 1.4},
		{"k": "coins", "shape": "surface", "lane": 2, "row": 0, "s": 0.4, "n": 8, "step": 0.2},
	]},
	# --- Row 1 long runs and row 2 (from 400 m) -------------------------------------
	{"name": "high_road", "min_d": 400.0, "weight": 1.2, "length": 3.8, "items": [
		{"k": "ramp", "lane": 1, "row": 0, "s": 0.35, "len": 0.6},
		{"k": "tiles", "lane": 1, "row": 1, "s": 0.95, "len": 0.6},
		{"k": "ramp", "lane": 1, "row": 1, "s": 1.55, "len": 0.6},
		{"k": "tiles", "lane": 1, "row": 2, "s": 2.15, "len": 0.6},
		{"k": "crates", "lane": 1, "s": 1.2, "len": 0.6},
		{"k": "fence", "lane": 0, "s": 2.0}, {"k": "fence", "lane": 2, "s": 2.0},
		{"k": "coins", "shape": "surface", "lane": 1, "row": 0, "s": 0.4, "n": 12, "step": 0.2},
	]},
	{"name": "twin_rows", "min_d": 400.0, "weight": 1.0, "length": 3.3, "items": [
		{"k": "tiles", "lane": 0, "row": 1, "s": 0.7, "len": 1.8},
		{"k": "tiles", "lane": 2, "row": 1, "s": 0.7, "len": 1.8},
		{"k": "crates", "lane": 0, "s": 1.0, "len": 0.6}, {"k": "crates", "lane": 2, "s": 1.0, "len": 0.6},
		{"k": "beam", "lane": 1, "s": 1.6},
		{"k": "coins", "shape": "surface", "lane": 0, "row": 1, "s": 0.9, "n": 6, "step": 0.25},
		{"k": "coins", "shape": "surface", "lane": 2, "row": 1, "s": 0.9, "n": 6, "step": 0.25},
	]},
	{"name": "row2_climb", "min_d": 400.0, "weight": 1.0, "length": 3.6, "items": [
		{"k": "tiles", "lane": 1, "row": 1, "s": 0.6, "len": 1.8},
		{"k": "tiles", "lane": 1, "row": 2, "s": 1.3, "len": 1.2},
		{"k": "fence", "lane": 1, "s": 0.9},
		{"k": "crates", "lane": 0, "s": 0.9, "len": 0.6}, {"k": "crates", "lane": 2, "s": 1.6, "len": 0.6},
		{"k": "coins", "shape": "surface", "lane": 1, "row": 2, "s": 1.5, "n": 5, "step": 0.2},
	]},
	# --- Collapsing tiles and rune gaps (from 800 m) --------------------------------
	{"name": "cracked_path", "min_d": 800.0, "weight": 1.0, "length": 3.2, "items": [
		{"k": "ramp", "lane": 1, "row": 0, "s": 0.3, "len": 0.3},
		{"k": "tiles", "lane": 1, "row": 1, "s": 0.6, "len": 0.6},
		{"k": "tiles", "lane": 1, "row": 1, "s": 1.2, "len": 0.6, "cracked": true},
		{"k": "tiles", "lane": 1, "row": 1, "s": 1.8, "len": 0.6},
		{"k": "tiles", "lane": 0, "row": 1, "s": 0.6, "len": 1.8},
		{"k": "crates", "lane": 2, "s": 1.0, "len": 0.6},
		{"k": "coins", "shape": "surface", "lane": 1, "row": 1, "s": 1.25, "n": 3, "step": 0.2},
		{"k": "coins", "shape": "surface", "lane": 0, "row": 1, "s": 0.8, "n": 4, "step": 0.3},
	]},
	{"name": "rune_gaps", "min_d": 800.0, "weight": 1.0, "length": 3.5, "items": [
		{"k": "tiles", "lane": 1, "row": 1, "s": 0.6, "len": 0.6},
		{"k": "tiles", "lane": 1, "row": 1, "s": 1.5, "len": 0.6},
		{"k": "tiles", "lane": 1, "row": 1, "s": 2.4, "len": 0.3},
		{"k": "crates", "lane": 0, "s": 0.8, "len": 0.6},
		{"k": "fence", "lane": 2, "s": 1.6},
		{"k": "coins", "shape": "jump", "lane": 1, "row": 1, "s": 1.05, "n": 6, "step": 0.1},
	]},
]


static func by_name(template_name: String) -> Dictionary:
	for t: Dictionary in TEMPLATES:
		if String(t["name"]) == template_name:
			return t
	return {}


## Empty track container.
static func empty_items() -> Dictionary:
	var obstacles: Array[MageTrack.Obstacle] = []
	var tiles: Array[MageTrack.Tile] = []
	var ramps: Array[MageTrack.Ramp] = []
	var coins: Array[MageTrack.Coin] = []
	return {"obstacles": obstacles, "tiles": tiles, "ramps": ramps, "coins": coins}


## A template's items placed at track position `at`, mirrored left / right if
## asked. `next_id` is an Array with one int, advanced per item.
static func instantiate(template: Dictionary, at: float, mirror: bool, next_id: Array) -> Dictionary:
	var out: Dictionary = empty_items()
	var obstacles: Array[MageTrack.Obstacle] = out["obstacles"]
	var tiles: Array[MageTrack.Tile] = out["tiles"]
	var ramps: Array[MageTrack.Ramp] = out["ramps"]
	var coins: Array[MageTrack.Coin] = out["coins"]
	var items: Array = template["items"]
	# Platforms first: "surface" coins sit on them.
	for item: Dictionary in items:
		var k: String = String(item["k"])
		if k == "tiles":
			var length: float = float(item["len"])
			var pieces: int = maxi(1, roundi(length / MageTrack.TILE_PIECE_LEN))
			for p: int in pieces:
				var tile := MageTrack.Tile.new()
				tile.id = _id(next_id)
				tile.lane = _lane(int(item["lane"]), mirror)
				tile.row = int(item["row"])
				tile.length = length / float(pieces)
				tile.s0 = at + float(item["s"]) + tile.length * float(p)
				tile.cracked = bool(item.get("cracked", false))
				tiles.append(tile)
		elif k == "ramp":
			var ramp := MageTrack.Ramp.new()
			ramp.id = _id(next_id)
			ramp.lane = _lane(int(item["lane"]), mirror)
			ramp.row = int(item["row"])
			ramp.s0 = at + float(item["s"])
			ramp.length = float(item["len"])
			ramps.append(ramp)
	for item: Dictionary in items:
		var k: String = String(item["k"])
		match k:
			"fence", "beam", "crates", "cart", "carriage":
				obstacles.append(_obstacle(item, at, mirror, next_id))
			"coins":
				_coins(item, at, mirror, next_id, out)
	return out


static func _id(next_id: Array) -> int:
	var id: int = int(next_id[0])
	next_id[0] = id + 1
	return id


static func _lane(lane: int, mirror: bool) -> int:
	return MageTrack.LANES - 1 - lane if mirror else lane


static func _obstacle(item: Dictionary, at: float, mirror: bool, next_id: Array) -> MageTrack.Obstacle:
	var o := MageTrack.Obstacle.new()
	o.id = _id(next_id)
	o.kind = StringName(String(item["k"]))
	o.s0 = at + float(item["s"])
	var lanes := PackedInt32Array()
	if item.has("lanes"):
		for l: Variant in item["lanes"] as Array:
			lanes.append(_lane(int(l), mirror))
	else:
		lanes.append(_lane(int(item["lane"]), mirror))
	match o.kind:
		&"fence":
			o.length = MageTrack.FENCE_LEN
			o.top = MageTrack.FENCE_TOP
		&"beam":
			o.length = MageTrack.BEAM_LEN
			o.base = MageTrack.BEAM_BASE
			o.top = MageTrack.BEAM_TOP
		&"crates":
			o.length = float(item.get("len", MageTrack.CRATE_MIN_LEN))
			o.top = MageTrack.CRATE_TOP
		&"cart":
			o.length = MageTrack.CART_LEN
			o.top = MageTrack.CART_TOP
			o.moving = true
		&"carriage":
			o.length = MageTrack.CARRIAGE_LEN
			o.top = MageTrack.CARRIAGE_ROOF
			o.roof = MageTrack.CARRIAGE_ROOF
			var left: int = int(item["lane"])
			lanes = PackedInt32Array([_lane(left, mirror), _lane(left + 1, mirror)])
			lanes.sort()
	o.lanes = lanes
	return o


static func _coins(item: Dictionary, at: float, mirror: bool, next_id: Array, out: Dictionary) -> void:
	var coins: Array[MageTrack.Coin] = out["coins"]
	var n: int = int(item["n"])
	var step: float = float(item["step"])
	var shape: String = String(item["shape"])
	var row: int = int(item.get("row", 0))
	for i: int in n:
		var coin := MageTrack.Coin.new()
		coin.id = _id(next_id)
		coin.s = at + float(item["s"]) + step * float(i)
		coin.row = row
		if shape == "weave":
			coin.lane = _lane(int((item["lanes"] as Array)[i]), mirror)
		else:
			coin.lane = _lane(int(item["lane"]), mirror)
		match shape:
			"jump":
				var p: float = float(i) / float(maxi(n - 1, 1))
				coin.y = MageTrack.row_y(row) + MageTrack.COIN_LIFT + MageTrack.JUMP_APEX * 0.85 * 4.0 * p * (1.0 - p)
			"surface":
				var surface: Vector2 = surface_at(out, coin.lane, coin.s)
				coin.y = surface.x + MageTrack.COIN_LIFT
				coin.row = int(surface.y)
			_:
				coin.y = MageTrack.row_y(row) + MageTrack.COIN_LIFT
		coins.append(coin)


## Highest walkable surface in `lane` at `s` among `items`: (height, row of
## its multiplier). Ground, tiles, ramps (their lower row) and carriage roofs.
static func surface_at(items: Dictionary, lane: int, s: float) -> Vector2:
	var best := Vector2(0.0, 0.0)
	for tile: MageTrack.Tile in items["tiles"] as Array[MageTrack.Tile]:
		if tile.lane == lane and tile.covers(s) and tile.height() > best.x:
			best = Vector2(tile.height(), tile.row)
	for ramp: MageTrack.Ramp in items["ramps"] as Array[MageTrack.Ramp]:
		if ramp.lane == lane and ramp.covers(s) and ramp.height_at(s) > best.x:
			best = Vector2(ramp.height_at(s), ramp.row)
	for o: MageTrack.Obstacle in items["obstacles"] as Array[MageTrack.Obstacle]:
		if o.roof > 0.0 and o.has_lane(lane) and s >= o.s0 and s <= o.s1() and o.roof > best.x:
			best = Vector2(o.roof, 0)
	return best


## Appends every item of `more` to `into`.
static func merge(into: Dictionary, more: Dictionary) -> void:
	for key: String in ["obstacles", "tiles", "ramps", "coins"]:
		(into[key] as Array).append_array(more[key] as Array)
