extends LGTestSuite
## Headless tests for the platform AR layer (no device, no ARCore), ported
## from Competitive Evolution AGR's ar_tests and generalized to game boards.
## Run: godot --headless --path . res://tests/ar_tests.tscn


func run_tests() -> void:
	_test_mode_selection()
	await _test_fallback_host()
	await _test_board_local_invariance()
	_test_anchor_service()
	_test_cloud_anchor_stub()
	_test_placement()
	_test_gestures()
	_test_calibration_flow()
	_test_front_pose_and_surface_mesh()
	await _test_ar_calibration_session()


# --- Fallback -----------------------------------------------------------------

func _test_mode_selection() -> void:
	check("no ARCore XR interface is registered headless", XRServer.find_interface(ARCoreBridge.INTERFACE_NAME) == null)
	check("ARCore plugin is absent headless", not ARCoreBridge.plugin_present())
	check("camera permission counts as granted off Android", ARCoreBridge.camera_permission_granted())
	check("no plugin and no interface selects the fallback", ARSession.choose_mode(false, null) == ARSession.Mode.FALLBACK)
	check("plugin without an XR interface still selects the fallback", ARSession.choose_mode(true, null) == ARSession.Mode.FALLBACK)
	check("plugin plus an XR interface selects AR", ARSession.choose_mode(true, XRInterfaceExtension.new()) == ARSession.Mode.AR)
	var bridge := ARCoreBridge.new()
	check("ARCoreBridge.start refuses cleanly without the plugin", (
		not bridge.start(get_viewport()) and not bridge.failure_reason.is_empty() and not get_viewport().use_xr
	))
	var reason: Array = []
	check("ARCoreBridge.acquire returns null with a reason without the plugin", (
		ARCoreBridge.acquire(get_viewport(), reason) == null and reason.size() == 1 and not get_viewport().use_xr
	))


func _test_fallback_host() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	check("fallback: the host creates an AR session", ar != null)
	check("fallback: the session is in FALLBACK mode with a reason", (
		ar.mode == ARSession.Mode.FALLBACK and not ar.fallback_reason.is_empty()
	))
	check("fallback: the orbit camera is the current camera", (
		host.orbit_camera.camera.current and get_viewport().get_camera_3d() == host.orbit_camera.camera
		and ar.active_camera() == host.orbit_camera.camera
	))
	check("fallback: viewport does not render XR", not get_viewport().use_xr)
	check("fallback: no XROrigin3D / XRCamera3D / calibration HUD is created", (
		host.find_children("*", "XROrigin3D", true, false).is_empty()
		and host.find_children("*", "XRCamera3D", true, false).is_empty()
		and ar.hud == null
	))
	check("fallback: AR never captures touch", not ar.captures_touch())
	check("fallback: anchor and pivot are identity", (
		xform_near(host.world_anchor.global_transform, Transform3D.IDENTITY)
		and xform_near(host.pivot.transform, Transform3D.IDENTITY)
	))
	check("fallback: an identity local anchor is in place and the board counts as locked", (
		ar.anchors.has_anchor() and ar.is_placed() and ar.is_board_locked()
	))
	check("fallback: the adjust outline stays hidden", not host.board_frame.visible)
	await free_host(host)


# --- Board-local space ----------------------------------------------------------

func _test_board_local_invariance() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var before: Array[Transform3D] = []
	for tile: MeshInstance3D in game.tiles:
		before.append(tile.transform)
	var ar: ARSession = host.session
	ar.apply_anchor_pose(Transform3D(Basis(Vector3.UP, 0.8), Vector3(1.2, 0.74, -0.6)))
	ar.placement = BoardPlacement.new()
	ar.placement.scale = 0.37
	ar.placement.yaw = 1.1
	ar.placement.offset = Vector3(0.05, 0.0, -0.03)
	ar.placement.magnify = 2.5
	host.pivot.transform = ar.placement.pivot_transform()
	await frames(2)
	var unchanged: bool = true
	for i: int in game.tiles.size():
		unchanged = unchanged and xform_near(game.tiles[i].transform, before[i])
	check("board: game-local transforms are unchanged by anchor pose and scale", unchanged)
	check("board: the pivot really moved and scaled in the world", (
		not near(game.global_position, Vector3.ZERO, 0.01)
		and is_equal_approx(host.pivot.global_transform.basis.get_scale().x, 0.37 * 2.5)
	))
	var round_trip: bool = true
	for index: int in 9:
		var world: Vector3 = game.to_global(TicTacToeGame.cell_center(index))
		var local: Vector3 = game.to_local(world)
		round_trip = round_trip and near(local, TicTacToeGame.cell_center(index), 0.0005)
	check("board: world points convert back to board space", round_trip)
	await free_host(host)


