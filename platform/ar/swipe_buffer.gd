class_name SwipeBuffer
extends RefCounted
## Input buffering for swipe games: a swipe that arrives while the action
## cannot start (mid-jump, mid-lane-change) waits up to `window` seconds and
## fires as soon as the game can act. Newer swipes replace older ones (the
## player's latest intent wins). Times are game seconds.

const DEFAULT_WINDOW: float = 0.15

var window: float = DEFAULT_WINDOW
var _direction: Vector2i = Vector2i.ZERO
var _time: float = -INF


func push(direction: Vector2i, now: float) -> void:
	_direction = direction
	_time = now


func has_pending(now: float) -> bool:
	return _direction != Vector2i.ZERO and now - _time <= window


## The buffered swipe if one is still fresh (consumed), else ZERO.
func take(now: float) -> Vector2i:
	if not has_pending(now):
		_direction = Vector2i.ZERO
		return Vector2i.ZERO
	var out: Vector2i = _direction
	_direction = Vector2i.ZERO
	return out


func clear() -> void:
	_direction = Vector2i.ZERO
