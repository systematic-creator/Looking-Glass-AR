class_name MageRunGame
extends LGGame
## Mage Run: a medieval fantasy three-lane endless runner on a storybook
## diorama. The wizard runs toward a castle at the far end of the board;
## the world scrolls toward the player. Swipe left / right to change lane,
## up to jump (or climb onto the arcane row above), down to slide (or drop a
## row). Two hologram "arcane rows" of rune-stone platforms (3 lanes each)
## appear above the road from 150 m and 400 m. Coins fill the staff meter;
## a full staff casts Shield, Magnet or Levitation (in turn).
##
## The logic lives in MageRunSim (no nodes, tested headless); this node
## draws it, reads swipes and taps, and runs the HUD and the pause /
## countdown / game-over flow. Turning the phone mid-run pauses; Resume
## counts down 3-2-1. See docs/mage-run.md.

## The board the layout is designed for (board m); a different (fitted)
## board scales the whole diorama uniformly to fit.
const DESIGN_BOARD := Vector2(0.3, 0.6)
## The world sits on a stone base this thick.
const BASE_HEIGHT: float = 0.008
## Room needed above the base (the top row, a jump on it, the hat).
const DESIGN_HEIGHT: float = 0.39
const ROAD_WIDTH: float = 0.24
const COUNTDOWN: float = 3.0
const GO_FLASH: float = 0.5
const DOUBLE_TAP: float = 0.35
const HINT_TIME: float = 6.0
const OUTLINE_WHILE_PLAYING: float = 0.15
const MAX_STEP: float = 1.0 / 60.0
const TILE_WIDTH: float = 0.068
const MAX_COINS: int = 96
const MAX_TILES: int = 64
const MAX_RAMPS: int = 12

enum State { READY, COUNTDOWN, RUNNING, PAUSED, OVER }

## Best score of this app session.
static var session_best: int = 0
## Where the "first run" hint is remembered (tests point it elsewhere).
static var settings_path: String = "user://mage_run.cfg"
## Seed for the next run (tests set it; < 0 = random).
static var next_seed: int = -1

var sim: MageRunSim
var state: State = State.READY
var pause_reason: StringName = &""
var countdown_t: float = 0.0
var go_t: float = 0.0
var hint_t: float = -1.0
var scale_u: float = 1.0
var best_this_run: bool = false
var threaded_generation: bool = true

var _world: Node3D
var _wizard: Node3D
var _wizard_body: MeshInstance3D
var _wizard_tip: MeshInstance3D
var _shadow: MeshInstance3D
var _rune_ring: MeshInstance3D
var _shield: MeshInstance3D
var _magnet: MeshInstance3D
var _levitation: MeshInstance3D
var _trail: CPUParticles3D
var _sparkle: CPUParticles3D
var _road_mat: ShaderMaterial
var _tile_mm: MultiMesh
var _ramp_mm: MultiMesh
var _coin_mm: MultiMesh
var _props: Dictionary = {}
var _mm_xforms: Dictionary = {}
var _anim_t: float = 0.0
var _squash: float = 0.0
var _stumble_t: float = 0.0
var _crash_t: float = 0.0
var _last_tap: float = -INF
var _clock: float = 0.0

var _hud: CanvasLayer
var _score_box: VBoxContainer
var _score_label: Label
var _info_label: Label
var _row_label: Label
var _staff_panel: PanelContainer
var _meter: ProgressBar
var _power_label: Label
var cast_button: Button
var pause_button: Button
var _countdown_label: Label
var _hint_panel: PanelContainer
var _hint_label: Label
var _pause_panel: PanelContainer
var _pause_label: Label
var resume_button: Button
var _over_panel: PanelContainer
var _over_label: Label
var restart_button: Button
var _hud_cache: Dictionary = {}


# --- Platform hooks -----------------------------------------------------------------

func captures_swipes() -> bool:
	return true


func box_outline_while_playing() -> float:
	return OUTLINE_WHILE_PLAYING


func describe_point(_point: Vector3) -> String:
	return "%d m" % int(sim.distance) if sim != null else ""


func _on_board_ready() -> void:
	var board: Vector2 = get_board_size()
	scale_u = minf(minf(board.x / DESIGN_BOARD.x, board.y / DESIGN_BOARD.y), get_box().height() / (DESIGN_HEIGHT + BASE_HEIGHT))
	_world = Node3D.new()
	_world.name = "World"
	_world.scale = Vector3.ONE * scale_u
	_world.position = Vector3(0, BASE_HEIGHT * scale_u, 0)
	add_child(_world)
	_build_scenery()
	_build_wizard()
	_build_pools()
	_build_hud()
	sim = MageRunSim.new(_pick_seed())
	sim.threaded = threaded_generation and OS.has_feature("mobile")
	_show_first_run_hint()
	state = State.READY
	if is_playing():
		_start_countdown()
	_sync_visuals(0.0)
	_refresh_hud()


func _on_box_changed(_box: PlayBox) -> void:
	pass


