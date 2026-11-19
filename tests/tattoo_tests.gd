extends "res://tests/surface_tests.gd"
## Tattoo Studio: ink maths (accumulation, once-per-stroke, eraser, colour),
## painting on the real mesh (seams, curvature, facing), the model contract
## and loader (glTF drop-in), the platform's tall box and ray-stroke /
## pinch hooks, and the game in the host: touch strokes, rotate, scale,
## focus, clear-all confirmation and ink permanence across viewpoints,
## zoom, scale, model switches, pause / resume and relaunch.
## Run: godot --headless --path . res://tests/tattoo_tests.tscn

const ID: StringName = &"tattoo_studio"
var male: Dictionary = {}
var male_paint: TattooPaintMesh


func run_tests() -> void:
	_reset_session()
	male = TattooBodyBuilder.build("male")
	male_paint = TattooPaintMesh.from_arrays(male["vertices"], male["uvs"], male["indices"])
	_test_ink_maths()
	_test_once_per_stroke()
	_test_eraser()
	_test_seam()
	_test_curvature_and_facing()
	_test_contract_defaults()
	_test_contract_rejects()
	_test_gltf_drop_in()
	_test_platform_box_and_manifest()
	await _test_hooks_gated()
	await _test_touch_strokes()
	await _test_rotate_scale_pinch()
	await _test_box_follows_model()
	await _test_focus()
	await _test_permanence()
	await _test_clear_confirm()
	await _test_ar_miniature_on_table()
	_reset_session()


func _reset_session() -> void:
	TattooStudioGame.session_layers = {}
	TattooStudioGame.session_scale = {}
	TattooStudioGame.session_yaw = {}
	TattooStudioGame.session_model = &""
	TattooStudioGame.session_tools = {}
	# The saved airspace (placement file) would carry a shrunken model over.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lg_placement_%s.cfg" % ID))


func _hit_front(paint: TattooPaintMesh, x: float, y: float) -> Dictionary:
	return paint.raycast(Vector3(x, y, 2.0), Vector3(0, 0, -1))


# --- Ink maths ---------------------------------------------------------------------

func _test_ink_maths() -> void:
	var black: Vector3 = TattooInkLayer.absorbance(Color(0.07, 0.07, 0.08))
	var od := Vector3.ZERO
	var load: float = 0.0
	var loads: Array[float] = []
	var lum: Array[float] = []
	var skin := Color(0.82, 0.64, 0.52).srgb_to_linear()
	for i: int in 6:
		var r: Array = TattooInkLayer.needle_pass(od, load, 1.0, black)
		od = r[0]
		load = r[1]
		loads.append(load)
		lum.append(TattooInkLayer.shade(skin, od).get_luminance())
	check("ink: pass loads 0.25 / 0.44 / 0.58 (diminishing returns)", (
		is_equal_approx(loads[0], 0.25) and absf(loads[1] - 0.4375) < 1e-4 and absf(loads[2] - 0.578125) < 1e-4
	))
	check("ink: each pass adds less than the one before", loads[1] - loads[0] < loads[0] and loads[2] - loads[1] < loads[1] - loads[0])
	check("ink: every pass darkens (light wash -> deep)", lum[0] < skin.get_luminance() and lum[1] < lum[0] and lum[2] < lum[1] and lum[5] < lum[2])
	check("ink: the first black pass is a mid wash, not solid", lum[0] > 0.03)
	var r50: Array = [Vector3.ZERO, 0.0]
	for i: int in 50:
		r50 = TattooInkLayer.needle_pass(r50[0], r50[1], 1.0, black)
	check("ink: load never passes 1, OD stays capped", float(r50[1]) <= 1.0 and (r50[0] as Vector3).x <= TattooInkLayer.OD_MAX)
	var red: Vector3 = TattooInkLayer.absorbance(Color(0.8, 0.1, 0.12))
	var r1: Array = TattooInkLayer.needle_pass(Vector3.ZERO, 0.0, 1.0, red)
	var r3: Array = TattooInkLayer.needle_pass(r1[0], r1[1], 1.0, red)
	r3 = TattooInkLayer.needle_pass(r3[0], r3[1], 1.0, red)
	var c1: Color = TattooInkLayer.shade(skin, r1[0])
	var c3: Color = TattooInkLayer.shade(skin, r3[0])
	check("ink: red gets more saturated with passes", c3.s > c1.s and c1.s > skin.s and c3.v < c1.v)
	check("ink: red absorbs green / blue far more than red", red.y > red.x * 4.0 and red.z > red.x * 4.0)
	var blue: Vector3 = TattooInkLayer.absorbance(Color(0.12, 0.26, 0.72))
	var mix: Array = TattooInkLayer.needle_pass(r1[0], r1[1], 1.0, blue)
	var cm: Color = TattooInkLayer.shade(skin, mix[0])
	check("ink: colours over each other mix subtractively (darker)", cm.get_luminance() < c1.get_luminance())
	var half: Array = TattooInkLayer.needle_pass(Vector3.ZERO, 0.0, 0.5, black)
	check("ink: half coverage (brush edge) gives half a pass", absf(float(half[1]) - 0.125) < 1e-5)
	check("ink: brush coverage 1 at the core, soft to 0 at the rim", (
		TattooInkLayer.coverage(0.0, 0.01) == 1.0 and TattooInkLayer.coverage(0.006, 0.01) == 1.0
		and TattooInkLayer.coverage(0.0099, 0.01) < 0.1 and TattooInkLayer.coverage(0.01, 0.01) == 0.0
	))


