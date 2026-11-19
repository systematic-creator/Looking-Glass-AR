extends "res://tests/anchor_tests.gd"
## Bedroom field run of lg-test-c3e778b (black folding table, low light,
## never locked): the outline / board during Fit edges and Adjust, covering
## the camera for 5 s (planes 0/11 tracked, anchor paused) and having to
## re-trace, and the low-feature warnings. Covers: anchor-relative outline
## and board before Lock, the unlocked height guard, the pose deadband,
## hiding the board while its anchor is paused, auto re-anchoring on a
## matching plane, "Re-place on table" (outline kept, no tracing), the loss
## / low-light messages, and the debug overlay (feature points, anchor
## cross, fixed world cross, feature-point height check).
## Run: godot --headless --path . res://tests/recovery_tests.tscn


func run_tests() -> void:
	ARSession.clear_saved_area()
	await _test_fit_and_adjust_are_anchor_relative()
	await _test_unlocked_height_guard_and_fit_polygon()
	await _test_deadband()
	await _test_covered_camera_recovers_on_matching_plane()
	await _test_replace_on_table_keeps_outline()
	await _test_messages_and_low_light()
	await _test_debug_overlay()
	ARSession.clear_saved_area()


func _world_outline(ar: ARSession) -> PackedVector2Array:
	return ar.play_area_world()


func _fit_world(ar: ARSession) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in ar.fitter.polygon:
		var w: Vector3 = ar.world_anchor.to_global(Vector3(p.x, 0.0, p.y))
		out.append(Vector2(w.x, w.z))
	return out


func _placed_fitting() -> GameHost:
	var host: GameHost = await _host()
	host.session.place_at_reticle()
	await frames(1)
	return host


func _test_fit_and_adjust_are_anchor_relative() -> void:
	var host: GameHost = await _placed_fitting()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	check("setup: placed on the plane, in Fit edges", ar.flow.step == CalibrationFlow.Step.FITTING and ar.anchor_kind == "plane" and ar.locked_on_plane)
	var board: Transform3D = _board(host)
	var outline: PackedVector2Array = _world_outline(ar)
	var grown: Array = _model_planes()
	grown[0] = {"pose": Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.1, PLY_HEIGHT, -0.55)), "polygon": _rect_poly(Rect2(-0.8, -0.45, 1.6, 0.9))}
	fake.planes = grown
	_step(ar, 2.5)
	check("fit edges: ARCore re-estimating the plane (centre / extent / turn) moves neither the board nor the outline", (
		xform_near(_board(host), board, 0.0005) and _same_polygon(outline, _world_outline(ar), 0.0005)
	))
	ar.finish_fit()
	fake.planes = _model_planes()
	_step(ar, 0.1)
	var adjusting: PackedVector2Array = _world_outline(ar)
	var small: Array = _model_planes()
	small[0] = {"pose": (small[0] as Dictionary)["pose"], "polygon": _rect_poly(Rect2(-0.62, -0.31, 1.24, 0.62))}
	fake.planes = small
	_step(ar, 1.5)
	check("adjust: a slightly refined plane (+7%%) does not replace the outline (no shimmering)", _same_polygon(adjusting, _world_outline(ar), 0.0005))
	await free_host(host)


func _test_unlocked_height_guard_and_fit_polygon() -> void:
	var host: GameHost = await _placed_fitting()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var fit_before: PackedVector2Array = _fit_world(ar)
	var board: Transform3D = _board(host)
	var id: int = fake.last_anchor_id()
	for i: int in 10:
		fake.anchor_shift[id] = Transform3D(Basis(), Vector3(0.0, -0.01 * float(i + 1), 0.0))
		_step(ar, 0.05)
	_step(ar, 2.0)
	check("fit edges: a board sinking 10 cm under its plane before Lock is put back on it", (
		ar.height_fixes == 1 and absf(_board(host).origin.y - PLY_HEIGHT) < 0.002 and ar.anchor_reason.contains("height fixed")
	))
	check("fit edges: re-anchoring keeps the fit handles' outline where it was", (
		_same_polygon(fit_before, _fit_world(ar), 0.002) and Vector2(_board(host).origin.x - board.origin.x, _board(host).origin.z - board.origin.z).length() < 0.002
	))
	ar.finish_fit()
	fake.anchor_shift[fake.last_anchor_id()] = Transform3D(Basis(), Vector3(0.0, 0.08, 0.0))
	ar._fit_handle = {}
	ar.gestures.handle(touch(0, Vector2(400, 400), true))
	_step(ar, 2.0)
	var held: bool = ar.height_fixes == 1
	ar.gestures.reset()
	_step(ar, 2.0)
	check("adjust: no height fix while a finger is down; done once it lifts", held and ar.height_fixes == 2)
	await free_host(host)


