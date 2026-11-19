class_name FakeARBridge
extends ARCoreBridge
## Headless stand-in for the ARCore plugin, used by the tests to drive the
## calibration flow without a device. Never used by the platform itself.

var running: bool = false
## What the centre-of-screen hit test reports.
var surface_found: bool = false
var surface_pose: Transform3D = Transform3D(Basis(), Vector3(0.0, -0.4, -0.7))
var info: Dictionary = {"camera_state": 0, "failure_reason": 0, "frames": 30, "points": 64, "planes": 0, "upward_planes": 0}
var anchors_made: int = 0
var release_count: int = 0
## Optional scene model: (normalized screen) -> hit Dictionary.
var hit_callback: Callable = Callable()
## Optional tracked planes; replaces the default single surface.
var planes: Array = []
## Anchor tracking state reported for every anchor (0 tracking, 1 paused).
var anchor_state: int = 0
## Per-anchor tracking state overrides (anchor id -> state).
var anchor_states: Dictionary = {}
## Optional feature points (replaces the default two).
var cloud: PackedVector3Array = PackedVector3Array()
## Applied to every reported anchor pose (simulates ARCore correcting the
## world, or garbage poses while an anchor is not tracking).
var pose_shift: Transform3D = Transform3D.IDENTITY
## Per-anchor extra shift (anchor id -> Transform3D), applied after
## pose_shift: simulates ARCore relocalizing ONE anchor to a wrong spot
## while the planes (and newly made anchors) stay put.
var anchor_shift: Dictionary = {}
## How anchors were made, in order: "screen" or "pose".
var anchor_calls: Array[String] = []
## Screen rotation model (the patched plugin's set_display_rotation):
## whether this "build" supports it, the device's Surface.ROTATION_* (-1 =
## unknown: the window shape decides), what ARCore was told, every change,
## and the corner UVs it reports for non-landscape rotations.
var rotation_supported: bool = true
var device_rot: int = -1
var rotation: int = 1
var rotation_calls: Array[int] = []
var corner_uvs: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.8), Vector2(1.0, 0.2), Vector2(0.0, 0.8), Vector2(0.0, 0.2)])
var _poses: Dictionary = {}
var _next_id: int = 1


func start(_viewport: Viewport) -> bool:
	running = true
	return true


func stop(_viewport: Viewport) -> void:
	running = false


func release(viewport: Viewport) -> void:
	release_count += 1
	_poses.clear()
	if viewport != null:
		viewport.use_xr = false


func is_running() -> bool:
	return running


func pause() -> void:
	pass


func resume() -> void:
	pass


func supports_rotation() -> bool:
	return rotation_supported


func device_rotation() -> int:
	return device_rot


func sync_display_rotation(window: Vector2) -> int:
	if not running or not rotation_supported:
		return -1
	var r: int = device_rot if device_rot >= 0 else LGOrientation.fallback_rotation(window)
	if r != rotation:
		rotation = r
		rotation_calls.append(r)
	return r


func display_rotation() -> int:
	return rotation


func uses_custom_background() -> bool:
	return rotation_supported and rotation != 1


func background_uvs() -> PackedVector2Array:
	return corner_uvs if uses_custom_background() else PackedVector2Array()


func camera_feed_id() -> int:
	return 1


func tracking_status() -> int:
	return XRInterface.XR_NORMAL_TRACKING


func tracking_info() -> Dictionary:
	return info


func horizontal_planes() -> Array:
	if not planes.is_empty():
		return planes
	if not surface_found:
		return []
	return [{"pose": surface_pose, "polygon": PackedVector2Array([Vector2(-0.3, -0.2), Vector2(0.3, -0.2), Vector2(0.3, 0.2), Vector2(-0.3, 0.2)])}]


func point_cloud(_max_points: int) -> PackedVector3Array:
	if not cloud.is_empty():
		return cloud
	return PackedVector3Array([Vector3(0.0, -0.4, -0.6), Vector3(0.1, -0.4, -0.7)])


func hit_test(normalized_screen: Vector2) -> Dictionary:
	if hit_callback.is_valid():
		return hit_callback.call(normalized_screen) as Dictionary
	if not surface_found:
		return {"hit": false}
	return {"hit": true, "pose": surface_pose, "kind": "plane"}


func create_anchor_at_screen(normalized_screen: Vector2) -> Dictionary:
	var hit: Dictionary = hit_test(normalized_screen)
	if not bool(hit.get("hit", false)):
		return {"id": -1}
	var pose: Transform3D = hit["pose"] as Transform3D
	var id: int = create_anchor(pose)
	if id >= 0:
		anchor_calls[anchor_calls.size() - 1] = "screen"
	return {"id": id, "pose": pose}


func create_anchor(pose: Transform3D) -> int:
	if int(info.get("camera_state", -1)) != 0:
		return -1
	var id: int = _next_id
	_next_id += 1
	_poses[id] = pose
	anchors_made += 1
	anchor_calls.append("pose")
	return id


func get_anchor_pose(anchor_id: int) -> Transform3D:
	var extra: Transform3D = anchor_shift.get(anchor_id, Transform3D.IDENTITY) as Transform3D
	return extra * pose_shift * (_poses.get(anchor_id, Transform3D.IDENTITY) as Transform3D)


## Id of the most recently made anchor (-1 if none).
func last_anchor_id() -> int:
	return _next_id - 1 if anchors_made > 0 else -1


func get_anchor_tracking_state(anchor_id: int) -> int:
	if not _poses.has(anchor_id):
		return -1
	return int(anchor_states.get(anchor_id, anchor_state))


func remove_anchor(anchor_id: int) -> void:
	_poses.erase(anchor_id)
