extends LGTestSuite
## Play-area tests: picking the placed-on plane, tracing an outline, keeping
## the board inside it, and phone-style touch taps reaching games.
##
## The AR scene model mirrors the phone test: a 1.2 x 0.4 m plywood sheet
## 12 cm above a driveway, whose ARCore plane wrongly extends 0.2 m past the
## plywood's front edge, plus the ground plane below.
## Run: godot --headless --path . res://tests/surface_tests.tscn

const PLY_HEIGHT: float = 0.12
const BOX_HEIGHT: float = 0.3
## Real plywood (x, z) and the over-extended ARCore polygon.
var ply_real := Rect2(-0.6, -0.9, 1.2, 0.4)
var ply_arcore := Rect2(-0.6, -0.9, 1.2, 0.6)
## An object standing on the plywood (only when box_on).
var box_rect := Rect2(0.3, -0.85, 0.15, 0.15)
var box_on: bool = false
var _session: ARSession


func run_tests() -> void:
	ARSession.clear_saved_area()
	_test_region_geometry()
	_test_clean_outline()
	await _test_plane_selection_and_clamp()
	await _test_tracing()
	await _test_saved_area_reuse()
	await _test_touch_taps_fallback()
	await _test_touch_taps_ar()
	await _test_label_never_over_cells()
	ARSession.clear_saved_area()


# --- Pure geometry ----------------------------------------------------------------

func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _test_region_geometry() -> void:
	var strip := SurfaceRegion.make(_rect_poly(Rect2(-0.6, -0.2, 1.2, 0.4)), SurfaceRegion.Source.TRACED)
	check("region: area and centroid of a 1.2 x 0.4 m strip", (
		is_equal_approx(strip.area(), 0.48) and strip.centroid().is_equal_approx(Vector2.ZERO)
	))
	var half := Vector2(0.15, 0.15)
	check("region: a 30 cm board fits in the middle", strip.fits(Vector2.ZERO, half, 0.0))
	check("region: hanging over the long edge does not fit", not strip.fits(Vector2(0.0, 0.15), half, 0.0))
	var clamped: Variant = strip.clamp_center(Vector2(0.0, 0.5), half, 0.0)
	check("region: a centre past the edge is pulled back just inside", (
		clamped != null and strip.fits(clamped as Vector2, half, 0.0)
		and (clamped as Vector2).y > 0.02 and (clamped as Vector2).y <= 0.2 - 0.15
	))
	var slid: Variant = strip.clamp_center(Vector2(0.9, 0.0), half, 0.0)
	check("region: sliding along the strip stops at its end", (
		slid != null and absf((slid as Vector2).x - (0.6 - 0.15 - SurfaceRegion.EDGE_MARGIN)) < 0.005
	))
	check("region: a board wider than the area has no fitting centre", strip.clamp_center(Vector2.ZERO, Vector2(0.3, 0.3), 0.0) == null)
	var fit: Dictionary = strip.fit_board(Vector2(0.3, 0.3), BoardPlacement.MIN_SCALE, 2.0)
	check("region: auto-fit sizes a square board to the strip's depth", (
		not fit.is_empty() and absf(float(fit["scale"]) - (0.4 - 2.0 * SurfaceRegion.EDGE_MARGIN) / 0.3) < 0.02
	))
	var long_fit: Dictionary = strip.fit_board(Vector2(0.6, 0.2), BoardPlacement.MIN_SCALE, 2.0)
	var footprint: PackedVector2Array = SurfaceRegion.footprint(long_fit["center"] as Vector2, Vector2(0.3, 0.1) * float(long_fit["scale"]), float(long_fit["yaw"]))
	var span_x: float = absf(footprint[1].x - footprint[0].x) + absf(footprint[2].x - footprint[1].x)
	check("region: auto-fit turns a long board along the long side", span_x > 0.9)
	var rotated := SurfaceRegion.make(_rect_poly(Rect2(-0.2, -0.6, 0.4, 1.2)), SurfaceRegion.Source.TRACED)
	check("region: principal direction follows the long side", (
		absf(absf(rotated.principal_yaw()) - PI * 0.5) < 0.01 and absf(strip.principal_yaw()) < 0.01
	))
	check("region: a tiny area cannot hold even the smallest board", (
		SurfaceRegion.make(_rect_poly(Rect2(0, 0, 0.05, 0.05)), SurfaceRegion.Source.TRACED).fit_board(Vector2(0.3, 0.3), BoardPlacement.MIN_SCALE).is_empty()
	))
	var l_shape := SurfaceRegion.make(PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.3), Vector2(0.3, 0.3), Vector2(0.3, 1), Vector2(0, 1)]), SurfaceRegion.Source.TRACED)
	check("region: concave areas are respected (no board across the notch)", (
		not l_shape.fits(Vector2(0.5, 0.5), Vector2(0.1, 0.1), 0.0) and l_shape.fits(Vector2(0.15, 0.6), Vector2(0.1, 0.1), 0.0)
	))


