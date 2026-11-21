class_name TattooStudioGame
extends LGGame
## Tattoo Studio: tattoo a humanoid model standing on the board (floor
## life-size, or a miniature on a table).
##
##   Game (board space, on the plane-attached anchor)
##     Turntable            <- yaw only; always at the board origin
##       ModelRoot          <- display scale + temporary focus magnification
##         Model (MeshInstance3D, skin shader sampling the ink atlas)
##     Pad                  <- hologram disc marking the model's spot
##     StudioUI (CanvasLayer)
##
## Object permanence: the model never re-centres. The platform keeps the
## board on its anchor; this game only turns the turntable and scales the
## model about its feet, and ink lives in the model's UV texture, so a
## tattoo stays put whatever the viewpoint, zoom, scale or model switch.
##
## Input: Draw mode takes one-finger ray strokes (the platform's
## ray-stroke hook) and paints where the ray meets the real mesh; Rotate
## mode turns the turntable with one-finger drags; pinch scales the model
## (or the focus magnification), twist turns it, in both modes.
## Focus (close-up aid; the AR camera clips nearer than 0.1 m): tap Focus,
## then tap a spot on the model: it eases up to FOCUS_DEFAULT x around that
## spot (the spot itself stays where it is) so fine work needs no leaning
## in; pinch changes the magnification; "True size" eases back.

enum Mode { DRAW, ROTATE }

const PALETTE: Array = [
	["Black", Color(0.07, 0.07, 0.08)],
	["Grey wash", Color(0.46, 0.46, 0.48)],
	["Red", Color(0.80, 0.10, 0.12)],
	["Orange", Color(0.93, 0.46, 0.10)],
	["Yellow", Color(0.96, 0.83, 0.18)],
	["Green", Color(0.12, 0.55, 0.24)],
	["Blue", Color(0.12, 0.26, 0.72)],
	["Purple", Color(0.42, 0.16, 0.58)],
	["Brown", Color(0.42, 0.25, 0.12)],
]
## Needle radius in metres ON THE MODEL (body-relative: lines scale with it).
const BRUSHES: Array = [["S", 0.004], ["M", 0.007], ["L", 0.012], ["XL", 0.022]]
## Stamps every STAMP_SPACING x radius along a stroke.
const STAMP_SPACING: float = 0.3
## Rays re-cast along a fast stroke at least this often (model metres), so
## lines follow the surface around curves instead of cutting chords.
const RAY_SPACING: float = 0.006
const MAX_RAYS_PER_EVENT: int = 24
## A jump bigger than this between two hits (e.g. off an arm onto the
## torso behind) starts a new line segment instead of bridging.
const MAX_BRIDGE: float = 0.05
const UPLOAD_INTERVAL: float = 1.0 / 30.0
const BOX_MARGIN: float = 0.06
const BOX_REQUEST_DELAY: float = 0.3
const FOCUS_DEFAULT: float = 3.0
const FOCUS_MIN: float = 1.5
const FOCUS_MAX: float = 6.0
const FOCUS_EASE: float = 10.0

## Session state (survives pause / resume and leaving the game).
static var session_layers: Dictionary = {}   # model id -> TattooInkLayer
static var session_scale: Dictionary = {}    # model id -> display scale
static var session_yaw: Dictionary = {}      # model id -> turntable yaw
static var session_model: StringName = &""
static var session_tools: Dictionary = {}

var entries: Array[TattooModelEntry] = []
var current: TattooModelEntry
var model: Dictionary = {}
var paint: TattooPaintMesh
var ink: TattooInkLayer
var turntable: Node3D
var model_root: Node3D
var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var pad: MeshInstance3D
var ui: TattooStudioUI

var mode: Mode = Mode.DRAW
var tool: TattooInkLayer.Tool = TattooInkLayer.Tool.NEEDLE
var colour_index: int = 0
var brush_index: int = 1
var model_scale: float = 1.0
var yaw: float = 0.0
## Focus: target / shown magnification and the spot (turntable space).
var focus_target: float = 1.0
var focus_shown: float = 1.0
var focus_point: Vector3 = Vector3.ZERO
var focus_picking: bool = false
var strokes: int = 0
var load_errors: PackedStringArray = PackedStringArray()

var _model_radius: float = 0.3
var _stroke_active: bool = false
var _last_hit: Dictionary = {}
var _last_ray: Array = []
var _upload_wait: float = 0.0
var _box_request: float = -1.0
var _box_wait: float = 0.0


# --- Lifecycle ----------------------------------------------------------------------

