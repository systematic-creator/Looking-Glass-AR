extends LGTestSuite
## Reusable platform systems (Crystal Defense groundwork, doc milestone M1):
## BoardGrid, FlowField, Wallet, PhaseMachine, SimClock, SimPool,
## SpatialHash2D, AreaViz, PlacementController, CatalogSheet, AnchorPopup.
## Run: godot --headless --path . res://tests/lg_systems_tests.tscn


func run_tests() -> void:
	_test_board_grid()
	_test_flood()
	_test_flow_field()
	_test_flow_field_diagonals()
	_test_wallet()
	_test_phase_machine()
	_test_sim_clock()
	_test_sim_pool()
	_test_spatial_hash()
	_test_area_viz()
	await _test_placement()
	await _test_catalog_and_popup()


func _test_board_grid() -> void:
	var g := BoardGrid.new(12, 12, 0.04)
	check("grid: 12x12 cells centred on the board", g.cell_count() == 144 and g.origin.is_equal_approx(Vector3(-0.24, 0, -0.24)))
	check("grid: to_board / from_board round-trip", g.from_board(g.to_board(Vector2(3.25, 7.5))).is_equal_approx(Vector2(3.25, 7.5)))
	check("grid: cell_at a cell centre", g.cell_at(g.cell_center_board(Vector2i(4, 9))) == Vector2i(4, 9))
	check("grid: out of bounds detected", not g.in_bounds(Vector2i(-1, 0)) and not g.in_bounds(Vector2i(12, 3)) and g.in_bounds(Vector2i(11, 11)))
	var fit: BoardGrid = BoardGrid.fit(Vector2(0.48, 0.48), 12, 12, 0.012)
	check("grid: fit() leaves the rim", is_equal_approx(fit.cell_size, 0.038))
	var big: BoardGrid = BoardGrid.fit(Vector2(6.0, 6.0), 12, 12)
	check("grid: same cells scale to a 6 m board", big.cell_count() == 144 and is_equal_approx(big.cell_size, 0.5))
	check("grid: 4 sides of 12 border cells, 44 border cells", g.side_cells(BoardGrid.Side.WEST).size() == 12 and g.side_cells(BoardGrid.Side.SOUTH).size() == 12 and g.border_cells().size() == 44)
	check("grid: west side is x = 0, north is y = 0", g.side_cells(BoardGrid.Side.WEST)[3] == Vector2i(0, 3) and g.side_cells(BoardGrid.Side.NORTH)[3] == Vector2i(3, 0))
	check("grid: side normals point outward", BoardGrid.side_normal(BoardGrid.Side.WEST) == Vector2(-1, 0) and BoardGrid.side_normal(BoardGrid.Side.SOUTH) == Vector2(0, 1))
	g.set_tag(Vector2i(2, 2), BoardGrid.Tag.TERRAIN)
	g.set_occupant(Vector2i(3, 3), 7)
	check("grid: tags and occupants", g.get_tag(Vector2i(2, 2)) == BoardGrid.Tag.TERRAIN and g.get_occupant(Vector2i(3, 3)) == 7 and not g.is_free(Vector2i(3, 3)) and g.is_free(Vector2i(4, 4)))
	check("grid: 4 and 8 neighbours (clipped at edges)", g.neighbours(Vector2i(0, 0)).size() == 2 and g.neighbours(Vector2i(5, 5), true).size() == 8)


func _test_flood() -> void:
	var g := BoardGrid.new(5, 5, 1.0)
	var mask := PackedByteArray()
	mask.resize(25)
	mask.fill(1)
	# A wall across x = 2 except (2, 4).
	for y: int in 4:
		mask[g.index(Vector2i(2, y))] = 0
	var r: PackedByteArray = g.flood([Vector2i(0, 0)], mask)
	check("flood: reaches round the end of a wall", r[g.index(Vector2i(4, 0))] == 1)
	mask[g.index(Vector2i(2, 4))] = 0
	r = g.flood([Vector2i(0, 0)], mask)
	check("flood: a full wall cuts the board", r[g.index(Vector2i(4, 0))] == 0 and r[g.index(Vector2i(1, 4))] == 1)
	# Diagonal squeeze between two blocked corners is not a path.
	var m2 := PackedByteArray()
	m2.resize(25)
	m2.fill(1)
	for c: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		m2[g.index(c)] = 0
	r = g.flood([Vector2i(0, 0)], m2)
	check("flood: no corner-cutting through a diagonal gap", r[g.index(Vector2i(1, 1))] == 0)