func _test_clean_outline() -> void:
	var noisy := PackedVector2Array()
	for i: int in 400:
		var a: float = TAU * float(i) / 400.0
		noisy.append(Vector2(cos(a) * 0.4, sin(a) * 0.25))
	var cleaned: PackedVector2Array = SurfaceRegion.clean_outline(noisy)
	check("trace cleanup: a dense stroke is thinned to at most MAX_POINTS", (
		cleaned.size() >= 3 and cleaned.size() <= SurfaceRegion.MAX_POINTS
	))
	var bow := PackedVector2Array([Vector2(0, 0), Vector2(0.5, 0.5), Vector2(0.5, 0), Vector2(0, 0.5)])
	var fixed: PackedVector2Array = SurfaceRegion.clean_outline(bow)
	check("trace cleanup: a self-crossing outline becomes its hull", fixed.size() == 4 and absf(SurfaceRegion.signed_area(fixed)) > 0.2)
	check("trace cleanup: a scribble with no area is rejected", (
		SurfaceRegion.clean_outline(PackedVector2Array([Vector2(0, 0), Vector2(0.02, 0.01), Vector2(0.04, 0.0)])).is_empty()
	))


# --- AR scene model -----------------------------------------------------------------

func _model_hit(normalized: Vector2) -> Dictionary:
	if _session == null or _session.xr_camera == null:
		return {"hit": false}
	var screen: Vector2 = normalized * get_viewport().get_visible_rect().size
	# ARCore's own hit test is exact (inverse of its projection).
	var ray: Array[Vector3] = ScreenRay.ray(_session.xr_camera, screen)
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	var layers: Array = []
	if box_on:
		layers.append([BOX_HEIGHT, box_rect])
	layers.append([PLY_HEIGHT, ply_arcore])
	for layer: Array in layers:
		var hit: Variant = Plane(Vector3.UP, float(layer[0])).intersects_ray(origin, direction)
		if hit != null and (layer[1] as Rect2).has_point(Vector2((hit as Vector3).x, (hit as Vector3).z)):
			return {"hit": true, "kind": "plane", "pose": Transform3D(Basis(), hit as Vector3)}
	var ground: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if ground != null and origin.distance_to(ground as Vector3) < 3.0:
		return {"hit": true, "kind": "plane", "pose": Transform3D(Basis(), ground as Vector3)}
	return {"hit": false}


func _model_planes() -> Array:
	var center: Vector2 = ply_arcore.get_center()
	var half: Vector2 = ply_arcore.size * 0.5
	return [
		{"pose": Transform3D(Basis(), Vector3(center.x, PLY_HEIGHT, center.y)),
			"polygon": _rect_poly(Rect2(-half, half * 2.0))},
		{"pose": Transform3D(Basis(), Vector3.ZERO), "polygon": _rect_poly(Rect2(-5, -5, 10, 10))},
	]


## AR host whose fake ARCore sees the plywood scene; camera above the front.
func _ar_host(id: StringName) -> GameHost:
	var fake := FakeARBridge.new()
	fake.hit_callback = _model_hit
	fake.planes = _model_planes()
	var host: GameHost = await make_host(id, fake)
	_session = host.session
	_look(Vector3(0.0, 0.6, 0.35), Vector3(0.0, PLY_HEIGHT, -0.6))
	await frames(3)
	return host


func _look(from: Vector3, at: Vector3) -> void:
	_session.xr_camera.transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


func _screen(world: Vector3) -> Vector2:
	return _session.xr_camera.unproject_position(world)


func _corners_world(game: Node3D) -> Array[Vector3]:
	var half: Vector2 = (game as LGGame).get_board_size() * 0.5
	var out: Array[Vector3] = []
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(game.to_global(Vector3(c.x, 0.0, c.y)))
	return out