func _on_resumed() -> void:
	if state == State.READY:
		_start_countdown()
	_refresh_hud()


func _on_paused() -> void:
	pause(&"app")
	_refresh_hud()


func _on_exit() -> void:
	if sim != null:
		sim.finish_tasks()


func _exit_tree() -> void:
	if sim != null:
		sim.finish_tasks()


## Turning the phone mid-run pauses (the platform rule: the game decides).
func _on_orientation_changed(_portrait: bool) -> void:
	_layout_hud()
	pause(&"rotate")
	_refresh_hud()


func _on_swipe(direction: Vector2i, _info: Dictionary) -> void:
	if state != State.RUNNING:
		return
	_hide_hint()
	var dir := Vector2i(direction.x * lane_sign(), direction.y)
	sim.swipe(dir)


## Taps do nothing in a run except a double tap, which casts the staff.
func _on_box_ray(_origin: Vector3, _direction: Vector3) -> void:
	if state != State.RUNNING:
		return
	if _clock - _last_tap <= DOUBLE_TAP:
		_last_tap = -INF
		cast()
	else:
		_last_tap = _clock


func is_over_game_ui(screen: Vector2) -> bool:
	for c: Control in [cast_button, pause_button, _pause_panel, _over_panel]:
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(screen):
			return true
	return false


# --- Flow ---------------------------------------------------------------------------

func _pick_seed() -> int:
	if next_seed >= 0:
		return next_seed
	return randi() % 1000000


func restart() -> void:
	if sim == null:
		return
	sim.reset(_pick_seed())
	sim.threaded = threaded_generation and OS.has_feature("mobile")
	for node: Node3D in _props.values():
		node.queue_free()
	_props.clear()
	_crash_t = 0.0
	_stumble_t = 0.0
	best_this_run = false
	state = State.READY
	if is_playing():
		_start_countdown()
	_sync_visuals(0.0)
	_refresh_hud()


func _start_countdown() -> void:
	if state == State.OVER:
		return
	state = State.COUNTDOWN
	countdown_t = COUNTDOWN
	_refresh_hud()


## Pause a run (Pause button, the phone turning, the app pausing).
func pause(reason: StringName = &"button") -> void:
	if state != State.RUNNING and state != State.COUNTDOWN:
		return
	state = State.PAUSED
	pause_reason = reason
	sim.buffer.clear()
	_refresh_hud()


## Resume counts down 3-2-1 first.
func resume() -> void:
	if state != State.PAUSED or not is_playing():
		return
	_start_countdown()


func cast() -> int:
	if state != State.RUNNING:
		return -1
	var p: int = sim.cast()
	_refresh_hud()
	return p


## Swipe left / right as the player sees it: if the board is seen from its
## far end (the player walked round), the wizard's left is screen right.
func lane_sign() -> int:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _world == null:
		return 1
	var a: Vector3 = _world.to_global(Vector3(MageTrack.lane_x(0), 0.03, MageTrack.WIZARD_Z))
	var b: Vector3 = _world.to_global(Vector3(MageTrack.lane_x(2), 0.03, MageTrack.WIZARD_Z))
	if camera.is_position_behind(a) or camera.is_position_behind(b):
		return 1
	return 1 if camera.unproject_position(b).x >= camera.unproject_position(a).x else -1


func _process(delta: float) -> void:
	if sim == null:
		return
	_clock += delta
	_anim_t += delta
	if is_playing():
		match state:
			State.COUNTDOWN:
				countdown_t -= delta
				if countdown_t <= 0.0:
					state = State.RUNNING
					go_t = GO_FLASH
					_refresh_hud()
			State.RUNNING:
				var left: float = minf(delta, 0.1)
				while left > 0.0 and sim.alive:
					var dt: float = minf(left, MAX_STEP)
					sim.step(dt)
					left -= dt
				_handle_events()
				if not sim.alive:
					_game_over()
		if hint_t > 0.0 and state == State.RUNNING:
			hint_t -= delta
			if hint_t <= 0.0:
				_hide_hint()
	go_t = maxf(go_t - delta, 0.0)
	_squash = maxf(_squash - delta * 5.0, 0.0)
	_stumble_t = maxf(_stumble_t - delta, 0.0)
	if state == State.OVER:
		_crash_t += delta
	_sync_visuals(delta)
	_refresh_hud()


func _game_over() -> void:
	state = State.OVER
	_crash_t = 0.0
	if sim.score() > session_best:
		session_best = sim.score()
		best_this_run = true
	_refresh_hud()


