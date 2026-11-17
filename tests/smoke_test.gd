extends LGTestSuite
## Smoke test: the main scene boots, lists games, and every bundled game
## launches through the real LookingGlass autoload.
## Run: godot --headless --path . res://tests/smoke_test.tscn


func run_tests() -> void:
	var looking_glass: Node = get_node_or_null(^"/root/LookingGlass")
	check("smoke: the LookingGlass autoload is present", looking_glass != null)
	var catalog: GameCatalog = looking_glass.get("catalog") as GameCatalog
	check("smoke: the catalog has no rejected manifests", catalog.errors.is_empty())
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	var launcher: Node = (load(main_scene) as PackedScene).instantiate()
	add_child(launcher)
	await frames(2)
	check("smoke: the launcher boots and shows every game", (launcher as Launcher).cards.size() == catalog.size())
	launcher.queue_free()
	await frames(1)
	for manifest: LGGameManifest in catalog.list():
		looking_glass.set("selected_game_id", manifest.id)
		var host := (load(LookingGlass.HOST_SCENE) as PackedScene).instantiate() as GameHost
		host.exit_handler = func() -> void: pass
		add_child(host)
		await frames(3)
		check("smoke: %s launches from the host scene and plays" % manifest.id, (
			host.game != null and host.game.manifest == manifest and host.game.is_playing()
		))
		await free_host(host)
	looking_glass.set("selected_game_id", &"")
	check("smoke: the Android AR export preset exists", FileAccess.get_file_as_string("res://export_presets.cfg").contains("name=\"Android AR\""))