func _costs(g: BoardGrid, solid: Array) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(g.cell_count())
	c.fill(1.0)
	for s: Vector2i in solid:
		c[g.index(s)] = INF
	return c


func _test_flow_field() -> void:
	var g := BoardGrid.new(12, 12, 1.0)
	var f := FlowField.new(g)
	var goal: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]
	f.build(_costs(g, []), goal)
	check("flow: goals at distance 0", f.distance(Vector2i(5, 5)) == 0.0)
	check("flow: straight-line distance on an open board", is_equal_approx(f.distance(Vector2i(0, 5)), 5.0))
	check("flow: diagonals cost sqrt(2)", is_equal_approx(f.distance(Vector2i(0, 0)), 5.0 * sqrt(2.0)))
	var p: Array[Vector2i] = f.path_from(Vector2i(0, 5))
	check("flow: path ends on the goal", p.size() > 0 and goal.has(p[p.size() - 1]))
	var dir: Vector2 = f.direction_at(Vector2(0.5, 5.5))
	check("flow: direction points at the goal (east)", dir.x > 0.9)
	var solid: Array = []
	for y: int in range(1, 12):
		solid.append(Vector2i(3, y))
	f.build(_costs(g, solid), goal)
	check("flow: routes round a wall (longer)", f.distance(Vector2i(0, 11)) > 12.0 and f.reachable(Vector2i(0, 11)))
	var path: Array[Vector2i] = f.path_from(Vector2i(0, 11))
	var crosses: bool = false
	for c: Vector2i in path:
		if solid.has(c):
			crosses = true
	check("flow: path never enters a solid cell", not crosses and path.size() > 12)
	solid.append(Vector2i(3, 0))
	f.build(_costs(g, solid), goal)
	check("flow: sealed-off cells are unreachable (INF)", not f.reachable(Vector2i(0, 11)) and f.distance(Vector2i(0, 11)) == INF)
	check("flow: version bumps on build", f.version >= 3)


func _test_flow_field_diagonals() -> void:
	var g := BoardGrid.new(3, 3, 1.0)
	var f := FlowField.new(g)
	var goal: Array[Vector2i] = [Vector2i(2, 2)]
	f.build(_costs(g, [Vector2i(2, 1), Vector2i(1, 2)]), goal)
	check("flow: no diagonal squeeze between two solid corners", not f.reachable(Vector2i(1, 1)))
	f.build(_costs(g, [Vector2i(2, 1)]), goal)
	check("flow: one solid corner forces the orthogonal route", is_equal_approx(f.distance(Vector2i(1, 1)), 2.0))


func _test_wallet() -> void:
	var w := Wallet.new(20)
	var seen: Array = []
	w.changed.connect(func(b: int, d: int, r: StringName) -> void: seen.append([b, d, r]))
	check("wallet: starts with 20", w.balance == 20)
	check("wallet: spend base price", w.spend(10, &"build") and w.balance == 10)
	check("wallet: cannot overspend", not w.spend(11) and w.balance == 10)
	w.markup = 1.5
	check("wallet: mid-wave markup rounds up (+50%)", w.price(5) == 8 and w.price(10) == 15 and Wallet.price_with(7, 1.5) == 11)
	check("wallet: can_afford uses the marked-up price", w.can_afford(6) and not w.can_afford(7))
	w.markup = 1.0
	w.earn_multiplier = 1.25
	check("wallet: earn applies the multiplier (rounded)", w.earn(4, &"kill") == 5 and w.balance == 15)
	w.refund(3)
	check("wallet: refund adds exactly", w.balance == 18)
	check("wallet: spend_exact ignores markup", w.spend_exact(8) and w.balance == 10)
	check("wallet: changed signal on every change", seen.size() == 4 and seen[0] == [10, -10, &"build"])
	check("wallet: totals earned / spent and a capped log", w.total_earned == 5 and w.total_spent == 18 and w.log.size() == 4 and w.log[1]["reason"] == &"kill")
	var d: Dictionary = w.to_save()
	var w2: Wallet = Wallet.from_save(d)
	check("wallet: to_save / from_save round-trip (balance, totals; not the situational multipliers)", w2.balance == 10 and w2.total_earned == 5 and w2.total_spent == 18 and w2.earn_multiplier == 1.0)
	check("wallet: save is plain data (JSON-safe)", JSON.parse_string(JSON.stringify(d)) is Dictionary)