func _inside(points: Array[Vector3], rect: Rect2, height: float) -> bool:
	for p: Vector3 in points:
		if not rect.grow(0.001).has_point(Vector2(p.x, p.z)) or absf(p.y - height) > 0.002:
			return false
	return true


func _test_plane_selection_and_clamp() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	# Aim the reticle 6 cm from the ARCore plane's front edge.
	_look(Vector3(0.0, 0.6, 0.35), Vector3(0.0, PLY_HEIGHT, ply_arcore.end.y - 0.06))
	await frames(3)
	check("plane: the reticle finds the plywood surface", ar.flow.step == CalibrationFlow.Step.SURFACE_FOUND and ar.hud.trace_button.visible)
	check("plane: Trace play area is offered next to Place here", ar.hud.trace_button.visible and ar.hud.place_button.visible)
	check("plane: Place here anchors on the plywood", ar.place_at_reticle())
	check("plane: the plywood plane (not the ground) is selected as the play area", (
		ar.region != null and ar.region.source == SurfaceRegion.Source.PLANE and absf(ar.region.area() - ply_arcore.get_area()) < 0.001
	))
	await frames(1)
	check("plane: a board placed near the edge is slid back inside the plane", _inside(_corners_world(host.game), ply_arcore, PLY_HEIGHT))
	check("plane: the play-area outline shows while adjusting", ar._region_node != null and ar._region_node.visible)
	var centre: Vector2 = _screen(host.game.global_position)
	var toward_ground: Vector2 = _screen(host.game.to_global(Vector3(0.0, 0.0, 0.9)))
	var moved: bool = false
	for i: int in 12:
		moved = ar.drag_board(centre.lerp(toward_ground, float(i) / 12.0), centre.lerp(toward_ground, float(i + 1) / 12.0)) or moved
	await frames(1)
	check("drag: dragging toward the driveway stops at the surface edge", _inside(_corners_world(host.game), ply_arcore, PLY_HEIGHT))
	check("drag: the board stays at the plywood's height (never drops to the ground)", (
		absf(host.game.global_position.y - PLY_HEIGHT) < 0.002 and absf(ar.placement.offset.y) < 0.0001
	))
	var along: Vector2 = _screen(host.game.to_global(Vector3(0.25, 0.0, 0.0)))
	var before_x: float = host.game.global_position.x
	ar.drag_board(_screen(host.game.global_position), along)
	await frames(1)
	check("drag: sliding along the plank still works", host.game.global_position.x > before_x + 0.1)
	var offset_before: Vector3 = ar.placement.offset
	_look(Vector3(0.0, PLY_HEIGHT + 0.02, 0.4), Vector3(0.0, PLY_HEIGHT + 0.02, -2.0))
	await frames(1)
	var mid: Vector2 = get_viewport().get_visible_rect().size * 0.5
	check("drag: rays grazing the surface are ignored (no metre-long jumps)", (
		not ar.drag_board(mid, mid + Vector2(0.0, -4.0)) and ar.placement.offset.is_equal_approx(offset_before)
	))
	var scale_before: float = ar.placement.scale
	ar.resize_board(4.0, 0.0)
	check("pinch: growing past the area is refused", is_equal_approx(ar.placement.scale, scale_before))
	await free_host(host)


func _trace_rect(ar: ARSession, rect: Rect2, height: float, per_side: int = 10) -> bool:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var started: bool = ar.trace_begin(_screen(Vector3(corners[0].x, height, corners[0].y)))
	if not started:
		return false
	for side: int in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		for k: int in range(1, per_side + 1):
			var p: Vector2 = a.lerp(b, float(k) / float(per_side))
			ar.trace_add(_screen(Vector3(p.x, height, p.y)))
	return ar.trace_end()


