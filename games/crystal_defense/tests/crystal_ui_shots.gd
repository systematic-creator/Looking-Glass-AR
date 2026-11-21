extends "res://tests/surface_tests.gd"
## Screenshots of Crystal Defense under the Looking Glass AR HUD in each AR
## state, portrait and landscape (not a test; run under xvfb):
## xvfb-run godot --path . res://games/crystal_defense/tests/crystal_ui_shots.tscn -- <out_dir>
## (No camera feed in the fake AR session, so the background is empty.)

var _out: String = "/workspace/android"


func run_tests() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	CrystalDefenseGame.next_seed = 5
	for portrait: bool in [true, false]:
		var shape: String = "portrait" if portrait else "landscape"
		get_tree().root.size = Vector2i(1080, 2340) if portrait else Vector2i(2340, 1080)
		ARSession.clear_saved_area()
		var xr := FakeXRInterface.new()
		if portrait:
			xr.projection = FakeXRInterface.arcore_projection(Vector2(1080, 1920), 1460.0, Vector2(531.0, 972.0))
		else:
			xr.projection = FakeXRInterface.arcore_projection(Vector2(1920, 1080), 1460.0, Vector2(972.0, 531.0))
		xr.install()
		await frames(3)
		var host: GameHost = await _ar_host(&"crystal_defense")
		var ar: ARSession = host.session
		# Stand-in for the camera feed (none in the fake session): a plain
		# backdrop, so every frame is cleared.
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.32, 0.30, 0.27)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.6)
		ar.xr_camera.environment = env
		ar.place_at_reticle()
		await frames(6)
		await _save("crystal_ui_%s_1_border_fit" % shape)
		ar.finish_fit()
		await frames(6)
		await _save("crystal_ui_%s_2_adjust_resize" % shape)
		ar.set_locked(true)
		await frames(4)
		var game: CrystalDefenseGame = host.game as CrystalDefenseGame
		for i: int in 50:
			game._process(1.0 / 20.0)
		var sim: CDSim = game.sim
		sim.wallet.balance = 400
		sim.build(&"arrow", Vector2i(3, 6))
		sim.build(&"palisade", Vector2i(2, 5))
		game._handle_events()
		await frames(4)
		await _save("crystal_ui_%s_3_locked" % shape)
		game.open_build()
		await frames(4)
		await _save("crystal_ui_%s_4_locked_build_menu" % shape)
		game.sheet.card(&"arrow").pressed.emit()
		await frames(4)
		await _save("crystal_ui_%s_5_locked_placing_tower" % shape)
		game.cancel_mode()
		ar.hud.magnify_button.button_pressed = true
		game.tap_cell(Vector2i(3, 6))
		await frames(4)
		await _save("crystal_ui_%s_6_magnify_tower_popup" % shape)
		game._clear_selection()
		game.start_wave()
		for i: int in 80:
			game._process(1.0 / 20.0)
		ar.hud.set_status("Re-finding the table… hold the phone on the board.")
		await frames(4)
		await _save("crystal_ui_%s_7_midwave_platform_banner" % shape)
		ar.hud.set_status("")
		await free_host(host)
		xr.uninstall()
	ARSession.clear_saved_area()
	CrystalDefenseGame.next_seed = -1
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
