extends "res://tests/surface_tests.gd"
## Platform UI vs game UI, for every bundled game, in AR, in both shapes
## (20:9 and 16:9): the AR HUD (placement / resize / border-fit buttons and
## handles, the Airspace slider, the locked row Unlock / Re-place / Recenter /
## Magnify, the status banner), the host's back button, dbg button and status
## line must never overlap anything the game draws. Before the board is
## locked the game UI is hidden; once locked (and magnified, and with a
## platform banner up such as a tracking warning) every visible game control
## is checked against every visible platform rect. Crystal Defense is also
## walked through its own UI states (menus, placement, popups, Start Wave /
## Autostart, banners, pause, defeat).
## Run: godot --headless --path . res://tests/ui_overlap_tests.tscn

const WINDOWS: Array[Vector2i] = [Vector2i(1080, 2340), Vector2i(2340, 1080), Vector2i(720, 1280), Vector2i(1280, 720)]
const BANNER_TEXT: String = "Re-finding the table… hold the phone on the board."

var _saved: Vector2i


func run_tests() -> void:
	_saved = get_tree().root.size
	ARSession.clear_saved_area()
	CrystalDefenseGame.next_seed = 3
	await _test_all_games()
	await _test_crystal_defense_states()
	if _xr != null:
		_xr.uninstall()
	get_tree().root.size = _saved
	await frames(3)
	ARSession.clear_saved_area()
	CrystalDefenseGame.next_seed = -1


var _xr: FakeXRInterface


## Window + an ARCore-style camera projection for that shape (so the fake
## session finds the table and its edges, as on a phone).
func _set_window(size: Vector2i) -> void:
	get_tree().root.size = size
	if _xr != null:
		_xr.uninstall()
	_xr = FakeXRInterface.new()
	if size.x > size.y:
		_xr.projection = FakeXRInterface.arcore_projection(Vector2(1920, 1080), 1460.0, Vector2(972.0, 531.0))
	else:
		_xr.projection = FakeXRInterface.arcore_projection(Vector2(1080, 1920), 1460.0, Vector2(531.0, 972.0))
	_xr.install()
	await frames(3)


func _view() -> Rect2:
	return get_viewport().get_visible_rect()


## Visible platform UI: AR HUD buttons, banner, Airspace panel, fit handles,
## debug line, and the host's back / dbg buttons and status text.
static func platform_rects(host: GameHost) -> Dictionary:
	var out: Dictionary = {}
	out["‹ Games"] = host._back_button.get_global_rect()
	if host.debug_button != null and host.debug_button.is_visible_in_tree():
		out["dbg"] = host.debug_button.get_global_rect()
	if host._status_label.is_visible_in_tree() and host._status_label.text != "":
		# The drawn text (right-aligned, may wrap).
		var lr: Rect2 = host._status_label.get_global_rect()
		var font: Font = host._status_label.get_theme_font("font")
		var w: float = minf(lr.size.x, font.get_string_size(host._status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, host._status_label.get_theme_font_size("font_size")).x)
		out["status"] = Rect2(Vector2(lr.end.x - w, lr.position.y), Vector2(w, lr.size.y))
	if host.session != null and host.session.hud != null:
		var hud: CalibrationHud = host.session.hud
		for b: Button in hud.all_buttons():
			if b.is_visible_in_tree():
				out["AR " + b.text] = b.get_global_rect()
		if hud._banner.is_visible_in_tree():
			out["AR banner"] = hud._banner.get_global_rect()
		if hud.airspace_panel.is_visible_in_tree():
			out["AR airspace"] = hud.airspace_panel.get_global_rect()
		if hud.debug_label.is_visible_in_tree() and hud.debug_label.text != "":
			out["AR debug"] = hud.debug_label.get_global_rect()
		if hud.fit_handles.is_visible_in_tree():
			for i: int in hud.fit_handles.handles.size():
				var at: Vector2 = hud.fit_handles.handles[i]["screen"] as Vector2
				var rad: float = FitHandles.CORNER_RADIUS * 1.25
				out["fit handle %d" % i] = Rect2(at - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
	return out


## Visible game UI: buttons, panels, progress bars and labels with text
## (full-screen containers excluded).
static func game_rects(game: Node, view: Rect2) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		var ctl := n as Control
		if ctl == null or not ctl.is_visible_in_tree():
			continue
		var r: Rect2 = ctl.get_global_rect()
		if r.size.x < 2.0 or r.size.y < 2.0 or (r.size.x >= view.size.x * 0.95 and r.size.y >= view.size.y * 0.95):
			continue
		var keep: bool = ctl is Button or ctl is PanelContainer or ctl is Panel or ctl is ProgressBar or (ctl is Label and (ctl as Label).text.strip_edges() != "" and ctl.modulate.a > 0.05)
		if keep:
			if ctl is Label:
				r = label_text_rect(ctl as Label)
			out["%s/%s" % [ctl.get_parent().name, ctl.name]] = r
	return out


## Where a label's text is drawn (its box can be much wider than the text).
static func label_text_rect(label: Label) -> Rect2:
	var r: Rect2 = label.get_global_rect()
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var w: float = 0.0
	for line: String in label.text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	w = minf(w + 8.0, r.size.x)
	var x: float = r.position.x
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = r.position.x + (r.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = r.end.x - w
	return Rect2(Vector2(x, r.position.y), Vector2(w, r.size.y))


static func overlaps(platform: Dictionary, game: Dictionary) -> PackedStringArray:
	var bad: PackedStringArray = []
	for p: String in platform:
		for g: String in game:
			if (platform[p] as Rect2).intersects(game[g] as Rect2):
				bad.append("%s × %s" % [g, p])
	return bad


func _check_state(host: GameHost, label: String) -> void:
	await frames(3)
	var view: Rect2 = _view()
	var p: Dictionary = platform_rects(host)
	var g: Dictionary = game_rects(host.game, view)
	var bad: PackedStringArray = overlaps(p, g)
	var shown: String = "%d game / %d platform rects" % [g.size(), p.size()]
	if not bad.is_empty():
		for k: String in bad:
			var parts: PackedStringArray = k.split(" × ")
			print("  ", k, " ", g[parts[0]], " ", p[parts[1]], " view ", view.size)
	check("%s: no game UI under platform UI (%s)%s" % [label, shown, "" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 6))], bad.is_empty())


