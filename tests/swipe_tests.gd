extends LGTestSuite
## Screen-space swipes (SwipeDetector, SwipeBuffer) and their routing
## through GameHost to LGGame._on_swipe.
## Run: godot --headless --path . res://tests/swipe_tests.tscn


func run_tests() -> void:
	_test_thresholds()
	_test_dominant_axis()
	_test_fire_on_threshold()
	_test_too_slow_is_a_drag()
	_test_s_stroke()
	_test_taps_are_not_swipes()
	_test_two_fingers()
	_test_directions_and_info()
	_test_buffer()
	await _test_host_routing()


func _down(d: SwipeDetector, at: Vector2, t: float, index: int = 0) -> Dictionary:
	return d.handle(touch(index, at, true), t)


func _move(d: SwipeDetector, at: Vector2, t: float, index: int = 0) -> Dictionary:
	return d.handle(drag(index, at, Vector2.ZERO), t)


func _up(d: SwipeDetector, at: Vector2, t: float, index: int = 0) -> Dictionary:
	return d.handle(touch(index, at, false), t)


func _detector(threshold: float = 48.0) -> SwipeDetector:
	var d := SwipeDetector.new()
	d.threshold_px = threshold
	return d


func _test_thresholds() -> void:
	# Window == viewport: physical pixels.
	var at160: float = SwipeDetector.threshold_for(160.0, 1280.0, 1280.0)
	var at420: float = SwipeDetector.threshold_for(420.0, 2340.0, 2340.0)
	check("threshold: 0.28 in at 160 dpi is about 45 px (%.1f)" % at160, absf(at160 - 44.8) < 0.5)
	check("threshold: 0.28 in at 420 dpi is about 118 px (%.1f)" % at420, absf(at420 - 117.6) < 0.5)
	# A 420 dpi phone, 1080 px tall landscape window, 720 px tall viewport:
	# the same physical stroke in viewport pixels.
	var scaled: float = SwipeDetector.threshold_for(420.0, 1080.0, 720.0)
	check("threshold: scaled to the content-scaled viewport (%.1f px)" % scaled, absf(scaled - 78.4) < 0.5)
	# Portrait on the same phone: 2340 px tall window, 1560 px tall viewport
	# -> same inches, same viewport pixels as landscape (the base swaps).
	var portrait: float = SwipeDetector.threshold_for(420.0, 2340.0, 1560.0)
	check("threshold: portrait keeps the same physical length (%.1f px)" % portrait, absf(portrait - scaled) < 0.5)
	check("threshold: unknown dpi falls back", is_equal_approx(SwipeDetector.threshold_for(0.0, 1080.0, 720.0), SwipeDetector.DEFAULT_THRESHOLD_PX))
	check("threshold: clamped", SwipeDetector.threshold_for(2000.0, 100.0, 1000.0) <= SwipeDetector.MAX_THRESHOLD_PX)


func _test_dominant_axis() -> void:
	check("axis: (100, 60) is right (1.67x)", SwipeDetector.dominant_direction(Vector2(100, 60)) == Vector2i.RIGHT)
	check("axis: (100, 80) is ambiguous (1.25x)", SwipeDetector.dominant_direction(Vector2(100, 80)) == Vector2i.ZERO)
	check("axis: (-10, -90) is up (screen y grows down)", SwipeDetector.dominant_direction(Vector2(-10, -90)) == Vector2i.UP)
	check("axis: (5, 70) is down", SwipeDetector.dominant_direction(Vector2(5, 70)) == Vector2i.DOWN)
	check("axis: (-70, 0) is left", SwipeDetector.dominant_direction(Vector2(-70, 0)) == Vector2i.LEFT)


func _test_fire_on_threshold() -> void:
	var d := _detector()
	_down(d, Vector2(300, 600), 0.0)
	check("fire: under the threshold nothing yet", _move(d, Vector2(330, 602), 0.04).is_empty())
	var swipe: Dictionary = _move(d, Vector2(352, 604), 0.07)
	check("fire: crossing 48 px fires before lift-off", not swipe.is_empty() and swipe["direction"] == Vector2i.RIGHT)
	check("fire: the rest of the stroke is ignored", _move(d, Vector2(420, 606), 0.1).is_empty() and _move(d, Vector2(500, 606), 0.12).is_empty())
	check("fire: lift-off adds nothing", _up(d, Vector2(500, 606), 0.14).is_empty())
	# A diagonal start resolves once it leans far enough.
	_down(d, Vector2(300, 600), 1.0)
	check("fire: a 45-degree stroke waits", _move(d, Vector2(345, 645), 1.05).is_empty())
	var lean: Dictionary = _move(d, Vector2(380, 650), 1.08)
	check("fire: ... and fires when one axis dominates", not lean.is_empty() and lean["direction"] == Vector2i.RIGHT)
	_up(d, Vector2(380, 650), 1.1)


