extends "res://tests/surface_tests.gd"
## Anchoring regressions from the coffee-table run of lg-test-d206a6e, where
## the board, after Lock, read "anc T free d 0.0/646.6mm lock 647mm
## surf -12.9cm lost 1": the lock had swapped the plane anchor for a free
## one, ARCore relocalized that free anchor 65 cm away (13 cm under the
## table) after a tracking loss, and the board followed it.
## Covers: plane-attached re-anchoring at Lock (with yaw / scale / drag and a
## hit pose turned like ARCore's), the free fallback and its later upgrade,
## the jump guard (bogus jumps rejected, real world shifts accepted, jumps
## that undo themselves), the plane-height guard, and the debug readout.
## Reuses the plywood scene model of surface_tests.gd.
## Run: godot --headless --path . res://tests/anchor_tests.tscn

const STEP: float = 1.0 / 60.0
## ARCore's plane hit poses are not aligned with the board: turn them.
const HIT_YAW: float = 0.7
var hit_yaw: float = 0.0
var hits_off: bool = false


func run_tests() -> void:
	ARSession.clear_saved_area()
	await _test_lock_makes_plane_anchor()
	await _test_lock_without_plane_falls_back_then_upgrades()
	await _test_field_relocalization_jump_is_rejected()
	await _test_world_shift_is_accepted()
	await _test_jump_that_undoes_itself()
	await _test_sinking_board_is_put_back_on_the_plane()
	await _test_board_above_plane_is_left_alone()
	await _test_jump_snapped_to_plane()
	ARSession.clear_saved_area()


func _hit(normalized: Vector2) -> Dictionary:
	if hits_off:
		return {"hit": false}
	var hit: Dictionary = _model_hit(normalized)
	if bool(hit.get("hit", false)):
		var pose: Transform3D = hit["pose"] as Transform3D
		hit["pose"] = Transform3D(Basis(Vector3.UP, hit_yaw), pose.origin)
	return hit


func _host() -> GameHost:
	hit_yaw = 0.0
	hits_off = false
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	(host.session.bridge as FakeARBridge).hit_callback = _hit
	return host


## Place on the plywood at the reticle and lock right there.
func _locked_host() -> GameHost:
	var host: GameHost = await _host()
	var ar: ARSession = host.session
	ar.place_at_reticle()
	ar.finish_fit()
	await frames(1)
	ar.set_locked(true)
	await frames(1)
	return host


