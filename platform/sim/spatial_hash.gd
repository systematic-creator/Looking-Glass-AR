class_name SpatialHash2D
extends RefCounted
## Uniform-grid spatial hash for range queries on 2D points (cell coordinates
## or metres). Rebuild it once per tick (clear + insert), then query circles.

var bucket_size: float = 1.0
var _buckets: Dictionary = {}
var _pos: Dictionary = {}


func _init(p_bucket_size: float = 1.0) -> void:
	bucket_size = maxf(0.0001, p_bucket_size)


func clear() -> void:
	_buckets.clear()
	_pos.clear()


func _key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / bucket_size), floori(p.y / bucket_size))


func insert(id: int, p: Vector2) -> void:
	var k: Vector2i = _key(p)
	if not _buckets.has(k):
		_buckets[k] = PackedInt32Array()
	var arr: PackedInt32Array = _buckets[k]
	arr.append(id)
	_buckets[k] = arr
	_pos[id] = p


## Ids within `radius` of `center` (unsorted).
func query(center: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo: Vector2i = _key(center - Vector2(radius, radius))
	var hi: Vector2i = _key(center + Vector2(radius, radius))
	var r2: float = radius * radius
	for bx: int in range(lo.x, hi.x + 1):
		for by: int in range(lo.y, hi.y + 1):
			var arr: Variant = _buckets.get(Vector2i(bx, by))
			if arr == null:
				continue
			for id: int in arr as PackedInt32Array:
				if (_pos[id] as Vector2).distance_squared_to(center) <= r2:
					out.append(id)
	return out


func position_of(id: int) -> Vector2:
	return _pos.get(id, Vector2.INF)
