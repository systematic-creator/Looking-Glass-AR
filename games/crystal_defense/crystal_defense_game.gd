class_name CrystalDefenseGame
extends LGGame
## Crystal Defense (milestones M1-M2): a 12 x 12 storybook diorama in a misty
## Cryptid forest. Defend the purple lightning Crystal from Pale Stalkers that
## pour in from the board's edges: build towers and barriers in an unlimited
## prep phase, start the wave, earn mana from kills and clears.
##
## The rules live in CDSim (no nodes, 20 Hz fixed step driven by a SimClock);
## this node draws the board in CELL units under `_cells` (scaled to metres)
## and runs the HUD. Board space is metres at placement scale 1; the platform
## scales the whole board with the locked size.

const BOARD: float = 0.48
const RIM: float = 0.012
const CELL: float = (BOARD - 2.0 * RIM) / CDDefs.GRID_N
const BASE_H: float = 0.010
const COUNTDOWN: float = 3.0
const BANNER_TIME: float = 2.2
const ARROW_TIME: float = 0.18
const MAX_ARROWS: int = 48
const MAX_BOMBS: int = 24
const MAX_FX: int = 16
const MAX_DYING: int = 24
const ORANGE := Color(1.0, 0.55, 0.12)
const PURPLE := Color(0.62, 0.3, 1.0)
const MANA_BLUE := Color(0.45, 0.8, 1.0)

enum UI { PLAY, PAUSED, COUNTDOWN }

## Tests: force the next run's seed (-1 = random).
static var next_seed: int = -1

var sim: CDSim
var clock := SimClock.new(20.0)
var vgrid: BoardGrid
var ui_state: UI = UI.PLAY
var pause_reason: StringName = &""
var countdown_t: float = 0.0
## &"none" | &"build" | &"move"
var mode: StringName = &"none"
var build_type: StringName = &""
var move_squad_id: int = 0
var selected_struct: int = 0
var selected_squad: int = 0
var crystal_selected: bool = false
var show_all_ranges: bool = false
var fast: bool = false
var banner_t: float = 0.0
var _sheet_sig: String = ""

var _anim: float = 0.0
var _cells: Node3D
var _structure_nodes: Dictionary = {}
var _squad_nodes: Dictionary = {}
var _squad_lunge: Dictionary = {}
var _rings_root: Node3D
var _arc_node: MeshInstance3D
var _placement: PlacementController
var _crystal_root: Node3D
var _crystal_mi: MeshInstance3D
var _crystal_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _cracks: ImmediateMesh
var _cracks_mi: MeshInstance3D
var _bolts: ImmediateMesh
var _bolt_list: Array[Dictionary] = []
var _bolt_timer: float = 0.0
var _crystal_flash: float = 0.0
var _crack_stage: int = -1
var _enemy_mm: MultiMesh
var _bar_mm: MultiMesh
var _dying_mm: MultiMesh
var _dying: Array[Dictionary] = []
var _arrow_mm: MultiMesh
var _arrows: Array[Dictionary] = []
var _bomb_mm: MultiMesh
var _fx_mm: MultiMesh
var _fx: Array[Dictionary] = []
var _burn_mm: MultiMesh
var _facing := PackedVector2Array()
var _telegraph_root: Node3D
var _telegraphs: Array[Dictionary] = []
var _side_rim_root: Node3D

# HUD
var _hud: CanvasLayer
var _top: PanelContainer
var _mana_label: Label
var _wave_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _info_label: Label
var _left_row: HBoxContainer
var _right_row: BoxContainer
var build_button: Button
var summon_button: Button
var start_button: Button
var auto_button: Button
var speed_button: Button
var eye_button: Button
var pause_button: Button
var _confirm_bar: PanelContainer
var confirm_button: Button
var turn_button: Button
var cancel_button: Button
var _confirm_label: Label
var sheet: CatalogSheet
var popup: AnchorPopup
var _banner: Label
var _countdown_label: Label
var _pause_panel: PanelContainer
var _pause_label: Label
var resume_button: Button
var _over_panel: PanelContainer
var _over_label: Label
var retry_button: Button


# --- Platform hooks -----------------------------------------------------------------

func board_surface_height() -> float:
	return BASE_H


func captures_drag() -> bool:
	return mode != &"none"


func describe_point(point: Vector3) -> String:
	if sim == null:
		return ""
	var c: Vector2i = vgrid.cell_at(point)
	if not vgrid.in_bounds(c):
		return ""
	var id: int = sim.structure_at(c)
	if id != 0:
		var s: Dictionary = sim.structures[id]
		return "%s Lv%d" % [CDDefs.structure(s["type"])["title"], s["level"]]
	if sim.is_crystal_cell(c):
		return "Crystal %d/%d" % [int(ceil(sim.crystal_hp)), int(sim.crystal_max)]
	return "Cell %d,%d" % [c.x, c.y]


func _on_board_ready() -> void:
	ui_insets_changed.connect(func(_b: float) -> void: _layout_hud())
	vgrid = BoardGrid.new(CDDefs.GRID_N, CDDefs.GRID_N, CELL)
	sim = CDSim.new(_pick_seed())
	_facing.resize(CDDefs.MAX_ALIVE)
	_build_world()
	_build_pools()
	_build_hud()
	_sync_structures()
	_sync_squads()
	_rebuild_side_rim()
	_refresh_hud()


func _on_resumed() -> void:
	_refresh_hud()


func _on_paused() -> void:
	pause(&"app")


func _on_orientation_changed(_portrait: bool) -> void:
	_layout_hud()
	if sim != null and _run_active():
		pause(&"rotate")
	_refresh_hud()


func is_over_game_ui(screen: Vector2) -> bool:
	if _hud == null:
		return false
	for c: Control in [_top, _left_row, _right_row, start_button, _confirm_bar, sheet, popup, _pause_panel, _over_panel]:
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(screen):
			return true
	return false


func _on_board_tap(point: Vector3) -> void:
	if sim == null or ui_state != UI.PLAY or sim.phase() == CDSim.PHASE_DEFEAT:
		return
	tap_cell(vgrid.cell_at(point))


func _on_board_drag(_from: Vector3, to: Vector3) -> void:
	if mode == &"none" or ui_state != UI.PLAY:
		return
	_placement.move_to(vgrid.cell_at(to))
	_refresh_confirm()


# --- Flow ---------------------------------------------------------------------------

func _pick_seed() -> int:
	return next_seed if next_seed >= 0 else randi() % 1000000


## A wave (or its lead-in) is under way: the phone turning pauses it.
func _run_active() -> bool:
	var p: StringName = sim.phase()
	return p == CDSim.PHASE_WAVE or p == CDSim.PHASE_INTRO or p == CDSim.PHASE_CLEAR or (p == CDSim.PHASE_PREP and sim.auto_countdown >= 0.0)


func restart() -> void:
	cancel_mode()
	_clear_selection()
	sim.reset(_pick_seed())
	clock.reset()
	_dying.clear()
	_arrows.clear()
	_fx.clear()
	_bolt_list.clear()
	_clear_telegraphs()
	ui_state = UI.PLAY
	_crack_stage = -1
	_sync_structures()
	_sync_squads()
	_rebuild_side_rim()
	_refresh_hud()


func pause(reason: StringName = &"button") -> void:
	if ui_state == UI.PAUSED or sim == null or sim.phase() == CDSim.PHASE_DEFEAT:
		return
	ui_state = UI.PAUSED
	pause_reason = reason
	clock.paused = true
	_refresh_hud()


## Resume counts down 3-2-1 first (a wave is moving under the player's hand).
func resume() -> void:
	if ui_state != UI.PAUSED:
		return
	ui_state = UI.COUNTDOWN
	countdown_t = COUNTDOWN
	_refresh_hud()


func set_fast(on: bool) -> void:
	fast = on
	clock.speed = 2.0 if on else 1.0
	_refresh_hud()


func start_wave() -> bool:
	if sim.auto_countdown >= 0.0:
		sim.cancel_autostart_countdown()
		_refresh_hud()
		return false
	cancel_mode()
	_clear_selection()
	var ok: bool = sim.start_wave()
	_handle_events()
	_refresh_hud()
	return ok


## Run the game forward `delta` seconds of frame time (the HUD, countdowns
## and the fixed-step sim).
func _process(delta: float) -> void:
	if sim == null:
		return
	_anim += delta
	if is_playing():
		match ui_state:
			UI.COUNTDOWN:
				countdown_t -= delta
				if countdown_t <= 0.0:
					ui_state = UI.PLAY
					clock.paused = false
			UI.PLAY:
				clock.paused = false
				var n: int = clock.advance(delta)
				for _i: int in n:
					sim.tick(CDSim.STEP)
				if n > 0:
					_handle_events()
	banner_t = maxf(0.0, banner_t - delta)
	_sync_visuals(delta)
	_refresh_hud()