func _test_too_slow_is_a_drag() -> void:
	var d := _detector()
	_down(d, Vector2(300, 600), 0.0)
	_move(d, Vector2(310, 600), 0.1)
	check("slow: a stroke reaching the threshold after 0.25 s is not a swipe", _move(d, Vector2(380, 600), 0.32).is_empty())
	check("slow: nor later in that stroke", _move(d, Vector2(480, 600), 0.36).is_empty())
	_up(d, Vector2(480, 600), 0.4)
	_down(d, Vector2(300, 600), 1.0)
	check("slow: the next stroke works again", not _move(d, Vector2(240, 600), 1.05).is_empty())


func _test_s_stroke() -> void:
	var d := _detector()
	_down(d, Vector2(300, 600), 0.0)
	var first: Dictionary = _move(d, Vector2(355, 600), 0.05)
	_move(d, Vector2(420, 600), 0.08)
	check("S: a perpendicular move after a swipe is ignored", _move(d, Vector2(420, 540), 0.1).is_empty())
	check("S: a half reversal is not enough", _move(d, Vector2(395, 540), 0.12).is_empty())
	var back: Dictionary = _move(d, Vector2(360, 540), 0.15)
	check("S: right then a full reversal left = two swipes", first["direction"] == Vector2i.RIGHT and not back.is_empty() and back["direction"] == Vector2i.LEFT)
	check("S: the second swipe is index 1", int(back.get("index", -1)) == 1)
	var third: Dictionary = _move(d, Vector2(420, 540), 0.2)
	check("S: and back right again (index 2)", not third.is_empty() and third["direction"] == Vector2i.RIGHT and int(third["index"]) == 2)
	_up(d, Vector2(420, 540), 0.25)
	# A pause at the turn makes the reversal a drag.
	_down(d, Vector2(300, 600), 1.0)
	_move(d, Vector2(355, 600), 1.05)
	check("S: a reversal after resting 0.3 s at the turn is not a swipe", _move(d, Vector2(290, 600), 1.4).is_empty())
	_up(d, Vector2(290, 600), 1.45)


func _test_taps_are_not_swipes() -> void:
	var d := _detector()
	_down(d, Vector2(300, 600), 0.0)
	var wobble: Dictionary = _move(d, Vector2(312, 606), 0.05)
	var up: Dictionary = _up(d, Vector2(312, 606), 0.08)
	check("tap: a tap with finger wobble is never a swipe", wobble.is_empty() and up.is_empty())
	# And the GestureTracker still sees that tap.
	var g := GestureTracker.new()
	g.tap_slop_px = 24.0
	g.handle(touch(0, Vector2(300, 600), true))
	g.handle(drag(0, Vector2(312, 606), Vector2.ZERO))
	var gesture: Dictionary = g.handle(touch(0, Vector2(312, 606), false))
	check("tap: ... while the gesture tracker reports it as a tap", gesture.get("kind", &"") == &"tap")


func _test_two_fingers() -> void:
	var d := _detector()
	_down(d, Vector2(300, 600), 0.0, 0)
	_down(d, Vector2(600, 600), 0.02, 1)
	check("two fingers: a pinch stroke is never a swipe", _move(d, Vector2(400, 600), 0.05, 0).is_empty() and _move(d, Vector2(500, 600), 0.06, 1).is_empty())
	_up(d, Vector2(500, 600), 0.08, 1)
	check("two fingers: not even after the second finger lifts", _move(d, Vector2(480, 600), 0.1, 0).is_empty())
	_up(d, Vector2(480, 600), 0.12, 0)
	_down(d, Vector2(300, 600), 0.5, 0)
	check("two fingers: the next one-finger stroke swipes", not _move(d, Vector2(300, 540), 0.55, 0).is_empty())
	# A lost release (index 0 down again) does not block swipes.
	_down(d, Vector2(300, 600), 1.0, 0)
	check("two fingers: a missed release does not stick", not _move(d, Vector2(300, 670), 1.05, 0).is_empty())


