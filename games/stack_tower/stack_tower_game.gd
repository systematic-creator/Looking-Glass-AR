class_name StackTowerGame
extends LGGame
## Stack Tower: a one-player timing game in a TALL simulation box. A hologram
## slab slides back and forth over the tower top, alternating X / Z; a tap
## anywhere places it. The part hanging past the slab below is sliced off and
## tumbles away as debris, the rest becomes the new top. Miss completely and
## the tower is done. A near-perfect tap (PERFECT_RATIO of the board, ~4 mm
## on the 30 cm board) snaps exactly, builds a perfect streak (bonus points,
## a glow pulse) and from REGROW_STREAK perfects on regrows the slab a little.
## Slabs sweep faster as the tower rises, and every layer shifts colour
## through a hologram gradient. When the top nears the box lid the whole
## tower sinks, so play goes on forever without ever leaving the box.
##
## Every size is relative to unit() (the board's shorter side), so the game
## plays the same on a table or, scaled up, on the floor.
##
## Two looks (the HUD's Style button, switchable mid-game, remembered for the
## app session): Hologram (see-through Holo glow, the default) and Solid
## (opaque, lit blocks in the same gradient colours with a dark outline per
## layer; the sliding slab is lifted with emission and a bright outline).

## Base slab: this fraction of the board's short side, square.
const BASE_RATIO: float = 0.65
## Layer thickness / unit.
const LAYER_RATIO: float = 0.075
## Pedestal (projector plate) height / unit.
const PEDESTAL_RATIO: float = 0.05
## Sliding slabs stay this far (/ unit) inside the box walls.
const EDGE_MARGIN_RATIO: float = 0.02
## The active slab's top stays this far (/ unit) under the box lid...
const TOP_MARGIN_RATIO: float = 0.03
## ... and the tower sinks to keep this many free layers above it.
const TOP_ROOM_LAYERS: float = 2.0
## A placement this close (/ unit) to the slab below snaps exactly: perfect.
const PERFECT_RATIO: float = 0.013
## Overlaps thinner than this (/ unit) count as a miss.
const MIN_OVERLAP_RATIO: float = 0.004
## From this many perfects in a row each perfect regrows the slab (/ unit).
const REGROW_STREAK: int = 3
const GROW_RATIO: float = 0.03
## Bonus points for a perfect: the streak length, at most MAX_BONUS.
const MAX_BONUS: int = 3
## One sweep across the box takes SWEEP_START s, SWEEP_STEP s less per
## layer, never under SWEEP_MIN s.
const SWEEP_START: float = 1.6
const SWEEP_STEP: float = 0.03
const SWEEP_MIN: float = 0.6
## Debris: falls with this gravity (unit / s^2), fades out in DEBRIS_TIME s.
const DEBRIS_GRAVITY_RATIO: float = 12.0
const DEBRIS_TIME: float = 1.1
## Tower sink easing (1/s) and the perfect pulse length (s).
const SCROLL_EASE: float = 6.0
const PULSE_TIME: float = 0.45
## After a game over, taps restart only after this long (s).
const RESTART_DELAY: float = 0.6
const OUTLINE_WHILE_PLAYING: float = 0.35

enum State { PLAYING, OVER }
enum Style { HOLOGRAM, SOLID }

## Solid look: outline thickness (/ unit), the sliding slab's emission lift,
## debris shrinks to this scale instead of fading.
const OUTLINE_RATIO: float = 0.005
const ACTIVE_LIFT: float = 0.45
const DEBRIS_END_SCALE: float = 0.3

## Best score of this app session (survives restarts and re-launches).
static var session_best: int = 0
## Look picked for this app session.
static var session_style: Style = Style.HOLOGRAM