func _test_deadband() -> void:
	var host: GameHost = await _locked_host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var locked: Transform3D = _board(host)
	var id: int = fake.last_anchor_id()
	var still: bool = true
	for i: int in 30:
		fake.anchor_shift[id] = Transform3D(Basis(Vector3.UP, 0.0005 * sin(float(i))), Vector3(0.0006 * sin(float(i) * 1.7), 0.0, 0.0006 * cos(float(i) * 2.3)))
		_step(ar, STEP)
		still = still and xform_near(_board(host), locked, 0.00001)
	check("deadband: sub-mm anchor jitter does not shake the board", still)
	fake.anchor_shift[id] = Transform3D(Basis(), Vector3(0.002, 0.0, 0.0))
	_step(ar, STEP)
	check("deadband: a 2 mm correction still applies", near(_board(host).origin, locked.origin + Vector3(0.002, 0.0, 0.0), 0.0002))
	await free_host(host)


## The field sequence: camera covered 5 s, then the camera tracks again but
## the anchor (and every plane) stays paused; later the table is tracked
## again at the same height.
func _test_covered_camera_recovers_on_matching_plane() -> void:
	var host: GameHost = await _placed_fitting()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.finish_fit()
	_step(ar, 0.1)
	var board: Transform3D = _board(host)
	var old_id: int = fake.last_anchor_id()
	_set_camera(fake, 1)
	fake.anchor_states[old_id] = 1
	fake.planes = []
	_step(ar, 5.0)
	check("covered: the board is hidden and the player is told what to do", (
		not host.world_anchor.visible and ar.hud.status_label.text.contains("Tracking lost") and ar.hud.status_label.text.contains("slowly")
	))
	check("covered: after a while Re-place on table is offered (outline kept)", ar.hud.replace_keep_button.visible and ar.hud.status_label.text.contains("Re-place on table"))
	_set_camera(fake, 0)
	_step(ar, 1.0)
	check("uncovered, anchor still paused (planes 0/11): the board stays hidden, not shown at a stale pose", (
		not host.world_anchor.visible and ar.anchors.tracking != AnchorBackend.Tracking.TRACKING and ar.hud.status_label.text.contains("Re-finding the table")
	))
	fake.planes = _model_planes()
	_step(ar, 1.5)
	check("table tracked again at the same height: re-anchored on the matching plane, board back exactly where it was", (
		host.world_anchor.visible and ar.recoveries == 1 and ar.anchor_reason.begins_with("recovered on matching plane")
		and fake.last_anchor_id() != old_id and xform_near(_board(host), board, 0.002) and not ar.hud.replace_keep_button.visible
	))
	check("recovered: no re-tracing (still the fitted outline), surf ~0", (
		ar.region != null and ar.region.source == SurfaceRegion.Source.FITTED and absf(ar.measure_surface_gap()) < 0.002
	))
	await free_host(host)


func _test_replace_on_table_keeps_outline() -> void:
	var host: GameHost = await _placed_fitting()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.placement.scale = 0.85
	ar._apply_transforms()
	ar.finish_fit()
	ar.set_locked(true)
	_step(ar, 0.1)
	var area: float = ar.region.area()
	var yaw_world: float = atan2(-_board(host).basis.x.z, _board(host).basis.x.x)
	var shape_before: PackedVector2Array = _world_outline(ar)
	var centre_before := Vector2(_board(host).origin.x, _board(host).origin.z)
	# Lost for good: no plane ever matches again.
	fake.anchor_states[fake.last_anchor_id()] = 1
	fake.planes = []
	_step(ar, 4.5)
	check("lost for good: Re-place on table offered", ar.hud.replace_keep_button.visible)
	ar.replace_on_table()
	fake.planes = _model_planes()
	_look(Vector3(0.25, 0.6, 0.3), Vector3(0.2, PLY_HEIGHT, -0.62))
	await frames(4)
	check("re-place on table: back to finding the surface, Use my outline offered", (
		ar.flow.step == CalibrationFlow.Step.SURFACE_FOUND and ar.hud.use_area_button.visible and ar.hud.use_area_button.text == "Use my outline"
		and ar.hud.status_label.text.contains("Use my outline")
	))
	var calls: int = fake.anchor_calls.size()
	check("use my outline: places at once (no tracing) on a plane anchor", (
		ar.use_saved_area() and ar.is_placed() and fake.anchor_calls.size() == calls + 1 and fake.anchor_calls[fake.anchor_calls.size() - 1] == "screen"
		and ar.anchor_reason == "outline re-placed on table"
	))
	await frames(1)
	var shape_after: PackedVector2Array = _world_outline(ar)
	var centre_after := Vector2(_board(host).origin.x, _board(host).origin.z)
	var moved := PackedVector2Array()
	for p: Vector2 in shape_before:
		moved.append(p - centre_before + centre_after)
	check("use my outline: same fitted outline (shape, size, turn) around the new board spot, then Fit edges to nudge it", (
		absf(ar.region.area() - area) < 0.0005 and _same_polygon(moved, shape_after, 0.002) and ar.flow.step == CalibrationFlow.Step.FITTING
		and absf(ar.placement.scale - 0.85) < 0.0001 and absf(atan2(-_board(host).basis.x.z, _board(host).basis.x.x) - yaw_world) < 0.001
		and absf(_board(host).origin.y - PLY_HEIGHT) < 0.001
	))
	ar.begin_replace()
	_step(ar, 0.2)
	check("plain Re-place still reuses the outline where it was (same session)", not ar.flow.shape_pending)
	await free_host(host)