func _on_board_ready() -> void:
	entries = TattooModelLoader.load_list()
	turntable = Node3D.new()
	turntable.name = "Turntable"
	add_child(turntable)
	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	turntable.add_child(model_root)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Model"
	model_root.add_child(mesh_instance)
	material = ShaderMaterial.new()
	material.shader = preload("res://games/tattoo_studio/scripts/skin.gdshader")
	material.set_shader_parameter("od_max", TattooInkLayer.OD_MAX)
	mesh_instance.material_override = material
	pad = MeshInstance3D.new()
	pad.name = "Pad"
	var disc := PlaneMesh.new()
	disc.size = Vector2.ONE
	pad.mesh = disc
	pad.material_override = Holo.disc_material(Holo.CYAN, 0.25, 0.92, 0.8)
	pad.position.y = 0.002
	add_child(pad)
	if session_tools.has("mode"):
		mode = int(session_tools["mode"]) as Mode
		tool = int(session_tools["tool"]) as TattooInkLayer.Tool
		colour_index = int(session_tools["colour"])
		brush_index = int(session_tools["brush"])
	ui = TattooStudioUI.new()
	ui.name = "StudioUI"
	add_child(ui)
	ui.build(entries, PALETTE, BRUSHES)
	ui.model_picked.connect(select_model)
	ui.model_scale_changed.connect(set_model_scale)
	ui.mode_picked.connect(func(m: int) -> void: set_mode(m as Mode))
	ui.tool_picked.connect(func(t: int) -> void: set_tool(t as TattooInkLayer.Tool))
	ui.colour_picked.connect(set_colour)
	ui.brush_picked.connect(set_brush)
	ui.clear_confirmed.connect(clear_all)
	ui.focus_pressed.connect(toggle_focus)
	ui.undo_pressed.connect(undo)
	ui.bottom_inset = ui_bottom_inset()
	ui_insets_changed.connect(func(bottom: float) -> void:
		ui.bottom_inset = bottom
		ui.layout())
	ui.set_shown(false)
	var first: StringName = session_model
	if find_entry(first) == null and not entries.is_empty():
		first = entries[0].id
	if first != &"":
		select_model(first)
	_update_status()


func _on_resumed() -> void:
	ui.set_shown(true)
	_update_status()


func _on_paused() -> void:
	_end_stroke()
	ui.set_shown(false)
	_save_session()


func _on_exit() -> void:
	_end_stroke()
	_save_session()


func _save_session() -> void:
	if current != null:
		session_model = current.id
		session_scale[current.id] = model_scale
		session_yaw[current.id] = yaw
	session_tools = {"mode": mode, "tool": tool, "colour": colour_index, "brush": brush_index}


func _process(delta: float) -> void:
	if ink != null and ink.dirty:
		_upload_wait -= delta
		if _upload_wait <= 0.0 or not _stroke_active:
			ink.upload()
			_upload_wait = UPLOAD_INTERVAL
	if _box_request >= 0.0:
		_box_wait -= delta
		if _box_wait <= 0.0:
			var h: float = _box_request
			_box_request = -1.0
			if absf(h - get_box().height()) > 0.01:
				request_box_height(h)
	if not is_equal_approx(focus_shown, focus_target):
		focus_shown = lerpf(focus_shown, focus_target, 1.0 - exp(-FOCUS_EASE * delta))
		if absf(focus_shown - focus_target) < 0.002:
			focus_shown = focus_target
		_apply_transform()


# --- Platform hooks ----------------------------------------------------------------

func captures_ray_strokes() -> bool:
	return mode == Mode.DRAW or focus_picking


func captures_drag() -> bool:
	return mode == Mode.ROTATE and not focus_picking


func captures_pinch() -> bool:
	return true


func is_over_game_ui(screen: Vector2) -> bool:
	return ui != null and ui.is_over(screen)


func box_outline_while_playing() -> float:
	return 0.0


func describe_point(point: Vector3) -> String:
	return "%s %+.2f,%+.2f" % [current.display_name if current != null else "model", point.x, point.z]


func _on_ray_stroke(phase: StrokePhase, origin: Vector3, direction: Vector3) -> void:
	if focus_picking:
		if phase == StrokePhase.BEGIN:
			var hit: Dictionary = cast(origin, direction)
			if not hit.is_empty():
				focus_at_model_point(hit["position"] as Vector3)
		return
	match phase:
		StrokePhase.BEGIN:
			_begin_stroke(origin, direction)
		StrokePhase.MOVE:
			_continue_stroke(origin, direction)
		_:
			_end_stroke()