func _handle_events() -> void:
	var structures_dirty: bool = false
	var squads_dirty: bool = false
	for e: Dictionary in sim.drain_events():
		match e["kind"] as StringName:
			&"build", &"upgrade", &"sell":
				structures_dirty = true
			&"summon", &"grow", &"evolve", &"dismiss", &"move", &"redeploy", &"redeployed", &"knockout":
				squads_dirty = true
			&"telegraph":
				_add_telegraph(e)
			&"death":
				if _dying.size() < MAX_DYING:
					_dying.append({"pos": e["pos"], "t": 0.0, "slot": e["slot"], "condense": e["condense"]})
			&"arrow":
				if _arrows.size() < MAX_ARROWS:
					_arrows.append({"from": e["from"], "to": e["to"], "t": 0.0})
			&"explode":
				_add_fx(e["pos"], float(e["radius"]), ORANGE)
			&"storm":
				_bolt_list.append({"to": e["to"], "t": 0.22})
			&"crystal_hit":
				_crystal_flash = 0.35
			&"squad_hit":
				_squad_lunge[int(e["id"])] = 0.18
			&"wave_start":
				_show_banner("Wave %d" % int(e["wave"]))
				_clear_side_rim()
			&"wave_clear":
				_show_banner("Wave %d cleared  +%d mana" % [int(e["wave"]), int(e["bonus"])])
				squads_dirty = true
			&"prep":
				_clear_telegraphs()
				_rebuild_side_rim()
			&"defeat":
				cancel_mode()
				_clear_selection()
	if structures_dirty:
		_sync_structures()
	if squads_dirty:
		_sync_squads()
	if structures_dirty or squads_dirty:
		if mode != &"none":
			_placement.refresh()
			_refresh_confirm()
		_refresh_popup()


func _show_banner(text: String) -> void:
	if _banner != null:
		_banner.text = text
	banner_t = BANNER_TIME


# --- Board interaction --------------------------------------------------------------

func tap_cell(c: Vector2i) -> void:
	if mode != &"none":
		if c == _placement.cell and _placement.is_valid():
			confirm()
		else:
			_placement.move_to(c)
			_refresh_confirm()
		return
	if sheet.is_open():
		sheet.close()
	if not vgrid.in_bounds(c):
		_clear_selection()
		return
	var sq: int = sim.squad_at(c)
	var st: int = sim.structure_at(c)
	_clear_selection()
	if st != 0:
		selected_struct = st
	elif sq != 0:
		selected_squad = sq
	elif sim.is_crystal_cell(c):
		crystal_selected = true
	_refresh_popup()
	_refresh_rings()


func _clear_selection() -> void:
	selected_struct = 0
	selected_squad = 0
	crystal_selected = false
	if popup != null:
		popup.visible = false
	_refresh_rings()


## Enter build mode for `type`: ghost + green/red grid at a sensible cell.
func begin_build(type: StringName) -> void:
	_clear_selection()
	sheet.close()
	mode = &"build"
	build_type = type
	var stats: Dictionary = CDDefs.level_stats(type, 1)
	var ring: Node3D = null
	if stats.has("range"):
		ring = AreaViz.ring(float(stats["range"]) * CELL, Holo.CYAN, CELL * 0.08)
	_placement.begin(CDMeshes.structure_mesh(type, 1), func(cell: Vector2i) -> Dictionary: return sim.can_build(build_type, cell), _default_build_cell(type), ring)
	_placement.ghost.scale = Vector3.ONE * CELL
	_refresh_confirm()
	_refresh_hud()


func begin_move(id: int) -> void:
	if not sim.squads.has(id):
		return
	_clear_selection()
	mode = &"move"
	move_squad_id = id
	var q: Dictionary = sim.squads[id]
	var stats: Dictionary = sim.squad_rank_stats(q)
	var arc := AreaViz.sector((float(stats["reach"]) + CDSim.ENGAGE_EXTRA + 0.5) * CELL, deg_to_rad(float(CDDefs.UNITS[q["unit"]]["arc_deg"])), Holo.GOLD)
	_placement.begin(CDMeshes.knight_mesh(int(q["rank"])), func(cell: Vector2i) -> Dictionary: return sim.can_move_squad(move_squad_id, cell), q["cell"], arc)
	_placement.ghost.scale = Vector3.ONE * CELL
	_aim_move_arc()
	_refresh_confirm()
	_refresh_hud()


func _aim_move_arc() -> void:
	if mode != &"move" or _placement.range_node == null or not sim.squads.has(move_squad_id):
		return
	var f: Vector2 = sim.squads[move_squad_id]["facing"]
	var yaw: float = atan2(-f.x, -f.y)
	_placement.range_node.rotation.y = yaw
	_placement.ghost.rotation.y = yaw


func _default_build_cell(type: StringName) -> Vector2i:
	var best := Vector2i(6, 9)
	var best_d: float = INF
	for y: int in CDDefs.GRID_N:
		for x: int in CDDefs.GRID_N:
			var c := Vector2i(x, y)
			if not bool(sim.can_build(type, c)["ok"]) and sim.can_build(type, c)["reason"] != "Need %d mana" % int(sim.can_build(type, c)["cost"]):
				continue
			var d: float = BoardGrid.center_of(c).distance_to(Vector2(6.0, 8.6))
			if d < best_d:
				best_d = d
				best = c
	return best


## ✓: place the ghost / move the squad.
func confirm() -> bool:
	if mode == &"build":
		if not _placement.is_valid():
			return false
		var id: int = sim.build(build_type, _placement.cell)
		_handle_events()
		if id != 0:
			cancel_mode()
		return id != 0
	elif mode == &"move":
		if not _placement.is_valid():
			return false
		var ok: bool = sim.move_squad(move_squad_id, _placement.cell)
		_handle_events()
		cancel_mode()
		return ok
	return false


func cancel_mode() -> void:
	if _placement != null:
		_placement.end()
	mode = &"none"
	build_type = &""
	move_squad_id = 0
	if _confirm_bar != null:
		_confirm_bar.visible = false
	_refresh_hud()


func turn_moving_squad() -> void:
	if mode == &"move":
		sim.turn_squad(move_squad_id, 1)
		_aim_move_arc()
		_sync_squads()


# --- Popups -------------------------------------------------------------------------

