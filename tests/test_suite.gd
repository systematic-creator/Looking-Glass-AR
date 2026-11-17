class_name LGTestSuite
extends Node
## Minimal headless test harness. Subclasses implement run_tests(); the
## suite prints PASS / FAIL lines and quits with exit code 1 on failure.

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await run_tests()
	print("%s: %d passed, %d failed" % [name, passed, failed])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if failed > 0 else 0)


func run_tests() -> void:
	pass


func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("PASS  %s" % label)
	else:
		failed += 1
		print("FAIL  %s" % label)
		push_error("Test failed: %s" % label)


func near(a: Vector3, b: Vector3, eps: float = 0.0005) -> bool:
	return a.distance_to(b) <= eps


func xform_near(a: Transform3D, b: Transform3D, eps: float = 0.0005) -> bool:
	return (
		near(a.origin, b.origin, eps)
		and near(a.basis.x, b.basis.x, eps)
		and near(a.basis.y, b.basis.y, eps)
		and near(a.basis.z, b.basis.z, eps)
	)


func frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func drag(index: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	return event


## A GameHost for `id` added to this suite. With `fake`, AR runs through it.
func make_host(id: StringName, fake: FakeARBridge = null) -> GameHost:
	var host := GameHost.new()
	host.game_id = id
	host.exit_handler = func() -> void: pass
	if fake != null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lg_placement_%s.cfg" % id))
		host.bridge_factory = func() -> ARCoreBridge: return fake
	add_child(host)
	await frames(2)
	return host


func free_host(host: GameHost) -> void:
	if host.session != null:
		host.session.shutdown()
	host.queue_free()
	await frames(1)
	get_viewport().use_xr = false