func _test_once_per_stroke() -> void:
	var ink := TattooInkLayer.new(1024)
	var hit: Dictionary = _hit_front(male_paint, 0.0, 1.2)
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var uv: Vector2 = hit["uv"]
	ink.begin_stroke(TattooInkLayer.Tool.NEEDLE, Color.BLACK)
	var first: int = ink.stamp(male_paint, p, n, 0.007)
	var after_one: float = ink.load_at_uv(uv)
	var again: int = 0
	for i: int in 20:
		again += ink.stamp(male_paint, p, n, 0.007)
	check("stroke: a stamp inks texels", first > 20 and absf(after_one - 0.25) < 0.01)
	check("stroke: holding still in one stroke adds nothing", again == 0 and is_equal_approx(ink.load_at_uv(uv), after_one))
	# A stroke passing nearby (lower coverage here) does not add either.
	ink.stamp(male_paint, p + Vector3(0.005, 0, 0), n, 0.007)
	check("stroke: overlapping stamps in one stroke count once", is_equal_approx(ink.load_at_uv(uv), after_one))
	ink.end_stroke()
	ink.begin_stroke(TattooInkLayer.Tool.NEEDLE, Color.BLACK)
	ink.stamp(male_paint, p, n, 0.007)
	ink.end_stroke()
	check("stroke: a second stroke deepens it (0.44)", absf(ink.load_at_uv(uv) - 0.4375) < 0.01)
	check("stroke: ink stays local (3 cm away is clean)", _hit_load(ink, 0.0, 1.23) == 0.0)
	ink.upload()
	check("ink: upload clears the dirty flag", not ink.dirty and ink.texture.get_width() == 1024)


func _hit_load(ink: TattooInkLayer, x: float, y: float) -> float:
	var h: Dictionary = _hit_front(male_paint, x, y)
	return 0.0 if h.is_empty() else ink.load_at_uv(h["uv"] as Vector2)


func _test_eraser() -> void:
	var ink := TattooInkLayer.new(1024)
	var hit: Dictionary = _hit_front(male_paint, 0.03, 1.15)
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	for i: int in 3:
		ink.begin_stroke(TattooInkLayer.Tool.NEEDLE, Color(0.12, 0.26, 0.72))
		ink.stamp(male_paint, p, n, 0.012)
		ink.end_stroke()
	var inked: float = ink.load_at_uv(hit["uv"] as Vector2)
	var od: Vector3 = ink.od_at_uv(hit["uv"] as Vector2)
	ink.begin_stroke(TattooInkLayer.Tool.ERASER, Color.BLACK)
	ink.stamp(male_paint, p + Vector3(0.0105, 0, 0), n, 0.012)
	ink.end_stroke()
	var partial: float = ink.load_at_uv(hit["uv"] as Vector2)
	check("eraser: its soft rim lightens without removing", partial < inked and partial > 0.0)
	var r: Array = TattooInkLayer.erase_pass(od, inked, 0.5)
	check("eraser: maths scales load and OD alike", is_equal_approx(float(r[1]), inked * 0.5) and (r[0] as Vector3).is_equal_approx(od * 0.5))
	ink.begin_stroke(TattooInkLayer.Tool.ERASER, Color.BLACK)
	ink.stamp(male_paint, p, n, 0.012)
	ink.end_stroke()
	check("eraser: its core removes the ink", ink.load_at_uv(hit["uv"] as Vector2) == 0.0 and ink.od_at_uv(hit["uv"] as Vector2) == Vector3.ZERO)
	var total_before: int = ink.inked_texels()
	ink.begin_stroke(TattooInkLayer.Tool.ERASER, Color.BLACK)
	ink.stamp(male_paint, p, n, 0.03)
	ink.end_stroke()
	check("eraser: a big eraser clears the whole patch", ink.inked_texels() == 0 and total_before > 0)