# --- AnchorService ------------------------------------------------------------

func _test_anchor_service() -> void:
	var backend := LocalAnchorBackend.new()
	var service := AnchorService.new(backend)
	var placed: Array[int] = []
	service.anchor_placed.connect(func(id: int, _pose: Transform3D) -> void: placed.append(id))
	var tilted := Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.3), Vector3(0.2, 0.9, -1.0))
	check("anchor: place_at_pose creates an anchor", service.place_at_pose(tilted) and service.has_anchor())
	check("anchor: placement emits anchor_placed", placed == [service.anchor_id])
	var level: Transform3D = service.pose
	check("anchor: the pose is kept upright (yaw only)", (
		near(level.basis.y, Vector3.UP) and near(level.origin, tilted.origin)
		and is_equal_approx(AnchorService.upright(Transform3D(Basis(Vector3.UP, 0.5), Vector3.ZERO)).basis.get_euler().y, 0.5)
	))
	backend.set_pose(service.anchor_id, Transform3D(Basis.IDENTITY, Vector3(0.25, 0.9, -1.0)))
	check("anchor: poll follows ARCore refining the anchor", near(service.poll().origin, Vector3(0.25, 0.9, -1.0)))
	var states: Array[int] = []
	service.tracking_changed.connect(func(state: int) -> void: states.append(state))
	backend.remove_anchor(service.anchor_id)
	service.poll()
	check("anchor: losing the anchor reports a tracking change and keeps the last pose", (
		states == [AnchorBackend.Tracking.UNKNOWN] and near(service.pose.origin, Vector3(0.25, 0.9, -1.0))
	))
	service.clear()
	check("anchor: clear drops the anchor", not service.has_anchor() and service.cloud_anchor_id.is_empty())
	backend.screen_anchor_pose = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, -0.5))
	check("anchor: place_at_screen anchors on the surface under the reticle", (
		service.place_at_screen(Vector2(0.5, 0.5)) and near(service.pose.origin, Vector3(0.0, 0.8, -0.5))
	))


func _test_cloud_anchor_stub() -> void:
	var host := AnchorService.new(LocalAnchorBackend.new())
	check("cloud: host_anchor without an anchor fails", not host.host_anchor() and host.cloud_state == AnchorService.CloudState.FAILED)
	host.place_at_pose(Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.3, 0.75, -0.8)))
	var hosted: Array[String] = []
	host.cloud_anchor_hosted.connect(func(id: String) -> void: hosted.append(id))
	check("cloud: host_anchor fills the Cloud Anchor ID field", (
		host.host_anchor() and not host.cloud_anchor_id.is_empty()
		and host.cloud_state == AnchorService.CloudState.HOSTED and hosted == [host.cloud_anchor_id]
	))
	var guest := AnchorService.new(LocalAnchorBackend.new())
	check("cloud: another phone resolves the same anchor pose by ID", (
		guest.resolve_anchor(host.cloud_anchor_id)
		and guest.cloud_state == AnchorService.CloudState.RESOLVED
		and xform_near(guest.pose, host.pose)
	))
	check("cloud: resolving an unknown ID fails", not guest.resolve_anchor("missing-id"))
	var arcore_like := LocalAnchorBackend.new()
	arcore_like.cloud_enabled = false
	var offline := AnchorService.new(arcore_like)
	offline.place_at_pose(Transform3D.IDENTITY)
	var offline_reasons: Array[String] = []
	offline.cloud_anchor_failed.connect(func(reason: String) -> void: offline_reasons.append(reason))
	check("cloud: a backend without Cloud Anchors fails host_anchor with a reason", (
		not offline.host_anchor() and offline_reasons.size() == 1 and offline.cloud_anchor_id.is_empty()
	))
	check("cloud: the real ARCore backend reports Cloud Anchors as not wired yet", not ARCoreAnchorBackend.new(ARCoreBridge.new()).supports_cloud())
	var placement := BoardPlacement.new()
	placement.scale = 0.8
	var payload: Dictionary = host.share_payload(placement)
	check("cloud: the share payload is the anchor ID plus anchor-relative placement only", (
		payload.get("cloud_anchor_id") == host.cloud_anchor_id
		and is_equal_approx(float((payload["placement"] as Dictionary)["scale"]), 0.8)
		and payload.size() == 2
	))