func _refresh_popup() -> void:
	if popup == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	if selected_struct != 0 and sim.structures.has(selected_struct):
		var s: Dictionary = sim.structures[selected_struct]
		var def: Dictionary = CDDefs.structure(s["type"])
		var lv: int = int(s["level"])
		var st: Dictionary = CDDefs.level_stats(s["type"], lv)
		var detail: String
		if CDDefs.is_barrier(s["type"]):
			detail = "HP %d · blocks the path" % int(st["hp"])
		else:
			detail = "Damage %s · %s shots/s · range %s" % [str(st["damage"]), str(snappedf(float(st["rate"]), 0.01)), str(snappedf(float(st["range"]), 0.01))]
		var up: Dictionary = sim.can_upgrade(selected_struct)
		var up_label: String = "Max level" if lv >= 3 else "Upgrade · ◆ %d" % int(up["cost"])
		if lv < 3 and not bool(up["ok"]):
			up_label += "  (%s)" % up["reason"]
		var actions: Array[Dictionary] = [
			{"id": &"upgrade", "label": up_label, "enabled": bool(up["ok"]), "accent": Holo.GREEN},
			{"id": &"sell", "label": "Sell · +%d" % sim.sell_value(selected_struct), "enabled": sim.phases.can(&"sell"), "accent": Holo.GOLD},
			{"id": &"close", "label": "Close", "enabled": true, "accent": Color(0.9, 0.95, 1.0)},
		]
		popup.show_at(_screen_of_cell(BoardGrid.center_of(s["cell"]), 1.0), "%s  Lv%d" % [def["title"], lv], detail, actions, view, ui_bottom_inset())
	elif selected_squad != 0 and sim.squads.has(selected_squad):
		var q: Dictionary = sim.squads[selected_squad]
		var rank: Dictionary = sim.squad_rank_stats(q)
		var up: Dictionary = sim.can_upgrade_squad(selected_squad)
		var label: String
		if bool(up["max"]):
			label = "Max rank"
		elif bool(up["evolve"]):
			var next_name: String = str((CDDefs.UNITS[q["unit"]]["ranks"] as Array)[int(q["rank"]) + 1]["name"])
			label = "Evolve → %s · ◆ %d" % [next_name, int(up["cost"])]
		else:
			label = "+1 %s · ◆ %d" % [rank["name"], int(up["cost"])]
		if not bool(up["ok"]) and not bool(up["max"]):
			label += "  (%s)" % up["reason"]
		var wave_on: bool = sim.phase() == CDSim.PHASE_WAVE
		var mv: Dictionary = sim.can_move_squad(selected_squad, q["cell"])
		var actions: Array[Dictionary] = [
			{"id": &"squad_up", "label": label, "enabled": bool(up["ok"]), "accent": Holo.GREEN},
			{"id": &"move", "label": ("Redeploy" if wave_on else "Move") + ("" if bool(mv["ok"]) else "  (%s)" % mv["reason"]), "enabled": bool(mv["ok"]), "accent": Holo.CYAN},
			{"id": &"turn", "label": "Turn ↻", "enabled": true, "accent": Holo.CYAN},
			{"id": &"dismiss", "label": "Dismiss · +%d" % sim.dismiss_value(selected_squad), "enabled": true, "accent": Holo.MAGENTA},
		]
		var detail: String = "%d/%d standing · EXP %d/%d" % [sim.squad_alive(q), sim.squad_size(q), int(q["exp"]), int(ceil(sim.squad_exp_needed(selected_squad)))]
		popup.show_at(_screen_of_cell(BoardGrid.center_of(q["cell"]), 0.6), "%s squad" % rank["name"], detail, actions, view, ui_bottom_inset())
	elif crystal_selected:
		var r: Dictionary = sim.can_repair()
		var actions: Array[Dictionary] = [
			{"id": &"repair", "label": "Repair +%d HP · ◆ %d" % [int(CDDefs.REPAIR_HP), int(r.get("cost", CDDefs.REPAIR_COST))] + ("" if bool(r["ok"]) else "  (%s)" % r["reason"]), "enabled": bool(r["ok"]), "accent": PURPLE},
			{"id": &"close", "label": "Close", "enabled": true, "accent": Color(0.9, 0.95, 1.0)},
		]
		popup.show_at(_screen_of_cell(sim.crystal_center, 1.6), "The Crystal", "%d / %d HP · Storm Pulse every %ds" % [int(ceil(sim.crystal_hp)), int(sim.crystal_max), int(CDDefs.STORM_PERIOD)], actions, view, ui_bottom_inset())
	else:
		popup.visible = false


func _on_popup_action(id: StringName) -> void:
	match id:
		&"upgrade":
			sim.upgrade(selected_struct)
		&"sell":
			sim.sell(selected_struct)
			selected_struct = 0
		&"squad_up":
			sim.upgrade_squad(selected_squad)
		&"move":
			var sq: int = selected_squad
			popup.visible = false
			begin_move(sq)
			return
		&"turn":
			sim.turn_squad(selected_squad, 1)
			_sync_squads()
		&"dismiss":
			sim.dismiss(selected_squad)
			selected_squad = 0
		&"repair":
			sim.repair()
		&"close":
			_clear_selection()
			return
	_handle_events()
	_refresh_popup()
	_refresh_rings()
	_refresh_hud()


# --- Catalog ------------------------------------------------------------------------

func open_build() -> void:
	cancel_mode()
	_clear_selection()
	sheet.set_title("Build")
	sheet.set_tabs([{"id": &"towers", "title": "Towers"}, {"id": &"barriers", "title": "Barriers"}] as Array[Dictionary])
	_fill_build_items()
	sheet.open(&"towers")
	_layout_hud()


func open_summon() -> void:
	cancel_mode()
	_clear_selection()
	sheet.set_title("Summon")
	sheet.set_tabs([{"id": &"squads", "title": "Squads"}] as Array[Dictionary])
	_fill_summon_items()
	sheet.open(&"squads")
	_layout_hud()


func _fill_build_items() -> void:
	var towers: Array[Dictionary] = []
	var barriers: Array[Dictionary] = []
	for type: StringName in CDDefs.BUILD_ORDER:
		var def: Dictionary = CDDefs.structure(type)
		var st: Dictionary = CDDefs.level_stats(type, 1)
		var cost: int = sim.wallet.price(int(st["cost"]))
		var lines: String = str(def.get("blurb", ""))
		var item := {"id": type, "title": def["title"], "cost": cost, "lines": lines, "enabled": sim.wallet.can_afford(int(st["cost"])) and sim.phases.can(&"build"),
			"note": "need ◆ %d" % cost if not sim.wallet.can_afford(int(st["cost"])) else "", "accent": Holo.GOLD if CDDefs.is_barrier(type) else Holo.CYAN}
		if CDDefs.is_barrier(type):
			if sim.barrier_count() >= CDDefs.GRID_N:
				item["enabled"] = false
				item["note"] = "barrier cap %d" % CDDefs.GRID_N
			barriers.append(item)
		else:
			towers.append(item)
	sheet.set_items(&"towers", towers)
	sheet.set_items(&"barriers", barriers)


func _fill_summon_items() -> void:
	var items: Array[Dictionary] = []
	for unit: StringName in CDDefs.SUMMON_ORDER:
		var u: Dictionary = CDDefs.UNITS[unit]
		var r: Dictionary = sim.can_summon(unit)
		items.append({"id": unit, "title": (u["ranks"] as Array)[0]["name"], "cost": int(r["cost"]), "lines": str(u.get("blurb", "")),
			"enabled": bool(r["ok"]), "note": r["reason"], "accent": Holo.GREEN})
	sheet.set_items(&"squads", items)


func _on_sheet_item(id: StringName) -> void:
	if CDDefs.UNITS.has(id):
		var sq: int = sim.summon(id)
		_handle_events()
		sheet.close()
		if sq != 0:
			selected_squad = sq
			_refresh_popup()
			_refresh_rings()
		_refresh_hud()
	else:
		begin_build(id)


# --- World --------------------------------------------------------------------------

func _build_world() -> void:
	# Diorama base: dark soil slab with a stone rim.
	var base := MeshInstance3D.new()
	base.name = "Base"
	var bm := BoxMesh.new()
	bm.size = Vector3(BOARD, BASE_H, BOARD)
	base.mesh = bm
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.16, 0.13, 0.11)
	soil.roughness = 1.0
	base.material_override = soil
	base.position = Vector3(0, BASE_H * 0.5, 0)
	add_child(base)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.42, 0.43, 0.47)
	rim_mat.roughness = 0.9
	for k: int in 4:
		var r := MeshInstance3D.new()
		var rm := BoxMesh.new()
		var along: bool = k < 2
		rm.size = Vector3(BOARD if along else RIM, BASE_H + 0.006, RIM if along else BOARD - 2.0 * RIM)
		r.mesh = rm
		r.material_override = rim_mat
		var off: float = BOARD * 0.5 - RIM * 0.5
		r.position = Vector3(0 if along else (off if k == 2 else -off), (BASE_H + 0.006) * 0.5, (off if k == 0 else -off) if along else 0)
		r.name = "Rim%d" % k
		add_child(r)
	_cells = Node3D.new()
	_cells.name = "Cells"
	_cells.position = Vector3(vgrid.origin.x, BASE_H + 0.0004, vgrid.origin.z)
	_cells.scale = Vector3.ONE * CELL
	add_child(_cells)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = CDMeshes.ground_mesh(vgrid)
	_cells.add_child(ground)
	# Terrain: dead pale trees and standing stones (merged).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k2: int = 0
	for c: Vector2i in CDDefs.WORLD["trees"]:
		CDMeshes.dead_tree(st, Vector3(c.x + 0.5, 0, c.y + 0.5), 31 + k2 * 17)
		k2 += 1
	for c: Vector2i in CDDefs.WORLD["stones"]:
		CDMeshes.standing_stone(st, Vector3(c.x + 0.5, 0, c.y + 0.5), 77 + k2 * 13)
		k2 += 1
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = st.commit()
	terrain.material_override = CDMeshes.lit_material()
	_cells.add_child(terrain)
	_build_crystal()
	_rings_root = Node3D.new()
	_rings_root.name = "Rings"
	_cells.add_child(_rings_root)
	_telegraph_root = Node3D.new()
	_telegraph_root.name = "Telegraphs"
	_cells.add_child(_telegraph_root)
	_side_rim_root = Node3D.new()
	_side_rim_root.name = "SideRim"
	_cells.add_child(_side_rim_root)
	_placement = PlacementController.new()
	add_child(_placement)
	_placement.setup(vgrid, BASE_H + 0.0006)