func _on_board_drag(from: Vector3, to: Vector3) -> void:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var reach: float = maxf(0.05, _model_radius * model_scale * 0.25)
	if a.length() < reach or b.length() < reach:
		set_yaw(yaw + (b.x - a.x) / maxf(reach * 2.0, 0.05))
		return
	set_yaw(yaw + wrapf(atan2(b.x, b.y) - atan2(a.x, a.y), -PI, PI))


func _on_board_pinch(scale_factor: float, twist: float) -> void:
	if focus_target > 1.0:
		focus_target = clampf(focus_target * scale_factor, FOCUS_MIN, FOCUS_MAX)
		focus_shown = focus_target
		_apply_transform()
	else:
		set_model_scale(model_scale * scale_factor)
	# Clockwise on screen = clockwise seen from above = negative yaw.
	if absf(twist) > 0.0:
		set_yaw(yaw - twist)


func _on_box_changed(box: PlayBox) -> void:
	if current == null:
		return
	var height: float = float(model.get("height", current.height_m))
	if height * model_scale > box.height() - 0.015:
		model_scale = maxf(current.min_scale, (box.height() - 0.02) / maxf(height, 0.01))
		_apply_transform()
		_show_scale()


# --- Models ----------------------------------------------------------------------

func find_entry(id: StringName) -> TattooModelEntry:
	for entry: TattooModelEntry in entries:
		if entry.id == id:
			return entry
	return null


## Show model `id` (its ink and scale come back as it was left).
func select_model(id: StringName) -> bool:
	var entry: TattooModelEntry = find_entry(id)
	if entry == null:
		return false
	if current != null and current.id == id and paint != null:
		return true
	var result: Dictionary = TattooModelLoader.load_model(entry)
	var errors: PackedStringArray = result["errors"]
	if not errors.is_empty():
		load_errors = errors
		set_status("%s can't be used: %s" % [entry.display_name, errors[0]])
		push_warning("Tattoo Studio: model '%s': %s" % [id, ", ".join(errors)])
		if ui != null and current != null:
			ui.show_state(current.id, mode, tool, colour_index, brush_index)
		return false
	_end_stroke()
	_save_session()
	current = entry
	model = result
	paint = result["paint"]
	mesh_instance.mesh = result["mesh"]
	if not session_layers.has(id):
		session_layers[id] = TattooInkLayer.new(clampi(entry.ink_resolution, 256, 2048))
	ink = session_layers[id]
	material.set_shader_parameter("ink_map", ink.texture)
	material.set_shader_parameter("skin_color", entry.skin_color)
	material.set_shader_parameter("scale_pattern", entry.scale_pattern)
	_model_radius = 0.05
	for v: Vector3 in paint.positions:
		_model_radius = maxf(_model_radius, Vector2(v.x, v.z).length())
	focus_target = 1.0
	focus_shown = 1.0
	focus_picking = false
	yaw = float(session_yaw.get(id, 0.0))
	model_scale = clampf(float(session_scale.get(id, entry.default_scale)), entry.min_scale, max_model_scale())
	session_model = id
	_apply_transform()
	_request_box_for_model(true)
	if ui != null:
		ui.show_state(id, mode, tool, colour_index, brush_index)
		_show_scale()
	_refresh_undo()
	_update_status()
	return true


func model_height() -> float:
	return float(model.get("height", 1.7))


## Largest display scale: the entry's limit, the box's height cap and a
## turntable spin that stays on the footprint.
func max_model_scale() -> float:
	if current == null:
		return 1.0
	var box: PlayBox = get_box()
	var by_height: float = (box.max_height - BOX_MARGIN) / maxf(model_height(), 0.01)
	var half: float = minf(box.size.x, box.size.z) * 0.5
	var by_footprint: float = (half - 0.01) / maxf(_model_radius, 0.01)
	return maxf(current.min_scale, minf(current.max_scale, minf(by_height, by_footprint)))


func set_model_scale(value: float) -> void:
	if current == null:
		return
	model_scale = clampf(value, current.min_scale, max_model_scale())
	_apply_transform()
	_show_scale()
	_request_box_for_model(false)


func set_yaw(value: float) -> void:
	yaw = wrapf(value, -PI, PI)
	_apply_transform()


## The airspace follows the model: just taller than it (after a short
## delay, so dragging the slider does not save the placement every frame).
func _request_box_for_model(now: bool) -> void:
	_box_request = model_height() * model_scale + BOX_MARGIN
	_box_wait = 0.0 if now else BOX_REQUEST_DELAY


