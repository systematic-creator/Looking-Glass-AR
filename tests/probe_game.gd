class_name ProbeGame
extends LGGame
## Test-only game that records every platform callback in order.

var events: Array[String] = []
var taps: Array[Vector3] = []
var drags: Array = []
var wants_drag: bool = false
var box_rays: Array = []
var box_changes: Array[float] = []
var outline_level: float = 0.0
var wants_swipes: bool = false
var swipes: Array[Vector2i] = []
## Every _on_orientation_changed (true = portrait), and is_portrait() at
## _on_board_ready.
var orientation_events: Array[bool] = []
var portrait_at_ready: bool = false


func _on_board_ready() -> void:
	events.append("ready")
	portrait_at_ready = is_portrait()
	set_status("probe ready")


func _on_board_locked() -> void:
	events.append("locked")


func _on_board_unlocked() -> void:
	events.append("unlocked")


func _on_resumed() -> void:
	events.append("resumed")


func _on_paused() -> void:
	events.append("paused")


func _on_exit() -> void:
	events.append("exit")


func _on_board_tap(point: Vector3) -> void:
	taps.append(point)


func _on_board_drag(from: Vector3, to: Vector3) -> void:
	drags.append([from, to])


func captures_drag() -> bool:
	return wants_drag


func _on_box_ray(origin: Vector3, direction: Vector3) -> void:
	box_rays.append([origin, direction])


func _on_box_changed(box: PlayBox) -> void:
	box_changes.append(box.height())


func box_outline_while_playing() -> float:
	return outline_level


func captures_swipes() -> bool:
	return wants_swipes


func _on_swipe(direction: Vector2i, _info: Dictionary) -> void:
	swipes.append(direction)


func _on_orientation_changed(portrait: bool) -> void:
	orientation_events.append(portrait)