func _test_tracing() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	check("trace: tracing starts from a found surface", ar.begin_trace() and ar.flow.step == CalibrationFlow.Step.TRACING)
	check("trace: the HUD swaps to Cancel while tracing", (
		ar.hud.trace_cancel_button.visible and not ar.hud.trace_button.visible and not ar.hud.place_button.visible
	))
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	fake.hit_callback = func(_n: Vector2) -> Dictionary: return {"hit": false}
	var far_screen: Vector2 = _screen(Vector3(0.0, PLY_HEIGHT, -1.9))
	check("trace: a stroke must start on a detected surface (or next to the reticle's)", (
		not ar.trace_begin(far_screen) and ar.flow.message().contains("Start your outline") and ar.trace_point_count() == 0
	))
	check("trace: a start where ARCore has no plane yet, next to the reticle, uses the reticle surface's height", (
		ar.trace_begin(_screen(Vector3(0.05, PLY_HEIGHT, -0.62))) and absf(ar._trace_height - PLY_HEIGHT) < 0.001
	))
	ar.clear_trace()
	fake.hit_callback = _model_hit
	var tiny := Rect2(-0.02, -0.72, 0.03, 0.03)
	_trace_rect(ar, tiny, PLY_HEIGHT, 3)
	check("trace: a tiny outline is rejected with a reason and tracing continues", (
		not ar.is_placed() and ar.flow.step == CalibrationFlow.Step.TRACING and ar.flow.message().contains("too small")
	))
	box_on = true
	ar.trace_begin(_screen(Vector3(-0.5, PLY_HEIGHT, -0.85)))
	var box_point: Vector2 = _screen(Vector3(box_rect.get_center().x, BOX_HEIGHT, box_rect.get_center().y))
	check("trace: points over an object standing on the area are rejected", not ar.trace_add(box_point))
	box_on = false
	ar.clear_trace()
	var traced := Rect2(ply_real.position + Vector2(0.01, 0.01), ply_real.size - Vector2(0.02, 0.02))
	check("trace: closing the outline places the board", _trace_rect(ar, traced, PLY_HEIGHT) and ar.is_placed())
	check("trace: the traced outline becomes the play area", (
		ar.region != null and ar.region.source == SurfaceRegion.Source.TRACED
		and absf(ar.region.area() - traced.get_area()) < 0.03
	))
	check("trace: placing on the outline opens the Fit edges stage", ar.flow.step == CalibrationFlow.Step.FITTING and ar.hud.fit_done_button.visible)
	check("trace: the anchor sits at the traced surface's height", absf(host.world_anchor.global_position.y - PLY_HEIGHT) < 0.002)
	await frames(1)
	check("trace: the board is auto-fitted inside the real plywood (not the over-extended plane)", (
		_inside(_corners_world(host.game), ply_real, PLY_HEIGHT)
	))
	check("trace: auto-fit keeps the game at its own size when it fits (never huge)", is_equal_approx(ar.placement.scale, 1.0))
	check("trace: the outline is remembered for this session", ARSession.saved_area_world.size() >= 4 and ar.flow.has_saved_area)
	var centre: Vector2 = _screen(host.game.global_position)
	var off_edge: Vector2 = _screen(host.game.to_global(Vector3(0.0, 0.0, 0.6)))
	for i: int in 8:
		ar.drag_board(centre.lerp(off_edge, float(i) / 8.0), centre.lerp(off_edge, float(i + 1) / 8.0))
	await frames(1)
	check("trace: dragging toward the real edge stops at the traced outline", _inside(_corners_world(host.game), ply_real, PLY_HEIGHT))
	ar.set_locked(true)
	var locked: Transform3D = host.game.global_transform
	_look(Vector3(0.8, 0.5, -0.2), Vector3(0.0, PLY_HEIGHT, -0.7))
	await frames(3)
	check("trace: once locked the board ignores camera movement", xform_near(host.game.global_transform, locked, 0.0001))
	check("trace: the outline hides while playing", not ar._region_node.visible)
	check("trace: locking straight from Fit edges confirms the outline (debug: fitted area)", ar.debug_suffix().contains("area fitted"))
	ar.begin_replace()
	check("trace: re-place clears the area but offers the traced one again", (
		ar.region == null and ar.flow.has_saved_area and bool(ar.flow.controls()["use_area"])
	))
	await free_host(host)


func _test_saved_area_reuse() -> void:
	var host: GameHost = await _ar_host(&"competitive_evolution")
	var ar: ARSession = host.session
	await frames(2)
	check("reuse: another game offers Use traced area", ar.hud.use_area_button.visible)
	check("reuse: the saved outline places the new game at once", ar.use_saved_area() and ar.is_placed())
	await frames(1)
	check("reuse: the 42 cm globe board is shrunk to fit the 38 cm plank", (
		ar.placement.scale < 1.0 and _inside(_corners_world(host.game), ply_real, PLY_HEIGHT)
	))
	await free_host(host)


# --- Touch taps -------------------------------------------------------------------