# --- Placement ------------------------------------------------------------------

func _test_placement() -> void:
	var placement := BoardPlacement.new()
	check("placement: a new board starts at its real size (scale 1)", placement.scale == 1.0)
	placement.offset = Vector3(0.1, 0.0, 0.2)
	placement.yaw = 0.5
	placement.scale = 0.5
	var pivot: Transform3D = placement.pivot_transform()
	check("placement: pivot = offset, yaw, scale relative to the anchor", (
		near(pivot.origin, Vector3(0.1, 0.0, 0.2))
		and is_equal_approx(pivot.basis.get_scale().x, 0.5)
		and is_equal_approx(pivot.basis.get_euler().y, 0.5)
	))
	placement.magnify = 2.0
	check("placement: magnify scales about the anchor (anchor point stays put)", (
		near(placement.pivot_transform() * Vector3.ZERO, Vector3(0.2, 0.0, 0.4))
		and is_equal_approx(placement.total_scale(), 1.0)
	))
	placement.recenter()
	check("placement: recenter returns to the anchor and keeps scale/rotation", (
		near(placement.offset, Vector3.ZERO) and placement.magnify == 1.0
		and placement.scale == 0.5 and placement.yaw == 0.5
	))
	check("placement: unlocked drag moves on the plane only", (
		placement.drag(Vector3(0.1, 0.3, 0.0)) and near(placement.offset, Vector3(0.1, 0.0, 0.0))
	))
	check("placement: pinch scale is clamped", placement.pinch(100.0) and placement.scale == BoardPlacement.MAX_SCALE)
	placement.locked = true
	var snapshot: Dictionary = placement.to_dict()
	check("placement: locked ignores drag, pinch and twist", (
		not placement.drag(Vector3.ONE) and not placement.pinch(0.5) and not placement.twist(1.0)
		and placement.to_dict() == snapshot
	))
	placement.magnify_by(3.0)
	check("placement: magnify still works while locked", is_equal_approx(placement.magnify, 3.0))
	var path: String = "user://lg_placement_test.cfg"
	placement.save(path)
	var restored := BoardPlacement.new()
	check("placement: scale/rotation/offset/lock persist; magnify does not", (
		restored.load_from(path) and restored.to_dict() == snapshot and restored.magnify == 1.0
	))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Gestures -------------------------------------------------------------------

func _test_gestures() -> void:
	var tracker := GestureTracker.new()
	tracker.handle(touch(0, Vector2(100, 100), true))
	var tap: Dictionary = tracker.handle(touch(0, Vector2(102, 101), false))
	check("gesture: a short touch is a tap", tap.get("kind") == &"tap")
	tracker.handle(touch(0, Vector2(100, 100), true))
	var moved: Dictionary = tracker.handle(drag(0, Vector2(160, 100), Vector2(60, 0)))
	var after_drag: Dictionary = tracker.handle(touch(0, Vector2(160, 100), false))
	check("gesture: one-finger movement is a drag, not a tap", (
		moved.get("kind") == &"drag" and is_equal_approx((moved["to"] as Vector2).x, 160.0)
		and after_drag.is_empty()
	))
	tracker.handle(touch(0, Vector2(100, 100), true))
	tracker.handle(touch(1, Vector2(200, 100), true))
	var pinch: Dictionary = tracker.handle(drag(1, Vector2(300, 100), Vector2(100, 0)))
	check("gesture: spreading two fingers is a 2x pinch", (
		pinch.get("kind") == &"pinch" and is_equal_approx(float(pinch["scale"]), 2.0)
	))
	var twist: Dictionary = tracker.handle(drag(1, Vector2(100, 300), Vector2(-200, 200)))
	check("gesture: rotating the second finger 90 degrees clockwise is a +90 twist", (
		twist.get("kind") == &"pinch" and is_equal_approx(float(twist["twist"]), PI * 0.5)
	))


