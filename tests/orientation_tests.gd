extends "res://tests/surface_tests.gd"
## Per-game screen orientation and rotation (OrientationService, GameHost,
## ARSession, the HUD layouts).
##   - manifest orientation (default "either") and validation,
##   - the host applies the game's orientation on load and restores
##     "either" on exit (the OS call is recorded, not made),
##   - a simulated rotation (the root window resized 2340x1080 <-> 1080x2340,
##     as Android does with configChanges) swaps the base canvas, re-lays out
##     every HUD inside the screen without overlaps, tells the game once,
##   - in AR: ARCore is told the display rotation, the portrait passthrough
##     takes over the background, the locked board's world pose is unchanged
##     and taps still land on the right cell before and after the turn.
## Run: godot --headless --path . res://tests/orientation_tests.tscn

const LANDSCAPE_WINDOW := Vector2i(2340, 1080)
const PORTRAIT_WINDOW := Vector2i(1080, 2340)

var xr: FakeXRInterface
var service: OrientationService
var _saved_window: Vector2i
var _orientation_calls: Array[int] = []


func run_tests() -> void:
	ARSession.clear_saved_area()
	_saved_window = get_tree().root.size
	service = OrientationService.of(self)
	check("service: the LookingGlass autoload owns an OrientationService", service != null)
	if service == null:
		return
	service.screen_setter = func(value: DisplayServer.ScreenOrientation) -> void: _orientation_calls.append(int(value))
	_test_rules()
	_test_manifests()
	await _test_apply_and_restore()
	await _test_rotation_fallback_host()
	await _test_hud_layouts()
	await _test_launcher_layout()
	xr = FakeXRInterface.new()
	xr.projection = FakeXRInterface.arcore_projection(Vector2(1920, 1080), 1460.0, Vector2(972.0, 531.0))
	xr.install()
	await _test_game_ui_with_locked_ar()
	await _test_stack_style_after_lock()
	await _test_ar_rotation()
	await _test_landscape_only_plugin()
	xr.uninstall()
	service.screen_setter = Callable()
	await _set_window(_saved_window)
	ARSession.clear_saved_area()


func _set_window(size: Vector2i) -> void:
	get_tree().root.size = size
	await frames(3)


func _view() -> Rect2:
	return get_viewport().get_visible_rect()


## Inside the screen with at least `margin` px to spare (UI touching the
## screen edge counts as a layout bug).
static func _contains(outer: Rect2, inner: Rect2, margin: float = 4.0) -> bool:
	return outer.grow(-margin).encloses(inner)


static func _overlap(a: Rect2, b: Rect2) -> bool:
	return a.grow(-1.0).intersects(b.grow(-1.0))


func _probe_manifest(mode: String = "either") -> LGGameManifest:
	var m := LGGameManifest.new()
	m.id = &"probe"
	m.display_name = "Probe"
	m.board_size = Vector2(0.3, 0.3)
	m.entry = "res://tests/probe_game.gd"
	m.orientation = mode
	return m


func _probe_host(mode: String = "either", fake: FakeARBridge = null) -> GameHost:
	var host := GameHost.new()
	host.game_id = &"probe"
	host.exit_handler = func() -> void: pass
	host.catalog = GameCatalog.new()
	host.catalog.register(_probe_manifest(mode))
	if fake != null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lg_placement_probe.cfg"))
		host.bridge_factory = func() -> ARCoreBridge: return fake
	add_child(host)
	await frames(2)
	return host


# --- Rules ------------------------------------------------------------------------