func _handle_events() -> void:
	for e: Dictionary in sim.take_events():
		match e["kind"] as StringName:
			&"coin":
				_burst(_wizard.position + Vector3(0, 0.035, -0.01), MageProps.GOLD)
			&"land":
				_squash = 1.0
			&"stumble":
				_stumble_t = 0.45
			&"smash":
				var node: Node3D = _props.get(int(e["id"])) as Node3D
				if node != null:
					HoloSplash.spawn(_world, node.position + Vector3(0, 0.03, 0), Holo.CYAN, 0.05)
			&"crumble":
				_burst(_wizard.position + Vector3(0, 0.0, 0.0), Color(1.0, 0.4, 0.35))
			&"crash":
				HoloSplash.spawn(_world, _wizard.position + Vector3(0, 0.03, -0.01), Holo.CYAN, 0.04)
			&"cast":
				HoloSplash.spawn(_world, _wizard.position + Vector3(0, 0.01, 0), Holo.GOLD, 0.05)


func _burst(at: Vector3, color: Color) -> void:
	_sparkle.position = at
	_sparkle.color = color
	_sparkle.restart()
	_sparkle.emitting = true


# --- First-run hint -----------------------------------------------------------------

func _show_first_run_hint() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	if bool(cfg.get_value("mage_run", "hint_seen", false)):
		hint_t = -1.0
		_hint_panel.visible = false
		return
	cfg.set_value("mage_run", "hint_seen", true)
	cfg.save(settings_path)
	hint_t = HINT_TIME
	_hint_panel.visible = true
	_update_hint_text()


func _update_hint_text() -> void:
	var controls: String = "Swipe ← → to change lane, ↑ to jump or climb, ↓ to slide or drop."
	if is_portrait():
		_hint_label.text = "Hold the phone upright, like this.\n" + controls
	else:
		_hint_label.text = "Tip: Mage Run plays best with the phone held upright.\n" + controls


func hint_visible() -> bool:
	return _hint_panel != null and _hint_panel.visible


func _hide_hint() -> void:
	hint_t = -1.0
	if _hint_panel != null:
		_hint_panel.visible = false


# --- Scenery ------------------------------------------------------------------------

func _build_scenery() -> void:
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = MageProps.base(DESIGN_BOARD.x, DESIGN_BOARD.y, BASE_HEIGHT, ROAD_WIDTH)
	base.material_override = MageProps.solid_material()
	_world.add_child(base)
	var road := MeshInstance3D.new()
	road.name = "Road"
	var plane := PlaneMesh.new()
	var length: float = MageTrack.NEAR_Z + DESIGN_BOARD.y * 0.5 - 0.002 - (MageTrack.GATE_Z + DESIGN_BOARD.y * 0.5)
	plane.size = Vector2(ROAD_WIDTH, length)
	road.mesh = plane
	var zc: float = (MageTrack.GATE_Z + MageTrack.NEAR_Z) * 0.5
	road.position = Vector3(0, 0.0006, zc)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = preload("res://games/mage_run/shaders/road.gdshader")
	_road_mat.set_shader_parameter("offset", MageTrack.WIZARD_Z - zc)
	_road_mat.set_shader_parameter("width", ROAD_WIDTH)
	road.material_override = _road_mat
	_world.add_child(road)
	var castle := MeshInstance3D.new()
	castle.name = "Castle"
	castle.mesh = MageProps.castle()
	castle.material_override = MageProps.solid_material()
	_world.add_child(castle)
	var portal := MeshInstance3D.new()
	portal.name = "GatePortal"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.236, 0.238)
	portal.mesh = quad
	portal.position = Vector3(0, 0.119, MageTrack.GATE_Z + 0.0005)
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://games/mage_run/shaders/gate_portal.gdshader")
	pm.set_shader_parameter("aspect", 0.236 / 0.238)
	portal.material_override = pm
	_world.add_child(portal)


