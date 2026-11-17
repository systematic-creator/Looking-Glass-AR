class_name ProbeGame
extends LGGame
## Test-only game that records every platform callback in order.

var events: Array[String] = []
var taps: Array[Vector3] = []
var drags: Array = []
var wants_drag: bool = false


func _on_board_ready() -> void:
	events.append("ready")
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