func _build_crystal() -> void:
	_crystal_root = Node3D.new()
	_crystal_root.name = "Crystal"
	_crystal_root.position = Vector3(sim.crystal_center.x, 0, sim.crystal_center.y)
	_cells.add_child(_crystal_root)
	var plinth_st := SurfaceTool.new()
	plinth_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CDMeshes.cylinder(plinth_st, Vector3.ZERO, 0.95, 0.12, CDMeshes.STONE_DARK, 10)
	CDMeshes.cylinder(plinth_st, Vector3(0, 0.12, 0), 0.7, 0.08, CDMeshes.STONE, 10)
	for i: int in 6:
		var a: float = TAU * i / 6.0
		CDMeshes.box(plinth_st, Vector3(cos(a) * 0.86, 0.2, sin(a) * 0.86), Vector3(0.12, 0.3, 0.12), CDMeshes.STONE)
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	plinth.mesh = plinth_st.commit()
	plinth.material_override = CDMeshes.lit_material()
	_crystal_root.add_child(plinth)
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.vertex_color_use_as_albedo = true
	_crystal_mat.albedo_color = Color(0.72, 0.45, 1.0, 0.88)
	_crystal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(0.55, 0.22, 1.0)
	_crystal_mat.emission_energy_multiplier = 1.2
	_crystal_mat.roughness = 0.15
	_crystal_mat.metallic_specular = 0.9
	_crystal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crystal_mi = MeshInstance3D.new()
	_crystal_mi.name = "Gem"
	_crystal_mi.mesh = CDMeshes.crystal_mesh(2.0, 0.42)
	_crystal_mi.material_override = _crystal_mat
	_crystal_mi.position = Vector3(0, 0.2, 0)
	_crystal_root.add_child(_crystal_mi)
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.42
	sm.radial_segments = 10
	sm.rings = 5
	core.mesh = sm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(0.95, 0.85, 1.0)
	core.material_override = _core_mat
	core.position = Vector3(0, 1.0, 0)
	_crystal_mi.add_child(core)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cracks = ImmediateMesh.new()
	_cracks_mi = MeshInstance3D.new()
	_cracks_mi.name = "Cracks"
	_cracks_mi.mesh = _cracks
	_cracks_mi.material_override = line_mat
	_crystal_mi.add_child(_cracks_mi)
	_bolts = ImmediateMesh.new()
	var bolts_mi := MeshInstance3D.new()
	bolts_mi.name = "Lightning"
	bolts_mi.mesh = _bolts
	bolts_mi.material_override = line_mat
	bolts_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cells.add_child(bolts_mi)


func _make_mm(node_name: String, mesh: Mesh, mat: Material, count: int, colors: bool = true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cells.add_child(mi)
	return mm


func _build_pools() -> void:
	_enemy_mm = _make_mm("Stalkers", CDMeshes.stalker_mesh(), null, CDDefs.MAX_ALIVE)
	_dying_mm = _make_mm("Dying", CDMeshes.stalker_mesh(), null, MAX_DYING)
	var bar := QuadMesh.new()
	bar.size = Vector2(0.56, 0.07)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.vertex_color_use_as_albedo = true
	bar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bar_mat.no_depth_test = true
	bar_mat.render_priority = 2
	_bar_mm = _make_mm("HealthBars", bar, bar_mat, CDDefs.MAX_ALIVE * 2)
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.035, 0.035, 0.36)
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(0.95, 0.9, 0.7)
	arrow_mat.emission_enabled = true
	arrow_mat.emission = Color(1.0, 0.9, 0.6)
	arrow_mat.emission_energy_multiplier = 0.6
	_arrow_mm = _make_mm("Arrows", shaft, arrow_mat, MAX_ARROWS, false)
	var ball := SphereMesh.new()
	ball.radius = 0.11
	ball.height = 0.22
	ball.radial_segments = 8
	ball.rings = 4
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.15, 0.14, 0.15)
	ball_mat.emission_enabled = true
	ball_mat.emission = ORANGE
	ball_mat.emission_energy_multiplier = 0.4
	_bomb_mm = _make_mm("Bombs", ball, ball_mat, MAX_BOMBS, false)
	var fx_mat := AreaViz.material(Color.WHITE).duplicate() as StandardMaterial3D
	_fx_mm = _make_mm("Explosions", AreaViz.ring_mesh(1.0, 0.28, Color.WHITE, 24), fx_mat, MAX_FX)
	_burn_mm = _make_mm("Burns", AreaViz.disc_mesh(1.0, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.9), 20), fx_mat, MAX_FX)


func _sync_structures() -> void:
	for id: int in _structure_nodes.keys():
		if not sim.structures.has(id):
			(_structure_nodes[id] as Node).queue_free()
			_structure_nodes.erase(id)
	for id: int in sim.structures:
		var s: Dictionary = sim.structures[id]
		var key: String = "%s_%d" % [s["type"], s["level"]]
		var mi: MeshInstance3D = _structure_nodes.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = "S%d" % id
			_cells.add_child(mi)
			_structure_nodes[id] = mi
		if mi.get_meta("key", "") != key:
			mi.mesh = CDMeshes.structure_mesh(s["type"], int(s["level"]))
			mi.set_meta("key", key)
		var c: Vector2 = BoardGrid.center_of(s["cell"])
		mi.position = Vector3(c.x, 0, c.y)
	_refresh_rings()


func _sync_squads() -> void:
	for id: int in _squad_nodes.keys():
		if not sim.squads.has(id):
			(_squad_nodes[id] as Node).queue_free()
			_squad_nodes.erase(id)
	for id: int in sim.squads:
		var q: Dictionary = sim.squads[id]
		var node: Node3D = _squad_nodes.get(id)
		var key: String = "%d_%d" % [int(q["rank"]), sim.squad_size(q)]
		if node == null or node.get_meta("key", "") != key:
			if node != null:
				node.queue_free()
			node = Node3D.new()
			node.name = "Q%d" % id
			node.set_meta("key", key)
			var n: int = sim.squad_size(q)
			var offsets: Array[Vector2] = _formation(n)
			for k: int in n:
				var m := MeshInstance3D.new()
				m.name = "M%d" % k
				m.mesh = CDMeshes.knight_mesh(int(q["rank"]))
				m.position = Vector3(offsets[k].x, 0, offsets[k].y)
				node.add_child(m)
			_cells.add_child(node)
			_squad_nodes[id] = node
		var members: Array = q["members"]
		for k: int in node.get_child_count():
			(node.get_child(k) as Node3D).visible = k < members.size() and float(members[k]) > 0.0 and float(q["redeploy_t"]) <= 0.0
		var cell: Vector2i = q["target_cell"] if float(q["redeploy_t"]) > 0.0 else q["cell"]
		var c: Vector2 = BoardGrid.center_of(cell)
		node.position = Vector3(c.x, 0, c.y)
		var f: Vector2 = q["facing"]
		node.rotation.y = atan2(-f.x, -f.y)
	_refresh_rings()


static func _formation(n: int) -> Array[Vector2]:
	match n:
		1:
			return [Vector2.ZERO]
		2:
			return [Vector2(-0.2, 0), Vector2(0.2, 0)]
		3:
			return [Vector2(0, -0.2), Vector2(-0.22, 0.15), Vector2(0.22, 0.15)]
		_:
			return [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]


func toggle_ranges() -> void:
	show_all_ranges = not show_all_ranges
	_refresh_rings()
	_refresh_hud()