func _test_rules() -> void:
	check("rules: either -> full sensor", LGOrientation.screen_orientation_for("either") == DisplayServer.SCREEN_SENSOR)
	check("rules: landscape -> sensor landscape (both directions)", LGOrientation.screen_orientation_for("landscape") == DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	check("rules: portrait -> sensor portrait", LGOrientation.screen_orientation_for("portrait") == DisplayServer.SCREEN_SENSOR_PORTRAIT)
	check("rules: base canvas swaps to 720x1280 in portrait", LGOrientation.base_size(true) == Vector2i(720, 1280) and LGOrientation.base_size(false) == Vector2i(1280, 720))
	check("rules: allows()", LGOrientation.allows("either", true) and LGOrientation.allows("either", false)
		and not LGOrientation.allows("landscape", true) and not LGOrientation.allows("portrait", false))
	check("rules: rotation fallback from the window shape", LGOrientation.fallback_rotation(Vector2(1080, 2340)) == 0 and LGOrientation.fallback_rotation(Vector2(2340, 1080)) == 1)
	var project: int = int(ProjectSettings.get_setting("display/window/handheld/orientation", -1))
	check("project: the app starts in full sensor orientation (6), so the launcher follows the phone", project == DisplayServer.SCREEN_SENSOR)


func _test_manifests() -> void:
	var m: LGGameManifest = _probe_manifest()
	check("manifest: orientation defaults to either", LGGameManifest.new().orientation == "either")
	check("manifest: either / landscape / portrait are valid", m.is_valid() and _probe_manifest("landscape").is_valid() and _probe_manifest("portrait").is_valid())
	var bad: LGGameManifest = _probe_manifest("sideways")
	var errors: PackedStringArray = bad.validate()
	check("manifest: an unknown orientation is rejected", errors.size() == 1 and errors[0].contains("orientation"))
	var catalog := GameCatalog.new()
	catalog.scan()
	var all_either: bool = catalog.size() >= 3
	for manifest: LGGameManifest in catalog.list():
		all_either = all_either and manifest.orientation == "either"
	check("manifest: every bundled game (Tic-Tac-Toe, Stack Tower, Competitive Evolution, Tattoo Studio, Mage Run, Crystal Defense) runs in either orientation", all_either and catalog.size() == 6)


# --- Apply / restore ----------------------------------------------------------------

func _test_apply_and_restore() -> void:
	_orientation_calls.clear()
	var host: GameHost = await _probe_host("portrait")
	check("apply: loading a portrait game requests sensor portrait", _orientation_calls == [int(DisplayServer.SCREEN_SENSOR_PORTRAIT)])
	check("apply: the service remembers the request", service.requested == "portrait")
	host.exit_game()
	check("restore: leaving the game restores either (full sensor)", _orientation_calls.back() == int(DisplayServer.SCREEN_SENSOR) and service.requested == "either")
	await free_host(host)
	_orientation_calls.clear()
	host = await _probe_host("either")
	check("apply: an either game requests full sensor", _orientation_calls == [int(DisplayServer.SCREEN_SENSOR)])
	await free_host(host)


# --- Rotation (touch fallback) -----------------------------------------------------

func _test_rotation_fallback_host() -> void:
	await _set_window(LANDSCAPE_WINDOW)
	check("rotate: landscape window -> landscape base canvas", not service.portrait and get_tree().root.content_scale_size == Vector2i(1280, 720))
	var host: GameHost = await _probe_host()
	var game: ProbeGame = host.game as ProbeGame
	check("rotate: a game loaded in landscape sees is_portrait() false", not game.portrait_at_ready and not game.is_portrait())
	var board_before: Transform3D = game.global_transform
	var rotations_before: int = service.rotations
	await _set_window(PORTRAIT_WINDOW)
	check("rotate: portrait window -> 720x1280 base, viewport 720x1560", service.portrait and get_tree().root.content_scale_size == Vector2i(720, 1280) and _view().size.is_equal_approx(Vector2(720, 1560)))
	check("rotate: one rotation, even though the base swap resizes again", service.rotations == rotations_before + 1)
	check("rotate: the game is told once (_on_orientation_changed(true))", game.orientation_events == [true] and game.is_portrait())
	check("rotate: a normal game keeps playing (only runners pause themselves)", game.is_playing())
	check("rotate: the board does not move", xform_near(game.global_transform, board_before, 0.00001))
	check("rotate: the touch camera keeps the board's width in portrait", host.orbit_camera.camera.keep_aspect == Camera3D.KEEP_WIDTH)
	check("rotate: host status line spans the top in portrait", host._status_label.anchor_left == 0.0 and host._status_label.anchor_right == 1.0)
	# Taps still land where the board is drawn.
	var cam: Camera3D = host.active_camera()
	var target := Vector3(0.05, 0.0, -0.04)
	var screen: Vector2 = cam.unproject_position(game.to_global(target))
	var hit: Variant = GameHost.screen_to_board(cam, game, screen)
	check("rotate: touch-camera tap mapping is exact in portrait", hit != null and (hit as Vector3).distance_to(target) < 0.0005)
	# The UI fades back in after the turn.
	var back: Button = host._back_button
	check("fade: platform UI starts transparent right after the turn", back.modulate.a < 0.99)
	await get_tree().create_timer(OrientationService.FADE_SECONDS + 0.15).timeout
	check("fade: ... and is fully back after FADE_SECONDS", is_equal_approx(back.modulate.a, 1.0) and not back.has_meta(&"lg_fade_base"))
	await _set_window(LANDSCAPE_WINDOW)
	check("rotate: back to landscape: told again, base restored", game.orientation_events == [true, false] and get_tree().root.content_scale_size == Vector2i(1280, 720))
	check("rotate: the touch camera keeps height in landscape", host.orbit_camera.camera.keep_aspect == Camera3D.KEEP_HEIGHT)
	await free_host(host)
	# A game loaded while already portrait builds for portrait.
	await _set_window(PORTRAIT_WINDOW)
	host = await _probe_host()
	game = host.game as ProbeGame
	check("rotate: a game loaded in portrait sees is_portrait() at _on_board_ready (no callback)", game.portrait_at_ready and game.orientation_events.is_empty())
	await free_host(host)
	await _set_window(LANDSCAPE_WINDOW)


# --- HUD layouts --------------------------------------------------------------------

func _check_host_hud(host: GameHost, label: String) -> void:
	var view: Rect2 = _view()
	var status: Rect2 = host._status_label.get_global_rect()
	var back: Rect2 = host._back_button.get_global_rect()
	check("%s: back button and status line inside the screen" % label, _contains(view, back) and _contains(view, status))
	check("%s: status line clear of the back button" % label, not _overlap(status, back))


## Tattoo Studio's panels: inside the screen, clear of each other, of the
## host's back button and status line, and of `others` (AR HUD buttons).
func _check_tattoo_hud(host: GameHost, others: Array[Rect2], label: String) -> void:
	var game := host.game as TattooStudioGame
	var ui: TattooStudioUI = game.ui
	var view: Rect2 = _view()
	var portrait: bool = view.size.y > view.size.x
	check("%s: studio UI laid out for %s" % [label, "portrait" if portrait else "landscape"], ui.portrait == portrait)
	var left: Rect2 = ui.left_panel.get_global_rect()
	var right: Rect2 = ui.right_panel.get_global_rect()
	check("%s: model and tool panels inside the screen" % label, _contains(view, left) and _contains(view, right))
	check("%s: model and tool panels apart" % label, not _overlap(left, right))
	var host_rects: Array[Rect2] = [host._back_button.get_global_rect(), host._status_label.get_global_rect()]
	var clear: bool = true
	for rect: Rect2 in host_rects + others:
		clear = clear and not _overlap(rect, left) and not _overlap(rect, right)
	check("%s: panels clear of the host and AR HUD (%d other rects)" % [label, others.size()], clear)
	if portrait:
		# The middle of the screen stays free for the model.
		var middle: float = right.position.y - left.end.y
		check("%s: portrait keeps %d px (>= 50%%) between the strip and the tool bar" % [label, roundi(middle)], middle >= view.size.y * 0.5)
		check("%s: portrait tool bar is a row (wider than tall)" % label, right.size.x > right.size.y)
	check("%s: a touch on a panel is UI, the middle of the screen is not" % label,
		game.is_over_game_ui(right.get_center()) and game.is_over_game_ui(left.get_center()) and not game.is_over_game_ui(view.get_center()))


## Every bundled game, board locked in AR, both shapes at 20:9 and 16:9:
## each visible game button is clear of the AR HUD's buttons and really
## receives a pointer at its centre (nothing on top of it eats the tap).
func _test_game_ui_with_locked_ar() -> void:
	var catalog := GameCatalog.new()
	catalog.scan()
	for window: Vector2i in [PORTRAIT_WINDOW, LANDSCAPE_WINDOW, Vector2i(720, 1280), Vector2i(1280, 720)]:
		await _set_window(window)
		var label: String = "%dx%d" % [window.x, window.y]
		for manifest: LGGameManifest in catalog.list():
			var host: GameHost = await _ar_host(manifest.id)
			host.session.place_at_reticle()
			await frames(2)
			host.session.set_locked(true)
			await frames(4)
			var ar_rects: Array[Rect2] = []
			for button: Button in host.session.hud.all_buttons():
				if button.is_visible_in_tree():
					ar_rects.append(button.get_global_rect())
			var buttons: Array[Button] = _game_buttons(host.game)
			var clear: bool = true
			var reached: bool = true
			var bad: PackedStringArray = []
			for button: Button in buttons:
				var rect: Rect2 = button.get_global_rect()
				for ar_rect: Rect2 in ar_rects:
					if _overlap(rect, ar_rect):
						clear = false
						bad.append("%s under AR" % button.name)
				var hit: Control = _control_at(rect.get_center())
				if hit != button and not button.is_ancestor_of(hit):
					reached = false
					bad.append("%s covered by %s" % [button.name, hit.name if hit != null else "nothing"])
			check("ar locked %s %s: %d game buttons clear of the AR HUD and tappable %s" % [label, manifest.id, buttons.size(), ", ".join(bad)], clear and reached and host.game.is_playing())
			await free_host(host)
	await _set_window(LANDSCAPE_WINDOW)


## Regression (user report): Stack Tower's Solid / Hologram toggle stopped
## working once the board was locked in AR (the AR HUD's Unlock / Re-place
## buttons sat on top of it). A real click must switch the style.
func _test_stack_style_after_lock() -> void:
	for window: Vector2i in [PORTRAIT_WINDOW, LANDSCAPE_WINDOW, Vector2i(720, 1280), Vector2i(1280, 720)]:
		await _set_window(window)
		var label: String = "%dx%d" % [window.x, window.y]
		StackTowerGame.session_style = StackTowerGame.Style.HOLOGRAM
		var host: GameHost = await _ar_host(&"stack_tower")
		host.session.place_at_reticle()
		await frames(2)
		host.session.set_locked(true)
		await frames(4)
		var game := host.game as StackTowerGame
		var layers_before: int = game.layers.size()
		for expected: StackTowerGame.Style in [StackTowerGame.Style.SOLID, StackTowerGame.Style.HOLOGRAM]:
			await _click(game.style_button.get_global_rect().get_center())
			check("stack style after lock %s: a click on Style switches to %s" % [label, "Solid" if expected == StackTowerGame.Style.SOLID else "Hologram"], game.style == expected)
		check("stack style after lock %s: the clicks never dropped a slab" % label, game.layers.size() == layers_before)
		check("stack style after lock %s: the button sits above the AR row (inset %d px)" % [label, roundi(game.ui_bottom_inset())],
			game.ui_bottom_inset() > 40.0 and game.style_button.get_global_rect().end.y <= _view().size.y - game.ui_bottom_inset())
		# Unlocking drops the AR row's inset back and the button follows.
		host.session.set_locked(false)
		await frames(4)
		check("stack style after lock %s: unlocked, the layout follows the AR HUD (inset %d px, button inside)" % [label, roundi(game.ui_bottom_inset())],
			_contains(_view(), game.style_button.get_global_rect()))
		await free_host(host)
	StackTowerGame.session_style = StackTowerGame.Style.HOLOGRAM
	await _set_window(LANDSCAPE_WINDOW)


func _click(point: Vector2) -> void:
	_control_at(point)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		click.global_position = point
		get_viewport().push_input(click, true)
		await frames(1)


static func _game_buttons(game: Node) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# Disabled buttons too (Mage Run's Cast waits for a full meter).
		if node is Button and (node as Button).is_visible_in_tree():
			out.append(node as Button)
		stack.append_array(node.get_children())
	return out


## The GUI control a pointer at `point` (viewport px) reaches.
func _control_at(point: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	return get_viewport().gui_get_hovered_control()


func _check_calibration_hud(hud: CalibrationHud, label: String, host: GameHost = null) -> void:
	var view: Rect2 = _view()
	if host != null:
		# The host's corner buttons stay on top of the AR HUD: nothing of the
		# HUD may sit under them.
		var corner: Array[Rect2] = [host._back_button.get_global_rect()]
		if host.debug_button.visible:
			corner.append(host.debug_button.get_global_rect())
		var hud_rects: Array[Rect2] = []
		if hud._banner.visible:
			hud_rects.append(hud._banner.get_global_rect())
		if hud.debug_label.visible:
			hud_rects.append(hud.debug_label.get_global_rect())
		for button: Button in hud.all_buttons():
			if button.is_visible_in_tree():
				hud_rects.append(button.get_global_rect())
		var clear: bool = true
		for a: Rect2 in corner:
			for b: Rect2 in hud_rects:
				clear = clear and not _overlap(a, b)
		check("%s: banner, debug line and buttons clear of \u2039 Games / dbg" % label, clear)
	var rects: Array[Rect2] = []
	var names: PackedStringArray = []
	var inside: bool = true
	for button: Button in hud.all_buttons():
		if not button.is_visible_in_tree():
			continue
		var r: Rect2 = button.get_global_rect()
		inside = inside and _contains(view, r)
		rects.append(r)
		names.append(button.text)
	var overlaps: bool = false
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			overlaps = overlaps or _overlap(rects[i], rects[j])
	check("%s: %d buttons (%s) inside the screen" % [label, rects.size(), ", ".join(names)], inside and rects.size() > 0)
	check("%s: no two buttons overlap" % label, not overlaps)
	if hud._banner.visible:
		var banner: Rect2 = hud._banner.get_global_rect()
		var clear: bool = true
		for r: Rect2 in rects:
			clear = clear and not _overlap(banner, r)
		check("%s: step banner inside the screen, clear of the buttons" % label, _contains(view, banner) and clear)
	if hud.airspace_panel.visible:
		var panel: Rect2 = hud.airspace_panel.get_global_rect()
		var clear_panel: bool = true
		for r: Rect2 in rects:
			clear_panel = clear_panel and not _overlap(panel, r)
		check("%s: Airspace slider inside the screen, clear of the buttons" % label, _contains(view, panel) and clear_panel)


func _check_stack_hud(host: GameHost, label: String) -> void:
	var game: StackTowerGame = host.game as StackTowerGame
	var view: Rect2 = _view()
	var score: Rect2 = game._score_box.get_global_rect()
	var style: Rect2 = game.style_button.get_global_rect()
	game._over_panel.visible = true
	await frames(1)
	var over: Rect2 = game._over_panel.get_global_rect()
	game._over_panel.visible = false
	check("%s: score, Style button and game-over panel inside the screen" % label, _contains(view, score) and _contains(view, style) and _contains(view, over))
	check("%s: the score is clear of the platform status line and back button" % label,
		not _overlap(game._score_label.get_global_rect(), host._status_label.get_global_rect()) and not _overlap(game._score_label.get_global_rect(), host._back_button.get_global_rect()))
	check("%s: the Style button is clear of the game-over panel" % label, not _overlap(style, over))


func _test_hud_layouts() -> void:
	for window: Vector2i in [PORTRAIT_WINDOW, LANDSCAPE_WINDOW]:
		await _set_window(window)
		var label: String = "%dx%d" % [window.x, window.y]
		# Tic-tac-toe (touch fallback): only the platform HUD on screen.
		var host: GameHost = await make_host(&"tic_tac_toe")
		host.game.set_status("X to move. Tap a cell on the board to place your mark.")
		await frames(2)
		_check_host_hud(host, "ttt %s" % label)
		await free_host(host)
		# Stack Tower.
		host = await make_host(&"stack_tower")
		await frames(2)
		_check_host_hud(host, "stack %s" % label)
		await _check_stack_hud(host, "stack %s" % label)
		await free_host(host)
		# Tattoo Studio: side columns in landscape, top strip + bottom bar in portrait.
		host = await make_host(&"tattoo_studio")
		await frames(2)
		_check_host_hud(host, "tattoo %s" % label)
		_check_tattoo_hud(host, [], "tattoo %s" % label)
		await free_host(host)
		host = await _ar_host(&"tattoo_studio")
		host.session.place_at_reticle()
		await frames(2)
		host.session.set_locked(true)
		await frames(3)
		var ar_buttons: Array[Rect2] = []
		for button: Button in host.session.hud.all_buttons():
			if button.is_visible_in_tree():
				ar_buttons.append(button.get_global_rect())
		if host.debug_button.visible:
			ar_buttons.append(host.debug_button.get_global_rect())
		_check_tattoo_hud(host, ar_buttons, "tattoo ar locked %s" % label)
		check("tattoo ar locked %s: the game is told the AR HUD's bottom inset (%d px)" % [label, roundi(host.game.ui_bottom_inset())], host.game.ui_bottom_inset() > 40.0)
		await free_host(host)
		# The AR calibration HUD through its steps.
		host = await _ar_host(&"tic_tac_toe")
		var ar: ARSession = host.session
		await frames(2)
		check("ar %s: HUD laid out for %s" % [label, "portrait" if service.portrait else "landscape"], ar.hud.portrait == service.portrait)
		_check_calibration_hud(ar.hud, "ar search %s" % label, host)
		ar.place_at_reticle()
		await frames(2)
		_check_calibration_hud(ar.hud, "ar adjust %s" % label, host)
		ar.begin_fit()
		await frames(2)
		_check_calibration_hud(ar.hud, "ar fit edges %s" % label, host)
		ar.finish_fit()
		await frames(2)
		_check_calibration_hud(ar.hud, "ar adjust after fit %s" % label, host)
		ar.set_locked(true)
		await frames(2)
		_check_calibration_hud(ar.hud, "ar locked %s" % label, host)
		_check_host_hud(host, "ar locked %s" % label)
		var debug: Label = ar.hud.debug_label
		ar.hud.toggle_debug()
		ar.hud.set_debug_text("debug line " + "x".repeat(200), false)
		await frames(2)
		check("ar %s: debug overlay inside the screen" % label, _contains(_view(), debug.get_global_rect()))
		_check_calibration_hud(ar.hud, "ar debug on %s" % label, host)
		check("ar %s: dbg button inside the screen" % label, _contains(_view(), host.debug_button.get_global_rect()))
		await free_host(host)
	await _set_window(LANDSCAPE_WINDOW)


func _test_launcher_layout() -> void:
	# 20:9 phones in both shapes, and 16:9 (1280x720, 720x1280) for the fit.
	for window: Vector2i in [PORTRAIT_WINDOW, LANDSCAPE_WINDOW, Vector2i(720, 1280), Vector2i(1280, 720)]:
		await _set_window(window)
		var launcher := Launcher.new()
		launcher.launch_handler = func(_id: StringName) -> void: pass
		add_child(launcher)
		await frames(3)
		var view: Rect2 = _view()
		var inside: bool = true
		for card: Variant in launcher.cards.values():
			inside = inside and _contains(view, (card as Control).get_global_rect())
		var label: String = "%dx%d" % [window.x, window.y]
		check("launcher %s: layout follows the screen (%s)" % [label, "portrait" if launcher.portrait else "landscape"], launcher.portrait == (window.y > window.x))
		check("launcher %s: every card inside the screen (%d cards)" % [label, launcher.cards.size()], inside and launcher.cards.size() == 6)
		await frames(2)
		if window == PORTRAIT_WINDOW or window == LANDSCAPE_WINDOW:
			check("launcher %s: every description shows in full" % label, launcher.descriptions_fit())
		if launcher.portrait:
			var first: Control = launcher.cards.values()[0] as Control
			check("launcher %s: portrait cards are wide (%d px of %d)" % [label, roundi(first.size.x), roundi(view.size.x)], first.size.x >= view.size.x * 0.8)
		launcher.queue_free()
		await frames(1)


# --- AR rotation --------------------------------------------------------------------

func _window_pos(viewport_pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * viewport_pos


func _phone_tap(viewport_pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = _window_pos(viewport_pos)
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _cell_hits(host: GameHost) -> Array:
	var game: TicTacToeGame = host.game as TicTacToeGame
	var hits: int = 0
	var worst: float = 0.0
	for index: int in 9:
		var screen: Vector2 = host.session.xr_camera.unproject_position(game.to_global(TicTacToeGame.cell_top(index)))
		_phone_tap(screen)
		await frames(1)
		var info: Dictionary = host.last_tap_info
		if String(info.get("what", "")) == "cell %d" % index:
			hits += 1
		worst = maxf(worst, float(info.get("error_px", 999.0)))
	return [hits, worst]


func _test_ar_rotation() -> void:
	await _set_window(LANDSCAPE_WINDOW)
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	check("ar: landscape session keeps the plugin's camera-feed background", host.environment.background_mode == Environment.BG_CAMERA_FEED and not ar.custom_background)
	check("ar: ARCore stays at ROTATION_90 in landscape (no call)", fake.rotation == 1 and fake.rotation_calls.is_empty())
	ar.place_at_reticle()
	ar.finish_fit()
	ar.set_locked(true)
	await frames(1)
	var game: TicTacToeGame = host.game as TicTacToeGame
	var centre: Vector3 = game.global_position
	_look(centre + Vector3(0.0, 0.45, 0.3), centre)
	await frames(1)
	var before: Array = await _cell_hits(host)
	check("ar landscape: every cell tap lands (%d/9, worst %.2f px)" % [before[0], before[1]], int(before[0]) == 9 and float(before[1]) < 1.0)
	var board_world: Transform3D = game.global_transform
	var anchor_world: Transform3D = host.world_anchor.global_transform
	var anchors_made: int = fake.anchors_made
	# Turn the phone: Android resizes the window; ARCore now returns a
	# portrait projection and a display-oriented (rolled) camera pose.
	await _set_window(PORTRAIT_WINDOW)
	xr.projection = FakeXRInterface.arcore_projection(Vector2(1080, 2340), 2050.0, Vector2(546.0, 1162.0))
	var eye: Vector3 = centre + Vector3(0.0, 0.5, 0.32)
	ar.xr_camera.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	await frames(2)
	check("ar portrait: ARCore told ROTATION_0 once", fake.rotation_calls == [0] and ar.display_rotation == 0)
	check("ar portrait: the app draws the passthrough (background canvas, layer %d)" % PassthroughBackground.LAYER,
		ar.custom_background and host.environment.background_mode == Environment.BG_CANVAS
		and host.environment.background_canvas_max_layer == PassthroughBackground.LAYER)
	check("ar portrait: the passthrough uses ARCore's corner UVs", ar.passthrough != null and ar.passthrough.visible and ar.passthrough.corners == fake.corner_uvs)
	check("ar portrait: the passthrough never fades", not OrientationService.fade_targets(get_tree().root).has(ar.passthrough.rect))
	check("ar portrait: the board's world pose is unchanged", xform_near(game.global_transform, board_world, 0.00001))
	check("ar portrait: the anchor is unchanged and no new anchor was made", xform_near(host.world_anchor.global_transform, anchor_world, 0.00001) and fake.anchors_made == anchors_made)
	check("ar portrait: still locked and playing", ar.is_board_locked() and game.is_playing())
	check("ar portrait: AR HUD in its portrait layout", ar.hud.portrait)
	var after: Array = await _cell_hits(host)
	check("ar portrait: every cell tap lands (%d/9, worst %.2f px)" % [after[0], after[1]], int(after[0]) == 9 and float(after[1]) < 1.0)
	# 180-degree flip to reverse landscape: same window shape, polled.
	await _set_window(LANDSCAPE_WINDOW)
	fake.device_rot = 3
	xr.projection = FakeXRInterface.arcore_projection(Vector2(2340, 1080), 2050.0, Vector2(1172.0, 534.0))
	_look(centre + Vector3(0.0, 0.45, 0.3), centre)
	await get_tree().create_timer(ARSession.ROTATION_POLL_SECONDS * 2.0).timeout
	await frames(1)
	check("ar reverse landscape: ARCore told ROTATION_270, the app keeps drawing the passthrough", fake.rotation == 3 and ar.custom_background)
	fake.device_rot = 1
	await get_tree().create_timer(ARSession.ROTATION_POLL_SECONDS * 2.0).timeout
	await frames(1)
	check("ar landscape again: back to ROTATION_90 and the plugin's feed background", fake.rotation == 1 and not ar.custom_background
		and host.environment.background_mode == Environment.BG_CAMERA_FEED and not ar.passthrough.visible)
	var again: Array = await _cell_hits(host)
	check("ar landscape again: every cell tap lands (%d/9)" % again[0], int(again[0]) == 9)
	check("ar: the board never moved through three turns", xform_near(game.global_transform, board_world, 0.00001))
	fake.device_rot = -1
	await _set_window(PORTRAIT_WINDOW)
	await frames(2)
	var environment: Environment = host.environment
	check("ar: portrait again before leaving (own background)", environment.background_mode == Environment.BG_CANVAS)
	host.session.shutdown()
	check("ar: leaving AR restores the host's own background and drops the passthrough", environment.background_mode == Environment.BG_COLOR and host.session.passthrough == null)
	await free_host(host)
	await _set_window(LANDSCAPE_WINDOW)


func _test_landscape_only_plugin() -> void:
	var fake := FakeARBridge.new()
	fake.hit_callback = _model_hit
	fake.planes = _model_planes()
	fake.rotation_supported = false
	_orientation_calls.clear()
	var host: GameHost = await make_host(&"tic_tac_toe", fake)
	check("old plugin: AR without rotation support locks the screen to landscape", service.requested == "landscape" and _orientation_calls.back() == int(DisplayServer.SCREEN_SENSOR_LANDSCAPE))
	host.exit_game()
	await free_host(host)
	check("old plugin: leaving restores either", service.requested == "either")
