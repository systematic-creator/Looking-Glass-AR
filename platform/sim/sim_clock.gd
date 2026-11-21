class_name SimClock
extends RefCounted
## Fixed-step simulation clock: feed it frame deltas, it tells you how many
## fixed ticks to run (with a speed multiplier and pause), and how far the
## render frame is between ticks (alpha) for interpolated visuals. A cap on
## steps per frame keeps a slow frame from snowballing.

var step: float = 1.0 / 20.0
var speed: float = 1.0
var paused: bool = false
var max_steps_per_frame: int = 8
var accumulator: float = 0.0
## Simulated seconds so far (ticks x step).
var time: float = 0.0
var ticks: int = 0


func _init(hz: float = 20.0) -> void:
	step = 1.0 / maxf(1.0, hz)


## Returns the number of ticks to run for this frame.
func advance(frame_delta: float) -> int:
	if paused:
		return 0
	accumulator += maxf(0.0, frame_delta) * speed
	var n: int = 0
	while accumulator >= step and n < max_steps_per_frame:
		accumulator -= step
		n += 1
	if n == max_steps_per_frame and accumulator > step:
		accumulator = fmod(accumulator, step)
	ticks += n
	time += n * step
	return n


## 0..1: how far the frame is past the last tick.
func alpha() -> float:
	return clampf(accumulator / step, 0.0, 1.0)


func reset() -> void:
	accumulator = 0.0
	time = 0.0
	ticks = 0