func _build_wizard() -> void:
	_wizard = Node3D.new()
	_wizard.name = "Wizard"
	_world.add_child(_wizard)
	var parts: Dictionary = MageProps.wizard()
	_wizard_body = MeshInstance3D.new()
	_wizard_body.name = "Body"
	_wizard_body.mesh = parts["body"]
	_wizard_body.material_override = MageProps.solid_material()
	_wizard.add_child(_wizard_body)
	_wizard_tip = MeshInstance3D.new()
	_wizard_tip.name = "StaffTip"
	_wizard_tip.mesh = parts["tip"]
	_wizard_tip.material_override = MageProps.glow_material()
	_wizard_body.add_child(_wizard_tip)
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	var sq := QuadMesh.new()
	sq.size = Vector2(0.04, 0.04)
	sq.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = sq
	var smat := ShaderMaterial.new()
	smat.shader = preload("res://games/mage_run/shaders/blob_shadow.gdshader")
	_shadow.material_override = smat
	_world.add_child(_shadow)
	_rune_ring = MeshInstance3D.new()
	_rune_ring.name = "RuneRing"
	var rq := QuadMesh.new()
	rq.size = Vector2(0.05, 0.05)
	rq.orientation = PlaneMesh.FACE_Y
	_rune_ring.mesh = rq
	_rune_ring.material_override = Holo.disc_material(Holo.CYAN, 0.25, 0.8, 0.9, 0.0, 0.0)
	_world.add_child(_rune_ring)
	_shield = MeshInstance3D.new()
	_shield.name = "Shield"
	var sphere := SphereMesh.new()
	sphere.radius = 0.038
	sphere.height = 0.076
	sphere.radial_segments = 16
	sphere.rings = 8
	_shield.mesh = sphere
	_shield.material_override = Holo.material(Color(0.45, 0.7, 1.0), 0.08, 1.2, 1.0)
	_shield.position = Vector3(0, 0.034, 0)
	_wizard.add_child(_shield)
	_magnet = MeshInstance3D.new()
	_magnet.name = "Magnet"
	var mq := QuadMesh.new()
	mq.size = Vector2(0.07, 0.07)
	mq.orientation = PlaneMesh.FACE_Y
	_magnet.mesh = mq
	_magnet.material_override = Holo.disc_material(Holo.GOLD, 0.0, 0.92, 1.0, 0.0, 0.0)
	_magnet.position = Vector3(0, 0.02, 0)
	_wizard.add_child(_magnet)
	_levitation = MeshInstance3D.new()
	_levitation.name = "Levitation"
	var lq := QuadMesh.new()
	lq.size = Vector2(0.055, 0.055)
	lq.orientation = PlaneMesh.FACE_Y
	_levitation.mesh = lq
	_levitation.material_override = Holo.disc_material(Holo.MAGENTA, 0.5, 0.75, 0.9, 0.4, 0.0)
	_levitation.position = Vector3(0, 0.001, 0)
	_wizard.add_child(_levitation)
	# Blue sparkle trail at the feet (local, drifting back a few cm).
	_trail = CPUParticles3D.new()
	_trail.name = "Trail"
	_trail.amount = 24
	_trail.lifetime = 0.3
	_trail.local_coords = true
	_trail.mesh = _mote_mesh()
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = 0.007
	_trail.direction = Vector3(0, 0.2, 1)
	_trail.spread = 25.0
	_trail.gravity = Vector3.ZERO
	_trail.initial_velocity_min = 0.06
	_trail.initial_velocity_max = 0.1
	_trail.scale_amount_min = 0.6
	_trail.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.8, 1.0, 1.0))
	ramp.set_color(1, Color(0.3, 0.4, 1.0, 0.0))
	_trail.color_ramp = ramp
	_trail.position = Vector3(0, 0.006, 0.006)
	_wizard.add_child(_trail)
	_sparkle = CPUParticles3D.new()
	_sparkle.name = "Sparkle"
	_sparkle.amount = 12
	_sparkle.lifetime = 0.35
	_sparkle.one_shot = true
	_sparkle.explosiveness = 1.0
	_sparkle.emitting = false
	_sparkle.local_coords = false
	_sparkle.mesh = _mote_mesh()
	_sparkle.direction = Vector3.UP
	_sparkle.spread = 70.0
	_sparkle.gravity = Vector3(0, -0.2, 0)
	_sparkle.initial_velocity_min = 0.03
	_sparkle.initial_velocity_max = 0.07
	_world.add_child(_sparkle)


static func _mote_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.004, 0.004)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.no_depth_test = false
	q.material = m
	return q


func _build_pools() -> void:
	var tile_mat := ShaderMaterial.new()
	tile_mat.shader = preload("res://games/mage_run/shaders/arcane_tile.gdshader")
	tile_mat.set_shader_parameter("width", TILE_WIDTH)
	_tile_mm = _make_multimesh("ArcaneTiles", MageProps.tile_unit(), tile_mat, MAX_TILES, true)
	_ramp_mm = _make_multimesh("ArcaneRamps", MageProps.ramp_unit(), tile_mat, MAX_RAMPS, true)
	var coin_mat := StandardMaterial3D.new()
	coin_mat.vertex_color_use_as_albedo = true
	coin_mat.metallic = 0.6
	coin_mat.roughness = 0.35
	coin_mat.emission_enabled = true
	coin_mat.emission = Color(0.55, 0.38, 0.05)
	coin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_coin_mm = _make_multimesh("Coins", MageProps.coin(), coin_mat, MAX_COINS, false)


