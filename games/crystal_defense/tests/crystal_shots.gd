extends LGTestSuite
## Renders the screenshots (not a test; run under xvfb with rendering):
## xvfb-run godot --path . res://games/crystal_defense/tests/crystal_shots.tscn -- <out_dir>

func run_tests() -> void:
	var out: String = "/workspace/android"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	CrystalDefenseGame.next_seed = 5
	# 1) Start of a run, portrait.
	get_tree().root.size = Vector2i(1080, 2340)
	await frames(3)
	var host: GameHost = await make_host(&"crystal_defense")
	var game: CrystalDefenseGame = host.game as CrystalDefenseGame
	_frame(host, true)
	for i in 50:
		game._process(1.0 / 20.0)
	await frames(10)
	await _save(out + "/crystal_start_portrait.png")
	await free_host(host)
	# 2) Mid-wave with towers and enemies, landscape.
	get_tree().root.size = Vector2i(2340, 1080)
	await frames(3)
	host = await make_host(&"crystal_defense")
	game = host.game as CrystalDefenseGame
	_frame(host, false)
	for i in 50:
		game._process(1.0 / 20.0)
	var sim: CDSim = game.sim
	sim.wallet.balance = 400
	for c: Vector2i in [Vector2i(3, 5), Vector2i(3, 7), Vector2i(8, 4)]:
		sim.build(&"arrow", c)
	sim.build(&"bombard", Vector2i(4, 9))
	for c: Vector2i in [Vector2i(2, 4), Vector2i(2, 6), Vector2i(2, 8), Vector2i(4, 3)]:
		sim.build(&"palisade", c)
	sim.build(&"stone_wall", Vector2i(9, 7))
	sim.upgrade(sim.structure_at(Vector2i(3, 5)))
	sim.upgrade(sim.structure_at(Vector2i(4, 9)))
	var k: int = sim.summon(&"knight")
	sim.squads[k]["exp"] = 999.0
	sim.upgrade_squad(k)
	sim.squads[k]["exp"] = 999.0
	sim.upgrade_squad(k)
	sim.move_squad(k, Vector2i(4, 6))
	sim.turn_squad(k, 2)
	game._handle_events()
	# Jump to wave 4 (West + East).
	sim.wave = 3
	sim.plan = {}
	game.start_wave()
	for i in 170:
		game._process(1.0 / 20.0)
	game.toggle_ranges()
	await frames(10)
	await _save(out + "/crystal_midwave_landscape.png")
	await free_host(host)
	CrystalDefenseGame.next_seed = -1
	get_tree().quit()


## A closer orbit view than the default fit (the default frames the whole box).
func _frame(host: GameHost, portrait: bool) -> void:
	var oc: OrbitCamera = host.orbit_camera
	oc.pitch = deg_to_rad(-52.0 if portrait else -48.0)
	oc.distance *= 0.62 if portrait else 0.78
	oc._apply()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
	check("saved " + path.get_file(), FileAccess.file_exists(path))