func _apply_transform() -> void:
	if turntable == null:
		return
	turntable.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	# Display scale about the feet, then the focus magnification about the
	# focus spot (which stays fixed in the room).
	var display := Transform3D(Basis().scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	var focus := Transform3D(Basis().scaled(Vector3.ONE * focus_shown), focus_point * (1.0 - focus_shown))
	model_root.transform = focus * display
	pad.scale = Vector3.ONE * (_model_radius * model_scale * 2.2)


func _show_scale() -> void:
	if ui != null and current != null:
		ui.show_scale(model_scale, current.min_scale, max_model_scale(), model_height())


# --- Focus (close-up aid) ---------------------------------------------------------

## Focus button: off -> pick a spot; picking -> cancel; focused -> true size.
func toggle_focus() -> void:
	if focus_target > 1.0 or focus_picking:
		end_focus()
	else:
		focus_picking = true
		_update_status()
		if ui != null:
			ui.show_focus(true, false)


## Magnify around a model-space point (the spot stays where it is).
func focus_at_model_point(point: Vector3, magnification: float = FOCUS_DEFAULT) -> void:
	# The spot in turntable space at the current (unfocused) display scale.
	focus_point = point * model_scale
	focus_picking = false
	focus_target = clampf(magnification, FOCUS_MIN, FOCUS_MAX)
	if ui != null:
		ui.show_focus(false, true)
	_update_status()


func end_focus() -> void:
	focus_picking = false
	focus_target = 1.0
	if ui != null:
		ui.show_focus(false, false)
	_update_status()


func is_focused() -> bool:
	return focus_target > 1.0


# --- Tools ------------------------------------------------------------------------

func set_mode(value: Mode) -> void:
	_end_stroke()
	mode = value
	_update_status()


func set_tool(value: TattooInkLayer.Tool) -> void:
	tool = value
	_update_status()


func set_colour(index: int) -> void:
	colour_index = clampi(index, 0, PALETTE.size() - 1)
	tool = TattooInkLayer.Tool.NEEDLE
	if ui != null:
		ui.show_state(current.id if current != null else &"", mode, tool, colour_index, brush_index)
	_update_status()


func set_brush(index: int) -> void:
	brush_index = clampi(index, 0, BRUSHES.size() - 1)
	_update_status()


func brush_radius() -> float:
	return float((BRUSHES[brush_index] as Array)[1])


func ink_colour() -> Color:
	return (PALETTE[colour_index] as Array)[1] as Color


func clear_all() -> void:
	if ink == null:
		return
	_end_stroke()
	ink.clear()
	ink.upload()
	_refresh_undo()
	_update_status()


## Take back the current model's last stroke (or Clear all). Each model
## keeps its own history (up to TattooInkLayer.MAX_UNDO steps) for the
## session, across model switches.
func undo() -> bool:
	if ink == null:
		return false
	_end_stroke()
	var done: bool = ink.undo()
	if done:
		ink.upload()
	_refresh_undo()
	return done


func undo_count() -> int:
	return ink.undo_count() if ink != null else 0


func _refresh_undo() -> void:
	if ui != null:
		ui.show_undo(undo_count())


func _update_status() -> void:
	if current == null:
		set_status("No model" if load_errors.is_empty() else "Model error: %s" % load_errors[0])
		return
	var what: String
	if focus_picking:
		what = "Focus: tap the spot to look at closely"
	elif mode == Mode.ROTATE:
		what = "Rotate: drag to turn, pinch to resize"
	elif tool == TattooInkLayer.Tool.ERASER:
		what = "Eraser %s" % (BRUSHES[brush_index] as Array)[0]
	else:
		what = "%s %s · go over again to deepen" % [(PALETTE[colour_index] as Array)[0], (BRUSHES[brush_index] as Array)[0]]
	var zoom: String = " · Focus %.1f×" % focus_target if focus_target > 1.0 else ""
	set_status("%s · %s%s" % [current.display_name, what, zoom])


# --- Painting ------------------------------------------------------------------------

## Board-space -> model-space transform of the mesh.
func model_transform() -> Transform3D:
	return turntable.transform * model_root.transform


## The real mesh under a board-space ray: hit in MODEL space, or {}.
func cast(origin: Vector3, direction: Vector3) -> Dictionary:
	if paint == null:
		return {}
	var inv: Transform3D = model_transform().affine_inverse()
	return paint.raycast(inv * origin, inv.basis * direction)


func _begin_stroke(origin: Vector3, direction: Vector3) -> void:
	if ink == null:
		return
	ink.begin_stroke(tool, ink_colour())
	_stroke_active = true
	strokes += 1
	_last_hit = cast(origin, direction)
	_last_ray = [origin, direction]
	if not _last_hit.is_empty():
		_stamp_segment(_last_hit, _last_hit, true)


func _continue_stroke(origin: Vector3, direction: Vector3) -> void:
	if not _stroke_active:
		_begin_stroke(origin, direction)
		return
	var hit: Dictionary = cast(origin, direction)
	var from_origin: Vector3 = _last_ray[0]
	var from_dir: Vector3 = _last_ray[1]
	_last_ray = [origin, direction]
	if hit.is_empty() and _last_hit.is_empty():
		return
	# Re-cast along the move so the line hugs the surface around curves.
	var span: float = 0.0
	if not hit.is_empty() and not _last_hit.is_empty():
		span = (hit["position"] as Vector3).distance_to(_last_hit["position"] as Vector3)
	var rays: int = clampi(int(ceil(span / RAY_SPACING)), 1, MAX_RAYS_PER_EVENT)
	if hit.is_empty() or _last_hit.is_empty():
		rays = MAX_RAYS_PER_EVENT / 2
	var prev: Dictionary = _last_hit
	for i: int in range(1, rays + 1):
		var f: float = float(i) / float(rays)
		var h: Dictionary = hit if i == rays else cast(from_origin.lerp(origin, f), from_dir.lerp(direction, f).normalized())
		if h.is_empty():
			prev = {}
			continue
		if prev.is_empty() or (prev["position"] as Vector3).distance_to(h["position"] as Vector3) > MAX_BRIDGE:
			_stamp_segment(h, h, true)
		else:
			_stamp_segment(prev, h, false)
		prev = h
	_last_hit = prev


## Stamps from hit a to hit b (model space) every STAMP_SPACING x radius.
func _stamp_segment(a: Dictionary, b: Dictionary, include_start: bool) -> void:
	var r: float = brush_radius()
	var pa: Vector3 = a["position"]
	var pb: Vector3 = b["position"]
	var na: Vector3 = a["normal"]
	var nb: Vector3 = b["normal"]
	var lo: Vector3 = pa.min(pb)
	var hi: Vector3 = pa.max(pb)
	var chunks: PackedInt32Array = paint.chunks_near(lo, hi, r)
	var length: float = pa.distance_to(pb)
	var count: int = maxi(1, int(ceil(length / (r * STAMP_SPACING))))
	var start: int = 0 if include_start else 1
	if length < 1e-6:
		count = 0
		start = 0 if include_start else 1
	for i: int in range(start, count + 1):
		var f: float = float(i) / float(maxi(count, 1))
		var n: Vector3 = na.lerp(nb, f)
		ink.stamp(paint, pa.lerp(pb, f), n.normalized() if n.length() > 1e-6 else na, r, chunks)


func _end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	_last_hit = {}
	_last_ray = []
	if ink != null:
		ink.end_stroke()
		ink.upload()
	_refresh_undo()


## Paint a stroke through model-space points (tests, screenshots, demos):
## each point is found on the surface by a ray from outside along -normal
## hint `toward` (model space).
func paint_model_points(points: Array, toward: Vector3, tool_used: TattooInkLayer.Tool = TattooInkLayer.Tool.NEEDLE) -> int:
	var xf: Transform3D = model_transform()
	var first: bool = true
	var hits: int = 0
	var saved: TattooInkLayer.Tool = tool
	tool = tool_used
	for p: Variant in points:
		var target: Vector3 = xf * (p as Vector3)
		var dir: Vector3 = (xf.basis * toward).normalized()
		var origin: Vector3 = target - dir * 2.0
		if first:
			_on_ray_stroke(StrokePhase.BEGIN, origin, dir)
			first = false
		else:
			_on_ray_stroke(StrokePhase.MOVE, origin, dir)
		if not _last_hit.is_empty():
			hits += 1
	_on_ray_stroke(StrokePhase.END, Vector3.ZERO, Vector3.FORWARD)
	tool = saved
	return hits


## Like paint_model_points, with one ray direction per point (model space):
## e.g. a band around an arm, each ray aimed at the arm's axis.
func paint_model_path(points: Array, towards: Array, tool_used: TattooInkLayer.Tool = TattooInkLayer.Tool.NEEDLE, standoff: float = 2.0) -> int:
	var xf: Transform3D = model_transform()
	var hits: int = 0
	var saved: TattooInkLayer.Tool = tool
	tool = tool_used
	for i: int in points.size():
		var target: Vector3 = xf * (points[i] as Vector3)
		var dir: Vector3 = (xf.basis * (towards[i] as Vector3)).normalized()
		_on_ray_stroke(StrokePhase.BEGIN if i == 0 else StrokePhase.MOVE, target - dir * standoff, dir)
		if not _last_hit.is_empty():
			hits += 1
	_on_ray_stroke(StrokePhase.END, Vector3.ZERO, Vector3.FORWARD)
	tool = saved
	return hits