func _step(ar: ARSession, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		ar._process(STEP)
		t += STEP


func _set_camera(fake: FakeARBridge, state: int) -> void:
	var info: Dictionary = fake.info.duplicate()
	info["camera_state"] = state
	fake.info = info


func _board(host: GameHost) -> Transform3D:
	return host.game.global_transform


func _play_area(ar: ARSession) -> PackedVector2Array:
	return ar.play_area_world()


func _same_polygon(a: PackedVector2Array, b: PackedVector2Array, tolerance: float) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i: int in a.size():
		if a[i].distance_to(b[i]) > tolerance:
			return false
	return true


func _test_lock_makes_plane_anchor() -> void:
	var host: GameHost = await _host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.place_at_reticle()
	await frames(1)
	check("setup: placed with a plane anchor from the reticle", ar.anchor_kind == "plane" and ar.anchor_reason == "reticle")
	# Turn, shrink and drag the board, the way Fit edges / the player do.
	ar.placement.yaw = 0.45
	ar.placement.scale = 0.8
	ar.placement.offset = Vector3(0.11, 0.0, -0.06)
	ar._apply_transforms()
	ar.finish_fit()
	await frames(1)
	var before: Transform3D = _board(host)
	var area_before: PackedVector2Array = _play_area(ar)
	var calls: int = fake.anchor_calls.size()
	hit_yaw = HIT_YAW
	ar.set_locked(true)
	await frames(1)
	var after: Transform3D = _board(host)
	var anchor: Vector3 = ar.anchors.pose.origin
	check("lock: a NEW plane-attached anchor (hit test) is made under the board", (
		fake.anchor_calls.size() == calls + 1 and fake.anchor_calls[fake.anchor_calls.size() - 1] == "screen"
		and ar.anchor_kind == "plane" and ar.anchor_reason == "lock: plane under board"
	))
	check("lock: the board does not move or turn or rescale (scale 0.8, yaw 0.45, 13 cm drag, hit pose turned 0.7 rad)", xform_near(after, before, 0.0005))
	check("lock: the anchor sits at the plane's height under the board centre", (
		absf(anchor.y - PLY_HEIGHT) < 0.0005 and Vector2(anchor.x - before.origin.x, anchor.z - before.origin.z).length() <= ARSession.LOCK_ANCHOR_REACH
	))
	check("lock: the board base is on the plane (surf ~0) and the play area stays where it was", (
		absf(ar.measure_surface_gap()) < 0.001 and _same_polygon(area_before, _play_area(ar), 0.001)
	))
	check("lock: the board sat on a detected plane at Lock", ar.locked_on_plane)
	_step(ar, 0.25)
	var debug: String = ar.debug_suffix()
	check("debug: anchor kind + reason, anchor vs board position, plane id/height (%s)" % debug, (
		debug.contains("anc T plane (lock: plane under board)") and debug.contains("anchor ") and debug.contains("board ")
		and debug.contains("pl#0 h0.12") and debug.contains("surf +0.0cm") and debug.contains("lock 0mm")
	))
	await free_host(host)


func _test_lock_without_plane_falls_back_then_upgrades() -> void:
	var host: GameHost = await _host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.place_at_reticle()
	ar.placement.offset = Vector3(0.08, 0.0, 0.0)
	ar._apply_transforms()
	ar.finish_fit()
	await frames(1)
	var before: Transform3D = _board(host)
	hits_off = true
	ar.set_locked(true)
	await frames(1)
	check("lock without a plane hit: falls back to a free anchor at the board, says why, board unmoved", (
		ar.anchor_kind == "free" and ar.anchor_reason.contains("no plane") and fake.anchor_calls[fake.anchor_calls.size() - 1] == "pose"
		and xform_near(_board(host), before, 0.0005)
	))
	hits_off = false
	_step(ar, 1.3)
	check("locked on a free anchor: moved onto a plane anchor as soon as the plane is hit (board unmoved)", (
		ar.anchor_kind == "plane" and ar.plane_upgrades == 1 and ar.anchor_reason.contains("upgraded")
		and fake.anchor_calls[fake.anchor_calls.size() - 1] == "screen" and xform_near(_board(host), before, 0.0005)
	))
	await free_host(host)


## The field case: tracking lost, then the anchor comes back 65 cm away and
## 13 cm low while the table (planes) has not moved.
func _test_field_relocalization_jump_is_rejected() -> void:
	var host: GameHost = await _locked_host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var locked: Transform3D = _board(host)
	var old_id: int = fake.last_anchor_id()
	_set_camera(fake, 1)
	_step(ar, 0.8)
	check("relocalization: the board is hidden while tracking is lost", not host.world_anchor.visible and ar.tracking_losses == 1)
	var jump := Vector3(0.40, -0.13, 0.49)
	fake.anchor_shift[old_id] = Transform3D(Basis(Vector3.UP, 0.05), jump)
	check("relocalization: the simulated jump matches the field reading (~647 mm)", absf(jump.length() * 1000.0 - 646.0) < 5.0)
	_set_camera(fake, 0)
	_step(ar, 0.3)
	var debug_held: String = ar.debug_suffix()
	check("relocalization: the 65 cm jump is held back, the board stays put (%s)" % debug_held, (
		host.world_anchor.visible and ar.jump_holding and xform_near(_board(host), locked, 0.0005) and debug_held.contains("jump held")
	))
	_step(ar, 0.6)
	check("relocalization: with the table still under the board, the jump is rejected and the board re-anchored on the plane", (
		not ar.jump_holding and ar.jumps_rejected == 1 and ar.anchor_kind == "plane"
		and fake.last_anchor_id() != old_id and fake.anchor_calls[fake.anchor_calls.size() - 1] == "screen"
	))
	_step(ar, 1.0)
	var debug: String = ar.debug_suffix()
	check("relocalization: the board never left the table: lock ~0 mm, surf ~0 (%s)" % debug, (
		xform_near(_board(host), locked, 0.001) and ar.drift_since_lock_mm < 2.0 and absf(ar.surface_gap) < 0.002
		and debug.contains("rej1") and debug.contains("surf +0.0cm") and debug.contains("lost 1")
	))
	await free_host(host)


## A real world shift (ARCore re-aligning everything, planes included) is
## followed: only the new spot is on a plane.
func _test_world_shift_is_accepted() -> void:
	var host: GameHost = await _locked_host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var locked: Transform3D = _board(host)
	var calls: int = fake.anchor_calls.size()
	var shift := Transform3D(Basis(), Vector3(0.25, -0.13, 0.1))
	fake.pose_shift = shift
	var moved: Array = []
	for plane: Variant in _model_planes():
		var entry: Dictionary = (plane as Dictionary).duplicate()
		entry["pose"] = shift * (entry["pose"] as Transform3D)
		moved.append(entry)
	fake.planes = moved
	_step(ar, 0.2)
	check("world shift: held at first like any big jump", ar.jump_holding and xform_near(_board(host), locked, 0.0005))
	_step(ar, 1.5)
	check("world shift: accepted (planes moved with the anchor), board follows onto the moved table, no re-anchoring", (
		not ar.jump_holding and ar.jumps_accepted == 1 and ar.jumps_rejected == 0 and fake.anchor_calls.size() == calls
		and near(_board(host).origin, shift * locked.origin, 0.002) and absf(ar.measure_surface_gap()) < 0.002
	))
	fake.pose_shift = Transform3D.IDENTITY
	await free_host(host)


func _test_jump_that_undoes_itself() -> void:
	var host: GameHost = await _locked_host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var locked: Transform3D = _board(host)
	var calls: int = fake.anchor_calls.size()
	fake.anchor_shift[fake.last_anchor_id()] = Transform3D(Basis(), Vector3(0.5, 0.0, 0.0))
	_step(ar, 0.2)
	var held: bool = ar.jump_holding and xform_near(_board(host), locked, 0.0005)
	fake.anchor_shift.clear()
	_step(ar, 0.5)
	check("glitch: a jump that comes back by itself is never shown and changes nothing", (
		held and not ar.jump_holding and xform_near(_board(host), locked, 0.0005) and fake.anchor_calls.size() == calls
		and ar.jumps_rejected == 0 and ar.jumps_accepted == 0
	))
	fake.anchor_shift[fake.last_anchor_id()] = Transform3D(Basis(), Vector3(0.02, 0.0, 0.0))
	_step(ar, 0.05)
	check("small ARCore corrections (2 cm) still apply at once", (
		not ar.jump_holding and near(_board(host).origin, locked.origin + Vector3(0.02, 0.0, 0.0), 0.0005)
	))
	await free_host(host)


## The anchor slowly sinks 13 cm below the table (each step small enough to
## pass the jump guard): the height guard puts the board back on the plane.
func _test_sinking_board_is_put_back_on_the_plane() -> void:
	var host: GameHost = await _locked_host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var locked: Transform3D = _board(host)
	var id: int = fake.last_anchor_id()
	for i: int in 13:
		fake.anchor_shift[id] = Transform3D(Basis(), Vector3(0.0, -0.01 * float(i + 1), 0.0))
		_step(ar, 0.05)
	_step(ar, 0.3)
	check("sinking: the board is shown 13 cm under the table for a moment (surf -13cm)", absf(ar.surface_gap + 0.13) < 0.005 and ar.height_fixes == 0)
	_step(ar, 2.0)
	check("sinking: after a sustained gap the board is re-anchored onto the plane (surf ~0, same x/z)", (
		ar.height_fixes == 1 and absf(ar.measure_surface_gap()) < 0.002 and absf(_board(host).origin.y - PLY_HEIGHT) < 0.002
		and Vector2(_board(host).origin.x - locked.origin.x, _board(host).origin.z - locked.origin.z).length() < 0.002
		and ar.anchor_kind == "plane" and ar.anchor_reason.contains("height fixed")
	))
	await free_host(host)


## A board deliberately standing 15 cm over the detected plane at Lock (an
## object ARCore did not map) is not pulled down.
func _test_board_above_plane_is_left_alone() -> void:
	var host: GameHost = await _host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.place_at_reticle()
	ar.finish_fit()
	fake.anchor_shift[fake.last_anchor_id()] = Transform3D(Basis(), Vector3(0.0, 0.15, 0.0))
	ar.anchors.poll()
	ar._apply_transforms()
	await frames(1)
	ar.set_locked(true)
	var y: float = _board(host).origin.y
	_step(ar, 2.5)
	check("not on a plane at Lock: the board is not snapped to the plane below", (
		not ar.locked_on_plane and ar.height_fixes == 0 and absf(_board(host).origin.y - y) < 0.001
	))
	await free_host(host)


## Neither the old nor the new spot sits on a plane at its height, but a
## plane is under the new spot: follow it, snapped onto that plane.
func _test_jump_snapped_to_plane() -> void:
	var host: GameHost = await _locked_host()
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	var shift := Transform3D(Basis(), Vector3(0.2, -0.1, 0.0))
	var moved: Array = []
	for plane: Variant in _model_planes():
		var entry: Dictionary = (plane as Dictionary).duplicate()
		entry["pose"] = Transform3D(Basis(), (entry["pose"] as Transform3D).origin + Vector3(0.2, -0.05, 0.0))
		moved.append(entry)
	fake.planes = moved
	fake.anchor_shift[fake.last_anchor_id()] = shift
	_step(ar, 1.2)
	check("unclear jump: accepted, then put on the plane under the new spot (surf ~0)", (
		ar.jumps_accepted == 1 and ar.height_fixes == 1 and absf(ar.measure_surface_gap()) < 0.003
	))
	await free_host(host)