func _test_seam() -> void:
	# The body tube's UV seam runs down the middle of the back.
	var body: Rect2 = (male["parts"] as Array)[0]["island"]
	var hit: Dictionary = male_paint.raycast(Vector3(0.0005, 1.2, -2.0), Vector3(0, 0, 1))
	var uv: Vector2 = hit["uv"]
	var at_edge: bool = absf(uv.x - body.position.x) < 0.01 or absf(uv.x - body.end.x) < 0.01
	check("seam: the back centre line is the body island's edge", at_edge)
	var ink := TattooInkLayer.new(1024)
	ink.begin_stroke(TattooInkLayer.Tool.NEEDLE, Color.BLACK)
	ink.stamp(male_paint, hit["position"], hit["normal"], 0.01)
	ink.end_stroke()
	var left: float = ink.load_at_uv(Vector2(body.position.x + 1.5 / 1024.0, uv.y))
	var right: float = ink.load_at_uv(Vector2(body.end.x - 1.5 / 1024.0, uv.y))
	check("seam: a stamp on the seam inks both sides of the atlas", left > 0.2 and right > 0.2)
	# Both sides of the seam in 3D are inked symmetrically.
	var l3: Dictionary = male_paint.raycast(Vector3(-0.006, 1.2, -2.0), Vector3(0, 0, 1))
	var r3: Dictionary = male_paint.raycast(Vector3(0.006, 1.2, -2.0), Vector3(0, 0, 1))
	check("seam: 6 mm either side of the seam on the body are inked", (
		ink.load_at_uv(l3["uv"] as Vector2) > 0.2 and ink.load_at_uv(r3["uv"] as Vector2) > 0.2
	))
	var gutter: float = ink.load_at_uv(Vector2(body.position.x - 4.0 / 1024.0, uv.y))
	check("seam: no ink bleeds into the gutter next to the island", gutter == 0.0)


func _test_curvature_and_facing() -> void:
	# Band round the right upper arm through the game's stroke path code.
	var game: TattooStudioGame = _offline_game()
	var axis_a := Vector3(0.228, 1.28, -0.008)
	var pts: Array = []
	var dirs: Array = []
	for i: int in 49:
		var th: float = TAU * float(i) / 48.0
		var d := Vector3(cos(th), 0.0, sin(th))
		pts.append(axis_a)
		dirs.append(-d)
	var hits: int = game.paint_model_path(pts, dirs, TattooInkLayer.Tool.NEEDLE, 0.052)
	var ink: TattooInkLayer = game.ink
	var missing: int = 0
	for i: int in 72:
		var th2: float = TAU * float(i) / 72.0
		var d2 := Vector3(cos(th2), 0.0, sin(th2))
		var h: Dictionary = game.paint.raycast(axis_a + d2 * 0.052, -d2)
		if h.is_empty() or ink.load_at_uv(h["uv"] as Vector2) <= 0.0:
			missing += 1
	check("curve: a stroke round the arm hits the mesh all the way", hits == 49)
	check("curve: the band is continuous all round the arm (72 samples)", missing == 0)
	var above: Dictionary = game.paint.raycast(axis_a + Vector3(0.1, 0.03, 0), Vector3(-1, 0, 0))
	check("curve: and stays a line (3 cm above is clean)", ink.load_at_uv(above["uv"] as Vector2) == 0.0)
	# Inked texels map back onto the surface within the brush of the band.
	var sampled: int = 0
	var off: int = 0
	var size: int = ink.size
	var y: int = 0
	while y < size and sampled < 40:
		var x: int = 0
		while x < size and sampled < 40:
			if ink.texel_load(x, y) > 0.0:
				var uvp := Vector2((x + 0.5) / size, (y + 0.5) / size)
				var tri: int = game.paint.triangle_at_uv(uvp)
				if tri >= 0:
					sampled += 1
					var pos: Vector3 = game.paint.position_at_uv(tri, uvp)
					if absf(pos.y - 1.28) > game.brush_radius() + 0.004:
						off += 1
			x += 7
		y += 3
	check("curve: inked texels sit on the band in 3D (%d sampled)" % sampled, sampled >= 20 and off == 0)
	game.free()
	# Facing: a big stamp on the back of the hand leaves the palm clean.
	var ink2 := TattooInkLayer.new(1024)
	var outer: Dictionary = male_paint.raycast(Vector3(1.0, 0.80, 0.017), Vector3(-1, 0, 0))
	var inner: Dictionary = male_paint.raycast(Vector3(0.25, 0.80, 0.017), Vector3(1, 0, 0))
	ink2.begin_stroke(TattooInkLayer.Tool.NEEDLE, Color.BLACK)
	ink2.stamp(male_paint, outer["position"], outer["normal"], 0.022)
	ink2.end_stroke()
	check("facing: the back of the hand takes the ink", ink2.load_at_uv(outer["uv"] as Vector2) > 0.2)
	check("facing: the palm side (2-3 cm away through the hand) stays clean", (
		not inner.is_empty() and ink2.load_at_uv(inner["uv"] as Vector2) == 0.0
	))


## A game outside the host (for painting tests).
func _offline_game() -> TattooStudioGame:
	var game: TattooStudioGame = (load("res://games/tattoo_studio/tattoo_studio.tscn") as PackedScene).instantiate()
	game.manifest = load("res://games/tattoo_studio/manifest.tres") as LGGameManifest
	game.lg_board_ready()
	game.lg_set_locked(true)
	return game