var state: State = State.PLAYING
var style: Style = Style.HOLOGRAM
var score: int = 0
var streak: int = 0
var best_streak: int = 0
var perfects: int = 0
## Placed layers, base first: {center: Vector2 (x, z), size: Vector2, level, color, node}.
var layers: Array[Dictionary] = []
## The sliding slab: {center, size, axis (0 = x, 1 = z), dir, phase, level, color, node}.
var active: Dictionary = {}
## Falling pieces: {node, velocity, spin, age, size}.
var debris: Array[Dictionary] = []
## Tower offset (<= 0): how far the tower has sunk to stay in the box.
var scroll: float = 0.0
var last_result: Dictionary = {}

var _tower: Node3D
var _pulse: Node3D
var _pulse_age: float = -1.0
var _over_age: float = 0.0
var _hud: CanvasLayer
var _score_box: VBoxContainer
var _score_label: Label
var _info_label: Label
var _over_panel: PanelContainer
var _over_label: Label
var restart_button: Button
var style_button: Button


# --- Geometry -------------------------------------------------------------------

## The board's shorter side: every size is a ratio of it.
func unit() -> float:
	var s: Vector2 = get_board_size()
	return minf(s.x, s.y)


func layer_height() -> float:
	return unit() * LAYER_RATIO


func base_size() -> float:
	return unit() * BASE_RATIO


func pedestal_top() -> float:
	return unit() * PEDESTAL_RATIO


func perfect_tolerance() -> float:
	return unit() * PERFECT_RATIO


func min_overlap() -> float:
	return unit() * MIN_OVERLAP_RATIO


## Bottom of `level` in tower space (before the sink offset).
func level_bottom(level: int) -> float:
	return pedestal_top() + float(level) * layer_height()


## Top of the placed tower, tower space.
func natural_top() -> float:
	return level_bottom(layers.size())


## Top of the placed tower in board space (sink included).
func tower_top() -> float:
	return natural_top() + scroll


## Layers placed on the base (the height score).
func height() -> int:
	return maxi(layers.size() - 1, 0)


## How far a slab of `size` along `axis` may slide from the board centre.
func sweep_reach(size: Vector2, axis: int) -> float:
	var extent: float = get_board_size().x if axis == 0 else get_board_size().y
	var s: float = size.x if axis == 0 else size.y
	return maxf(extent * 0.5 - s * 0.5 - unit() * EDGE_MARGIN_RATIO, 0.0)


static func sweep_time(level: int) -> float:
	return maxf(SWEEP_MIN, SWEEP_START - SWEEP_STEP * float(level))


## Slab position along its axis at sweep `phase` (0..1 = one sweep).
static func sweep_position(phase: float, reach: float, dir: float) -> float:
	return dir * (-reach + 2.0 * reach * pingpong(phase, 1.0))


static func layer_color(level: int) -> Color:
	return Color.from_hsv(fposmod(0.52 + float(level) * 0.022, 1.0), 0.78, 1.0)


static func perfect_bonus(p_streak: int) -> int:
	return mini(p_streak, MAX_BONUS)


## Slice a slab (centre `moving`, length `moving_size` along one axis) over
## the one below (centre `below`, `below_size`). Returns:
##   miss     no usable overlap: the whole slab falls
##   perfect  within `tolerance`: snaps onto the slab below, nothing cut
##   center, size          the kept part
##   cut_center, cut_size  the sliced-off part (cut_size 0 = nothing)
static func slice(below: float, below_size: float, moving: float, moving_size: float, tolerance: float, min_keep: float = 0.0005) -> Dictionary:
	var lo: float = maxf(below - below_size * 0.5, moving - moving_size * 0.5)
	var hi: float = minf(below + below_size * 0.5, moving + moving_size * 0.5)
	var overlap: float = hi - lo
	if overlap < min_keep:
		return {"miss": true, "perfect": false, "center": moving, "size": 0.0, "cut_center": moving, "cut_size": moving_size}
	if absf(moving - below) <= tolerance:
		return {"miss": false, "perfect": true, "center": below, "size": minf(moving_size, below_size), "cut_center": below, "cut_size": 0.0}
	var cut_lo: float
	var cut_hi: float
	if moving > below:
		cut_lo = hi
		cut_hi = moving + moving_size * 0.5
	else:
		cut_lo = moving - moving_size * 0.5
		cut_hi = lo
	return {
		"miss": false, "perfect": false, "center": (lo + hi) * 0.5, "size": overlap,
		"cut_center": (cut_lo + cut_hi) * 0.5, "cut_size": maxf(cut_hi - cut_lo, 0.0),
	}


