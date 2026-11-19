class_name FitHandles
extends Control
## Screen overlay for the "Fit edges" stage: big round corner handles and
## bar-shaped edge handles drawn at the play-area outline's screen positions
## (set each frame by ARSession). A small dot marks the exact point, so a
## handle can be lined up with a table edge even under a fingertip; the
## grabbed handle is drawn bigger. Input is handled by ARSession (this only
## draws; it never takes touches).

const CORNER_RADIUS: float = 30.0
const EDGE_LENGTH: float = 56.0
const EDGE_WIDTH: float = 18.0

## [{"kind": EdgeFitter.Handle, "index": int, "screen": Vector2, "along": Vector2}]
var handles: Array[Dictionary] = []
## Index into `handles` of the grabbed one (-1 = none).
var active: int = -1


func _init() -> void:
	name = "FitHandles"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_handles(p_handles: Array[Dictionary], p_active: int) -> void:
	handles = p_handles
	active = p_active
	queue_redraw()


func _draw() -> void:
	for i: int in handles.size():
		var h: Dictionary = handles[i]
		var at: Vector2 = h["screen"] as Vector2
		var grabbed: bool = i == active
		var grow: float = 1.25 if grabbed else 1.0
		if int(h["kind"]) == EdgeFitter.Handle.CORNER:
			draw_circle(at, CORNER_RADIUS * grow, Color(1.0, 0.82, 0.3, 0.42 if grabbed else 0.28))
			draw_arc(at, CORNER_RADIUS * grow, 0.0, TAU, 40, Color(1.0, 0.95, 0.75, 0.95), 4.0)
		else:
			var along: Vector2 = (h.get("along", Vector2.RIGHT) as Vector2).normalized()
			if along == Vector2.ZERO:
				along = Vector2.RIGHT
			var half: Vector2 = along * EDGE_LENGTH * 0.5 * grow
			draw_line(at - half, at + half, Color(0.3, 0.95, 1.0, 0.55 if grabbed else 0.4), EDGE_WIDTH * grow)
			draw_line(at - half, at + half, Color(0.85, 1.0, 1.0, 0.95), 3.0)
		draw_circle(at, 4.0, Color.WHITE)
