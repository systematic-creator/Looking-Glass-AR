class_name SwipeDetector
extends RefCounted
## Screen-space swipes for runners (pure input maths, unit-tested headless).
## Runs beside GestureTracker; GameHost feeds it touches while the game
## captures_swipes().
##
## A swipe is a ONE-finger stroke that moves at least `threshold_px` along a
## dominant axis (>= DOMINANCE x the other axis) within `max_time` of
## touch-down. It fires the moment it crosses the threshold (not on lift),
## once per stroke, except that reversing by another full threshold fires
## the opposite direction ("S" stroke: quick left-right corrections).
## Strokes slower than max_time are drags, never swipes. A second finger
## cancels the stroke (pinch stays reserved) until every finger is up.
##
## handle(event, now) returns {} or
##   {"direction": Vector2i (LEFT / RIGHT / UP / DOWN, screen as held),
##    "velocity": Vector2 px/s, "time": s, "from": Vector2, "to": Vector2,
##    "distance": px, "index": int (0 = first swipe of the stroke)}

## Minimum stroke, inches (about 45 px at 160 dpi, 118 px at 420 dpi).
const SWIPE_MIN_INCHES: float = 0.28
const SWIPE_MAX_TIME: float = 0.25
## The dominant axis must be this many times the other one.
const DOMINANCE: float = 1.4
## Threshold bounds in viewport pixels.
const MIN_THRESHOLD_PX: float = 32.0
const MAX_THRESHOLD_PX: float = 220.0
const DEFAULT_THRESHOLD_PX: float = 48.0

var threshold_px: float = DEFAULT_THRESHOLD_PX
var max_time: float = SWIPE_MAX_TIME

var _fingers: Dictionary = {}
var _index: int = -1
var _active: bool = false
## Where the current leg of the stroke started (touch-down, or the turn).
var _anchor: Vector2 = Vector2.ZERO
var _anchor_time: float = 0.0
var _last: Vector2 = Vector2.ZERO
var _fired: Vector2i = Vector2i.ZERO
var _count: int = 0


## Swipe threshold in viewport pixels for a screen: SWIPE_MIN_INCHES of
## finger travel (dpi), scaled from window pixels to the content-scaled
## viewport (the same conversion GameHost uses for its tap slop).
static func threshold_for(dpi: float, window_height: float, view_height: float) -> float:
	if dpi <= 0.0 or window_height <= 0.0 or view_height <= 0.0:
		return DEFAULT_THRESHOLD_PX
	return clampf(dpi * SWIPE_MIN_INCHES * view_height / window_height, MIN_THRESHOLD_PX, MAX_THRESHOLD_PX)


## The dominant direction of a displacement, or ZERO if neither axis
## dominates by DOMINANCE.
static func dominant_direction(d: Vector2) -> Vector2i:
	var ax: float = absf(d.x)
	var ay: float = absf(d.y)
	if ax >= ay * DOMINANCE and ax > 0.0:
		return Vector2i.RIGHT if d.x > 0.0 else Vector2i.LEFT
	if ay >= ax * DOMINANCE and ay > 0.0:
		return Vector2i.DOWN if d.y > 0.0 else Vector2i.UP
	return Vector2i.ZERO


func reset() -> void:
	_fingers.clear()
	_index = -1
	_active = false
	_fired = Vector2i.ZERO
	_count = 0


func is_tracking() -> bool:
	return _active


func handle(event: InputEvent, now: float) -> Dictionary:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if touch.index == 0:
				# Nothing else can be down: forget releases we never saw.
				_fingers.clear()
			_fingers[touch.index] = true
			if _fingers.size() == 1:
				_index = touch.index
				_active = true
				_anchor = touch.position
				_last = touch.position
				_anchor_time = now
				_fired = Vector2i.ZERO
				_count = 0
			else:
				_active = false
			return {}
		_fingers.erase(touch.index)
		if touch.index == _index or _fingers.is_empty():
			_active = false
			_index = -1
		return {}
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if not _active or drag.index != _index or _fingers.size() != 1:
			return {}
		return _on_move(drag.position, now)
	return {}


func _on_move(position: Vector2, now: float) -> Dictionary:
	_last = position
	if _fired == Vector2i.ZERO:
		if now - _anchor_time > max_time:
			# Too slow: a drag, not a swipe; ignore the rest of the stroke.
			_active = false
			return {}
		return _try_fire(position, now)
	# After a swipe only travel along the fired axis counts: sideways drift
	# is followed (never a swipe of its own), the turn point tracks the
	# finger further along the fired direction, and a full reversal from it
	# fires the opposite way.
	if _fired.x != 0:
		_anchor.y = position.y
	else:
		_anchor.x = position.x
	var along: Vector2 = Vector2(_fired)
	if (position - _anchor).dot(along) > 0.0:
		_anchor = position
		_anchor_time = now
		return {}
	if now - _anchor_time > max_time:
		return {}
	# _try_fire only accepts the reversal of the last swipe here.
	return _try_fire(position, now)


func _try_fire(position: Vector2, now: float) -> Dictionary:
	var d: Vector2 = position - _anchor
	var direction: Vector2i = dominant_direction(d)
	if direction == Vector2i.ZERO:
		return {}
	var along: float = absf(d.x) if direction.x != 0 else absf(d.y)
	if along < threshold_px:
		return {}
	if _fired != Vector2i.ZERO and direction != -_fired:
		return {}
	var elapsed: float = maxf(now - _anchor_time, 1.0 / 240.0)
	var out: Dictionary = {
		"direction": direction,
		"velocity": d / elapsed,
		"time": now - _anchor_time,
		"from": _anchor,
		"to": position,
		"distance": d.length(),
		"index": _count,
	}
	_count += 1
	_fired = direction
	_anchor = position
	_anchor_time = now
	return out