## Range rings: every tower with the eye on, plus the selection; the
## selected squad's arc.
func _refresh_rings() -> void:
	if _rings_root == null:
		return
	for c: Node in _rings_root.get_children():
		_rings_root.remove_child(c)
		c.queue_free()
	for id: int in sim.structures:
		var s: Dictionary = sim.structures[id]
		if CDDefs.is_barrier(s["type"]):
			continue
		if not show_all_ranges and id != selected_struct:
			continue
		var st: Dictionary = CDDefs.level_stats(s["type"], int(s["level"]))
		var ring: MeshInstance3D = AreaViz.ring(float(st["range"]), Holo.CYAN if id == selected_struct else Color(Holo.CYAN, 0.55), 0.08)
		var c: Vector2 = BoardGrid.center_of(s["cell"])
		ring.position = Vector3(c.x, 0.04, c.y)
		_rings_root.add_child(ring)
	if selected_squad != 0 and sim.squads.has(selected_squad):
		var q: Dictionary = sim.squads[selected_squad]
		var stats: Dictionary = sim.squad_rank_stats(q)
		var arc: MeshInstance3D = AreaViz.sector(float(stats["reach"]) + CDSim.ENGAGE_EXTRA + 0.5, deg_to_rad(float(CDDefs.UNITS[q["unit"]]["arc_deg"])), Holo.GOLD)
		var c: Vector2 = BoardGrid.center_of(q["cell"])
		arc.position = Vector3(c.x, 0.04, c.y)
		var f: Vector2 = q["facing"]
		arc.rotation.y = atan2(-f.x, -f.y)
		arc.name = "SquadArc"
		_rings_root.add_child(arc)
	if crystal_selected:
		var storm: MeshInstance3D = AreaViz.ring(CDDefs.STORM_RANGE + 1.0, PURPLE, 0.08)
		storm.position = Vector3(sim.crystal_center.x, 0.04, sim.crystal_center.y)
		_rings_root.add_child(storm)


func ring_count() -> int:
	return _rings_root.get_child_count() if _rings_root != null else 0


# --- Spawn warnings -----------------------------------------------------------------

func _edge_strip(cells: Array, side: int, color: Color, width: float) -> MeshInstance3D:
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[cells.size() - 1]
	var n: Vector2 = BoardGrid.side_normal(side)
	var p0 := Vector2(mini(a.x, b.x), mini(a.y, b.y))
	var p1 := Vector2(maxi(a.x, b.x) + 1, maxi(a.y, b.y) + 1)
	var s0: Vector3
	var s1: Vector3
	if side == BoardGrid.Side.WEST or side == BoardGrid.Side.EAST:
		var x: float = 0.0 if side == BoardGrid.Side.WEST else float(CDDefs.GRID_N)
		x -= n.x * width * 0.5
		s0 = Vector3(x, 0.06, p0.y)
		s1 = Vector3(x, 0.06, p1.y)
	else:
		var y: float = 0.0 if side == BoardGrid.Side.NORTH else float(CDDefs.GRID_N)
		y -= n.y * width * 0.5
		s0 = Vector3(p0.x, 0.06, y)
		s1 = Vector3(p1.x, 0.06, y)
	var mi := MeshInstance3D.new()
	mi.mesh = AreaViz.strip_mesh(s0, s1, width, Color.WHITE)
	var m := AreaViz.material(color).duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _add_telegraph(e: Dictionary) -> void:
	var mi: MeshInstance3D = _edge_strip(e["cells"], int(e["side"]), ORANGE, 0.42)
	mi.name = "Telegraph"
	_telegraph_root.add_child(mi)
	_telegraphs.append({"node": mi, "t_spawn": float(e["t_spawn"])})


func _clear_telegraphs() -> void:
	for t: Dictionary in _telegraphs:
		(t["node"] as Node).queue_free()
	_telegraphs.clear()


func telegraph_count() -> int:
	return _telegraphs.size()


func _rebuild_side_rim() -> void:
	_clear_side_rim()
	if sim.plan.is_empty():
		return
	for side: int in sim.plan.get("sides", []):
		var cells: Array[Vector2i] = vgrid.side_cells(side)
		var mi: MeshInstance3D = _edge_strip(cells, side, Color(ORANGE, 0.35), 0.16)
		mi.name = "SideRim%d" % side
		_side_rim_root.add_child(mi)


func _clear_side_rim() -> void:
	if _side_rim_root == null:
		return
	for c: Node in _side_rim_root.get_children():
		c.queue_free()


func _add_fx(pos: Vector2, radius: float, color: Color) -> void:
	if _fx.size() >= MAX_FX:
		_fx.pop_front()
	_fx.append({"pos": pos, "radius": radius, "t": 0.0, "color": color})


# --- Visual sync --------------------------------------------------------------------

func _sync_visuals(delta: float) -> void:
	if _cells == null:
		return
	var alpha: float = clock.alpha() if ui_state == UI.PLAY else 1.0
	var live: PackedInt32Array = sim.enemies.live
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var bar_basis := Basis()
	if cam != null:
		var b: Basis = _cells.global_transform.basis.inverse() * cam.global_transform.basis
		bar_basis = Basis(b.x.normalized(), b.y.normalized(), b.z.normalized())
	var n: int = 0
	var bars: int = 0
	for i: int in live:
		var p: Vector2 = sim.e_prev[i].lerp(sim.e_pos[i], alpha)
		var mv: Vector2 = sim.e_pos[i] - sim.e_prev[i]
		if mv.length_squared() > 0.000001:
			_facing[i] = mv.normalized()
		elif _facing[i] == Vector2.ZERO:
			_facing[i] = (sim.crystal_center - p).normalized()
		var f: Vector2 = _facing[i]
		var moving: bool = mv.length_squared() > 0.000001 and sim.e_engaged[i] == 0
		var gait: float = _anim * 9.0 + float(i) * 1.7
		var bob: float = absf(sin(gait)) * 0.04 if moving else 0.0
		var scale_k: float = [1.0, 1.25, 1.5][clampi(sim.e_condense[i], 0, 2)]
		var lean: float = 0.12 if moving else (0.25 + 0.15 * sin(_anim * 14.0 + i) if sim.e_engaged[i] != 0 else 0.0)
		var basis := Basis(Vector3.UP, atan2(-f.x, -f.y)) * Basis(Vector3.RIGHT, -lean) * Basis(Vector3.FORWARD, sin(gait) * 0.08 if moving else 0.0)
		basis = basis.scaled(Vector3.ONE * scale_k)
		_enemy_mm.set_instance_transform(n, Transform3D(basis, Vector3(p.x, bob, p.y)))
		var col := Color(1, 1, 1)
		if sim.e_condense[i] == 1:
			col = Color(0.78, 0.84, 1.0)
		elif sim.e_condense[i] >= 2:
			col = Color(0.8, 0.65, 1.0)
		if sim.e_flash[i] > 0.0:
			col = Color(1.0, 0.45, 0.4)
		_enemy_mm.set_instance_color(n, col)
		n += 1
		var frac: float = clampf(sim.e_hp[i] / maxf(0.001, sim.e_max[i]), 0.0, 1.0)
		if frac < 0.999 and bars + 1 < _bar_mm.instance_count:
			var top := Vector3(p.x, 0.92 * scale_k, p.y)
			_bar_mm.set_instance_transform(bars, Transform3D(bar_basis, top))
			_bar_mm.set_instance_color(bars, Color(0.1, 0.05, 0.08))
			bars += 1
			var fg_basis: Basis = Basis(bar_basis.x * frac, bar_basis.y, bar_basis.z)
			var shift: Vector3 = bar_basis.x * (-0.28 * (1.0 - frac)) + bar_basis.z * 0.002
			_bar_mm.set_instance_transform(bars, Transform3D(fg_basis, top + shift))
			_bar_mm.set_instance_color(bars, Color(1.0, 0.25, 0.2).lerp(Color(0.4, 1.0, 0.45), frac))
			bars += 1
	_enemy_mm.visible_instance_count = n
	_bar_mm.visible_instance_count = bars
	# Dying: fall back, sink and fade.
	var keep: Array[Dictionary] = []
	var dn: int = 0
	for d: Dictionary in _dying:
		d["t"] = float(d["t"]) + delta
		var t: float = float(d["t"]) / 0.55
		if t >= 1.0:
			continue
		keep.append(d)
		var p2: Vector2 = d["pos"]
		var f2: Vector2 = _facing[int(d["slot"])] if _facing[int(d["slot"])] != Vector2.ZERO else Vector2(0, 1)
		var k: float = [1.0, 1.25, 1.5][clampi(int(d["condense"]), 0, 2)] * (1.0 - 0.5 * t)
		var basis2 := Basis(Vector3.UP, atan2(-f2.x, -f2.y)) * Basis(Vector3.RIGHT, t * 1.3)
		_dying_mm.set_instance_transform(dn, Transform3D(basis2.scaled(Vector3.ONE * k), Vector3(p2.x, -0.2 * t, p2.y)))
		_dying_mm.set_instance_color(dn, Color(1.0 - 0.6 * t, 1.0 - 0.6 * t, 1.0 - 0.4 * t))
		dn += 1
	_dying = keep
	_dying_mm.visible_instance_count = dn
	_sync_projectiles(delta)
	_sync_squad_anim(delta)
	_sync_crystal(delta)
	_sync_telegraphs()