func _make_multimesh(node_name: String, mesh: Mesh, mat: Material, count: int, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(node)
	return mm


# --- Drawing the sim ----------------------------------------------------------------

## The near-end dissolve: 1 well inside, 0 at the near edge of the box.
static func near_fade(z_near: float) -> float:
	return clampf((MageTrack.NEAR_Z - z_near) / MageTrack.NEAR_FADE, 0.0, 1.0)


## Is a track item from s0 to s1 drawn (inside the box, out of the castle's back)?
func _item_shown(s0: float, s1: float) -> bool:
	return MageTrack.board_z(s1, sim.distance) >= MageTrack.FAR_Z and MageTrack.board_z(s0, sim.distance) < MageTrack.NEAR_Z


func _sync_visuals(_delta: float) -> void:
	if sim == null or _world == null:
		return
	var d: float = sim.distance
	_road_mat.set_shader_parameter("scroll", d * MageTrack.RUN_TO_BOARD)
	_sync_props(d)
	_sync_tiles(d)
	_sync_coins(d)
	_sync_wizard()


func _sync_props(d: float) -> void:
	var seen: Dictionary = {}
	for o: MageTrack.Obstacle in sim.obstacles:
		if o.broken or not _item_shown(o.s0, o.s1()):
			continue
		seen[o.id] = true
		var node: MeshInstance3D = _props.get(o.id) as MeshInstance3D
		if node == null:
			node = _make_prop(o)
			_props[o.id] = node
			_world.add_child(node)
		var z_far: float = MageTrack.board_z(o.s1(), d)
		var z_near: float = MageTrack.board_z(o.s0, d)
		var cx: float = (o.min_x() + o.max_x()) * 0.5
		node.position = Vector3(cx, 0.0, (z_far + z_near) * 0.5)
		var f: float = near_fade(z_near)
		node.scale = Vector3.ONE * f
		node.visible = f > 0.0
	for id: Variant in _props.keys():
		if not seen.has(id):
			(_props[id] as Node).queue_free()
			_props.erase(id)


func _make_prop(o: MageTrack.Obstacle) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "%s%d" % [String(o.kind).capitalize(), o.id]
	var depth: float = o.length * MageTrack.RUN_TO_BOARD
	match o.kind:
		&"fence":
			node.mesh = MageProps.fence(depth)
		&"beam":
			node.mesh = MageProps.beam(depth)
		&"crates":
			node.mesh = MageProps.crates(depth, o.lanes.size())
		&"cart":
			node.mesh = MageProps.cart(depth)
		&"carriage":
			node.mesh = MageProps.carriage(depth)
	node.material_override = MageProps.solid_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("kind", o.kind)
	return node


func _sync_tiles(d: float) -> void:
	var n: int = 0
	for t: MageTrack.Tile in sim.tiles:
		if t.gone or n >= MAX_TILES or not _item_shown(t.s0, t.s1()):
			continue
		var z_far: float = MageTrack.board_z(t.s1(), d)
		var z_near: float = MageTrack.board_z(t.s0, d)
		var f: float = near_fade(z_near)
		if f <= 0.0:
			continue
		var len_b: float = z_near - z_far
		var basis := Basis.from_scale(Vector3(TILE_WIDTH, MageTrack.TILE_THICKNESS, len_b * 0.97) * f)
		var pos := Vector3(MageTrack.lane_x(t.lane), MageTrack.row_y(t.row) - MageTrack.TILE_THICKNESS * (1.0 - f) * 0.5, (z_far + z_near) * 0.5)
		_set_xf(_tile_mm, n, Transform3D(basis, pos))
		var emerge: float = clampf((z_near - MageTrack.GATE_Z) / 0.06, 0.0, 1.0)
		var crumble: float = 0.0 if t.crumble < 0.0 else clampf(t.crumble / MageTrack.CRACK_TIME, 0.0, 1.0)
		_tile_mm.set_instance_custom_data(n, Color(minf(f, emerge), 1.0 if t.cracked else 0.0, crumble, len_b))
		n += 1
	_tile_mm.visible_instance_count = n
	var r_n: int = 0
	for r: MageTrack.Ramp in sim.ramps:
		if r_n >= MAX_RAMPS or not _item_shown(r.s0, r.s1()):
			continue
		var z_far: float = MageTrack.board_z(r.s1(), d)
		var z_near: float = MageTrack.board_z(r.s0, d)
		var f: float = near_fade(z_near)
		if f <= 0.0:
			continue
		var basis := Basis.from_scale(Vector3(TILE_WIDTH, MageTrack.ROW_HEIGHT, z_near - z_far) * f)
		_set_xf(_ramp_mm, r_n, Transform3D(basis, Vector3(MageTrack.lane_x(r.lane), MageTrack.row_y(r.row), (z_far + z_near) * 0.5)))
		var emerge: float = clampf((z_near - MageTrack.GATE_Z) / 0.06, 0.0, 1.0)
		_ramp_mm.set_instance_custom_data(r_n, Color(minf(f, emerge), 0.0, 0.0, z_near - z_far))
		r_n += 1
	_ramp_mm.visible_instance_count = r_n


## Instance transforms are also kept CPU-side (content_aabbs; the headless
## renderer does not store MultiMesh data).
func _set_xf(mm: MultiMesh, i: int, xf: Transform3D) -> void:
	mm.set_instance_transform(i, xf)
	var cache: Array = _mm_xforms.get(mm, [])
	if cache.size() < mm.instance_count:
		cache.resize(mm.instance_count)
		_mm_xforms[mm] = cache
	cache[i] = xf


func _sync_coins(d: float) -> void:
	var n: int = 0
	var spin: float = _anim_t * 3.0
	var wiz: Vector3 = _wizard.position + Vector3(0, 0.035, 0) if _wizard != null else Vector3.ZERO
	for c: MageTrack.Coin in sim.coin_items:
		if n >= MAX_COINS or (c.taken and not c.flying):
			continue
		var z: float = MageTrack.board_z(c.s, d)
		if z < MageTrack.GATE_Z - 0.01 or z > MageTrack.NEAR_Z - MageTrack.COIN_RADIUS:
			continue
		var pos := Vector3(MageTrack.lane_x(c.lane), c.y, z)
		var f: float = near_fade(z + MageTrack.COIN_RADIUS)
		if c.flying:
			var t: float = sim.coin_fly_t(c)
			pos = pos.lerp(wiz, t)
			f *= 1.0 - t * 0.6
		if f <= 0.0:
			continue
		var basis := Basis(Vector3.UP, spin + c.s * 1.7).scaled(Vector3.ONE * f)
		_set_xf(_coin_mm, n, Transform3D(basis, pos))
		n += 1
	_coin_mm.visible_instance_count = n


func _sync_wizard() -> void:
	var y: float = sim.y
	_wizard.position = Vector3(sim.x, y, MageTrack.WIZARD_Z)
	var lean: float = 0.0
	if sim.changing_lane():
		lean = -signf(float(sim.lane - sim.from_lane)) * 0.35 * sin(sim.lane_t * PI)
	var bob: float = 0.0
	var basis := Basis()
	if state == State.OVER:
		var t: float = clampf(_crash_t / 0.35, 0.0, 1.0)
		basis = Basis(Vector3.RIGHT, -t * PI * 0.45)
	elif sim.sliding():
		basis = Basis(Vector3.RIGHT, 0.9).scaled(Vector3(1.0, 0.55, 1.0))
	else:
		if sim.grounded and state == State.RUNNING:
			bob = absf(sin(_anim_t * 14.0)) * 0.003
		var stretch: float = 1.0
		if not sim.grounded:
			stretch = 1.0 + clampf(sim.vy, -1.0, 1.0) * 0.08
		var squash: float = 1.0 - _squash * 0.18
		basis = Basis(Vector3.FORWARD, lean).scaled(Vector3(1.0 / sqrt(squash * stretch), squash * stretch, 1.0 / sqrt(squash * stretch)))
		if _stumble_t > 0.0:
			basis = Basis(Vector3.UP, sin(_stumble_t * 40.0) * 0.4) * basis
	_wizard_body.transform = Transform3D(basis, Vector3(0, bob, 0))
	# Ground contact: the blob shadow on the surface below; the rune ring on
	# the road when he is up on an arcane row (depth cue).
	var below: float = 0.0
	for sup: Dictionary in sim.supports_at(MageTrack.lane_at(sim.x), sim.distance):
		var h: float = float(sup["h"])
		if h <= y + 0.001 and h > below and sup["kind"] != &"levitation":
			below = h
	var gap: float = y - below
	_shadow.position = Vector3(sim.x, below + 0.0012, MageTrack.WIZARD_Z)
	_shadow.scale = Vector3.ONE * clampf(1.0 - gap * 4.0, 0.4, 1.0)
	_rune_ring.visible = y > MageTrack.ROW_HEIGHT * 0.5
	_rune_ring.position = Vector3(sim.x, 0.0015, MageTrack.WIZARD_Z)
	_shield.visible = sim.shield_t > 0.0
	_magnet.visible = sim.magnet_t > 0.0
	_levitation.visible = sim.levitating()
	_trail.emitting = state == State.RUNNING and sim.grounded and not sim.sliding()
	_magnet.rotation.y = _anim_t * 2.0


# --- Containment (tests) --------------------------------------------------------------

## Board-space AABBs of everything drawn on the track right now (props,
## tiles, ramps, coins, the wizard), to check nothing leaves the play box.
func content_aabbs() -> Array[AABB]:
	var out: Array[AABB] = []
	var to_board: Transform3D = global_transform.affine_inverse()
	for node: MeshInstance3D in _props.values():
		if node.visible and node.scale.x > 0.0:
			out.append(to_board * node.global_transform * node.mesh.get_aabb())
	for mm: MultiMesh in [_tile_mm, _ramp_mm, _coin_mm]:
		var mesh_aabb: AABB = mm.mesh.get_aabb()
		var cache: Array = _mm_xforms.get(mm, [])
		for i: int in mm.visible_instance_count:
			out.append(to_board * _world.global_transform * (cache[i] as Transform3D) * mesh_aabb)
	out.append(to_board * _wizard_body.global_transform * _wizard_body.mesh.get_aabb())
	if _shield.visible:
		out.append(to_board * _shield.global_transform * _shield.mesh.get_aabb())
	return out


func scenery_aabbs() -> Array[AABB]:
	var out: Array[AABB] = []
	var to_board: Transform3D = global_transform.affine_inverse()
	for n: String in ["Base", "Road", "Castle", "GatePortal"]:
		var node: MeshInstance3D = _world.get_node(n) as MeshInstance3D
		out.append(to_board * node.global_transform * node.mesh.get_aabb())
	return out


# --- HUD ----------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "MageRunHud"
	_hud.layer = 4
	add_child(_hud)
	_score_box = VBoxContainer.new()
	_score_box.name = "Score"
	_score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score_box.add_theme_constant_override("separation", 0)
	_hud.add_child(_score_box)
	_score_label = _label(56, Color(1.0, 0.86, 0.4))
	_score_box.add_child(_score_label)
	_info_label = _label(24, Color(0.92, 0.96, 1.0))
	_score_box.add_child(_info_label)
	_row_label = _label(24, Holo.CYAN)
	_score_box.add_child(_row_label)
	# Staff meter + cast button (bottom left).
	_staff_panel = PanelContainer.new()
	_staff_panel.name = "Staff"
	_staff_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_staff_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.06, 0.16, 0.55), 12, 10))
	_hud.add_child(_staff_panel)
	var staff_box := VBoxContainer.new()
	staff_box.add_theme_constant_override("separation", 6)
	_staff_panel.add_child(staff_box)
	_power_label = _label(20, Color(0.85, 0.92, 1.0))
	staff_box.add_child(_power_label)
	_meter = ProgressBar.new()
	_meter.name = "StaffMeter"
	_meter.max_value = MageRunSim.METER_FULL
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(220, 18)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.25, 0.9)
	bg.set_corner_radius_all(9)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.75, 1.0)
	fill.set_corner_radius_all(9)
	_meter.add_theme_stylebox_override("background", bg)
	_meter.add_theme_stylebox_override("fill", fill)
	staff_box.add_child(_meter)
	cast_button = Button.new()
	cast_button.name = "CastButton"
	cast_button.focus_mode = Control.FOCUS_NONE
	cast_button.custom_minimum_size = Vector2(220, 64)
	cast_button.add_theme_font_size_override("font_size", 24)
	_style_button(cast_button, Color(0.45, 0.75, 1.0))
	cast_button.pressed.connect(func() -> void: cast())
	staff_box.add_child(cast_button)
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = "II"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	pause_button.add_theme_font_size_override("font_size", 34)
	_style_button(pause_button, Color(0.9, 0.95, 1.0))
	pause_button.pressed.connect(func() -> void: pause(&"button"))
	_hud.add_child(pause_button)
	_countdown_label = _label(150, Color(1.0, 0.9, 0.45))
	_countdown_label.name = "Countdown"
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_label.offset_left = -200
	_countdown_label.offset_right = 200
	_countdown_label.offset_top = -110
	_countdown_label.offset_bottom = 110
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.add_child(_countdown_label)
	_hint_panel = _center_panel("Hint", Color(0.04, 0.06, 0.16, 0.72))
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label = _label(26, Color(0.95, 0.97, 1.0))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_panel.add_child(_hint_label)
	_hint_panel.visible = false
	_pause_panel = _center_panel("PausePanel", Color(0.03, 0.05, 0.13, 0.86))
	var pbox := VBoxContainer.new()
	pbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pbox.add_theme_constant_override("separation", 14)
	_pause_panel.add_child(pbox)
	var ptitle := _label(42, Color(1.0, 0.86, 0.4))
	ptitle.text = "Paused"
	pbox.add_child(ptitle)
	_pause_label = _label(24, Color(0.9, 0.95, 1.0))
	_pause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pbox.add_child(_pause_label)
	resume_button = Button.new()
	resume_button.name = "ResumeButton"
	resume_button.text = "Resume"
	resume_button.focus_mode = Control.FOCUS_NONE
	resume_button.custom_minimum_size = Vector2(240, 76)
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume_button.add_theme_font_size_override("font_size", 30)
	_style_button(resume_button, Holo.CYAN)
	resume_button.pressed.connect(resume)
	pbox.add_child(resume_button)
	_pause_panel.visible = false
	_over_panel = _center_panel("GameOver", Color(0.03, 0.05, 0.13, 0.88))
	var obox := VBoxContainer.new()
	obox.alignment = BoxContainer.ALIGNMENT_CENTER
	obox.add_theme_constant_override("separation", 12)
	_over_panel.add_child(obox)
	var otitle := _label(40, Holo.MAGENTA)
	otitle.text = "The run is over"
	obox.add_child(otitle)
	_over_label = _label(24, Color(0.9, 0.97, 1.0))
	obox.add_child(_over_label)
	restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Run again"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.custom_minimum_size = Vector2(240, 76)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.add_theme_font_size_override("font_size", 30)
	_style_button(restart_button, Holo.CYAN)
	restart_button.pressed.connect(restart)
	obox.add_child(restart_button)
	_over_panel.visible = false
	_layout_hud()