func _test_messages_and_low_light() -> void:
	check("message: too dark says to turn on a light", ARSession.loss_message(false, {"failure_reason": CalibrationFlow.FAILURE_INSUFFICIENT_LIGHT, "points": 10}, false).contains("Turn on a light"))
	check("message: few features adds 'More light helps'", ARSession.loss_message(true, {"points": 12}, false).ends_with("More light helps."))
	check("message: the offer names Re-place on table", ARSession.loss_message(true, {"points": 200}, true).contains("Re-place on table"))
	var host: GameHost = await _placed_fitting()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var info: Dictionary = fake.info.duplicate()
	info["points"] = 20
	fake.info = info
	_step(ar, 2.6)
	check("low light: with ~20 feature points for 2 s the Fit edges message adds the light hint", (
		ar.low_features and ar.hud.status_label.text.contains("more light")
	))
	ar.finish_fit()
	ar.set_locked(true)
	ar.low_features = false
	_step(ar, 2.6)
	check("low light while playing: the hint shows on the status banner", ar.hud.status_label.text == CalibrationFlow.LOW_LIGHT_HINT and ar.hud._banner.visible)
	info = info.duplicate()
	info["points"] = 150
	fake.info = info
	_step(ar, 0.5)
	check("low light: the hint goes away with enough feature points", not ar.low_features and not ar.hud._banner.visible)
	await free_host(host)


func _test_debug_overlay() -> void:
	var host: GameHost = await _placed_fitting()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var placed_at: Vector3 = ar.board_origin_point()
	var cloud := PackedVector3Array()
	for i: int in 9:
		cloud.append(Vector3(-0.08 + 0.02 * float(i), PLY_HEIGHT + 0.02, -0.62))
	fake.cloud = cloud
	ar.hud.toggle_debug()
	_step(ar, 0.3)
	check("debug overlay: shown while placed with the debug line", ar.debug_overlay_visible())
	var points: MultiMeshInstance3D = ar.get_node(^"AnchorDebug/FeaturePoints") as MultiMeshInstance3D
	var anchor_cross: Node3D = ar.get_node(^"AnchorDebug/AnchorCross") as Node3D
	check("debug overlay: ARCore feature points, a cross at the anchor and a fixed world cross where the board was placed", (
		points.multimesh.instance_count == 9 and near(anchor_cross.global_position, ar.world_anchor.global_position, 0.0005)
		and near(ar.world_marker_point(), placed_at, 0.0005)
	))
	var debug: String = ar.debug_suffix()
	check("debug: feature points on the play area sit 2 cm over ARCore's plane (%s)" % debug, debug.contains("feat +2.0cm n9"))
	var id: int = fake.last_anchor_id()
	fake.anchor_shift[id] = Transform3D(Basis(), Vector3(0.02, 0.0, 0.0))
	_step(ar, 0.3)
	check("debug overlay: the world cross never moves with the anchor (shows world vs anchor drift)", (
		near(ar.world_marker_point(), placed_at, 0.0005) and near(anchor_cross.global_position, ar.world_anchor.global_position, 0.0005)
	))
	ar.hud.toggle_debug()
	_step(ar, 0.3)
	check("debug overlay: hidden with the debug line", not ar.debug_overlay_visible())
	fake.cloud = PackedVector3Array()
	await free_host(host)