# --- Contract + loader -----------------------------------------------------------------

func _test_contract_defaults() -> void:
	var entries: Array[TattooModelEntry] = TattooModelLoader.load_list()
	var ids: Array = entries.map(func(e: TattooModelEntry) -> StringName: return e.id)
	check("models: the list has male, female and lizard man", ids == [&"male", &"female", &"lizard"])
	for entry: TattooModelEntry in entries:
		var result: Dictionary = TattooModelLoader.build(entry)
		var paint: TattooPaintMesh = result["paint"]
		check("contract: %s passes (%d tris, %.2f m)" % [entry.id, paint.tri_count, float(result["height"])], (
			(result["errors"] as PackedStringArray).is_empty() and paint.tri_count < 40000
		))
		check("contract: %s UVs do not overlap" % entry.id, TattooModelContract.uv_overlap(paint) == 0.0)
	var parts: Array = TattooBodyBuilder.build("lizard")["parts"]
	var overlap: bool = false
	for i: int in parts.size():
		for j: int in range(i + 1, parts.size()):
			if (parts[i]["island"] as Rect2).intersects(parts[j]["island"] as Rect2):
				overlap = true
	var names: Array = parts.map(func(p: Dictionary) -> String: return String(p["name"]))
	check("models: lizard man has a snout and a tail, islands apart", names.has("snout") and names.has("tail") and not overlap)
	var l: Dictionary = TattooBodyBuilder.build("lizard")
	var tail_between_legs: bool = false
	var lv: PackedVector3Array = l["vertices"]
	var tail_start: int = 0
	for p: Dictionary in parts:
		if p["name"] == "tail":
			break
	# Tasteful: nothing hangs between the legs below the crotch from the front.
	for v: Vector3 in lv:
		if v.y < 0.78 and v.y > 0.15 and absf(v.x) < 0.012 and v.z > -0.05:
			tail_between_legs = true
	check("models: nothing sits between the legs below the crotch", not tail_between_legs and tail_start == 0)


func _arrays_of(kind: String) -> Array:
	var data: Dictionary = TattooBodyBuilder.build(kind)
	return [(data["vertices"] as PackedVector3Array).duplicate(), (data["uvs"] as PackedVector2Array).duplicate(), data["indices"]]


func _test_contract_rejects() -> void:
	var entry := TattooModelEntry.new()
	entry.height_m = 1.75
	var a: Array = _arrays_of("male")
	var no_uv := PackedVector2Array()
	no_uv.resize((a[0] as PackedVector3Array).size())
	no_uv.fill(Vector2.ZERO)
	check("contract: missing UV0 is rejected", _has(TattooModelContract.validate(TattooPaintMesh.from_arrays(a[0], no_uv, a[2]), entry), "UV0"))
	var tiled: PackedVector2Array = (a[1] as PackedVector2Array).duplicate()
	for i: int in tiled.size():
		tiled[i] *= 2.0
	check("contract: tiling UVs (outside 0-1) are rejected", _has(TattooModelContract.validate(TattooPaintMesh.from_arrays(a[0], tiled, a[2]), entry), "outside"))
	var stacked: PackedVector2Array = (a[1] as PackedVector2Array).duplicate()
	for i: int in stacked.size():
		stacked[i] = Vector2(fmod(stacked[i].x * 3.0, 1.0), fmod(stacked[i].y * 3.0, 1.0))
	check("contract: overlapping UVs are rejected", _has(TattooModelContract.validate(TattooPaintMesh.from_arrays(a[0], stacked, a[2]), entry), "overlap"))
	var cm: PackedVector3Array = (a[0] as PackedVector3Array).duplicate()
	for i: int in cm.size():
		cm[i] *= 100.0
	check("contract: centimetres (100x) are rejected", _has(TattooModelContract.validate(TattooPaintMesh.from_arrays(cm, a[1], a[2]), entry), "metres"))
	var raised: PackedVector3Array = (a[0] as PackedVector3Array).duplicate()
	for i: int in raised.size():
		raised[i].y += 0.5
	check("contract: origin not at the feet is rejected", _has(TattooModelContract.validate(TattooPaintMesh.from_arrays(raised, a[1], a[2]), entry), "floor"))
	var lying: PackedVector3Array = (a[0] as PackedVector3Array).duplicate()
	for i: int in lying.size():
		lying[i] = Vector3(lying[i].x, lying[i].z + 0.13, lying[i].y)
	check("contract: a model lying down (Z up) is rejected", _has(TattooModelContract.validate(TattooPaintMesh.from_arrays(lying, a[1], a[2]), entry), "+Y"))
	check("contract: the original passes", TattooModelContract.validate(TattooPaintMesh.from_arrays(a[0], a[1], a[2]), entry).is_empty())
	var bad := TattooModelEntry.new()
	bad.id = &"bad"
	bad.source = "procedural:dragon"
	check("loader: unknown procedural kind is an error", _has(TattooModelLoader.build(bad)["errors"], "unknown"))
	bad.source = "user://missing_model.glb"
	check("loader: a missing file is an error", _has(TattooModelLoader.build(bad)["errors"], "could not load"))


