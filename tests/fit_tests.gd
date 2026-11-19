extends "res://tests/surface_tests.gd"
## "Fit edges" calibration stage: the EdgeFitter maths, the stage in the
## AR flow, dragging handles with phone touches onto the real plywood edge
## (the ARCore plane in the model over-extends it by 20 cm), Reset / Done,
## the board staying inside, the glow clipped to the fitted edges, and the
## fit surviving pause / resume, plane refreshes and re-use.
## Runs through the phone path (ARCore-style XR projection, 2340x1080 window).
## Run: godot --headless --path . res://tests/fit_tests.tscn

var xr: FakeXRInterface
var _saved_window: Vector2i


func run_tests() -> void:
	ARSession.clear_saved_area()
	_test_fitter_maths()
	_saved_window = get_tree().root.size
	get_tree().root.size = Vector2i(2340, 1080)
	await frames(2)
	xr = FakeXRInterface.new()
	xr.projection = FakeXRInterface.arcore_projection(Vector2(1920, 1080), 1460.0, Vector2(972.0, 531.0))
	xr.install()
	await _test_stage_and_drags()
	await _test_traced_outline_fit()
	xr.uninstall()
	get_tree().root.size = _saved_window
	await frames(1)
	ARSession.clear_saved_area()


# --- EdgeFitter -----------------------------------------------------------------