func _test_phase_machine() -> void:
	var m := PhaseMachine.new()
	m.allow(&"", [&"prep"])
	m.allow(&"prep", [&"wave"])
	m.allow(&"wave", [&"clear", &"defeat"])
	m.allow(&"clear", [&"prep"])
	m.permit(&"prep", [&"build", &"move"])
	var changes: Array = []
	m.phase_changed.connect(func(a: StringName, b: StringName) -> void: changes.append([a, b]))
	check("phases: enter allowed", m.enter(&"prep") and m.phase == &"prep")
	check("phases: illegal transition refused", not m.enter(&"clear") and m.phase == &"prep")
	check("phases: permits per phase", m.can(&"build") and not m.can(&"redeploy"))
	m.enter(&"wave")
	check("phases: actions not permitted in other phases", not m.can(&"build"))
	m.enter(&"clear", 1.5)
	check("phases: timed phase does not expire early", m.advance(1.0) == &"" and m.phase == &"clear")
	check("phases: timed phase reports its timeout", m.advance(0.6) == &"clear")
	m.set_paused(&"rotate", true)
	m.set_paused(&"button", true)
	m.set_paused(&"rotate", false)
	check("phases: pause reasons stack", m.is_paused() and m.is_paused_by(&"button") and not m.is_paused_by(&"rotate"))
	m.clear_pauses()
	check("phases: clear_pauses", not m.is_paused())
	check("phases: phase_changed fires", changes.size() == 3)
	var m2 := PhaseMachine.new()
	m2.allow(&"", [&"prep"])
	m2.load_save(m.to_save())
	check("phases: save round-trip", m2.phase == &"clear")


func _test_sim_clock() -> void:
	var c := SimClock.new(20.0)
	check("clock: 20 Hz", is_equal_approx(c.step, 0.05))
	check("clock: one frame of 1/60 s is 0 ticks, three is 1", c.advance(1.0 / 60.0) == 0 and c.advance(1.0 / 60.0) == 0 and c.advance(1.0 / 60.0) == 1)
	c.speed = 2.0
	check("clock: 2x speed doubles ticks", c.advance(0.1) == 4)
	c.paused = true
	check("clock: paused gives no ticks", c.advance(1.0) == 0)
	c.paused = false
	c.speed = 1.0
	check("clock: a slow frame is capped (no spiral)", c.advance(5.0) == c.max_steps_per_frame and c.accumulator < c.step)
	c.advance(0.025)
	check("clock: alpha is the fraction to the next tick", c.alpha() > 0.4 and c.alpha() < 0.6)


func _test_sim_pool() -> void:
	var p := SimPool.new(60)
	var ids: Array[int] = []
	for i: int in 60:
		ids.append(p.acquire())
	check("pool: 60 slots, then full", p.is_full() and p.acquire() == -1 and p.count() == 60)
	p.release(ids[10])
	check("pool: release frees a slot for reuse", not p.is_full() and not p.is_alive(ids[10]) and p.acquire() == ids[10])
	check("pool: peak tracked", p.peak == 60)
	p.clear()
	check("pool: clear empties", p.count() == 0 and p.live.size() == 0)


func _test_spatial_hash() -> void:
	var h := SpatialHash2D.new(1.0)
	h.insert(1, Vector2(0.5, 0.5))
	h.insert(2, Vector2(3.5, 0.5))
	h.insert(3, Vector2(1.4, 0.6))
	var q: PackedInt32Array = h.query(Vector2(0.5, 0.5), 1.0)
	check("hash: radius query finds near ids only", q.has(1) and q.has(3) and not q.has(2))
	check("hash: position_of", h.position_of(2).is_equal_approx(Vector2(3.5, 0.5)))
	h.clear()
	check("hash: clear", h.query(Vector2(0.5, 0.5), 5.0).size() == 0)


func _test_area_viz() -> void:
	var ring: ArrayMesh = AreaViz.ring_mesh(1.0, 0.1)
	var aabb: AABB = ring.get_aabb()
	check("viz: ring spans its radius, flat", is_equal_approx(aabb.size.x, 2.0) and aabb.size.y < 0.0001)
	var sector: ArrayMesh = AreaViz.sector_mesh(1.0, PI * 0.5)
	check("viz: sector faces -Z", sector.get_aabb().position.z < -0.9 and sector.get_aabb().end.z <= 0.0001)
	check("viz: one shared material per colour", AreaViz.material(Holo.CYAN) == AreaViz.material(Holo.CYAN))
	var strip: ArrayMesh = AreaViz.strip_mesh(Vector3.ZERO, Vector3(2, 0, 0), 0.2)
	check("viz: strip spans a to b with width", is_equal_approx(strip.get_aabb().size.x, 2.0) and is_equal_approx(strip.get_aabb().size.z, 0.2))