func _sync_projectiles(delta: float) -> void:
	var keep: Array[Dictionary] = []
	var an: int = 0
	for a: Dictionary in _arrows:
		a["t"] = float(a["t"]) + delta * clock.speed
		var t: float = float(a["t"]) / ARROW_TIME
		if t >= 1.0:
			continue
		keep.append(a)
		var from: Vector2 = a["from"]
		var to: Vector2 = a["to"]
		var p0 := Vector3(from.x, 1.05, from.y)
		var p1 := Vector3(to.x, 0.45, to.y)
		var at: Vector3 = p0.lerp(p1, t) + Vector3(0, sin(t * PI) * 0.25, 0)
		var dir: Vector3 = (p1 - p0).normalized()
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), at)
		_arrow_mm.set_instance_transform(an, xf)
		an += 1
	_arrows = keep
	_arrow_mm.visible_instance_count = an
	var bn: int = 0
	for b: Dictionary in sim.bombs:
		if bn >= MAX_BOMBS:
			break
		var t: float = clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
		var from: Vector2 = b["from"]
		var to: Vector2 = b["to"]
		var p: Vector2 = from.lerp(to, t)
		_bomb_mm.set_instance_transform(bn, Transform3D(Basis(), Vector3(p.x, 0.6 + 1.6 * 4.0 * t * (1.0 - t), p.y)))
		bn += 1
	_bomb_mm.visible_instance_count = bn
	var fxk: Array[Dictionary] = []
	var fn: int = 0
	for e: Dictionary in _fx:
		e["t"] = float(e["t"]) + delta
		var t: float = float(e["t"]) / 0.4
		if t >= 1.0:
			continue
		fxk.append(e)
		var r: float = float(e["radius"]) * (0.3 + 0.7 * t)
		var p: Vector2 = e["pos"]
		_fx_mm.set_instance_transform(fn, Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(p.x, 0.08, p.y)))
		_fx_mm.set_instance_color(fn, Color(e["color"], 1.0 - t))
		fn += 1
	_fx = fxk
	_fx_mm.visible_instance_count = fn
	var un: int = 0
	for burn: Dictionary in sim.burns:
		if un >= MAX_FX:
			break
		var r: float = float(burn["radius"])
		var p: Vector2 = burn["pos"]
		_burn_mm.set_instance_transform(un, Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(p.x, 0.05, p.y)))
		_burn_mm.set_instance_color(un, Color(1.0, 0.35, 0.1, 0.25 + 0.1 * sin(_anim * 12.0)))
		un += 1
	_burn_mm.visible_instance_count = un


func _sync_squad_anim(delta: float) -> void:
	for id: int in _squad_lunge.keys():
		var t: float = float(_squad_lunge[id]) - delta
		if t <= 0.0:
			_squad_lunge.erase(id)
		else:
			_squad_lunge[id] = t
	for id: int in _squad_nodes:
		if not sim.squads.has(id):
			continue
		var q: Dictionary = sim.squads[id]
		var node: Node3D = _squad_nodes[id]
		var members: Array = q["members"]
		var redeploying: bool = float(q["redeploy_t"]) > 0.0
		var lunge: float = float(_squad_lunge.get(id, 0.0)) / 0.18
		for k: int in node.get_child_count():
			var m: Node3D = node.get_child(k)
			m.visible = not redeploying and k < members.size() and float(members[k]) > 0.0
			var base: Vector2 = _formation(node.get_child_count())[k]
			m.position = Vector3(base.x, 0, base.y - sin(lunge * PI) * 0.15)
		var cell: Vector2i = q["target_cell"] if redeploying else q["cell"]
		var c: Vector2 = BoardGrid.center_of(cell)
		node.position = Vector3(c.x, 0, c.y)
		var f: Vector2 = q["facing"]
		node.rotation.y = atan2(-f.x, -f.y)


func crack_stage() -> int:
	var frac: float = sim.crystal_hp / maxf(1.0, sim.crystal_max)
	if frac > 0.75:
		return 0
	if frac > 0.5:
		return 1
	if frac > 0.25:
		return 2
	return 3


func _sync_crystal(delta: float) -> void:
	var frac: float = clampf(sim.crystal_hp / maxf(1.0, sim.crystal_max), 0.0, 1.0)
	_crystal_flash = maxf(0.0, _crystal_flash - delta)
	var beat: float = 0.0
	if frac < 0.2 and sim.phase() != CDSim.PHASE_DEFEAT:
		beat = pow(maxf(0.0, sin(_anim * 7.0)), 8.0)
	var energy: float = 0.5 + 1.0 * frac + 1.6 * beat + 2.0 * _crystal_flash
	if sim.phase() == CDSim.PHASE_DEFEAT:
		energy = 0.1
	_crystal_mat.emission_energy_multiplier = energy
	_crystal_mat.albedo_color = Color(0.72, 0.45, 1.0, 0.88).lerp(Color(0.45, 0.38, 0.55, 0.92), 1.0 - frac)
	_core_mat.albedo_color = Color(0.95, 0.85, 1.0).lerp(Color(1.0, 0.35, 0.45), maxf(_crystal_flash * 2.0, beat * 0.6))
	_crystal_mi.position.y = 0.2 + 0.04 * sin(_anim * 1.6)
	_crystal_mi.rotation.y = _anim * 0.25
	var stage: int = crack_stage()
	if stage != _crack_stage:
		_crack_stage = stage
		_draw_cracks(stage)
	_bolt_timer -= delta
	var redraw: bool = _bolt_timer <= 0.0
	for b: Dictionary in _bolt_list:
		b["t"] = float(b["t"]) - delta
	_bolt_list = _bolt_list.filter(func(b: Dictionary) -> bool: return float(b["t"]) > 0.0)
	if redraw or not _bolt_list.is_empty():
		_bolt_timer = 0.09
		_draw_lightning(frac)


func _draw_cracks(stage: int) -> void:
	_cracks.clear_surfaces()
	if stage <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	_cracks.surface_begin(Mesh.PRIMITIVE_LINES)
	for k: int in stage * 3:
		var a: float = rng.randf() * TAU
		var y: float = rng.randf_range(0.5, 1.5)
		var p := Vector3(cos(a) * 0.43, y, sin(a) * 0.43)
		for _s: int in 4:
			var q: Vector3 = p + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.18, 0.18), rng.randf_range(-0.08, 0.08))
			var r: float = 0.43 * (1.0 - absf(q.y - 0.8) * 0.35)
			var qa: float = atan2(q.z, q.x)
			q = Vector3(cos(qa) * r, q.y, sin(qa) * r)
			_cracks.surface_set_color(Color(1.0, 0.95, 1.0, 0.9))
			_cracks.surface_add_vertex(p)
			_cracks.surface_set_color(Color(1.0, 0.95, 1.0, 0.9))
			_cracks.surface_add_vertex(q)
			p = q
	_cracks.surface_end()


## Lightning crawling over the Crystal, plus Storm Pulse bolts to targets.
func _draw_lightning(frac: float) -> void:
	_bolts.clear_surfaces()
	if sim.phase() == CDSim.PHASE_DEFEAT:
		return
	_bolts.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := Vector3(sim.crystal_center.x, 0, sim.crystal_center.y)
	var arcs: int = 2 + int(round(2.0 * frac))
	for k: int in arcs:
		var a0: float = randf() * TAU
		var p := c + Vector3(cos(a0) * 0.45, randf_range(0.4, 0.8), sin(a0) * 0.45)
		for _s: int in 5:
			var a: float = a0 + randf_range(-0.6, 0.6)
			var q := c + Vector3(cos(a) * randf_range(0.3, 0.55), p.y + randf_range(0.12, 0.3), sin(a) * randf_range(0.3, 0.55))
			_line(p, q, Color(0.85, 0.7, 1.0, 0.95))
			p = q
	var top := c + Vector3(0, 2.1, 0)
	for b: Dictionary in _bolt_list:
		var to2: Vector2 = b["to"]
		var to := Vector3(to2.x, 0.4, to2.y)
		var p := top
		for s: int in 6:
			var q: Vector3 = top.lerp(to, float(s + 1) / 6.0)
			if s < 5:
				q += Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), randf_range(-0.15, 0.15))
			_line(p, q, Color(0.95, 0.85, 1.0, 1.0))
			p = q
	_bolts.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_bolts.surface_set_color(col)
	_bolts.surface_add_vertex(a)
	_bolts.surface_set_color(col)
	_bolts.surface_add_vertex(b)


