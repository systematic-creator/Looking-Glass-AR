class_name HoloDrop
extends Node
## Drop-in animation for a hologram piece: falls from above (gravity ease),
## squashes on landing and springs back with a small hop, flashes, and sends
## a ripple across the board. Add with HoloDrop.start(); it drives `body`
## (position.y offset and scale only) and frees itself when done.
##
## The curve is pure (pose_at), so tests can check it without waiting, and
## advance() steps it by hand.

signal landed()
signal finished()

## Seconds of free fall, then of squash / settle.
const FALL_TIME: float = 0.3
const SETTLE_TIME: float = 0.42
const SQUASH: float = 0.38
const HOP: float = 0.25

var body: Node3D
var ripple: MeshInstance3D
var height: float = 0.15
var ripple_radius: float = 0.1
var elapsed: float = 0.0
var _landed: bool = false


## Animate `body` dropping from `p_height` metres above its rest position.
## `p_ripple` (optional, from Holo.ripple) is shown expanding on landing.
static func start(p_body: Node3D, p_height: float, p_ripple: MeshInstance3D = null) -> HoloDrop:
	var drop := HoloDrop.new()
	drop.name = "HoloDrop"
	drop.body = p_body
	drop.height = p_height
	drop.ripple = p_ripple
	p_body.add_child(drop)
	drop._apply(drop.pose_at(0.0))
	return drop


static func total_time() -> float:
	return FALL_TIME + SETTLE_TIME


## Pose at `t` seconds: {"y": offset above rest, "scale": Vector3,
## "flash": 0..1, "ripple": 0..1 progress (-1 before landing)}.
func pose_at(t: float) -> Dictionary:
	return HoloDrop.curve(t, height)


static func curve(t: float, drop_height: float) -> Dictionary:
	if t < FALL_TIME:
		var f: float = clampf(t / FALL_TIME, 0.0, 1.0)
		# Free fall: slow at the top, fastest at impact; a little stretch.
		var stretch: float = 1.0 + 0.18 * f * f
		return {
			"y": drop_height * (1.0 - f * f),
			"scale": Vector3(1.0 / sqrt(stretch), stretch, 1.0 / sqrt(stretch)),
			"flash": 0.0,
			"ripple": -1.0,
		}
	var s: float = clampf((t - FALL_TIME) / SETTLE_TIME, 0.0, 1.0)
	if s >= 1.0:
		return {"y": 0.0, "scale": Vector3.ONE, "flash": 0.0, "ripple": 1.0}
	# Damped spring: squashed flat on impact, overshoots, settles.
	var squash_y: float = 1.0 - SQUASH * exp(-5.0 * s) * cos(s * 11.0)
	var widen: float = 1.0 / sqrt(maxf(squash_y, 0.2))
	var hop: float = drop_height * HOP * 0.25 * maxf(0.0, sin(s * TAU)) * (1.0 - s) * (1.0 - s)
	return {
		"y": hop,
		"scale": Vector3(widen, squash_y, widen),
		"flash": (1.0 - s) * (1.0 - s),
		"ripple": s,
	}


func _process(delta: float) -> void:
	advance(delta)


## Step the animation by `delta` seconds (tests call this directly).
func advance(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		queue_free()
		return
	elapsed += delta
	_apply(pose_at(elapsed))
	if not _landed and elapsed >= FALL_TIME:
		_landed = true
		landed.emit()
	if elapsed >= total_time():
		finish()


## Jump to the end: piece at rest, normal size, no flash, ripple hidden
## (emits `landed` first if it had not landed yet).
func finish() -> void:
	if not _landed:
		_landed = true
		landed.emit()
	if body != null and is_instance_valid(body):
		_apply(HoloDrop.curve(total_time(), height))
	if ripple != null and is_instance_valid(ripple):
		ripple.queue_free()
		ripple = null
	set_process(false)
	finished.emit()
	if is_inside_tree():
		queue_free()


func is_running() -> bool:
	return elapsed < total_time()


func _apply(pose: Dictionary) -> void:
	body.position.y = float(pose["y"])
	body.scale = pose["scale"] as Vector3
	Holo.set_param(body, &"flash", float(pose["flash"]))
	if ripple != null and is_instance_valid(ripple):
		var progress: float = float(pose["ripple"])
		ripple.visible = progress >= 0.0 and progress < 1.0
		if ripple.visible:
			var mat: ShaderMaterial = ripple.material_override as ShaderMaterial
			mat.set_shader_parameter("ring_radius", lerpf(0.15, 0.95, progress))
			mat.set_shader_parameter("intensity", (1.0 - progress) * 1.4)