# --- Platform hooks -------------------------------------------------------------

func box_outline_while_playing() -> float:
	return OUTLINE_WHILE_PLAYING


## Keep the "Play without AR" camera on the tower top as it rises.
func view_focus_height() -> float:
	return clampf(tower_top(), 0.0, get_box().height())


func describe_point(_point: Vector3) -> String:
	return "height %d" % height()


func _on_board_ready() -> void:
	ui_insets_changed.connect(func(_bottom: float) -> void: _layout_hud())
	var size: Vector2 = get_board_size()
	add_child(Holo.glow_base(size))
	_build_pedestal()
	_tower = Node3D.new()
	_tower.name = "Tower"
	add_child(_tower)
	style = session_style
	_build_hud()
	restart()


func _on_box_changed(_box: PlayBox) -> void:
	_update_scroll(0.0, true)


func _on_resumed() -> void:
	_refresh_hud()


func _on_paused() -> void:
	_refresh_hud()


## Every tap is a box ray: place the slab (or, after a game over, restart).
func _on_box_ray(_origin: Vector3, _direction: Vector3) -> void:
	tap()


func tap() -> void:
	if state == State.OVER:
		if _over_age >= RESTART_DELAY:
			restart()
		return
	place()


# --- Game -----------------------------------------------------------------------

func restart() -> void:
	for layer: Dictionary in layers:
		_free(layer.get("node"))
	layers.clear()
	for piece: Dictionary in debris:
		_free(piece.get("node"))
	debris.clear()
	if not active.is_empty():
		_free(active.get("node"))
	active = {}
	for child: Node in _tower.get_children():
		child.queue_free()
	_pulse = null
	_pulse_age = -1.0
	scroll = 0.0
	_tower.position.y = 0.0
	score = 0
	streak = 0
	best_streak = 0
	perfects = 0
	last_result = {}
	state = State.PLAYING
	_over_age = 0.0
	var s: float = base_size()
	_add_layer(Vector2.ZERO, Vector2(s, s), 0)
	_spawn_active()
	_refresh_hud()


## Drop the sliding slab where it is.
func place() -> Dictionary:
	if state != State.PLAYING or active.is_empty() or layers.is_empty():
		return {}
	var top: Dictionary = layers.back()
	var axis: int = int(active["axis"])
	var a_center: Vector2 = active["center"]
	var a_size: Vector2 = active["size"]
	var t_center: Vector2 = top["center"]
	var t_size: Vector2 = top["size"]
	var result: Dictionary = slice(t_center[axis], t_size[axis], a_center[axis], a_size[axis], perfect_tolerance(), min_overlap())
	last_result = result
	var level: int = int(active["level"])
	var color: Color = active["color"]
	_free(active["node"])
	active = {}
	if bool(result["miss"]):
		_add_debris(a_center, a_size, level, color, axis, signf(a_center[axis] - t_center[axis]))
		_game_over()
		return result
	var center: Vector2 = a_center
	var size: Vector2 = a_size
	center[axis] = float(result["center"])
	size[axis] = float(result["size"])
	if bool(result["perfect"]):
		streak += 1
		perfects += 1
		best_streak = maxi(best_streak, streak)
		score += 1 + perfect_bonus(streak)
		if streak >= REGROW_STREAK:
			var grown: Vector2 = Vector2(minf(size.x + unit() * GROW_RATIO, base_size()), minf(size.y + unit() * GROW_RATIO, base_size()))
			size = grown
			center = _keep_on_board(center, size)
	else:
		streak = 0
		score += 1
		if float(result["cut_size"]) > 0.0:
			var cut_center: Vector2 = a_center
			var cut_size: Vector2 = a_size
			cut_center[axis] = float(result["cut_center"])
			cut_size[axis] = float(result["cut_size"])
			_add_debris(cut_center, cut_size, level, color, axis, signf(float(result["cut_center"]) - float(result["center"])))
	session_best = maxi(session_best, score)
	var layer: Dictionary = _add_layer(center, size, level)
	var splash_at := Vector3(center.x, level_bottom(level) + layer_height() + 0.002, center.y)
	HoloSplash.spawn(_tower, splash_at, color, maxf(size.x, size.y) * 0.5).name = "Splash%d" % level
	if bool(result["perfect"]):
		_start_pulse(layer)
	_spawn_active()
	_update_scroll(0.0, false)
	_refresh_hud()
	return result