func _tap(position: Vector2, index: int = 0, wobble: Vector2 = Vector2.ZERO) -> void:
	get_viewport().push_input(touch(index, position, true), true)
	if wobble != Vector2.ZERO:
		get_viewport().push_input(drag(index, position + wobble, wobble), true)
	get_viewport().push_input(touch(index, position + wobble, false), true)


func _test_touch_taps_fallback() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var camera: Camera3D = host.active_camera()
	var cell := func(index: int) -> Vector2: return camera.unproject_position(game.to_global(TicTacToeGame.cell_top(index)))
	_tap(cell.call(4) as Vector2)
	check("touch: a screen-touch tap on a tile places a mark", game.rules.cells[4] == TicTacToeRules.Mark.X)
	check("touch: the tap shows a marker where it landed", host._tap_marker != null and host._tap_marker.visible)
	_tap(cell.call(0) as Vector2, 0, Vector2(9.0, -7.0))
	check("touch: a fingertip wobble of a few pixels is still a tap", game.rules.cells[0] == TicTacToeRules.Mark.O)
	get_viewport().push_input(touch(1, Vector2(50, 600), true), true)
	_tap(cell.call(8) as Vector2)
	check("touch: a touch whose release was lost does not block later taps", game.rules.cells[8] == TicTacToeRules.Mark.X)
	var yaw: float = host.orbit_camera.yaw
	_tap(cell.call(2) as Vector2, 0, Vector2(90.0, 0.0))
	check("touch: a long finger move orbits instead of tapping", (
		game.rules.cells[2] == TicTacToeRules.Mark.NONE and host.orbit_camera.yaw != yaw
	))
	var back: Vector2 = host._back_button.get_global_rect().get_center()
	var marks: int = game.rules.cells.count(TicTacToeRules.Mark.NONE)
	host._input(touch(0, back, true))
	host._input(touch(0, back, false))
	check("touch: touching the Games button is not a board tap", (
		host.is_over_platform_ui(back) and game.rules.cells.count(TicTacToeRules.Mark.NONE) == marks
	))
	var near_edge: Vector3 = TicTacToeGame.cell_top(6) + Vector3(-0.055, 0.0, 0.0)
	host.route_gesture({"kind": &"tap", "position": camera.unproject_position(game.to_global(near_edge))})
	check("touch: a tap just past the grid edge still picks the edge tile", game.rules.cells[6] != TicTacToeRules.Mark.NONE)
	check("touch: tap slop is at least the default on any screen", host.tap_slop_for_screen() >= GestureTracker.TAP_SLOP_PX)
	await free_host(host)


func _test_touch_taps_ar() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	_look(Vector3(0.0, 0.6, 0.35), Vector3(0.0, PLY_HEIGHT, -0.7))
	await frames(2)
	ar.place_at_reticle()
	# A pinch during adjust whose second release is lost (eaten by a button).
	get_viewport().push_input(touch(0, Vector2(500, 400), true), true)
	get_viewport().push_input(touch(1, Vector2(700, 400), true), true)
	get_viewport().push_input(touch(0, Vector2(500, 400), false), true)
	ar.set_locked(true)
	await frames(1)
	var game: TicTacToeGame = host.game as TicTacToeGame
	_tap(_screen(game.to_global(TicTacToeGame.cell_top(4))))
	check("touch AR: after locking, a screen tap through the AR camera places a mark", game.rules.cells[4] == TicTacToeRules.Mark.X)
	_tap(_screen(game.to_global(TicTacToeGame.cell_top(1))), 0, Vector2(-12.0, 10.0))
	check("touch AR: wobbly phone taps work on the locked board", game.rules.cells[1] == TicTacToeRules.Mark.O)
	check("touch AR: the debug line counts taps that hit the board", ar.debug_suffix().contains("taps 2/2"))
	await free_host(host)


func _test_label_never_over_cells() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var clear: bool = true
	for i: int in 8:
		var angle: float = TAU * float(i) / 8.0
		host.orbit_camera.yaw = angle
		host.orbit_camera.orbit(Vector2.ZERO)
		await frames(1)
		var p: Vector3 = game.label_position()
		clear = clear and maxf(absf(p.x), absf(p.z)) > TicTacToeGame.CELL * 1.5 + 0.03
		var viewer: Vector3 = game.to_local(host.orbit_camera.camera.global_position)
		clear = clear and Vector2(p.x, p.z).dot(Vector2(viewer.x, viewer.z)) < 0.0
	check("label: the floating banner stays beyond the far edge from every side", clear)
	await free_host(host)