func _sync_telegraphs() -> void:
	var keep: Array[Dictionary] = []
	for t: Dictionary in _telegraphs:
		var left: float = float(t["t_spawn"]) + 1.0 - sim.wave_time
		if left <= 0.0 or sim.phase() != CDSim.PHASE_WAVE:
			(t["node"] as Node).queue_free()
			continue
		keep.append(t)
		var mi: MeshInstance3D = t["node"]
		var m: StandardMaterial3D = mi.material_override
		var urgency: float = clampf(1.0 - (float(t["t_spawn"]) - sim.wave_time) / CDDefs.TELEGRAPH, 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(_anim * (6.0 + 10.0 * urgency))
		m.albedo_color = Color(ORANGE, 0.35 + 0.55 * pulse)
	_telegraphs = keep


func _screen_of_cell(c: Vector2, h: float) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var view: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1080, 2340)
	if cam == null or _cells == null:
		return view * 0.5
	var world: Vector3 = _cells.to_global(Vector3(c.x, h, c.y))
	if cam.is_position_behind(world):
		return view * 0.5
	return cam.unproject_position(world)


# --- HUD ----------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "CrystalDefenseHud"
	_hud.layer = 4
	add_child(_hud)
	_top = PanelContainer.new()
	_top.name = "Top"
	_top.add_theme_stylebox_override("panel", LGUI.panel_style(Color(0.03, 0.05, 0.13, 0.62), 16, 12))
	_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.add_child(_top)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", 4)
	_top.add_child(tb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	tb.add_child(row)
	_mana_label = LGUI.label(34, MANA_BLUE)
	_mana_label.name = "Mana"
	row.add_child(_mana_label)
	_wave_label = LGUI.label(30, Color(1.0, 0.86, 0.45))
	_wave_label.name = "Wave"
	row.add_child(_wave_label)
	var hp_row := HBoxContainer.new()
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_row.add_theme_constant_override("separation", 10)
	tb.add_child(hp_row)
	_hp_label = LGUI.label(20, Color(0.88, 0.8, 1.0))
	hp_row.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "CrystalHP"
	_hp_bar.custom_minimum_size = Vector2(300, 18)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.max_value = CDDefs.CRYSTAL_HP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.08, 0.2, 0.9)
	bg.set_corner_radius_all(9)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PURPLE
	fill.set_corner_radius_all(9)
	_hp_bar.add_theme_stylebox_override("background", bg)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	_info_label = LGUI.label(20, Color(0.92, 0.95, 1.0))
	_info_label.name = "Info"
	tb.add_child(_info_label)
	# Bottom left: Build, Summon.
	_left_row = HBoxContainer.new()
	_left_row.name = "LeftRow"
	_left_row.add_theme_constant_override("separation", 12)
	_left_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_left_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud.add_child(_left_row)
	build_button = LGUI.button("Build", Holo.CYAN, 28, Vector2(160, 96))
	build_button.name = "BuildButton"
	build_button.pressed.connect(open_build)
	_left_row.add_child(build_button)
	summon_button = LGUI.button("Summon", Holo.GREEN, 28, Vector2(180, 96))
	summon_button.name = "SummonButton"
	summon_button.pressed.connect(open_summon)
	_left_row.add_child(summon_button)
	# Bottom right: Auto, 2x, ranges, pause.
	_right_row = BoxContainer.new()
	_right_row.name = "RightRow"
	_right_row.add_theme_constant_override("separation", 12)
	_right_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_right_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_right_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.add_child(_right_row)
	auto_button = LGUI.button("Auto", Holo.GOLD, 24, Vector2(110, 96))
	auto_button.name = "AutoButton"
	auto_button.toggle_mode = true
	auto_button.toggled.connect(func(on: bool) -> void:
		sim.set_autostart(on)
		_refresh_hud())
	_right_row.add_child(auto_button)
	speed_button = LGUI.button("1x", Color(0.9, 0.95, 1.0), 26, Vector2(96, 96))
	speed_button.name = "SpeedButton"
	speed_button.pressed.connect(func() -> void: set_fast(not fast))
	_right_row.add_child(speed_button)
	eye_button = LGUI.button("◎", Holo.CYAN, 34, Vector2(96, 96))
	eye_button.name = "RangesButton"
	eye_button.toggle_mode = true
	eye_button.pressed.connect(toggle_ranges)
	_right_row.add_child(eye_button)
	pause_button = LGUI.button("II", Color(0.9, 0.95, 1.0), 32, Vector2(96, 96))
	pause_button.name = "PauseButton"
	pause_button.pressed.connect(func() -> void: pause(&"button"))
	_right_row.add_child(pause_button)
	start_button = LGUI.button("Start Wave 1", ORANGE, 30, Vector2(330, 96))
	start_button.name = "StartButton"
	start_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	start_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	start_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	start_button.pressed.connect(func() -> void: start_wave())
	_hud.add_child(start_button)
	# Placement confirm bar.
	_confirm_bar = PanelContainer.new()
	_confirm_bar.name = "ConfirmBar"
	_confirm_bar.add_theme_stylebox_override("panel", LGUI.panel_style(Color(0.03, 0.05, 0.13, 0.82), 16, 10))
	_confirm_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_confirm_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud.add_child(_confirm_bar)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 6)
	_confirm_bar.add_child(cb)
	_confirm_label = LGUI.label(22)
	cb.add_child(_confirm_label)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 12)
	cb.add_child(crow)
	confirm_button = LGUI.button("✓ Place", Holo.GREEN, 28, Vector2(220, 92))
	confirm_button.name = "ConfirmButton"
	confirm_button.pressed.connect(func() -> void: confirm())
	crow.add_child(confirm_button)
	turn_button = LGUI.button("↻", Holo.GOLD, 32, Vector2(96, 92))
	turn_button.name = "TurnButton"
	turn_button.pressed.connect(turn_moving_squad)
	crow.add_child(turn_button)
	cancel_button = LGUI.button("✕", Color(0.9, 0.95, 1.0), 30, Vector2(96, 92))
	cancel_button.name = "CancelButton"
	cancel_button.pressed.connect(cancel_mode)
	crow.add_child(cancel_button)
	_confirm_bar.visible = false
	sheet = CatalogSheet.new()
	sheet.item_chosen.connect(_on_sheet_item)
	sheet.set_cost_formatter(func(c: int) -> String: return "◆ %d" % c)
	_hud.add_child(sheet)
	popup = AnchorPopup.new()
	popup.action_chosen.connect(_on_popup_action)
	_hud.add_child(popup)
	_banner = LGUI.label(52, Color(1.0, 0.86, 0.45))
	_banner.name = "Banner"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_child(_banner)
	_countdown_label = LGUI.label(150, Color(1.0, 0.9, 0.45))
	_countdown_label.name = "Countdown"
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_label.offset_left = -200
	_countdown_label.offset_right = 200
	_countdown_label.offset_top = -110
	_countdown_label.offset_bottom = 110
	_hud.add_child(_countdown_label)
	_pause_panel = _center_panel("PausePanel")
	var pbox := VBoxContainer.new()
	pbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pbox.add_theme_constant_override("separation", 14)
	_pause_panel.add_child(pbox)
	var ptitle := LGUI.label(42, Color(1.0, 0.86, 0.45))
	ptitle.text = "Paused"
	pbox.add_child(ptitle)
	_pause_label = LGUI.label(24)
	_pause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pbox.add_child(_pause_label)
	resume_button = LGUI.button("Resume", Holo.CYAN, 30, Vector2(240, 88))
	resume_button.name = "ResumeButton"
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume_button.pressed.connect(resume)
	pbox.add_child(resume_button)
	_pause_panel.visible = false
	_over_panel = _center_panel("DefeatPanel")
	var obox := VBoxContainer.new()
	obox.alignment = BoxContainer.ALIGNMENT_CENTER
	obox.add_theme_constant_override("separation", 12)
	_over_panel.add_child(obox)
	var otitle := LGUI.label(40, Holo.MAGENTA)
	otitle.text = "The Crystal shattered"
	obox.add_child(otitle)
	_over_label = LGUI.label(24)
	obox.add_child(_over_label)
	retry_button = LGUI.button("Defend again", Holo.CYAN, 30, Vector2(280, 88))
	retry_button.name = "RetryButton"
	retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(restart)
	obox.add_child(retry_button)
	_over_panel.visible = false
	_layout_hud()


func _center_panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", LGUI.panel_style(Color(0.03, 0.05, 0.13, 0.88), 18, 22))
	_hud.add_child(panel)
	return panel