func _test_directions_and_info() -> void:
	var d := _detector()
	var cases: Array = [[Vector2(0, -60), Vector2i.UP], [Vector2(0, 60), Vector2i.DOWN], [Vector2(-60, 0), Vector2i.LEFT], [Vector2(60, 0), Vector2i.RIGHT]]
	var ok: bool = true
	var t: float = 0.0
	var info: Dictionary = {}
	for c: Array in cases:
		_down(d, Vector2(300, 600), t)
		var s: Dictionary = _move(d, Vector2(300, 600) + (c[0] as Vector2), t + 0.05)
		ok = ok and not s.is_empty() and s["direction"] == c[1]
		info = s
		_up(d, Vector2(300, 600), t + 0.1)
		t += 1.0
	check("directions: up / down / left / right", ok)
	var v: Vector2 = info.get("velocity", Vector2.ZERO) as Vector2
	check("info: velocity in px/s (60 px in 0.05 s = 1200)", absf(v.x - 1200.0) < 1.0)
	check("info: from / to / distance / time", info.has("from") and info.has("to") and absf(float(info["distance"]) - 60.0) < 0.01 and absf(float(info["time"]) - 0.05) < 0.001)


func _test_buffer() -> void:
	var b := SwipeBuffer.new()
	check("buffer: empty", b.take(0.0) == Vector2i.ZERO)
	b.push(Vector2i.UP, 1.0)
	check("buffer: pending within 0.15 s", b.has_pending(1.1))
	check("buffer: taken when the game can act (0.1 s later)", b.take(1.1) == Vector2i.UP)
	check("buffer: consumed once", b.take(1.11) == Vector2i.ZERO)
	b.push(Vector2i.LEFT, 2.0)
	check("buffer: stale after 0.15 s", b.take(2.2) == Vector2i.ZERO)
	b.push(Vector2i.LEFT, 3.0)
	b.push(Vector2i.DOWN, 3.05)
	check("buffer: the latest swipe wins", b.take(3.1) == Vector2i.DOWN)


func _probe_manifest() -> LGGameManifest:
	var m := LGGameManifest.new()
	m.id = &"probe"
	m.display_name = "Probe"
	m.board_size = Vector2(0.3, 0.3)
	m.entry = "res://tests/probe_game.gd"
	return m


func _test_host_routing() -> void:
	var host := GameHost.new()
	host.game_id = &"probe"
	host.exit_handler = func() -> void: pass
	host.catalog = GameCatalog.new()
	host.catalog.register(_probe_manifest())
	add_child(host)
	await frames(2)
	var game: ProbeGame = host.game as ProbeGame
	host._swipes.threshold_px = 48.0
	check("host: fallback view is playing", game.is_playing())
	var yaw_before: float = host.orbit_camera.yaw
	# Not capturing: a stroke orbits the camera and is no swipe.
	host._input(touch(0, Vector2(400, 400), true))
	host._input(drag(0, Vector2(480, 400), Vector2(80, 0)))
	host._input(touch(0, Vector2(480, 400), false))
	check("host: without captures_swipes() strokes orbit the touch camera", game.swipes.is_empty() and not is_equal_approx(host.orbit_camera.yaw, yaw_before))
	game.wants_swipes = true
	yaw_before = host.orbit_camera.yaw
	host._input(touch(0, Vector2(400, 400), true))
	host._input(drag(0, Vector2(330, 400), Vector2(-70, 0)))
	host._input(drag(0, Vector2(260, 400), Vector2(-70, 0)))
	host._input(touch(0, Vector2(260, 400), false))
	check("host: captures_swipes() -> one LEFT swipe reaches the game", game.swipes == [Vector2i.LEFT])
	check("host: ... and the stroke does not orbit the camera", is_equal_approx(host.orbit_camera.yaw, yaw_before))
	var taps_before: int = game.box_rays.size()
	host._input(touch(0, Vector2(640, 360), true))
	host._input(touch(0, Vector2(640, 360), false))
	check("host: a tap is still a tap (box ray), not a swipe", game.box_rays.size() == taps_before + 1 and game.swipes.size() == 1)
	game.lg_set_app_paused(true)
	host._input(touch(0, Vector2(400, 400), true))
	host._input(drag(0, Vector2(400, 300), Vector2(0, -100)))
	host._input(touch(0, Vector2(400, 300), false))
	check("host: no swipes while the game is paused", game.swipes.size() == 1)
	game.lg_set_app_paused(false)
	host._input(touch(0, Vector2(400, 400), true))
	host._input(drag(0, Vector2(400, 300), Vector2(0, -100)))
	host._input(touch(0, Vector2(400, 300), false))
	check("host: UP after resuming", game.swipes == [Vector2i.LEFT, Vector2i.UP])
	await free_host(host)