func _locked_host(id: StringName) -> GameHost:
	var host: GameHost = await _ar_host(id)
	host.session.place_at_reticle()
	await frames(2)
	host.session.set_locked(true)
	await frames(4)
	return host


func _test_all_games() -> void:
	var catalog := GameCatalog.new()
	catalog.scan()
	for window: Vector2i in WINDOWS:
		await _set_window(window)
		var shape: String = "%dx%d" % [window.x, window.y]
		for manifest: LGGameManifest in catalog.list():
			var id: StringName = manifest.id
			var host: GameHost = await _ar_host(id)
			var ar: ARSession = host.session
			var hud: CalibrationHud = ar.hud
			# Placing on the detected surface opens Border fit (handles);
			# Done goes on to Adjust (resize / Airspace / Lock).
			ar.place_at_reticle()
			await frames(3)
			var steps: Array[int] = []
			for attempt: int in 2:
				check("%s %s step %d: the game waits (not playing)" % [shape, id, ar.flow.step], not host.game.is_playing())
				if id == &"crystal_defense":
					check("%s crystal_defense step %d: no game controls showing" % [shape, ar.flow.step], game_rects(host.game, _view()).is_empty())
				if ar.flow.step == CalibrationFlow.Step.FITTING:
					steps.append(ar.flow.step)
					check("%s %s border fit: handles up" % [shape, id], hud.fit_handles.is_visible_in_tree() and not hud.fit_handles.handles.is_empty())
					await _check_state(host, "%s %s border fit" % [shape, id])
					ar.finish_fit()
				elif ar.flow.step == CalibrationFlow.Step.ADJUSTING:
					steps.append(ar.flow.step)
					await _check_state(host, "%s %s adjusting/resize" % [shape, id])
					ar.begin_fit()
				await frames(3)
			check("%s %s: walked Border fit and Adjust (%s)" % [shape, id, steps], steps.has(CalibrationFlow.Step.FITTING) and steps.has(CalibrationFlow.Step.ADJUSTING))
			host.session.set_locked(true)
			await frames(4)
			check("%s %s locked: playing" % [shape, id], host.game.is_playing())
			await _check_state(host, "%s %s locked" % [shape, id])
			hud.magnify_button.button_pressed = true
			await frames(2)
			await _check_state(host, "%s %s locked + magnify" % [shape, id])
			# A platform banner while playing (tracking warning, low light).
			var row_inset: float = host.game.ui_bottom_inset()
			hud.set_status(BANNER_TEXT)
			await frames(3)
			check("%s %s locked + platform banner: banner sits above the AR row and lifts the game's bottom inset (%d -> %d px)" % [shape, id, roundi(row_inset), roundi(host.game.ui_bottom_inset())],
				hud.banner_at_bottom and hud._banner.get_global_rect().end.y <= _view().size.y - row_inset + 1.0 and host.game.ui_bottom_inset() > row_inset + 40.0)
			await _check_state(host, "%s %s locked + platform banner" % [shape, id])
			hud.set_status("")
			host.session.set_locked(false)
			await frames(3)
			check("%s %s unlocked: the step banner is back at the top" % [shape, id], not hud.banner_at_bottom and hud._banner.get_global_rect().position.y < _view().size.y * 0.3)
			await free_host(host)