## Portrait: stats under the platform's status line; Build / Summon bottom
## left, Auto / 2x / ranges / pause bottom right, Start Wave (or the confirm
## bar) centred above them. Landscape: stats top centre; one bottom row with
## Start Wave in the middle. Everything clears ui_bottom_inset().
func _layout_hud() -> void:
	if _top == null:
		return
	var portrait: bool = is_portrait()
	var view: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1080, 2340)
	var bottom: float = maxf(20.0, ui_bottom_inset() + 12.0)
	_top.offset_top = 112.0 if portrait else 14.0
	_top.offset_bottom = _top.offset_top + 10.0
	var w: float = 640.0 if portrait else 500.0
	_top.offset_left = -w * 0.5
	_top.offset_right = w * 0.5
	_left_row.offset_left = 20.0
	_left_row.offset_bottom = -bottom
	_left_row.offset_top = -bottom - 96.0
	# Portrait is narrow (~720 px): the Auto / 2x / ranges / pause column
	# stands at the bottom right; landscape keeps one row.
	_right_row.vertical = portrait
	var rn: int = _right_row.get_child_count()
	var rh: float = (96.0 * rn + 12.0 * (rn - 1)) if portrait else 96.0
	var rw: float = 110.0 if portrait else (110.0 + 96.0 * 3 + 36.0)
	_right_row.offset_right = -20.0
	_right_row.offset_left = -20.0 - rw
	_right_row.offset_bottom = -bottom
	_right_row.offset_top = -bottom - rh
	var lift: float = (bottom + 96.0 + 20.0) if portrait else bottom
	start_button.offset_bottom = -lift
	start_button.offset_top = -lift - 96.0
	start_button.offset_left = -165.0
	start_button.offset_right = 165.0
	_confirm_bar.offset_bottom = -(bottom + 96.0 + 20.0) if portrait else -(bottom + 96.0 + 20.0)
	_confirm_bar.offset_top = _confirm_bar.offset_bottom - 10.0
	_confirm_bar.offset_left = -200.0
	_confirm_bar.offset_right = 200.0
	_banner.offset_top = (360.0 if portrait else 170.0)
	_banner.offset_bottom = _banner.offset_top + 80.0
	_banner.offset_left = -(view.x * 0.5 - 40.0)
	_banner.offset_right = view.x * 0.5 - 40.0
	var pw: float = 560.0 if portrait else 680.0
	for panel: PanelContainer in [_pause_panel, _over_panel]:
		panel.offset_left = -pw * 0.5
		panel.offset_right = pw * 0.5
		panel.offset_top = -150.0
		panel.offset_bottom = 150.0
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_label.custom_minimum_size = Vector2(pw - 60.0, 0)
	# The catalog sits above the bottom row so Start / pause stay reachable.
	sheet.layout(portrait, view, ui_bottom_inset() + 96.0 + 16.0)
	if popup.visible:
		popup.place(view, ui_bottom_inset() + 96.0 + 16.0)


func _set_text(label: Control, text: String) -> void:
	if label is Label and (label as Label).text != text:
		(label as Label).text = text
	elif label is Button and (label as Button).text != text:
		(label as Button).text = text


func _refresh_confirm() -> void:
	if mode == &"none":
		_confirm_bar.visible = false
		return
	_confirm_bar.visible = true
	var r: Dictionary = _placement.result()
	var ok: bool = bool(r.get("ok", false))
	turn_button.visible = mode == &"move"
	if mode == &"build":
		var cost: int = int(sim.can_build(build_type, _placement.cell)["cost"])
		_set_text(confirm_button, "✓ Place ◆ %d" % cost)
		_set_text(_confirm_label, "%s — %s" % [CDDefs.structure(build_type)["title"], "tap ✓ or the same cell" if ok else str(r.get("reason", ""))])
	else:
		_set_text(confirm_button, "✓ Redeploy" if sim.phase() == CDSim.PHASE_WAVE else "✓ Move here")
		_set_text(_confirm_label, "Move squad — %s" % ("tap ✓ or the same cell" if ok else str(r.get("reason", ""))))
	confirm_button.disabled = not ok


func hud_text() -> String:
	return "%s | %s | %s | %s" % [_mana_label.text, _wave_label.text, _hp_label.text, _info_label.text]


func _refresh_hud() -> void:
	if _hud == null or sim == null:
		return
	_hud.visible = is_playing()
	var p: StringName = sim.phase()
	var mana_text: String = "◆ %d" % sim.wallet.balance
	if sim.wallet.markup > 1.0:
		mana_text += "  ·  +50%"
	_set_text(_mana_label, mana_text)
	var phase_text: String
	match p:
		CDSim.PHASE_INTRO:
			phase_text = "Get ready"
		CDSim.PHASE_PREP:
			phase_text = "Wave %d · Prep" % sim.next_wave()
		CDSim.PHASE_WAVE:
			phase_text = "Wave %d" % sim.wave
		CDSim.PHASE_CLEAR:
			phase_text = "Wave %d cleared" % sim.wave
		_:
			phase_text = "Defeated"
	_set_text(_wave_label, phase_text)
	_hp_bar.max_value = sim.crystal_max
	_hp_bar.value = sim.crystal_hp
	_set_text(_hp_label, "Crystal %d" % int(ceil(sim.crystal_hp)))
	var info: String = ""
	if p == CDSim.PHASE_WAVE:
		var left: int = sim.enemies.count()
		var to_come: int = 0
		for g: Dictionary in sim.plan.get("groups", []):
			to_come += int(g["bodies"]) - int(g["spawned"])
		info = "%d Stalkers on the board · %d to come" % [left, to_come]
		if int(sim.plan.get("condense", 0)) > 0:
			info += " · Condensed"
	elif p == CDSim.PHASE_PREP:
		var sides: Array = sim.plan.get("sides", [])
		var names: PackedStringArray = []
		for s: int in sides:
			names.append(["West", "East", "North", "South"][s])
		info = "%d Pale Stalkers from the %s" % [int(sim.plan.get("count", 0)), ", ".join(names)]
		if sim.autostart and sim.auto_multiplier() > 1.0:
			info += " · mana ×%.2f" % sim.auto_multiplier()
	_set_text(_info_label, info)
	var placing: bool = mode != &"none"
	var defeat: bool = p == CDSim.PHASE_DEFEAT
	start_button.visible = p == CDSim.PHASE_PREP and not placing and not sheet.is_open()
	if sim.auto_countdown >= 0.0:
		_set_text(start_button, "Starting in %d · Wait" % int(ceil(sim.auto_countdown)))
	else:
		_set_text(start_button, "Start Wave %d" % sim.next_wave())
	build_button.disabled = not sim.phases.can(&"build") or defeat
	summon_button.disabled = not sim.phases.can(&"summon") or defeat
	if auto_button.button_pressed != sim.autostart:
		auto_button.set_pressed_no_signal(sim.autostart)
	_set_text(speed_button, "2x" if fast else "1x")
	if eye_button.button_pressed != show_all_ranges:
		eye_button.set_pressed_no_signal(show_all_ranges)
	_pause_panel.visible = ui_state == UI.PAUSED
	match pause_reason:
		&"rotate":
			_set_text(_pause_label, "You turned the phone. Resume when you're ready.")
		&"app":
			_set_text(_pause_label, "Welcome back. The wave is waiting.")
		_:
			_set_text(_pause_label, "The Stalkers are frozen mid-step.")
	_countdown_label.visible = ui_state == UI.COUNTDOWN
	if ui_state == UI.COUNTDOWN:
		_set_text(_countdown_label, str(int(ceil(countdown_t))))
	_over_panel.visible = defeat
	if defeat:
		_set_text(_over_label, "You held %d wave%s · %d Stalkers felled" % [maxi(0, sim.wave - 1), "" if sim.wave - 1 == 1 else "s", sim.total_kills])
	_banner.visible = banner_t > 0.0 and not defeat
	if _banner.visible:
		_banner.modulate.a = clampf(banner_t / 0.4, 0.0, 1.0)
	if sheet.is_open():
		var sig: String = "%d|%s|%d|%d|%s" % [sim.wallet.balance, p, sim.barrier_count(), sim.squads.size(), sheet.current_tab]
		if sig != _sheet_sig:
			_sheet_sig = sig
			if sheet.current_tab == &"squads":
				_fill_summon_items()
			else:
				_fill_build_items()
	var status: String
	if placing:
		status = "Placing: drag or tap a cell"
	elif p == CDSim.PHASE_PREP:
		status = "Prep: build, then Start Wave"
	elif p == CDSim.PHASE_WAVE:
		status = "Defend the Crystal"
	else:
		status = ""
	if get_status() != status:
		set_status(status)