func _game_over() -> void:
	state = State.OVER
	_over_age = 0.0
	session_best = maxi(session_best, score)
	_refresh_hud()


## Centre a slab of `size` so it stays inside the board (and the walls' margin).
func _keep_on_board(center: Vector2, size: Vector2) -> Vector2:
	var board: Vector2 = get_board_size()
	var m: float = unit() * EDGE_MARGIN_RATIO
	var hx: float = maxf(board.x * 0.5 - size.x * 0.5 - m, 0.0)
	var hz: float = maxf(board.y * 0.5 - size.y * 0.5 - m, 0.0)
	return Vector2(clampf(center.x, -hx, hx), clampf(center.y, -hz, hz))


func _add_layer(center: Vector2, size: Vector2, level: int) -> Dictionary:
	var color: Color = layer_color(level)
	var node := _slab_node(size, color, &"layer")
	node.name = "Layer%d" % level
	node.position = Vector3(center.x, level_bottom(level) + layer_height() * 0.5, center.y)
	_tower.add_child(node)
	var layer: Dictionary = {"center": center, "size": size, "level": level, "color": color, "node": node}
	layers.append(layer)
	return layer


func _spawn_active() -> void:
	var top: Dictionary = layers.back()
	var level: int = layers.size()
	var axis: int = (level + 1) % 2
	var size: Vector2 = top["size"]
	var color: Color = layer_color(level)
	var node := _slab_node(size, color, &"active")
	node.name = "Active"
	var edges := Node3D.new()
	edges.name = "Edges"
	edges.visible = style == Style.HOLOGRAM
	node.add_child(edges)
	_add_edges(edges, size, color)
	_tower.add_child(node)
	active = {
		"center": top["center"], "size": size, "axis": axis, "dir": 1.0 if level % 2 == 1 else -1.0,
		"phase": 0.0, "level": level, "color": color, "node": node,
	}
	_move_active(0.0)


func _move_active(delta: float) -> void:
	if active.is_empty():
		return
	var level: int = int(active["level"])
	active["phase"] = float(active["phase"]) + delta / sweep_time(level)
	var axis: int = int(active["axis"])
	var center: Vector2 = active["center"]
	center[axis] = sweep_position(float(active["phase"]), sweep_reach(active["size"], axis), float(active["dir"]))
	active["center"] = center
	var node: Node3D = active["node"]
	node.position = Vector3(center.x, level_bottom(level) + layer_height() * 0.5, center.y)


## Current sweep speed of the active slab (board units / s).
func sweep_speed() -> float:
	if active.is_empty():
		return 0.0
	var axis: int = int(active["axis"])
	return 2.0 * sweep_reach(active["size"], axis) / sweep_time(int(active["level"]))


## A slab block; `role` is &"layer", &"active" or &"debris" (sets the look).
func _slab_node(size: Vector2, color: Color, role: StringName) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, layer_height() * 0.94, size.y)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("role", role)
	node.set_meta("color", color)
	_apply_look(node)
	return node


## Hologram material for a role (see-through glow).
static func holo_material(color: Color, role: StringName) -> ShaderMaterial:
	match role:
		&"active":
			return Holo.material(color, 0.26, 1.1, 1.0)
		&"debris":
			return Holo.material(color, 0.2, 0.9, 1.0)
	return Holo.material(color, 0.1, 0.65, 1.0)


