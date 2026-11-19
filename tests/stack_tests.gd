extends "res://tests/surface_tests.gd"
## Stack Tower: slicing math, perfect tolerance and streak regrow, miss and
## game over / restart, scoring and the session best, sweep speed, the tower
## sinking so it never leaves the tall box, debris containment, and the
## "Play without AR" camera following the tower top.
## Run: godot --headless --path . res://tests/stack_tests.tscn

const DT: float = 1.0 / 60.0


func run_tests() -> void:
	StackTowerGame.session_best = 0
	StackTowerGame.session_style = StackTowerGame.Style.HOLOGRAM
	_test_slice_math()
	_test_manifest_and_box()
	await _test_start_and_sweep()
	await _test_tap_anywhere_and_cut()
	await _test_perfects_and_regrow()
	await _test_miss_and_restart()
	await _test_scroll_keeps_inside_box()
	await _test_camera_follows_top()
	await _test_ar_tap_anywhere()
	await _test_solid_style()
	StackTowerGame.session_style = StackTowerGame.Style.HOLOGRAM
	StackTowerGame.session_best = 0
	ARSession.clear_saved_area()


func _game(host: GameHost) -> StackTowerGame:
	return host.game as StackTowerGame


func _step(game: StackTowerGame, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		game._process(DT)
		t += DT


## Put the sliding slab `offset` from the slab below (along its axis).
func _aim(game: StackTowerGame, offset: float) -> void:
	var axis: int = int(game.active["axis"])
	var center: Vector2 = game.active["center"]
	var below: Vector2 = (game.layers.back() as Dictionary)["center"]
	center[axis] = below[axis] + offset
	game.active["center"] = center


func _test_slice_math() -> void:
	var tol: float = 0.004
	var r: Dictionary = StackTowerGame.slice(0.0, 0.2, 0.05, 0.2, tol)
	check("slice: 5 cm right keeps the 15 cm overlap, centred at +2.5 cm", not r["miss"] and not r["perfect"] and is_equal_approx(r["size"], 0.15) and is_equal_approx(r["center"], 0.025))
	check("slice: ... and cuts the 5 cm overhang at +12.5 cm", is_equal_approx(r["cut_size"], 0.05) and is_equal_approx(r["cut_center"], 0.125))
	r = StackTowerGame.slice(0.01, 0.1, -0.02, 0.1, tol)
	check("slice: overhang on the left side is cut on the left", is_equal_approx(r["size"], 0.07) and is_equal_approx(r["center"], -0.005) and is_equal_approx(r["cut_size"], 0.03) and is_equal_approx(r["cut_center"], -0.055))
	r = StackTowerGame.slice(0.0, 0.1, 0.03, 0.1, tol)
	check("slice: kept + cut = the whole slab", is_equal_approx(float(r["size"]) + float(r["cut_size"]), 0.1))
	r = StackTowerGame.slice(0.02, 0.1, 0.0235, 0.1, tol)
	check("perfect: within tolerance snaps exactly onto the slab below, nothing cut", r["perfect"] and is_equal_approx(r["center"], 0.02) and is_equal_approx(r["size"], 0.1) and r["cut_size"] == 0.0)
	r = StackTowerGame.slice(0.02, 0.1, 0.0245, 0.1, tol)
	check("perfect: just past tolerance is a normal cut", not r["perfect"] and is_equal_approx(r["cut_size"], 0.0045))
	r = StackTowerGame.slice(0.0, 0.1, 0.1, 0.1, tol)
	check("miss: no overlap is a miss (the whole slab falls)", r["miss"] and is_equal_approx(r["cut_size"], 0.1))
	r = StackTowerGame.slice(0.0, 0.1, -0.0999, 0.1, tol, 0.0012)
	check("miss: a sliver thinner than the minimum is a miss", r["miss"])
	check("sweep: ping-pongs between -reach and +reach", (
		is_equal_approx(StackTowerGame.sweep_position(0.0, 0.05, 1.0), -0.05) and is_equal_approx(StackTowerGame.sweep_position(1.0, 0.05, 1.0), 0.05)
		and is_equal_approx(StackTowerGame.sweep_position(1.5, 0.05, 1.0), 0.0) and is_equal_approx(StackTowerGame.sweep_position(0.0, 0.05, -1.0), 0.05)
	))
	check("speed: sweeps get faster with height, never under 0.6 s", (
		StackTowerGame.sweep_time(1) > StackTowerGame.sweep_time(10) and StackTowerGame.sweep_time(10) > StackTowerGame.sweep_time(25)
		and is_equal_approx(StackTowerGame.sweep_time(200), StackTowerGame.SWEEP_MIN)
	))
	check("score: a perfect's bonus is the streak, at most 3", StackTowerGame.perfect_bonus(1) == 1 and StackTowerGame.perfect_bonus(2) == 2 and StackTowerGame.perfect_bonus(9) == 3)
	check("colour: layers shift through a gradient", not StackTowerGame.layer_color(0).is_equal_approx(StackTowerGame.layer_color(1)) and StackTowerGame.layer_color(0).is_equal_approx(StackTowerGame.layer_color(0)))


func _test_manifest_and_box() -> void:
	var catalog := GameCatalog.new()
	catalog.scan()
	var m: LGGameManifest = catalog.get_manifest(&"stack_tower")
	check("catalog: Stack Tower is registered next to Tic-Tac-Toe", m != null and catalog.has_game(&"tic_tac_toe") and catalog.errors.is_empty())
	check("manifest: a one-player tall-box game on a 30 cm board", m.tall_box and m.max_players == 1 and m.board_size == Vector2(0.3, 0.3) and m.icon != null)
	var box: PlayBox = PlayBox.from_manifest(m)
	check("box: tall cap is 4x the 30 cm side = 1.2 m (normal cap would be 0.9 m)", (
		is_equal_approx(PlayBox.height_cap(m.board_size, true), 1.2) and is_equal_approx(box.max_height, 1.2) and is_equal_approx(PlayBox.height_cap(m.board_size), 0.9)
	))
	var copy: LGGameManifest = m.duplicate() as LGGameManifest
	copy.box_max_height = 3.5
	check("manifest: a tall box over 3.0 m is invalid; without tall_box it caps at 0.9 m", (
		copy.validate().size() > 0 and m.validate().is_empty()
		and is_equal_approx(PlayBox.from_manifest(_untall(m)).max_height, 0.9)
	))
	check("box: 80 cm default airspace, adjustable 35-120 cm", is_equal_approx(box.height(), 0.8) and is_equal_approx(box.min_height, 0.35) and box.is_adjustable())


func _untall(m: LGGameManifest) -> LGGameManifest:
	var copy: LGGameManifest = m.duplicate() as LGGameManifest
	copy.tall_box = false
	return copy


func _test_start_and_sweep() -> void:
	StackTowerGame.session_best = 0
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	check("start: playing in the touch fallback", game != null and game.is_playing() and game.state == StackTowerGame.State.PLAYING)
	var base: Dictionary = game.layers[0]
	check("start: base slab is 65% of the short side (19.5 cm), centred", is_equal_approx((base["size"] as Vector2).x, 0.195) and (base["center"] as Vector2) == Vector2.ZERO)
	check("start: sizes are board-relative (1.5 cm layers, ~4 mm perfect)", is_equal_approx(game.layer_height(), 0.0225) and is_equal_approx(game.perfect_tolerance(), 0.0039))
	check("start: one slab slides on X above the base", int(game.active["axis"]) == 0 and int(game.active["level"]) == 1)
	var node: MeshInstance3D = game.active["node"]
	var x0: float = node.position.x
	_step(game, 0.3)
	check("sweep: the slab moves along X only", absf(node.position.x - x0) > 0.01 and is_equal_approx(node.position.z, 0.0))
	var inside: bool = true
	for i: int in 200:
		game._process(DT)
		inside = inside and game.node_in_box(node)
	check("sweep: it never leaves the box footprint", inside)
	check("hud: score, height and session best", game.hud_text() == "0 | Height 0   Best 0" and not game.is_game_over_shown())
	check("hud: the platform status says how to play", host.get_status_text().contains("Tap anywhere"))
	await free_host(host)


func _test_tap_anywhere_and_cut() -> void:
	StackTowerGame.session_best = 0
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	# A tap in the top-left corner of the screen, nowhere near the board.
	host.route_gesture({"kind": &"tap", "position": Vector2(30, get_viewport().get_visible_rect().size.y - 30)})
	check("tap: a tap anywhere drops the slab", game.layers.size() == 2 and game.score == 1)
	check("tap: the next slab slides on Z", int(game.active["axis"]) == 1 and int(game.active["level"]) == 2)
	var top_before: Dictionary = game.layers.back()
	_aim(game, 0.03)
	var r: Dictionary = game.place()
	var top: Dictionary = game.layers.back()
	check("cut: 3 cm off on Z keeps the overlap (size and centre)", (
		not r["perfect"] and is_equal_approx((top["size"] as Vector2).y, (top_before["size"] as Vector2).y - 0.03)
		and is_equal_approx((top["center"] as Vector2).y, (top_before["center"] as Vector2).y + 0.015)
		and is_equal_approx((top["size"] as Vector2).x, (top_before["size"] as Vector2).x)
	))
	check("cut: the overhang falls as one debris piece of 3 cm", game.debris.size() >= 1 and is_equal_approx(((game.debris.back()["node"] as MeshInstance3D).mesh as BoxMesh).size.z, 0.03))
	var splash: Node = game.get_node_or_null(^"Tower/Splash2")
	check("splash: the landing dust cloud from tic-tac-toe, in the layer's colour", splash is HoloSplash and (splash as HoloSplash).color.is_equal_approx(StackTowerGame.layer_color(2)))
	var piece: MeshInstance3D = game.debris.back()["node"]
	var y0: float = piece.position.y
	var inside: bool = true
	var t: float = 0.0
	while t < 0.5:
		game._process(DT)
		t += DT
		inside = inside and game.node_in_box(piece)
	check("debris: falls and tumbles", piece.position.y < y0 - 0.02 and not piece.basis.is_equal_approx(Basis()))
	check("debris: fades out", float((piece.material_override as ShaderMaterial).get_shader_parameter("intensity")) < 0.7)
	_step(game, 1.0)
	check("debris: stays inside the box and is gone after ~1 s", inside and game.debris.is_empty())
	check("score: two placements, no perfects = 2", game.score == 2 and game.streak == 0 and game.height() == 2)
	await free_host(host)


func _test_perfects_and_regrow() -> void:
	StackTowerGame.session_best = 0
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	_aim(game, 0.04)
	game.place()
	var shrunk: Vector2 = (game.layers.back() as Dictionary)["size"]
	_aim(game, game.perfect_tolerance() * 0.8)
	var r: Dictionary = game.place()
	var top: Dictionary = game.layers.back()
	var below: Dictionary = game.layers[game.layers.size() - 2]
	check("perfect: a near-perfect drop snaps exactly onto the one below", r["perfect"] and (top["center"] as Vector2).is_equal_approx(below["center"]) and (top["size"] as Vector2).is_equal_approx(shrunk))
	check("perfect: no debris, streak 1, score 1 + 1 bonus", game.debris.size() == 1 and game.streak == 1 and game.score == 3)
	check("perfect: a gold glow pulse and a flash on the layer", (
		game.pulse() != null and float(((top["node"] as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("flash")) > 1.0
	))
	_step(game, 0.6)
	check("perfect: the pulse fades and is removed, the layer's flash back to 0", (
		game.pulse() == null and float(((top["node"] as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("flash")) == 0.0
	))
	_aim(game, -game.perfect_tolerance() * 0.5)
	game.place()
	check("perfect: streak 2 (bonus 2), no regrow yet", game.streak == 2 and game.score == 6 and ((game.layers.back() as Dictionary)["size"] as Vector2).is_equal_approx(shrunk))
	var flashed: MeshInstance3D = (game.layers.back() as Dictionary)["node"]
	_aim(game, 0.0)
	game.place()
	check("perfect: back-to-back perfects never leave an old layer flashing", float((flashed.material_override as ShaderMaterial).get_shader_parameter("flash")) == 0.0)
	var grown: Vector2 = (game.layers.back() as Dictionary)["size"]
	check("regrow: the 3rd perfect in a row regrows the slab a little", game.streak == 3 and grown.x > shrunk.x + 0.008 and is_equal_approx(grown.y, game.base_size()) and game.score == 10)
	for i: int in 6:
		_aim(game, 0.0)
		game.place()
	var capped: Vector2 = (game.layers.back() as Dictionary)["size"]
	check("regrow: never past the base size, still on the board", (
		capped.x <= game.base_size() + 0.0001 and capped.y <= game.base_size() + 0.0001 and game.node_in_box((game.layers.back() as Dictionary)["node"])
	))
	check("hud: shows the perfect streak", game.hud_text().contains("Perfect ×9") and game.best_streak == 9)
	_aim(game, 0.02)
	game.place()
	check("perfect: an imperfect drop resets the streak", game.streak == 0)
	await free_host(host)


func _test_miss_and_restart() -> void:
	StackTowerGame.session_best = 0
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	for i: int in 3:
		_aim(game, 0.0)
		game.place()
	var score_before: int = game.score
	var top_size: Vector2 = (game.layers.back() as Dictionary)["size"]
	_aim(game, top_size[int(game.active["axis"])] + 0.002)
	var r: Dictionary = game.place()
	check("miss: missing the tower ends the game", r["miss"] and game.state == StackTowerGame.State.OVER and game.active.is_empty())
	check("miss: the whole slab falls as debris", game.debris.size() == 1)
	check("game over: the panel shows height, score and best, with Restart", (
		game.is_game_over_shown() and game.restart_button.visible and game._over_label.text.contains("Height 3")
		and StackTowerGame.session_best == score_before and host.get_status_text().contains("Restart")
	))
	var layers_before: int = game.layers.size()
	game.tap()
	check("game over: an immediate tap does not restart (no accidental restarts)", game.state == StackTowerGame.State.OVER and game.layers.size() == layers_before)
	game.restart_button.pressed.emit()
	await frames(1)
	check("restart: a fresh tower (base only, score 0), best kept for the session", (
		game.state == StackTowerGame.State.PLAYING and game.layers.size() == 1 and game.score == 0 and game.debris.is_empty()
		and StackTowerGame.session_best == score_before and game.hud_text().contains("Best %d" % score_before) and not game.is_game_over_shown()
		and is_equal_approx(game.scroll, 0.0)
	))
	_aim(game, 0.5)
	game.place()
	_step(game, StackTowerGame.RESTART_DELAY + 0.05)
	game.tap()
	check("restart: after a moment a tap anywhere restarts too", game.state == StackTowerGame.State.PLAYING and game.layers.size() == 1)
	await free_host(host)


func _test_scroll_keeps_inside_box() -> void:
	StackTowerGame.session_best = 0
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	host.set_box_height(0.4)
	var box_h: float = game.get_box().height()
	var inside: bool = true
	var under_lid: bool = true
	for i: int in 40:
		_aim(game, 0.0 if i % 4 != 3 else 0.006)
		game.place()
		for k: int in 6:
			game._process(DT)
			var node: MeshInstance3D = game.active["node"]
			inside = inside and game.node_in_box(node)
			under_lid = under_lid and game.tower_top() + game.layer_height() <= box_h + 0.0001
	check("scroll: 40 layers (90 cm) in a 40 cm box: the tower sinks", game.scroll < -0.4 and game.height() == 40)
	check("scroll: the sliding slab never leaves the box, the lid is never passed", inside and under_lid)
	_step(game, 1.0)
	var room: float = box_h - (game.tower_top() + game.layer_height())
	check("scroll: settles with two free layers under the lid", absf(room - (game.unit() * StackTowerGame.TOP_MARGIN_RATIO + 2.0 * game.layer_height())) < 0.002)
	var sunk: int = 0
	var all_in: bool = true
	for layer: Dictionary in game.layers:
		if layer["node"] == null:
			sunk += 1
		elif is_instance_valid(layer["node"]):
			all_in = all_in and game.node_in_box(layer["node"]) or game.board_aabb(layer["node"]).position.y < game.pedestal_top()
	check("scroll: layers that sink into the pedestal are freed, the rest stay in the box", sunk > 10 and all_in)
	host.set_box_height(0.35)
	await frames(1)
	check("scroll: lowering the airspace sinks the tower at once", game.tower_top() + game.layer_height() <= 0.35 + 0.0001)
	host.set_box_height(1.2)
	_step(game, 2.0)
	check("scroll: a taller box never lifts the tower above the pedestal", game.scroll <= 0.0)
	await free_host(host)


func _test_camera_follows_top() -> void:
	var ttt: GameHost = await make_host(&"tic_tac_toe")
	var ttt_pos: Vector3 = ttt.orbit_camera.position
	await frames(5)
	check("camera: tic-tac-toe keeps the fixed framing", ttt.view_focus_point() == null and ttt.orbit_camera.position.is_equal_approx(ttt_pos))
	await free_host(ttt)
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	for i: int in 12:
		_aim(game, 0.0)
		game.place()
	var focus: Vector3 = host.view_focus_point()
	check("camera: the focus is the tower top", absf(focus.y - game.tower_top()) < 0.001 and game.tower_top() > 0.25)
	for i: int in 90:
		host._process(DT)
	check("camera: the touch camera eases up to the tower top", host.orbit_camera.position.distance_to(host.view_focus_point()) < 0.01)
	await free_host(host)


func _test_ar_tap_anywhere() -> void:
	ARSession.clear_saved_area()
	var host: GameHost = await _ar_host(&"stack_tower")
	var ar: ARSession = host.session
	_look(Vector3(0.0, 0.7, 0.45), Vector3(0.0, PLY_HEIGHT, -0.7))
	await frames(2)
	ar.place_at_reticle()
	ar.finish_fit()
	ar.set_locked(true)
	await frames(2)
	var game: StackTowerGame = _game(host)
	check("AR: Stack Tower plays on the locked board in its tall box", game.is_playing() and ar.is_ar() and is_equal_approx(game.get_box().height(), 0.8))
	var size: Vector2 = get_viewport().get_visible_rect().size
	_tap(Vector2(size.x * 0.85, size.y * 0.2))
	await frames(1)
	check("AR: a screen tap away from the board drops the slab", game.layers.size() == 2)
	var orbit_before: Vector3 = host.orbit_camera.position
	for i: int in 30:
		host._process(DT)
	check("AR: the touch-camera focus is ignored in AR", host.orbit_camera.position.is_equal_approx(orbit_before))
	await free_host(host)


func _is_solid(node: MeshInstance3D) -> bool:
	var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
	var hull: MeshInstance3D = node.get_node_or_null(^"Outline") as MeshInstance3D
	return (
		mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
		and mat.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and is_equal_approx(mat.albedo_color.a, 1.0)
		and hull != null and (hull.material_override as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_FRONT
		and ((hull.mesh as BoxMesh).size.x > (node.mesh as BoxMesh).size.x)
	)


func _test_solid_style() -> void:
	StackTowerGame.session_best = 0
	StackTowerGame.session_style = StackTowerGame.Style.HOLOGRAM
	var host: GameHost = await make_host(&"stack_tower")
	var game: StackTowerGame = _game(host)
	check("style: Hologram is the default (see-through Holo shader, edges on the slab)", (
		game.style == StackTowerGame.Style.HOLOGRAM and game.layers[0]["node"].material_override is ShaderMaterial
		and (game.active["node"] as Node).get_node(^"Edges").visible and game.style_button.text == "Style: Hologram"
	))
	for o: float in [0.02, 0.0, -0.01]:
		_aim(game, o)
		game.place()
	_aim(game, 0.03)
	game.place()
	var score_before: int = game.score
	var layers_before: int = game.layers.size()
	var phase_before: float = float(game.active["phase"])
	# Tap the Style button through the host, like a finger.
	var button_centre: Vector2 = game.style_button.get_global_rect().get_center()
	check("style: the HUD button is game UI (not a board touch)", game.is_over_game_ui(button_centre) and host.is_over_platform_ui(button_centre))
	_tap(button_centre)
	await frames(1)
	check("style: a finger on the Style button never reaches the board", game.layers.size() == layers_before and game.score == score_before)
	# (Headless pushed touches skip touch-to-mouse emulation, so press it here.)
	game.style_button.pressed.emit()
	await frames(1)
	check("style: tapping Style switches to Solid mid-game without dropping a slab or restarting", (
		game.style == StackTowerGame.Style.SOLID and game.layers.size() == layers_before and game.score == score_before
		and float(game.active["phase"]) >= phase_before and game.style_button.text == "Style: Solid"
	))
	var all_solid: bool = true
	var colours_kept: bool = true
	for layer: Dictionary in game.layers:
		var node: MeshInstance3D = layer["node"]
		all_solid = all_solid and _is_solid(node)
		var c: Color = (node.material_override as StandardMaterial3D).albedo_color
		colours_kept = colours_kept and Color(c.r, c.g, c.b).is_equal_approx(StackTowerGame.layer_color(int(layer["level"])))
	check("solid: every layer is an opaque, lit block with an outline (inverted hull)", all_solid)
	check("solid: layers keep the per-layer gradient colours", colours_kept)
	var layer_outline: Color = ((game.layers.back()["node"] as Node).get_node(^"Outline").material_override as StandardMaterial3D).albedo_color
	check("solid: layer outlines are a darker shade of the layer colour", layer_outline.get_luminance() < StackTowerGame.layer_color(4).get_luminance() * 0.5)
	var active: MeshInstance3D = game.active["node"]
	var active_mat: StandardMaterial3D = active.material_override as StandardMaterial3D
	var top_mat: StandardMaterial3D = (game.layers.back()["node"] as MeshInstance3D).material_override as StandardMaterial3D
	var active_outline: Color = (active.get_node(^"Outline").material_override as StandardMaterial3D).albedo_color
	check("solid: the sliding slab stands out: solid, emission lift, bright outline, no hologram edges", (
		_is_solid(active) and active_mat.emission_energy_multiplier > top_mat.emission_energy_multiplier + 0.3
		and active_outline.get_luminance() > 0.9 and not active.get_node(^"Edges").visible
	))
	check("solid: no additive / see-through ghosting on the tower", (
		game.debris.size() >= 1 and _is_solid(game.debris.back()["node"]) and active_mat.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
	))
	var piece: Dictionary = game.debris.back()
	var inside: bool = true
	for i: int in 30:
		game._process(DT)
		inside = inside and game.node_in_box(piece["node"])
	check("solid: debris shrinks away instead of fading, inside the box", (
		inside and (piece["node"] as MeshInstance3D).scale.x < 0.95 and is_equal_approx(((piece["node"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a, 1.0)
	))
	_aim(game, 0.0)
	game.place()
	var perfect_node: MeshInstance3D = game.layers.back()["node"]
	check("solid: a perfect still pulses (emission flash) and splashes", game.pulse() != null and game.get_flash(perfect_node) > 1.0 and _is_solid(perfect_node))
	_step(game, 0.6)
	check("solid: the flash settles back to a plain block", is_equal_approx((perfect_node.material_override as StandardMaterial3D).emission_energy_multiplier, 0.0))
	check("solid: new layers and slabs come out solid", _is_solid(perfect_node) and _is_solid(game.active["node"]))
	check("style: the choice is remembered for the session", StackTowerGame.session_style == StackTowerGame.Style.SOLID)
	await free_host(host)
	host = await make_host(&"stack_tower")
	game = _game(host)
	check("style: re-opening the game starts in Solid", game.style == StackTowerGame.Style.SOLID and _is_solid(game.layers[0]["node"]) and _is_solid(game.active["node"]))
	var top_size: Vector2 = game.layers.back()["size"]
	_aim(game, top_size[int(game.active["axis"])] + 0.01)
	game.place()
	game.restart_button.pressed.emit()
	await frames(1)
	check("style: Restart keeps the style", game.style == StackTowerGame.Style.SOLID and _is_solid(game.layers[0]["node"]))
	game.toggle_style()
	var back: bool = game.layers[0]["node"].material_override is ShaderMaterial and (game.layers[0]["node"] as Node).get_node_or_null(^"Outline") == null
	check("style: toggling back gives Hologram again (outlines removed, edges back)", (
		back and game.style == StackTowerGame.Style.HOLOGRAM and (game.active["node"] as Node).get_node(^"Edges").visible
		and StackTowerGame.session_style == StackTowerGame.Style.HOLOGRAM
	))
	await free_host(host)