## Crystal Defense's own UI states, board locked in AR (magnify on, and a
## platform banner up for the top-of-screen states).
func _test_crystal_defense_states() -> void:
	for window: Vector2i in WINDOWS:
		await _set_window(window)
		var shape: String = "%dx%d" % [window.x, window.y]
		var host: GameHost = await _locked_host(&"crystal_defense")
		var game: CrystalDefenseGame = host.game as CrystalDefenseGame
		var hud: CalibrationHud = host.session.hud
		hud.magnify_button.button_pressed = true
		for i: int in 50:
			game._process(1.0 / 20.0)
		var sim: CDSim = game.sim
		sim.wallet.balance = 500
		var tower: int = sim.build(&"arrow", Vector2i(3, 6))
		game._handle_events()
		await _check_state(host, "%s cd prep HUD + Start Wave" % shape)
		game.open_build()
		await _check_state(host, "%s cd Build menu (Towers)" % shape)
		game.sheet.show_tab(&"barriers")
		await _check_state(host, "%s cd Build menu (Barriers)" % shape)
		game.sheet.card(&"palisade").pressed.emit()
		await _check_state(host, "%s cd placing ghost + ✓ bar" % shape)
		game.cancel_mode()
		game.open_summon()
		await _check_state(host, "%s cd Summon menu" % shape)
		game.sheet.card(&"knight").pressed.emit()
		await _check_state(host, "%s cd squad popup" % shape)
		game.begin_move(game.selected_squad)
		await _check_state(host, "%s cd squad move bar (✓ ↻ ✕)" % shape)
		game.cancel_mode()
		game.tap_cell(Vector2i(3, 6))
		await _check_state(host, "%s cd tower popup" % shape)
		game.tap_cell(Vector2i(5, 5))
		await _check_state(host, "%s cd Crystal popup" % shape)
		game._clear_selection()
		# Autostart countdown on the Start button.
		sim.start_wave()
		sim.set_autostart(true)
		sim.crystal_hp = 1.0e6
		var guard: int = 0
		while sim.phase() != CDSim.PHASE_PREP and guard < 4000:
			game._process(1.0 / 20.0)
			guard += 1
		game._process(0.01)
		await _check_state(host, "%s cd Autostart countdown" % shape)
		sim.set_autostart(false)
		game.start_wave()
		for i: int in 40:
			game._process(1.0 / 20.0)
		game._show_banner("Wave %d" % sim.wave)
		await _check_state(host, "%s cd mid-wave HUD + wave banner" % shape)
		hud.set_status(BANNER_TEXT)
		await _check_state(host, "%s cd mid-wave + platform banner" % shape)
		game.tap_cell(Vector2i(3, 6))
		await _check_state(host, "%s cd tower popup + platform banner" % shape)
		game._clear_selection()
		hud.set_status("")
		game.pause(&"button")
		await _check_state(host, "%s cd pause panel" % shape)
		game.resume()
		for i: int in 70:
			game._process(1.0 / 20.0)
		sim.crystal_hp = 0.0
		for i: int in 3:
			game._process(1.0 / 20.0)
		check("%s cd defeat reached" % shape, sim.phase() == CDSim.PHASE_DEFEAT and game._over_panel.visible)
		await _check_state(host, "%s cd defeat panel" % shape)
		check("%s cd: tower id sanity" % shape, tower != 0)
		await free_host(host)