# --- Calibration --------------------------------------------------------------

func _test_calibration_flow() -> void:
	var flow := CalibrationFlow.new()
	check("calibration: starts scanning with no place button", (
		flow.step == CalibrationFlow.Step.SCANNING and not bool(flow.controls()["place"])
		and bool(flow.controls()["sweep_hint"]) and flow.is_calibrating()
	))
	check("calibration: the game is paused while scanning", not flow.should_run_game())
	var tracking: Dictionary = {"camera_state": 0, "frames": 10, "points": 4}
	flow.update(5.0, tracking, false)
	check("calibration: few feature points ask the player to sweep", flow.message().begins_with("Sweep the phone"))
	check("calibration: no fallback offer before the timeout", not flow.offers_fallback())
	check("calibration: tracking failures read as plain English", (
		CalibrationFlow.tracking_message({"camera_state": 1, "frames": 5, "failure_reason": 2}).contains("too dark")
		and CalibrationFlow.tracking_message({"camera_state": 1, "frames": 5, "failure_reason": 3}).contains("too fast")
		and CalibrationFlow.tracking_message({"camera_state": 1, "frames": 5, "failure_reason": 4}).contains("not enough detail")
		and CalibrationFlow.tracking_message({}).begins_with("Starting the camera")
	))
	flow.update(CalibrationFlow.FALLBACK_OFFER_SECONDS, tracking, false)
	check("calibration: after the timeout, Place in front of me / Play without AR are offered", (
		flow.offers_fallback() and bool(flow.controls()["place_in_front"]) and bool(flow.controls()["play_without_ar"])
	))
	flow.update(0.1, tracking, true)
	check("calibration: a surface shows the Place board button", (
		flow.step == CalibrationFlow.Step.SURFACE_FOUND and bool(flow.controls()["place"])
		and not flow.offers_fallback()
	))
	flow.set_locked(true)
	check("calibration: lock is ignored before the board is placed", flow.step == CalibrationFlow.Step.SURFACE_FOUND)
	flow.placed()
	check("calibration: placing moves to adjust (Lock + Re-place, still paused)", (
		flow.step == CalibrationFlow.Step.ADJUSTING and bool(flow.controls()["lock"])
		and bool(flow.controls()["replace"]) and not flow.should_run_game()
	))
	flow.set_locked(true)
	check("calibration: locking starts play", (
		flow.step == CalibrationFlow.Step.LOCKED and flow.should_run_game() and not flow.is_calibrating()
		and bool(flow.controls()["unlock"])
	))
	flow.set_locked(false)
	check("calibration: unlocking returns to adjust and pauses", (
		flow.step == CalibrationFlow.Step.ADJUSTING and not flow.should_run_game()
	))
	flow.restart()
	check("calibration: re-place restarts scanning", flow.step == CalibrationFlow.Step.SCANNING and flow.scan_seconds == 0.0)
	var track := CalibrationFlow.new()
	track.observe(0.6, {"camera_state": 0, "frames": 3})
	track.observe(0.6, {"camera_state": 1, "frames": 4})
	track.observe(0.6, {"camera_state": 0, "frames": 5})
	check("calibration: a tracking dropout resets the stable-tracking timer", not track.tracking_stable())
	track.observe(0.5, {"camera_state": 0, "frames": 6})
	check("calibration: a second of continuous tracking counts as stable", track.tracking_stable())
	var line: String = CalibrationFlow.debug_line({
		"initialized": true, "is_primary": true, "use_xr": true, "resume_status": 0, "configure_status": 0,
		"update_status": 0, "frames": 120, "update_errors": 0, "camera_state": 1, "failure_reason": 4,
		"tracking_frames": 0, "timestamp_changes": 118, "points": 0, "point_cloud_status": 0,
		"upward_planes": 0, "planes_any_state": 0, "texture_id": 7, "debuggable": true, "arcore_version": "1.53",
		"camera_texture": Vector2i(640, 480),
	})
	check("calibration: the debug line names every pipeline stage", (
		line.contains("init Y") and line.contains("primary Y") and line.contains("resume 0")
		and line.contains("update 0 (120 ok / 0 err)") and line.contains("cam PAUSED/few features")
		and line.contains("new frames 118") and line.contains("pts 0") and line.contains("debuggable Y")
		and line.contains("ARCore 1.53") and line.contains("camtex 640x480")
	))
	check("calibration: the debug line copes with an unpatched plugin", CalibrationFlow.debug_line({}).contains("no data"))