func _center_panel(node_name: String, bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", _panel_style(bg, 18, 22))
	_hud.add_child(panel)
	return panel


static func _panel_style(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(Holo.CYAN, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.08, 0.95))
	label.add_theme_constant_override("outline_size", 8)
	return label


func _style_button(button: Button, accent: Color) -> void:
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.03, 0.06, 0.16, 0.75) if state_name != "pressed" else Color(accent, 0.35)
		if state_name == "disabled":
			s.bg_color = Color(0.03, 0.05, 0.1, 0.5)
		s.border_color = accent if state_name != "disabled" else Color(accent, 0.35)
		s.set_border_width_all(2)
		s.set_corner_radius_all(14)
		button.add_theme_stylebox_override(state_name, s)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.75, 0.8, 0.9, 0.7))


## Portrait: the score sits under the platform's status line (which spans
## the top beside "‹ Games"); landscape: top centre, clear of the status at
## the top right. Staff bottom left, pause bottom right, panels centred.
func _layout_hud() -> void:
	if _score_box == null:
		return
	var portrait: bool = is_portrait()
	_score_box.offset_top = 112.0 if portrait else 14.0
	_score_box.offset_left = -300.0 if portrait else -210.0
	_score_box.offset_right = 300.0 if portrait else 210.0
	_staff_panel.offset_left = 20.0
	_staff_panel.offset_bottom = -20.0
	_staff_panel.offset_top = -20.0 - 150.0
	_staff_panel.offset_right = 20.0 + 244.0
	_staff_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pause_button.offset_left = -20.0 - 96.0
	pause_button.offset_right = -20.0
	pause_button.offset_top = -20.0 - 96.0
	pause_button.offset_bottom = -20.0
	var w: float = 560.0 if portrait else 720.0
	for panel: PanelContainer in [_hint_panel, _pause_panel, _over_panel]:
		panel.offset_left = -w * 0.5
		panel.offset_right = w * 0.5
		panel.offset_top = -150.0
		panel.offset_bottom = 150.0
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hint_panel.offset_top = 120.0 if portrait else 40.0
	_hint_panel.offset_bottom = 300.0 if portrait else 200.0
	_hint_label.custom_minimum_size = Vector2(w - 60.0, 0)
	_pause_label.custom_minimum_size = Vector2(w - 60.0, 0)
	if _hint_panel.visible:
		_update_hint_text()


