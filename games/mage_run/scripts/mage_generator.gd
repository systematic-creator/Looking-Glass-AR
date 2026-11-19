class_name MageGenerator
extends RefCounted
## Seeded procedural track: picks the next chunk template for the distance
## (the arcane rows and harder mixes unlock at MageTrack's thresholds),
## mirrors it at random, and only accepts it if MageValidator finds it fair
## AND a safe path runs from the previous chunk's entry lanes through the
## join into it. Otherwise it tries another (and falls back to a breather).
## Same seed, same track.

const TRIES: int = 10

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
## End of the generated track (run m).
var end_s: float = 0.0
var chunks: Array[Dictionary] = []
var rejected: int = 0
var _next_id: Array = [1]
## The previous chunk: {template, s0, length, items, entry}.
var _prev: Dictionary = {}


func _init(p_seed: int = 0, start_s: float = 0.0) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	end_s = start_s


## Templates allowed at `distance`, with weights (row templates get more
## common past their unlock).
static func candidates(distance: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in MageChunks.TEMPLATES:
		var min_d: float = float(t["min_d"])
		if min_d > distance:
			continue
		var w: float = float(t["weight"])
		if min_d >= MageTrack.ROW1_AT:
			w *= 1.0 + clampf((distance - min_d) / 300.0, 0.0, 1.5)
		elif distance > MageTrack.ROW2_AT and min_d < 30.0:
			w *= 0.6
		out.append({"template": t, "weight": w})
	return out


## Generate the next chunk; appends its items to `track` (a MageChunks item
## container). Returns the chunk record.
func next_chunk(track: Dictionary) -> Dictionary:
	var chosen: Dictionary = make_chunk()
	MageChunks.merge(track, chosen["items"] as Dictionary)
	return chosen


## Generate the next chunk without touching any shared track (safe on a
## worker thread; merge its "items" afterwards).
func make_chunk() -> Dictionary:
	var distance: float = end_s
	var speed: float = MageTrack.speed_at(distance)
	var pool: Array[Dictionary] = candidates(distance)
	var last_name: String = "" if chunks.is_empty() else String((chunks.back() as Dictionary)["name"])
	var chosen: Dictionary = {}
	for attempt: int in TRIES:
		var t: Dictionary = _pick(pool)
		if String(t["name"]) == last_name and attempt < TRIES - 1:
			continue
		var mirror: bool = rng.randf() < 0.5
		var record: Dictionary = _try(t, mirror, speed)
		if not record.is_empty():
			chosen = record
			break
		rejected += 1
	if chosen.is_empty():
		chosen = _try(MageChunks.by_name("breather"), false, speed)
		if chosen.is_empty():
			# Even the breather failed (should not happen): accept it from every lane.
			_prev = {}
			chosen = _try(MageChunks.by_name("breather"), false, speed)
	end_s += float(chosen["length"])
	_prev = chosen
	chunks.append(chosen)
	return chosen


func _pick(pool: Array[Dictionary]) -> Dictionary:
	var total: float = 0.0
	for c: Dictionary in pool:
		total += float(c["weight"])
	var r: float = rng.randf() * total
	for c: Dictionary in pool:
		r -= float(c["weight"])
		if r <= 0.0:
			return c["template"] as Dictionary
	return (pool.back() as Dictionary)["template"] as Dictionary


func _try(t: Dictionary, mirror: bool, speed: float) -> Dictionary:
	var length: float = float(t["length"])
	var ids: Array = [int(_next_id[0])]
	var items: Dictionary = MageChunks.instantiate(t, end_s, mirror, ids)
	if not MageValidator.rule_errors(items, end_s, length, speed).is_empty():
		return {}
	var entry: Array[Vector2i] = []
	var from_s: float = end_s
	var field: Dictionary = items
	if _prev.is_empty():
		entry = [Vector2i(1, 0)]
	else:
		entry = _prev["entry"]
		from_s = float(_prev["s0"])
		field = MageChunks.empty_items()
		MageChunks.merge(field, _prev["items"] as Dictionary)
		MageChunks.merge(field, items)
		# A cart in the new chunk must not roll through the previous one.
		for e: String in MageValidator.rule_errors(field, from_s, end_s + length - from_s, speed):
			if e.begins_with("cart"):
				return {}
	var r: Dictionary = MageValidator.search(field, from_s, end_s + length, entry, speed, end_s)
	if not bool(r["ok"]):
		return {}
	var next_entry: Array[Vector2i] = []
	if _prev.is_empty():
		var own: Dictionary = MageValidator.search(items, end_s, end_s + length, entry, speed, end_s)
		for l: int in own["boundary"] as Array[int]:
			next_entry.append(Vector2i(l, 0))
	else:
		for l: int in r["boundary"] as Array[int]:
			next_entry.append(Vector2i(l, 0))
	if next_entry.is_empty():
		return {}
	_next_id[0] = int(ids[0])
	return {"name": String(t["name"]), "s0": end_s, "length": length, "mirror": mirror, "items": items, "entry": next_entry, "speed": speed}