func _test_front_pose_and_surface_mesh() -> void:
	var camera := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(0.0, 1.4, 0.0))
	var pose: Transform3D = ARSession.front_pose(camera)
	check("place in front: 0.6 m ahead and below the camera, level", (
		near(pose.origin, Vector3(0.0, 1.4 - ARSession.FRONT_PLACE_DROP, -ARSession.FRONT_PLACE_DISTANCE), 0.001)
		and near(pose.basis.y, Vector3.UP, 0.001) and near(-pose.basis.z, Vector3.FORWARD, 0.001)
	))
	var straight_down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(0.0, 1.0, 0.0))
	check("place in front: still level when the phone points straight down", near(ARSession.front_pose(straight_down).basis.y, Vector3.UP, 0.001))
	var square := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var mesh: ArrayMesh = ARSession.plane_mesh(square)
	check("surface overlay: a plane polygon becomes a triangle fan", mesh != null and mesh.surface_get_array_len(0) == 12)
	check("surface overlay: degenerate polygons are skipped", ARSession.plane_mesh(PackedVector2Array([Vector2.ZERO, Vector2.ONE])) == null)


# --- Full AR calibration through a host -------------------------------------------

func _test_ar_calibration_session() -> void:
	var fake := FakeARBridge.new()
	var host: GameHost = await make_host(&"tic_tac_toe", fake)
	var ar: ARSession = host.session
	var game: LGGame = host.game
	check("ar calibration: AR starts through the injected bridge", ar.is_ar() and ar.hud != null and ar.xr_camera != null)
	check("ar calibration: the game is loaded but not playing while calibrating", (
		game != null and not game.is_playing() and not game.is_board_locked()
	))
	check("ar calibration: the board is hidden until placed", not host.world_anchor.visible)
	await get_tree().create_timer(0.25).timeout
	check("ar calibration: scanning shows the sweep hint and live stats", (
		ar.flow.step == CalibrationFlow.Step.SCANNING and ar.hud.sweep_hint.visible
		and ar.hud.stats_label.text.contains("64")
	))
	check("ar calibration: the debug line is hidden until asked for", (
		not ar.hud.debug_requested and not ar.hud.register_panel_tap(0.0)
	))
	for i: int in 4:
		ar.hud.register_panel_tap(0.1 * float(i + 1))
	check("ar calibration: five taps on the step panel toggle the debug line", ar.hud.debug_requested)
	for i: int in 5:
		ar.hud.register_panel_tap(5.0 + 0.1 * float(i))
	check("ar calibration: five more taps hide it again", not ar.hud.debug_requested)
	ar.flow.scan_seconds = CalibrationFlow.FALLBACK_OFFER_SECONDS + 1.0
	await frames(2)
	check("ar calibration: the fallback buttons appear after the timeout", (
		ar.hud.place_in_front_button.visible and ar.hud.play_without_ar_button.visible
	))
	fake.info = {"camera_state": 1, "failure_reason": 0, "frames": 30, "points": 0}
	await get_tree().create_timer(0.3).timeout
	check("ar calibration: place in front works before tracking, held camera-relative", (
		ar.place_in_front() and ar.is_placed() and ar.front_follow and fake.anchors_made == 0
		and ar.flow.anchor_pending and ar.hud.status_label.text.begins_with("Holding the board")
	))
	ar.xr_camera.position = Vector3(0.4, 0.0, 0.0)
	await frames(2)
	check("ar calibration: the camera-held board follows the camera instead of sliding away", (
		absf(host.world_anchor.global_position.x - 0.4) < 0.01
		and absf(host.world_anchor.global_position.z + ARSession.FRONT_PLACE_DISTANCE) < 0.01
	))
	fake.info = {"camera_state": 0, "failure_reason": 0, "frames": 30, "points": 64}
	await get_tree().create_timer(0.5).timeout
	check("ar calibration: brief tracking is not trusted for the anchor yet", ar.front_follow and fake.anchors_made == 0)
	await get_tree().create_timer(1.0).timeout
	check("ar calibration: stable tracking converts the held board to a world anchor", (
		not ar.front_follow and fake.anchors_made == 1 and not ar.flow.anchor_pending
	))
	var anchored_at: Vector3 = host.world_anchor.global_position
	ar.xr_camera.position = Vector3(-0.5, 0.0, 0.3)
	await frames(2)
	check("ar calibration: once anchored the board stays put when the camera moves", near(host.world_anchor.global_position, anchored_at, 0.001))
	check("ar calibration: the debug line reports the tracking diagnostics", (
		ar.hud.debug_label.text.contains("cam TRACKING") and ar.hud.debug_label.text.contains("pts 64")
	))
	check("ar calibration: adjusting keeps the game paused, shows Lock and the footprint outline", (
		ar.flow.step == CalibrationFlow.Step.ADJUSTING and not game.is_playing()
		and ar.hud.lock_button.visible and host.board_frame.visible
	))
	ar.set_locked(true)
	await frames(1)
	check("ar calibration: locking starts the game and hides the outline", (
		game.is_playing() and game.is_board_locked() and not host.board_frame.visible
		and not ar.hud.lock_button.visible and ar.hud.unlock_button.visible
	))
	ar.begin_replace()
	check("ar calibration: re-place pauses the game again and restarts scanning", (
		not game.is_playing() and ar.flow.step == CalibrationFlow.Step.SCANNING and not ar.is_placed()
		and not host.world_anchor.visible
	))
	fake.surface_found = true
	await frames(2)
	check("ar calibration: a found surface shows the reticle and Place board", (
		ar.flow.step == CalibrationFlow.Step.SURFACE_FOUND and ar.hud.place_button.visible and ar.reticle.visible
	))
	check("ar calibration: Place board anchors on the surface", ar.place_at_reticle() and ar.is_placed())
	check("ar placement: the board lives in world space, not under the AR camera or origin", (
		not ar.xr_camera.is_ancestor_of(host.world_anchor) and not ar.xr_origin.is_ancestor_of(host.world_anchor)
		and not ar.xr_camera.is_ancestor_of(game)
	))
	check("ar placement: the anchor sits exactly at the hit pose", near(host.world_anchor.global_position, fake.surface_pose.origin, 0.001))
	check("ar placement: the game's board plane rests on the surface", absf(game.global_position.y - fake.surface_pose.origin.y) < 0.001)
	ar.set_locked(true)
	var locked_anchor: Transform3D = host.world_anchor.global_transform
	var locked_game: Transform3D = game.global_transform
	ar.xr_camera.transform = Transform3D(Basis(Vector3.UP, 0.9), Vector3(0.6, 0.2, 0.4))
	await frames(3)
	check("ar placement: after lock, moving the AR camera does not move the board", (
		xform_near(host.world_anchor.global_transform, locked_anchor, 0.0001)
		and xform_near(game.global_transform, locked_game, 0.0001)
	))
	check("ar placement: the AR camera stays the current camera after lock", get_viewport().get_camera_3d() == ar.xr_camera)
	ar.fall_back("Player chose to play without AR.")
	await frames(1)
	check("ar calibration: Play without AR keeps the game playing in the touch view", (
		not ar.is_ar() and game.is_playing() and host.orbit_camera.camera.current
		and not get_viewport().use_xr and fake.release_count == 1
	))
	check("ar calibration: the board is centred at the origin again outside AR", (
		xform_near(host.world_anchor.global_transform, Transform3D.IDENTITY)
	))
	await free_host(host)
