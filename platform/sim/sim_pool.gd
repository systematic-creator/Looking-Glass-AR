class_name SimPool
extends RefCounted
## Fixed-capacity slot pool for simulation entities stored in plain arrays
## (no per-entity nodes). acquire() hands out a free slot index (or -1 when
## full), release() returns it. Iterate live slots with `live` (kept in
## acquisition order; removal is O(n) but n is small, e.g. 60 enemies).
## Pair it with a MultiMesh of the same capacity to draw the entities.

var capacity: int = 0
var alive: PackedByteArray = PackedByteArray()
var live: PackedInt32Array = PackedInt32Array()
var _free: PackedInt32Array = PackedInt32Array()
var peak: int = 0


func _init(p_capacity: int = 64) -> void:
	capacity = maxi(0, p_capacity)
	alive.resize(capacity)
	clear()


func clear() -> void:
	alive.fill(0)
	live.clear()
	_free.clear()
	for i: int in range(capacity - 1, -1, -1):
		_free.append(i)


func acquire() -> int:
	if _free.is_empty():
		return -1
	var i: int = _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	alive[i] = 1
	live.append(i)
	peak = maxi(peak, live.size())
	return i


func release(i: int) -> void:
	if i < 0 or i >= capacity or alive[i] == 0:
		return
	alive[i] = 0
	var k: int = live.find(i)
	if k >= 0:
		live.remove_at(k)
	_free.append(i)


func count() -> int:
	return live.size()


func is_full() -> bool:
	return _free.is_empty()


func is_alive(i: int) -> bool:
	return i >= 0 and i < capacity and alive[i] != 0