func hud_text() -> String:
	return "%s | %s | %s" % [_score_label.text, _info_label.text, _row_label.text]


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _refresh_hud() -> void:
	if _hud == null or sim == null:
		return
	var playing: bool = is_playing()
	_hud.visible = playing
	_set_text(_score_label, str(sim.score()))
	var info: String = "%d m   ★ %d" % [int(sim.distance), sim.coins]
	if sim.multiplier > 1:
		info += "   ×%d" % sim.multiplier
	info += "   Best %d" % session_best
	_set_text(_info_label, info)
	var r: int = sim.row() if sim.y > MageTrack.ROW_HEIGHT * 0.5 else 0
	_set_text(_row_label, ["", "Arcane I  ×2 coins", "Arcane II  ×3 coins"][r] as String)
	_meter.value = sim.meter
	var power: String = MageRunSim.POWER_NAMES[int(sim.power_to_cast())]
	cast_button.disabled = not sim.meter_full() or state != State.RUNNING
	var cast_text: String = ("Cast %s" % power) if sim.meter_full() else "Staff %d/%d" % [sim.meter, MageRunSim.METER_FULL]
	if cast_button.text != cast_text:
		cast_button.text = cast_text
	var active: PackedStringArray = []
	if sim.shield_t > 0.0:
		active.append("Shield %ds" % ceili(sim.shield_t))
	if sim.magnet_t > 0.0:
		active.append("Magnet %ds" % ceili(sim.magnet_t))
	if sim.levitation_t > 0.0:
		active.append("Levitation %ds" % ceili(sim.levitation_t))
	_set_text(_power_label, "  ".join(active) if not active.is_empty() else "Next: %s" % power)
	pause_button.visible = state == State.RUNNING or state == State.COUNTDOWN
	_pause_panel.visible = state == State.PAUSED
	_set_text(_pause_label, "The phone turned: get comfortable, then Resume." if pause_reason == &"rotate" else "Tap Resume to run on (3-2-1 first).")
	_over_panel.visible = state == State.OVER
	if state == State.OVER:
		var best_line: String = "New best!" if best_this_run else "Best %d" % session_best
		_set_text(_over_label, "%d m   ★ %d   Score %d\n%s   Seed %d" % [int(sim.distance), sim.coins, sim.score(), best_line, sim.seed_value])
	var cd: String = ""
	if state == State.COUNTDOWN:
		cd = str(ceili(countdown_t))
	elif state == State.RUNNING and go_t > 0.0:
		cd = "Go!"
	_set_text(_countdown_label, cd)
	_countdown_label.visible = not cd.is_empty()
	var status: String = ""
	match state:
		State.READY:
			status = "Mage Run: lock the board to start."
		State.PAUSED:
			status = "Paused."
		State.OVER:
			status = "The run is over. Tap Run again."
	if get_status() != status:
		set_status(status)