func _test_placement() -> void:
	var g := BoardGrid.new(12, 12, 0.04)
	var pc := PlacementController.new()
	add_child(pc)
	pc.setup(g, 0.01)
	var blocked: Dictionary = {"cell": Vector2i(5, 5)}
	var v := func(c: Vector2i) -> Dictionary: return {"ok": c != blocked["cell"], "reason": "blocked" if c == blocked["cell"] else ""}
	var r: Dictionary = pc.begin(BoxMesh.new(), v, Vector2i(4, 4))
	check("placement: begin validates the start cell", bool(r["ok"]) and pc.active and pc.visible)
	check("placement: ghost sits on the cell", pc.ghost.position.is_equal_approx(g.cell_center_board(Vector2i(4, 4), 0.01)))
	check("placement: draws a green/red cell overlay around the ghost", pc.preview_cell_count() > 20)
	r = pc.move_to(Vector2i(5, 5))
	check("placement: invalid cell says why", not bool(r["ok"]) and r["reason"] == "blocked" and not pc.is_valid())
	r = pc.move_to(Vector2i(40, -3))
	check("placement: clamps to the grid", pc.cell == Vector2i(11, 0))
	pc.move_to_point(g.cell_center_board(Vector2i(2, 7)))
	check("placement: move_to_point uses board space", pc.cell == Vector2i(2, 7) and pc.is_valid())
	blocked["cell"] = Vector2i(2, 7)
	check("placement: refresh re-validates after a board change", not bool(pc.refresh()["ok"]))
	pc.end()
	check("placement: end hides everything", not pc.active and not pc.visible and pc.preview_cell_count() == 0)
	pc.queue_free()
	await frames(1)


func _test_catalog_and_popup() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var sheet := CatalogSheet.new()
	layer.add_child(sheet)
	sheet.set_tabs([{"id": &"a", "title": "A"}, {"id": &"b", "title": "B"}] as Array[Dictionary])
	sheet.set_items(&"a", [{"id": &"x", "title": "X", "cost": 10, "lines": "one", "enabled": true}, {"id": &"y", "title": "Y", "cost": 99, "enabled": false, "note": "need 99"}] as Array[Dictionary])
	sheet.set_items(&"b", [{"id": &"z", "title": "Z", "cost": 5}] as Array[Dictionary])
	var chosen: Array = []
	sheet.item_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	sheet.layout(true, Vector2(720, 1560), 0.0)
	sheet.open()
	await frames(2)
	check("catalog: opens on the first tab with its cards", sheet.is_open() and sheet.current_tab == &"a" and sheet.card(&"x") != null and sheet.card(&"z") == null)
	check("catalog: unaffordable cards are disabled with a note", sheet.card(&"y").disabled and sheet.card(&"y").text.contains("need 99"))
	sheet.card(&"x").pressed.emit()
	check("catalog: choosing a card emits item_chosen", chosen == [&"x"])
	sheet.show_tab(&"b")
	check("catalog: tabs switch the cards", sheet.card(&"z") != null and sheet.card(&"x") == null)
	check("catalog: portrait = bottom sheet", sheet.anchor_top == 1.0 and sheet.anchor_left == 0.0)
	sheet.layout(false, Vector2(1560, 720), 0.0)
	check("catalog: landscape = right drawer", sheet.anchor_left == 1.0 and sheet.anchor_top == 0.0)
	sheet.close()
	check("catalog: close", not sheet.is_open())
	var popup := AnchorPopup.new()
	layer.add_child(popup)
	var acts: Array = []
	popup.action_chosen.connect(func(id: StringName) -> void: acts.append(id))
	popup.show_at(Vector2(700, 300), "Tower", "detail", [{"id": &"up", "label": "Upgrade"}, {"id": &"sell", "label": "Sell", "enabled": false}] as Array[Dictionary], Vector2(720, 1560))
	await frames(2)
	var rect := Rect2(popup.position, popup.size)
	check("popup: stays inside the screen", Rect2(Vector2.ZERO, Vector2(720, 1560)).encloses(rect))
	check("popup: buttons are touch-sized and honour enabled", popup.button(&"up").custom_minimum_size.y >= 64 and popup.button(&"sell").disabled)
	popup.button(&"up").pressed.emit()
	check("popup: action_chosen", acts == [&"up"])
	popup.dismiss()
	check("popup: dismiss", not popup.visible)
	layer.queue_free()
	await frames(1)