## Solid material: opaque, lit (the host's sun + ambient), gradient colour.
## The sliding slab gets an emission lift so it stands out from the top.
static func solid_material(color: Color, role: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.6
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = ACTIVE_LIFT if role == &"active" else 0.0
	return mat


## Dark (bright for the sliding slab) outline: the back faces of a slightly
## larger box, unshaded. Plain inverted hull, gl_compatibility safe.
static func outline_material(color: Color, role: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.albedo_color = Color(1.0, 1.0, 0.92) if role == &"active" else Color(color.darkened(0.72), 1.0)
	return mat


## (Re)apply the current style to a slab made by _slab_node.
func _apply_look(node: MeshInstance3D) -> void:
	var role: StringName = node.get_meta("role", &"layer")
	var color: Color = node.get_meta("color", Holo.CYAN)
	var outline: Node = node.get_node_or_null(^"Outline")
	if outline != null:
		node.remove_child(outline)
		outline.queue_free()
	var edges: Node3D = node.get_node_or_null(^"Edges") as Node3D
	if style == Style.SOLID:
		node.material_override = solid_material(color, role)
		var hull := MeshInstance3D.new()
		hull.name = "Outline"
		var grow: float = unit() * OUTLINE_RATIO * (1.5 if role == &"active" else 1.0)
		var mesh := BoxMesh.new()
		mesh.size = (node.mesh as BoxMesh).size + Vector3(grow, grow, grow) * 2.0
		hull.mesh = mesh
		hull.material_override = outline_material(color, role)
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(hull)
	else:
		node.material_override = holo_material(color, role)
	if edges != null:
		edges.visible = style == Style.HOLOGRAM


## Switch Hologram / Solid; restyles the whole tower in place (no restart).
func set_style(p_style: Style) -> void:
	style = p_style
	session_style = p_style
	for layer: Dictionary in layers:
		var node: Variant = layer.get("node")
		if node is MeshInstance3D and is_instance_valid(node):
			_apply_look(node as MeshInstance3D)
	if not active.is_empty():
		_apply_look(active["node"] as MeshInstance3D)
	for piece: Dictionary in debris:
		_apply_look(piece["node"] as MeshInstance3D)
		_fade_debris(piece)
	_refresh_hud()


func toggle_style() -> void:
	set_style(Style.SOLID if style == Style.HOLOGRAM else Style.HOLOGRAM)


## Perfect flash on a slab: the Holo flash, or an emission burst when solid.
func set_flash(node: MeshInstance3D, amount: float) -> void:
	var mat: Material = node.material_override
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("flash", amount)
	elif mat is StandardMaterial3D:
		var lift: float = ACTIVE_LIFT if node.get_meta("role", &"layer") == &"active" else 0.0
		(mat as StandardMaterial3D).emission_energy_multiplier = lift + amount * 0.9


func get_flash(node: MeshInstance3D) -> float:
	var mat: Material = node.material_override
	if mat is ShaderMaterial:
		return float((mat as ShaderMaterial).get_shader_parameter("flash"))
	return (mat as StandardMaterial3D).emission_energy_multiplier / 0.9


## Hologram debris fades; solid debris (opaque) shrinks away instead.
func _fade_debris(piece: Dictionary) -> void:
	var node: MeshInstance3D = piece["node"]
	var t: float = clampf(float(piece["age"]) / DEBRIS_TIME, 0.0, 1.0)
	var mat: Material = node.material_override
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("intensity", 1.0 - t)
		node.scale = Vector3.ONE
	else:
		node.scale = Vector3.ONE * lerpf(1.0, DEBRIS_END_SCALE, t * t)


## Glowing top edges (the sliding slab and the pedestal).
func _add_edges(node: Node3D, size: Vector2, color: Color, y: float = -1.0, thickness: float = -1.0) -> void:
	var top: float = layer_height() * 0.47 if y < 0.0 else y
	var t: float = unit() * 0.011 if thickness < 0.0 else thickness
	var line := Holo.line_material(color, 1.4)
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var c: Array[Vector3] = [Vector3(-hx, top, -hz), Vector3(hx, top, -hz), Vector3(hx, top, hz), Vector3(-hx, top, hz)]
	for i: int in 4:
		node.add_child(Holo.bar(c[i], c[(i + 1) % 4], t, line))


func _build_pedestal() -> void:
	var s: float = base_size() * 1.12
	var plate := MeshInstance3D.new()
	plate.name = "Pedestal"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(s, pedestal_top(), s)
	plate.mesh = mesh
	plate.material_override = Holo.material(Holo.CYAN, 0.08, 0.75, 1.0)
	plate.position.y = pedestal_top() * 0.5
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plate)
	_add_edges(plate, Vector2(s, s), Holo.CYAN, pedestal_top() * 0.5, unit() * 0.012)


func _add_debris(center: Vector2, size: Vector2, level: int, color: Color, axis: int, outward: float) -> void:
	var node := _slab_node(size, color, &"debris")
	node.name = "Debris%d" % level
	node.position = Vector3(center.x, level_bottom(level) + layer_height() * 0.5, center.y)
	_tower.add_child(node)
	var push := Vector3.ZERO
	push[0 if axis == 0 else 2] = (outward if outward != 0.0 else 1.0) * unit() * 0.5
	var spin_axis: Vector3 = Vector3(0, 0, -1) if axis == 0 else Vector3(1, 0, 0)
	debris.append({"node": node, "velocity": push, "spin": spin_axis * (outward if outward != 0.0 else 1.0) * 3.2, "age": 0.0, "color": color})
	_contain(node)


## Falling, tumbling, fading debris; always kept inside the box.
func _update_debris(delta: float) -> void:
	var g: float = unit() * DEBRIS_GRAVITY_RATIO
	for i: int in range(debris.size() - 1, -1, -1):
		var piece: Dictionary = debris[i]
		var node: MeshInstance3D = piece["node"]
		piece["age"] = float(piece["age"]) + delta
		var v: Vector3 = piece["velocity"]
		v.y -= g * delta
		node.position += v * delta
		var spin: Vector3 = piece["spin"]
		if spin.length() > 0.0001:
			node.rotate(spin.normalized(), spin.length() * delta)
		var pushed: Vector3 = _contain(node)
		if pushed.y > 0.0:
			v.y = 0.0
			v *= 0.5
			piece["spin"] = spin * 0.85
		if pushed.x != 0.0:
			v.x = 0.0
		if pushed.z != 0.0:
			v.z = 0.0
		piece["velocity"] = v
		_fade_debris(piece)
		if float(piece["age"]) >= DEBRIS_TIME:
			node.queue_free()
			debris.remove_at(i)


## The node's AABB in board space (tower sink included).
func board_aabb(node: MeshInstance3D) -> AABB:
	var aabb: AABB = node.transform * node.mesh.get_aabb()
	aabb.position.y += scroll
	return aabb


## Push a node back inside the play box (PlayBox.clamp_point on its AABB's
## corners). Returns the push applied (board units).
func _contain(node: MeshInstance3D) -> Vector3:
	var aabb: AABB = board_aabb(node)
	var lo: Vector3 = aabb.position
	var hi: Vector3 = aabb.end
	var push: Vector3 = (clamp_to_box(lo) - lo) + (clamp_to_box(hi) - hi)
	node.position += push
	return push


## True if the node's AABB lies inside the box (PlayBox.contains on corners).
func node_in_box(node: MeshInstance3D, eps: float = 0.0005) -> bool:
	var aabb: AABB = board_aabb(node).grow(-eps)
	return box_contains(aabb.position) and box_contains(aabb.end)


## How far the tower must sink so the active slab's top keeps under the lid:
## `hard` (never exceed the box) and the eased `target` (TOP_ROOM_LAYERS spare).
func scroll_limits() -> Dictionary:
	var lid: float = get_box().height() - unit() * TOP_MARGIN_RATIO
	var need: float = lid - (natural_top() + layer_height())
	return {"hard": minf(0.0, need), "target": minf(0.0, need - TOP_ROOM_LAYERS * layer_height())}


func _update_scroll(delta: float, snap: bool) -> void:
	if _tower == null:
		return
	var limits: Dictionary = scroll_limits()
	var target: float = float(limits["target"])
	if snap:
		scroll = minf(scroll, target)
	elif delta > 0.0:
		scroll = lerpf(scroll, minf(scroll, target), 1.0 - exp(-SCROLL_EASE * delta))
	scroll = minf(scroll, float(limits["hard"]))
	_tower.position.y = scroll
	# Layers that sank fully into the pedestal are gone.
	for layer: Dictionary in layers:
		var node: Node3D = layer.get("node")
		if node != null and level_bottom(int(layer["level"])) + layer_height() + scroll < pedestal_top() - 0.0001:
			node.queue_free()
			layer["node"] = null


func _start_pulse(layer: Dictionary) -> void:
	_end_pulse()
	var node: MeshInstance3D = layer["node"]
	set_flash(node, 1.2)
	_pulse = Node3D.new()
	_pulse.name = "PerfectPulse"
	_pulse.position = node.position
	_add_edges(_pulse, layer["size"], Holo.GOLD, layer_height() * 0.5, unit() * 0.008)
	_tower.add_child(_pulse)
	_pulse.set_meta("layer", node)
	_pulse.set_meta("size", layer["size"])
	_pulse_age = 0.0


func _update_pulse(delta: float) -> void:
	if _pulse == null or _pulse_age < 0.0:
		return
	_pulse_age += delta
	var t: float = clampf(_pulse_age / PULSE_TIME, 0.0, 1.0)
	var size: Vector2 = _pulse.get_meta("size")
	var board: Vector2 = get_board_size()
	var grow_max: float = minf((board.x - unit() * 0.01) / size.x, (board.y - unit() * 0.01) / size.y)
	var s: float = lerpf(1.0, minf(1.3, grow_max), t)
	_pulse.scale = Vector3(s, 1.0, s)
	Holo.set_param(_pulse, &"intensity", 1.6 * (1.0 - t))
	var layer_node: Node = _pulse.get_meta("layer")
	if is_instance_valid(layer_node):
		set_flash(layer_node as MeshInstance3D, 1.2 * (1.0 - t))
	if t >= 1.0:
		_end_pulse()


## Drop the pulse and clear its layer's flash (also when a new one replaces it).
func _end_pulse() -> void:
	if _pulse == null:
		return
	var layer_node: Node = _pulse.get_meta("layer")
	if is_instance_valid(layer_node):
		set_flash(layer_node as MeshInstance3D, 0.0)
	_pulse.queue_free()
	_pulse = null
	_pulse_age = -1.0


func pulse() -> Node3D:
	return _pulse


func _process(delta: float) -> void:
	if not is_playing():
		return
	if state == State.PLAYING:
		_move_active(delta)
	else:
		_over_age += delta
	_update_scroll(delta, false)
	_update_debris(delta)
	_update_pulse(delta)


func _free(node: Variant) -> void:
	if node is Node and is_instance_valid(node):
		(node as Node).queue_free()


# --- HUD ------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "StackHud"
	_hud.layer = 4
	add_child(_hud)
	var top := VBoxContainer.new()
	top.name = "Score"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -260.0
	top.offset_right = 260.0
	top.offset_top = 18.0
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hud.add_child(top)
	_score_box = top
	_score_label = _hud_label(64, Holo.CYAN)
	top.add_child(_score_label)
	_info_label = _hud_label(24, Color(0.85, 0.95, 1.0))
	top.add_child(_info_label)
	style_button = Button.new()
	style_button.name = "StyleButton"
	style_button.focus_mode = Control.FOCUS_NONE
	style_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	style_button.offset_left = 20.0
	style_button.offset_right = 290.0
	style_button.offset_top = -96.0
	style_button.offset_bottom = -24.0
	style_button.add_theme_font_size_override("font_size", 26)
	_style_button(style_button)
	style_button.pressed.connect(toggle_style)
	_hud.add_child(style_button)
	_over_panel = PanelContainer.new()
	_over_panel.name = "GameOver"
	_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over_panel.offset_left = -230.0
	_over_panel.offset_right = 230.0
	_over_panel.offset_top = -120.0
	_over_panel.offset_bottom = 120.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.14, 0.82)
	style.border_color = Holo.CYAN
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(22)
	style.shadow_color = Color(Holo.CYAN, 0.35)
	style.shadow_size = 14
	_over_panel.add_theme_stylebox_override("panel", style)
	_hud.add_child(_over_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_over_panel.add_child(box)
	var title := _hud_label(40, Holo.MAGENTA)
	title.text = "Game over"
	box.add_child(title)
	_over_label = _hud_label(26, Color(0.9, 0.97, 1.0))
	box.add_child(_over_label)
	restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Restart"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.custom_minimum_size = Vector2(220.0, 72.0)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.add_theme_font_size_override("font_size", 30)
	_style_button(restart_button)
	restart_button.pressed.connect(restart)
	box.add_child(restart_button)
	_layout_hud()


## Portrait: the platform's status line spans the top beside "‹ Games", so
## the score sits below it; the rest is anchored and fits a 720-wide screen.
## The Style button keeps above the AR HUD's button row while the board is
## locked in AR (ui_bottom_inset()); it used to sit under it and lose taps.
func _layout_hud() -> void:
	if _score_box == null:
		return
	var bottom: float = maxf(24.0, ui_bottom_inset() + 12.0)
	style_button.offset_top = -bottom - 72.0
	style_button.offset_bottom = -bottom
	_score_box.offset_top = 112.0 if is_portrait() else 18.0
	_score_box.offset_left = -300.0 if is_portrait() else -260.0
	_score_box.offset_right = 300.0 if is_portrait() else 260.0


func _on_orientation_changed(_portrait: bool) -> void:
	_layout_hud()


func _style_button(button: Button) -> void:
	for state_name: String in ["normal", "hover", "pressed"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color(0.02, 0.08, 0.14, 0.7) if state_name == "normal" else Color(Holo.CYAN, 0.32)
		button_style.border_color = Holo.CYAN
		button_style.set_border_width_all(2)
		button_style.set_corner_radius_all(12)
		button.add_theme_stylebox_override(state_name, button_style)
	button.add_theme_color_override("font_color", Color(0.9, 0.98, 1.0))


## HUD buttons are not board touches (no slab drop when tapping them).
func is_over_game_ui(screen: Vector2) -> bool:
	if style_button != null and style_button.visible and style_button.get_global_rect().has_point(screen):
		return true
	return _over_panel != null and _over_panel.visible and _over_panel.get_global_rect().has_point(screen)


func _hud_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.04, 0.08, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	return label


func hud_text() -> String:
	return "%s | %s" % [_score_label.text, _info_label.text]


func is_game_over_shown() -> bool:
	return _over_panel != null and _over_panel.visible


func _refresh_hud() -> void:
	if _score_label == null:
		return
	_score_label.text = str(score)
	style_button.text = "Style: %s" % ("Solid" if style == Style.SOLID else "Hologram")
	var info: String = "Height %d   Best %d" % [height(), session_best]
	if streak > 0:
		info += "   Perfect ×%d" % streak
	_info_label.text = info
	_over_panel.visible = state == State.OVER
	_over_label.text = "Height %d   Score %d\nBest %d   Perfects %d (best streak %d)" % [height(), score, session_best, perfects, best_streak]
	if state == State.OVER:
		set_status("The tower is done. Tap Restart.")
	elif not is_playing():
		set_status("Stack Tower: lock the board to play.")
	elif layers.size() <= 1:
		set_status("Tap anywhere to drop the slab.")
	elif streak >= REGROW_STREAK:
		set_status("Perfect streak ×%d: the slab grows back!" % streak)
	elif streak > 0:
		set_status("Perfect! ×%d" % streak)
	else:
		set_status("Height %d. Tap to drop." % height())