func _dense_rect(r: Rect2, per_side: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i: int in 4:
		for k: int in per_side:
			out.append(c[i].lerp(c[(i + 1) % 4], float(k) / float(per_side)) + Vector2(0.002 * sin(k * 1.7), 0.002 * cos(k * 2.3)))
	return out


func _test_fitter_maths() -> void:
	var fitter := EdgeFitter.new()
	fitter.begin(_dense_rect(Rect2(-0.4, -0.3, 0.8, 0.6), 12))
	check("fitter: a 48-point traced rectangle simplifies to a few draggable corners", (
		fitter.polygon.size() >= 4 and fitter.polygon.size() <= EdgeFitter.MAX_CORNERS
		and absf(absf(SurfaceRegion.signed_area(fitter.polygon)) - 0.48) < 0.01
	))
	var square := PackedVector2Array([Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(0.2, 0.2), Vector2(-0.2, 0.2)])
	fitter.begin(square)
	check("fitter: handles are every corner plus every edge midpoint", fitter.handles().size() == 8)
	var ok_n: bool = true
	for i: int in 4:
		var mid: Vector2 = (fitter.polygon[i] + fitter.polygon[(i + 1) % 4]) * 0.5
		ok_n = ok_n and fitter.outward_normal(i).dot(mid) > 0.0
	var reversed := square.duplicate()
	reversed.reverse()
	var other := EdgeFitter.new()
	other.begin(reversed)
	for i: int in 4:
		var mid: Vector2 = (other.polygon[i] + other.polygon[(i + 1) % 4]) * 0.5
		ok_n = ok_n and other.outward_normal(i).dot(mid) > 0.0
	check("fitter: edge normals point outward for either winding", ok_n)
	check("fitter: a corner moves by the drag", fitter.move_corner(2, Vector2(0.05, 0.03)) and fitter.polygon[2].is_equal_approx(Vector2(0.25, 0.23)))
	fitter.reset()
	check("fitter: Reset restores the starting outline", not fitter.is_changed())
	# Edge 1 runs (0.2,-0.2) -> (0.2,0.2): outward is +x.
	check("fitter: an edge slides along its normal only (sideways motion ignored)", (
		fitter.move_edge(1, Vector2(0.04, 0.1)) and fitter.polygon[1].is_equal_approx(Vector2(0.24, -0.2))
		and fitter.polygon[2].is_equal_approx(Vector2(0.24, 0.2)) and fitter.is_changed()
	))
	fitter.reset()
	check("fitter: a corner dragged across the outline (self-intersection) is refused", (
		not fitter.move_corner(0, Vector2(0.5, 0.5)) and not fitter.is_changed()
	))
	fitter.reset()
	check("fitter: an edge pushed onto the opposite one (collapse) is refused", not fitter.move_edge(1, Vector2(-0.39, 0.0)))
	fitter.reset()
	check("fitter: a corner dropped onto its neighbour (tiny edge) is refused", not fitter.move_corner(0, Vector2(0.39, 0.0)))


# --- The stage in the AR flow ---------------------------------------------------

func _phone_touch(viewport_pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = get_tree().root.get_final_transform() * viewport_pos
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _phone_drag(from: Vector2, to: Vector2, steps: int = 10) -> void:
	_phone_touch(from, true)
	await frames(1)
	var final: Transform2D = get_tree().root.get_final_transform()
	var last: Vector2 = from
	for k: int in steps:
		var at: Vector2 = from.lerp(to, float(k + 1) / float(steps))
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = final * at
		e.relative = final.basis_xform(at - last)
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		last = at
		await frames(1)
	_phone_touch(to, false)
	await frames(1)


func _world_poly(ar: ARSession, host: GameHost) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector2 in ar.fitter.polygon:
		out.append(host.world_anchor.to_global(Vector3(p.x, 0.0, p.y)))
	return out


func _max_z(points: Array[Vector3]) -> float:
	var z: float = -INF
	for p: Vector3 in points:
		z = maxf(z, p.z)
	return z


func _test_stage_and_drags() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	ar.place_at_reticle()
	await frames(2)
	check("stage: placing on a detected surface opens Fit edges (step 3 of 4)", (
		ar.flow.step == CalibrationFlow.Step.FITTING and ar.flow.title().begins_with("Step 3 of 4")
		and ar.hud.fit_done_button.visible and ar.hud.fit_reset_button.visible and not ar.hud.lock_button.visible
		and ar.hud.replace_button.visible and not ar.hud.airspace_panel.visible
	))
	check("stage: the handles are drawn on screen (corners + edges)", (
		ar.hud.fit_handles.visible and ar.hud.fit_handles.handles.size() >= 4
	))
	check("stage: the game is not running while fitting", not host.game.is_playing())
	var before: Array[Vector3] = _world_poly(ar, host)
	check("stage: the starting outline is the (over-extended) ARCore plane", absf(_max_z(before) - ply_arcore.end.y) < 0.01)
	# Grab the near edge (the one 20 cm past the real plywood) and drag it in.
	var near_edge: Dictionary = {}
	for h: Dictionary in ar.fit_handle_screens():
		if int(h["kind"]) != EdgeFitter.Handle.EDGE:
			continue
		var i: int = int(h["index"])
		var a: Vector2 = ar.fitter.polygon[i]
		var b: Vector2 = ar.fitter.polygon[(i + 1) % ar.fitter.polygon.size()]
		var mid: Vector3 = host.world_anchor.to_global(Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5))
		if absf(mid.z - ply_arcore.end.y) < 0.01:
			near_edge = h
			near_edge["world"] = mid
	check("stage: the near edge's handle is on screen", not near_edge.is_empty())
	var board_before: Transform3D = host.game.global_transform
	if not near_edge.is_empty():
		var from: Vector2 = near_edge["screen"] as Vector2
		var target_world: Vector3 = Vector3((near_edge["world"] as Vector3).x, PLY_HEIGHT, ply_real.end.y)
		await _phone_drag(from, ar.xr_camera.unproject_position(target_world), 12)
	var after: Array[Vector3] = _world_poly(ar, host)
	check("drag: the near edge now sits on the real plywood edge (< 1 cm)", absf(_max_z(after) - ply_real.end.y) < 0.01)
	check("drag: the far side did not move", absf(after[0].distance_to(before[0])) < 0.21)
	check("drag: the board stays inside the fitted edges", _inside(_corners_world(host.game), Rect2(ply_real.position, ply_real.size), PLY_HEIGHT))
	# A drag that starts away from every handle changes nothing.
	var poly: PackedVector2Array = ar.fitter.polygon.duplicate()
	var board_now: Transform3D = host.game.global_transform
	var empty_spot: Vector2 = ar.xr_camera.unproject_position(host.game.to_global(Vector3(0.0, 0.0, 0.0)))
	await _phone_drag(empty_spot, empty_spot + Vector2(120, 40), 6)
	check("drag: a drag away from the handles moves neither the outline nor the board", (
		ar.fitter.polygon == poly and xform_near(host.game.global_transform, board_now, 0.0001)
	))
	# Corner: nudge a visible corner 3 cm along x.
	var corner: Dictionary = {}
	var view := Rect2(Vector2(80, 80), get_viewport().get_visible_rect().size - Vector2(160, 260))
	for h: Dictionary in ar.fit_handle_screens():
		if int(h["kind"]) == EdgeFitter.Handle.CORNER and view.has_point(h["screen"] as Vector2):
			corner = h
			break
	check("drag: a corner handle is on screen", not corner.is_empty())
	if not corner.is_empty():
		var idx: int = int(corner["index"])
		var p: Vector2 = ar.fitter.polygon[idx]
		var world: Vector3 = host.world_anchor.to_global(Vector3(p.x, 0.0, p.y))
		var inward := Vector3(-signf(world.x) * 0.03 if absf(world.x) > 0.01 else 0.03, 0.0, 0.0)
		await _phone_drag(corner["screen"] as Vector2, ar.xr_camera.unproject_position(world + inward), 8)
		var moved: Vector2 = ar.fitter.polygon[idx]
		var moved_world: Vector3 = host.world_anchor.to_global(Vector3(moved.x, 0.0, moved.y))
		check("drag: the corner follows the finger on the surface (3 cm, < 3 mm error)", moved_world.distance_to(world + inward) < 0.003)
	ar.reset_fit()
	check("stage: Reset returns to the starting outline", not ar.fitter.is_changed() and absf(_max_z(_world_poly(ar, host)) - ply_arcore.end.y) < 0.01)
	await _phone_drag(ar.xr_camera.unproject_position(near_edge.get("world", Vector3.ZERO) as Vector3),
		ar.xr_camera.unproject_position(Vector3((near_edge.get("world", Vector3.ZERO) as Vector3).x, PLY_HEIGHT, ply_real.end.y)), 12)
	var fitted: PackedVector2Array = ar.fitter.polygon.duplicate()
	ar.hud.fit_done_pressed.emit()
	await frames(1)
	check("done: Done commits the fitted outline as the play area and goes to Adjust", (
		ar.flow.step == CalibrationFlow.Step.ADJUSTING and ar.region.source == SurfaceRegion.Source.FITTED
		and ar.region.polygon == fitted and ar.hud.lock_button.visible and ar.hud.fit_edges_button.visible
	))
	check("done: the fitted outline is the session's reusable area", ARSession.saved_area_world.size() == fitted.size())
	check("done: the debug line says fitted", ar.debug_suffix().contains("area fitted"))
	# The board can no longer be dragged past the real edge.
	var centre: Vector2 = ar.xr_camera.unproject_position(host.game.global_position)
	var toward: Vector2 = ar.xr_camera.unproject_position(host.game.global_position + Vector3(0, 0, 0.5))
	for i: int in 8:
		ar.drag_board(centre.lerp(toward, float(i) / 8.0), centre.lerp(toward, float(i + 1) / 8.0))
	await frames(1)
	check("done: the board is clamped to the fitted edge, not the plane", _inside(_corners_world(host.game), ply_real, PLY_HEIGHT))
	# Glow clipping.
	var glow: MeshInstance3D = _find_glow(host.game)
	var mat: ShaderMaterial = glow.material_override as ShaderMaterial if glow != null else null
	check("glow: the projector glow is clipped to the fitted outline", (
		mat != null and int(mat.get_shader_parameter("clip_count")) == fitted.size()
	))
	var past_edge := Vector2(host.game.global_position.x, ply_real.end.y + 0.03)
	check("glow: nothing is drawn past the real edge, the board centre is inside", (
		not Holo.clip_contains(past_edge) and Holo.clip_contains(Vector2(host.game.global_position.x, host.game.global_position.z))
	))
	var glow_spills: bool = false
	var glow_aabb: AABB = glow.global_transform * glow.get_aabb() if glow != null else AABB()
	glow_spills = glow_aabb.end.z > ply_real.end.y
	check("glow: (the glow mesh itself is bigger than the area: the clip is what keeps it in)", glow_spills)
	# Region refreshes must not overwrite the fit.
	ar._region_refresh = 0.99
	ar._process(0.05)
	check("refresh: the 1 s plane refresh leaves a fitted area alone", ar.region.source == SurfaceRegion.Source.FITTED and ar.region.polygon == fitted)
	# Back into the stage from Adjust.
	check("again: Fit edges from Adjust re-opens the stage on the fitted outline", (
		ar.begin_fit() and ar.flow.step == CalibrationFlow.Step.FITTING and ar.fitter.polygon == fitted
	))
	host.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await frames(1)
	host.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await frames(2)
	check("persist: pause / resume mid-fit keeps the stage and the outline", (
		ar.flow.step == CalibrationFlow.Step.FITTING and ar.fitter.polygon == fitted
	))
	ar.set_locked(true)
	await frames(1)
	check("lock: Lock from Fit edges commits the fit and starts the game", (
		host.game.is_playing() and ar.region.source == SurfaceRegion.Source.FITTED and not ar.hud.fit_handles.visible
	))
	# Lock re-anchors under the board (the outline is re-expressed, same place).
	fitted = ar.region.polygon.duplicate()
	host.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await frames(1)
	host.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await frames(2)
	check("persist: pause / resume while playing keeps the fitted area and the clip", (
		ar.region.polygon == fitted and int(mat.get_shader_parameter("clip_count")) == fitted.size()
	))
	var game: TicTacToeGame = host.game as TicTacToeGame
	game.lg_tap(TicTacToeGame.cell_center(4))
	var ripple_ok: bool = false
	for child: Node in game.get_node(^"Marks").get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is ShaderMaterial:
			ripple_ok = int(((child as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("clip_count")) >= 3
	check("glow: glows made later (landing ripples) are clipped too", ripple_ok)
	ar.begin_replace()
	await frames(1)
	check("reuse: after Re-place, Use traced area offers the fitted outline", ar.flow.has_saved_area and ar.use_saved_area())
	check("reuse: and opens Fit edges on it", ar.flow.step == CalibrationFlow.Step.FITTING and absf(_max_z(_world_poly(ar, host)) - ply_real.end.y) < 0.01)
	await free_host(host)


func _find_glow(root: Node) -> MeshInstance3D:
	for child: Node in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is PlaneMesh:
			var m: Material = (child as MeshInstance3D).material_override
			if m is ShaderMaterial and (m as ShaderMaterial).shader == Holo.DISC_SHADER:
				return child as MeshInstance3D
	return null


func _test_traced_outline_fit() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	# A sloppy trace: the near side drawn 6 cm too far out.
	var sloppy := Rect2(ply_real.position + Vector2(0.02, 0.02), ply_real.size + Vector2(-0.04, 0.04))
	ar.begin_trace()
	var placed: bool = _trace_rect(ar, sloppy, PLY_HEIGHT)
	check("trace: a sloppy trace still places the board", placed and ar.is_placed())
	check("trace: and opens Fit edges with a few corners", (
		ar.flow.step == CalibrationFlow.Step.FITTING and ar.fitter.polygon.size() <= EdgeFitter.MAX_CORNERS
	))
	ar.finish_fit()
	check("trace: Done without changes keeps the traced shape", absf(ar.region.area() - sloppy.get_area()) < 0.03)
	await frames(1)
	check("trace: the fitted area clips the glow (next frame)", Holo.clip_polygon.size() == ar.region.polygon.size())
	await free_host(host)