func _has(errors: PackedStringArray, needle: String) -> bool:
	for e: String in errors:
		if e.contains(needle):
			return true
	return false


func _test_gltf_drop_in() -> void:
	var path: String = "user://tattoo_dropin_test.glb"
	var root := Node3D.new()
	var inst := MeshInstance3D.new()
	inst.mesh = TattooBodyBuilder.build_mesh("female")
	inst.name = "Body"
	root.add_child(inst)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var ok: bool = doc.append_from_scene(root, state) == OK and doc.write_to_filesystem(state, path) == OK
	root.free()
	check("gltf: a test model is written as .glb", ok and FileAccess.file_exists(path))
	var entry := TattooModelEntry.new()
	entry.id = &"dropin"
	entry.display_name = "Drop-in"
	entry.source = path
	entry.height_m = 1.66
	var result: Dictionary = TattooModelLoader.build(entry)
	check("gltf: the loader reads it and it passes the contract", (
		result["mesh"] != null and (result["errors"] as PackedStringArray).is_empty()
	))
	var paint: TattooPaintMesh = result["paint"]
	var hit: Dictionary = paint.raycast(Vector3(0, 1.15, 2), Vector3(0, 0, -1)) if paint != null else {}
	check("gltf: and is paintable (ray hit with UV)", not hit.is_empty() and (hit["uv"] as Vector2) != Vector2.ZERO)
	entry.height_m = 0.0166
	check("gltf: a wrong declared height (cm vs m) is reported", _has(TattooModelLoader.build(entry)["errors"], "metres"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Platform ------------------------------------------------------------------------

func _test_platform_box_and_manifest() -> void:
	check("box: tall cap is 4x the long side, at most 3.0 m", (
		is_equal_approx(PlayBox.height_cap(Vector2(1.1, 1.1), true), 3.0) and is_equal_approx(PlayBox.height_cap(Vector2(0.4, 0.3), true), 1.6)
	))
	check("box: the normal cap stays 1.0 m", is_equal_approx(PlayBox.height_cap(Vector2(1.1, 1.1)), 1.0))
	var manifest: LGGameManifest = load("res://games/tattoo_studio/manifest.tres") as LGGameManifest
	var box: PlayBox = PlayBox.from_manifest(manifest)
	check("manifest: Tattoo Studio is valid and declares the tall box", manifest.is_valid() and manifest.tall_box)
	check("box: Tattoo Studio's box goes to 3.0 m (1.92 preferred)", is_equal_approx(box.max_height, 3.0) and is_equal_approx(box.height(), 1.92))
	var copy: LGGameManifest = manifest.duplicate() as LGGameManifest
	copy.tall_box = false
	check("box: without the exception the same manifest caps at 1.0 m", is_equal_approx(PlayBox.from_manifest(copy).max_height, 1.0))
	copy.tall_box = true
	copy.box_max_height = 3.5
	check("manifest: a tall box over 3.0 m is invalid", _has(copy.validate(), "tall_box"))


func _test_hooks_gated() -> void:
	var game: TattooStudioGame = (load("res://games/tattoo_studio/tattoo_studio.tscn") as PackedScene).instantiate()
	game.manifest = load("res://games/tattoo_studio/manifest.tres") as LGGameManifest
	game.lg_board_ready()
	check("hooks: no ray strokes / pinch before the board is locked", (
		not game.lg_ray_stroke(LGGame.StrokePhase.BEGIN, Vector3(0, 1.2, 2), Vector3(0, 0, -1)) and not game.lg_pinch(1.2, 0.0)
	))
	game.lg_set_locked(true)
	check("hooks: Draw mode takes ray strokes, not drags", game.captures_ray_strokes() and not game.captures_drag())
	check("hooks: strokes arrive while playing", game.lg_ray_stroke(LGGame.StrokePhase.BEGIN, Vector3(0, 1.2, 2), Vector3(0, 0, -1)))
	game.lg_ray_stroke(LGGame.StrokePhase.END, Vector3.ZERO, Vector3.FORWARD)
	game.set_mode(TattooStudioGame.Mode.ROTATE)
	check("hooks: Rotate mode takes drags, not strokes", not game.captures_ray_strokes() and game.captures_drag())
	check("hooks: lg_ray_stroke refuses when the game does not capture", not game.lg_ray_stroke(LGGame.StrokePhase.BEGIN, Vector3(0, 1.2, 2), Vector3(0, 0, -1)))
	var probe := LGGame.new()
	check("hooks: the base LGGame captures neither", not probe.captures_ray_strokes() and not probe.captures_pinch() and not probe.is_over_game_ui(Vector2.ZERO))
	probe.free()
	game.free()
	await frames(1)


# --- In the host -----------------------------------------------------------------------

func _screen_of(host: GameHost, game: TattooStudioGame, model_point: Vector3) -> Vector2:
	return host.active_camera().unproject_position(game.to_global(game.model_transform() * model_point))


func _stroke(points: Array[Vector2], index: int = 0) -> void:
	get_viewport().push_input(touch(index, points[0], true), true)
	for i: int in range(1, points.size()):
		get_viewport().push_input(drag(index, points[i], points[i] - points[i - 1]), true)
	get_viewport().push_input(touch(index, points[points.size() - 1], false), true)


func _chest_line(host: GameHost, game: TattooStudioGame, y: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in 13:
		out.append(_screen_of(host, game, Vector3(lerpf(-0.1, 0.1, float(i) / 12.0), y, 0.11)))
	return out


func _test_touch_strokes() -> void:
	_reset_session()
	var host: GameHost = await make_host(ID)
	var game: TattooStudioGame = host.game as TattooStudioGame
	check("host: Tattoo Studio loads, plays, shows its tools", game != null and game.is_playing() and game.ui.visible and game.current.id == &"male")
	host.orbit_camera.yaw = 0.0
	host.orbit_camera.pitch = deg_to_rad(-8.0)
	host.orbit_camera.distance = 2.4
	host.orbit_camera.orbit(Vector2.ZERO)
	await frames(2)
	var yaw_before: float = host.orbit_camera.yaw
	_stroke(_chest_line(host, game, 1.25))
	await frames(1)
	var inked: int = game.ink.inked_texels()
	check("host: a finger stroke across the chest tattoos it", inked > 100 and game.strokes == 1)
	check("host: painting does not orbit the camera", is_equal_approx(host.orbit_camera.yaw, yaw_before))
	var hit: Dictionary = game.paint.raycast(Vector3(0.0, 1.25, 2.0), Vector3(0, 0, -1))
	check("host: the ink is where the finger went (chest centre)", game.ink.load_at_uv(hit["uv"] as Vector2) > 0.2)
	# A stroke that starts on the tool panel never paints.
	var panel: Rect2 = game.ui.right_panel.get_global_rect()
	var on_panel: Array[Vector2] = [panel.get_center(), panel.get_center() + Vector2(-40, 10), panel.get_center() + Vector2(-80, 20)]
	_stroke(on_panel)
	await frames(1)
	check("host: touches on the game's tools are not strokes", game.strokes == 1 and game.ink.inked_texels() == inked)
	# A second finger ends the stroke (pinch, not paint).
	var line: Array[Vector2] = _chest_line(host, game, 1.18)
	get_viewport().push_input(touch(0, line[0], true), true)
	get_viewport().push_input(drag(0, line[3], line[3] - line[0]), true)
	get_viewport().push_input(touch(1, line[0] + Vector2(0, 120), true), true)
	await frames(1)
	check("host: a second finger ends the stroke", not game.ink.in_stroke() and game.strokes == 2)
	get_viewport().push_input(touch(1, line[0] + Vector2(0, 120), false), true)
	get_viewport().push_input(touch(0, line[3], false), true)
	await frames(1)
	await free_host(host)


func _test_rotate_scale_pinch() -> void:
	_reset_session()
	var host: GameHost = await make_host(ID)
	var game: TattooStudioGame = host.game as TattooStudioGame
	game.set_mode(TattooStudioGame.Mode.ROTATE)
	var inked: int = game.ink.inked_texels()
	game._on_board_drag(Vector3(0.3, 0, 0.3), Vector3(0.3, 0, -0.3))
	check("rotate: a drag round the model turns the turntable", absf(game.yaw) > 0.5 and game.turntable.position == Vector3.ZERO)
	_stroke([Vector2(500, 300), Vector2(560, 300), Vector2(620, 300)])
	await frames(1)
	check("rotate: drags in Rotate mode never paint", game.ink.inked_texels() == inked and game.strokes == 0)
	var yaw0: float = game.yaw
	game.lg_pinch(0.5, 0.3)
	check("pinch: scales the model and twist turns it", is_equal_approx(game.model_scale, 0.5) and absf(wrapf(yaw0 - game.yaw - 0.3, -PI, PI)) < 1e-4)
	game.lg_pinch(0.01, 0.0)
	check("pinch: scale stops at the model's minimum", is_equal_approx(game.model_scale, game.current.min_scale))
	game.set_model_scale(5.0)
	check("scale: stops at life size", is_equal_approx(game.model_scale, 1.0))
	game.select_model(&"lizard")
	check("scale: the lizard's turntable spin stays on the footprint", game.model_scale <= 1.0 and game._model_radius * game.model_scale <= game.get_box().size.x * 0.5)
	await free_host(host)


func _test_box_follows_model() -> void:
	_reset_session()
	var host: GameHost = await make_host(ID)
	var game: TattooStudioGame = host.game as TattooStudioGame
	await frames(2)
	check("box: starts just above the life-size model", absf(host.box.height() - (game.model_height() + TattooStudioGame.BOX_MARGIN)) < 0.011)
	game.ui.scale_slider.value = 0.3
	await get_tree().create_timer(0.6).timeout
	await frames(2)
	check("box: follows the scale slider down", absf(host.box.height() - (game.model_height() * 0.3 + TattooStudioGame.BOX_MARGIN)) < 0.011 and is_equal_approx(game.model_scale, 0.3))
	host.set_box_height(0.3)
	check("box: lowering the airspace shrinks the model to fit", game.model_height() * game.model_scale <= 0.3)
	await free_host(host)


func _test_focus() -> void:
	_reset_session()
	var host: GameHost = await make_host(ID)
	var game: TattooStudioGame = host.game as TattooStudioGame
	host.orbit_camera.yaw = 0.0
	host.orbit_camera.pitch = deg_to_rad(-8.0)
	host.orbit_camera.distance = 2.4
	host.orbit_camera.orbit(Vector2.ZERO)
	await frames(2)
	var spot := Vector3(0.0, 1.3, 0.11)
	var spot_world: Vector3 = game.to_global(game.model_transform() * spot)
	game.ui.focus_button.pressed.emit()
	check("focus: the Focus button asks for a spot", game.focus_picking and game.captures_ray_strokes() and game.ui.focus_button.text == "Cancel focus")
	var screen: Vector2 = _screen_of(host, game, spot)
	_stroke([screen])
	await frames(1)
	check("focus: tapping the model magnifies (3x) without painting", game.is_focused() and game.strokes == 0 and game.ink.inked_texels() == 0)
	await get_tree().create_timer(1.0).timeout
	await frames(2)
	var surface_hit: Dictionary = game.paint.raycast(spot + Vector3(0, 0, 1), Vector3(0, 0, -1))
	var surface_spot: Vector3 = surface_hit["position"]
	var picked: Vector3 = game.focus_point / game.model_scale
	var spot_world_after: Vector3 = game.to_global(game.model_transform() * picked)
	var before_surface: Vector3 = game.to_global((game.turntable.transform * Transform3D(Basis().scaled(Vector3.ONE * game.model_scale), Vector3.ZERO)) * picked)
	check("focus: the tapped spot is the one under the finger", picked.distance_to(surface_spot) < 0.02)
	check("focus: eases to 3x and the spot stays where it was", is_equal_approx(game.focus_shown, 3.0) and spot_world_after.distance_to(before_surface) < 1e-4)
	check("focus: the model's anchor (board) never moves", game.transform == Transform3D.IDENTITY and game.turntable.position == Vector3.ZERO and spot_world.distance_to(spot_world) == 0.0)
	_stroke(_chest_line(host, game, 1.3).slice(5, 8))
	await frames(1)
	var uv: Vector2 = surface_hit["uv"]
	check("focus: painting while magnified lands on the same skin", game.strokes == 1 and game.ink.load_at_uv(uv) > 0.0)
	var inked: int = game.ink.inked_texels()
	game.lg_pinch(1.5, 0.0)
	check("focus: pinch changes the magnification, not the model size", is_equal_approx(game.focus_target, 4.5) and is_equal_approx(game.model_scale, 1.0))
	game.ui.focus_button.pressed.emit()
	await get_tree().create_timer(1.0).timeout
	await frames(2)
	check("focus: True size eases back exactly", not game.is_focused() and is_equal_approx(game.focus_shown, 1.0) and game.model_root.transform.is_equal_approx(Transform3D.IDENTITY))
	check("focus: ink is unchanged by zooming in and out", game.ink.inked_texels() == inked)
	await free_host(host)


func _test_permanence() -> void:
	_reset_session()
	var host: GameHost = await make_host(ID)
	var game: TattooStudioGame = host.game as TattooStudioGame
	host.orbit_camera.yaw = 0.0
	host.orbit_camera.pitch = deg_to_rad(-8.0)
	host.orbit_camera.distance = 2.4
	host.orbit_camera.orbit(Vector2.ZERO)
	await frames(2)
	_stroke(_chest_line(host, game, 1.25))
	await frames(1)
	var snapshot: PackedByteArray = game.ink.data.duplicate()
	var spot := Vector3(0.0, 1.25, 0.0)
	var front: Dictionary = game.paint.raycast(spot + Vector3(0, 0, 1), Vector3(0, 0, -1))
	var on_skin: Vector3 = front["position"]
	var slant: Dictionary = game.paint.raycast(on_skin + Vector3(0.5, 0.3, 1), Vector3(-0.5, -0.3, -1).normalized())
	check("permanence: two viewpoints find the same inked skin", (
		game.ink.load_at_uv(front["uv"] as Vector2) > 0.0 and game.ink.load_at_uv(slant["uv"] as Vector2) > 0.0
	))
	for yaw: float in [0.8, 2.5, -1.7]:
		host.orbit_camera.yaw = yaw
		host.orbit_camera.orbit(Vector2.ZERO)
		host.orbit_camera.zoom(1.6)
		await frames(2)
	check("permanence: orbiting and zooming the view changes nothing", game.ink.data == snapshot)
	var world_before: Vector3 = game.to_global(game.model_transform() * (front["position"] as Vector3))
	game.set_model_scale(0.4)
	game.set_yaw(1.0)
	var moved: Vector3 = game.model_transform() * (front["position"] as Vector3)
	var again: Dictionary = game.cast(moved + game.model_transform().basis * Vector3(0, 0, 1), game.model_transform().basis * Vector3(0, 0, -1))
	check("permanence: after scale + turn the tattoo is still on the same skin", (
		game.ink.data == snapshot and (again["uv"] as Vector2).distance_to(front["uv"] as Vector2) < 0.002
	))
	game.set_model_scale(1.0)
	game.set_yaw(0.0)
	check("permanence: back at true size it is exactly where it was", game.to_global(game.model_transform() * (front["position"] as Vector3)).distance_to(world_before) < 1e-5)
	game.select_model(&"female")
	check("permanence: another model starts clean", game.ink.inked_texels() == 0)
	game.select_model(&"male")
	check("permanence: switching back keeps the male's tattoo", game.ink.data == snapshot)
	game.lg_set_app_paused(true)
	check("permanence: pausing hides the tools and stops strokes", not game.is_playing() and not game.ui.visible)
	game.lg_set_app_paused(false)
	check("permanence: resume keeps the ink", game.is_playing() and game.ink.data == snapshot)
	await free_host(host)
	var host2: GameHost = await make_host(ID)
	var game2: TattooStudioGame = host2.game as TattooStudioGame
	check("permanence: leaving and reopening the game keeps it (this session)", game2.current.id == &"male" and game2.ink.data == snapshot)
	await free_host(host2)


func _test_clear_confirm() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lg_placement_%s.cfg" % ID))
	var host: GameHost = await make_host(ID)
	var game: TattooStudioGame = host.game as TattooStudioGame
	var before: int = game.ink.inked_texels()
	game.ui.clear_button.pressed.emit()
	check("clear: Clear all asks first", game.ui.confirm_panel.visible and game.ink.inked_texels() == before and before > 0)
	check("clear: the question blocks board touches", game.is_over_game_ui(game.ui.confirm_panel.get_global_rect().get_center()))
	game.ui.confirm_no.pressed.emit()
	check("clear: Keep leaves the tattoo", not game.ui.confirm_panel.visible and game.ink.inked_texels() == before)
	game.ui.clear_button.pressed.emit()
	game.ui.confirm_yes.pressed.emit()
	check("clear: confirming removes every tattoo on the model", game.ink.inked_texels() == 0 and not game.ui.confirm_panel.visible)
	await free_host(host)


## AR: a miniature on the plywood table. Strokes through the AR camera
## paint; walking round it (side, behind, close-up) never moves the model.
func _test_ar_miniature_on_table() -> void:
	_reset_session()
	ARSession.clear_saved_area()
	var host: GameHost = await _ar_host(ID)
	var ar: ARSession = host.session
	ar.place_at_reticle()
	ar.finish_fit()
	ar.set_locked(true)
	await frames(2)
	var game: TattooStudioGame = host.game as TattooStudioGame
	check("AR: the locked board plays and takes ray strokes", game.is_playing() and host.game_takes_strokes())
	game.set_model_scale(0.25)
	await get_tree().create_timer(0.5).timeout
	await frames(2)
	var chest: Vector3 = game.to_global(game.model_transform() * Vector3(0.0, 1.25, 0.11))
	var board_xf: Transform3D = game.global_transform
	_look(chest + Vector3(0.0, 0.08, 0.35), chest)
	await frames(2)
	var line: Array[Vector2] = []
	for i: int in 13:
		var p := Vector3(lerpf(-0.1, 0.1, float(i) / 12.0), 1.25, 0.11)
		line.append(_screen(game.to_global(game.model_transform() * p)))
	_stroke(line)
	await frames(1)
	var hit: Dictionary = game.paint.raycast(Vector3(0.0, 1.25, 2.0), Vector3(0, 0, -1))
	check("AR: a stroke on the miniature's chest inks it", game.strokes == 1 and game.ink.load_at_uv(hit["uv"] as Vector2) > 0.2)
	var snapshot: PackedByteArray = game.ink.data.duplicate()
	for eye: Vector3 in [Vector3(0.4, 0.1, 0.0), Vector3(0.0, 0.15, -0.4), Vector3(-0.15, 0.02, 0.12)]:
		_look(chest + eye, chest)
		await frames(3)
	check("AR: walking round the model never moves it (board pose fixed)", game.global_transform.is_equal_approx(board_xf))
	check("AR: and never changes the tattoo", game.ink.data == snapshot)
	await free_host(host)
	ARSession.clear_saved_area()
