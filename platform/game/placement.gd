class_name PlacementController
extends Node3D
## Tap-to-place with a validity preview on a BoardGrid.
##
##   begin(ghost_mesh, validator)   show a ghost; validator(cell) returns
##                                  {"ok": bool, "reason": String}
##   move_to(cell)                  move the ghost (a tap / drag on the board)
##   result()                       the current cell's verdict
##   end()                          hide everything
##
## While active, the cells within `preview_radius` of the ghost are drawn as a
## hologram grid: green where the validator says yes, red where it says no,
## and the ghost's own cell brighter. Optional `range_node` (an AreaViz
## overlay) follows the ghost. The game owns confirming (a ✓ button / a
## second tap) and paying; this node only previews.

signal moved(cell: Vector2i, result: Dictionary)

const VALID_COLOR := Color(0.35, 1.0, 0.55)
const INVALID_COLOR := Color(1.0, 0.3, 0.25)

var grid: BoardGrid
## Board-space height of the ground the grid lies on.
var ground_height: float = 0.0
var preview_radius: int = 3
var active: bool = false
var cell: Vector2i = Vector2i(-1, -1)
var validator: Callable
var ghost: MeshInstance3D
var range_node: Node3D
var _result: Dictionary = {"ok": false, "reason": ""}
var _cells_mm: MultiMesh
var _cells_mi: MultiMeshInstance3D
var _ghost_ok_mat: Material
var _ghost_bad_mat: Material


func setup(p_grid: BoardGrid, p_ground_height: float) -> void:
	grid = p_grid
	ground_height = p_ground_height
	if _cells_mi == null:
		_build()
	_layout_cells()


func _build() -> void:
	name = "Placement"
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.9, 0.9)
	_cells_mm = MultiMesh.new()
	_cells_mm.transform_format = MultiMesh.TRANSFORM_3D
	_cells_mm.use_colors = true
	_cells_mm.mesh = quad
	_cells_mm.instance_count = (2 * 8 + 1) * (2 * 8 + 1)
	_cells_mm.visible_instance_count = 0
	_cells_mi = MultiMeshInstance3D.new()
	_cells_mi.name = "PlacementCells"
	_cells_mi.multimesh = _cells_mm
	var m := AreaViz.material(Color.WHITE).duplicate() as StandardMaterial3D
	_cells_mi.material_override = m
	_cells_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cells_mi)
	ghost = MeshInstance3D.new()
	ghost.name = "Ghost"
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	_ghost_ok_mat = Holo.material(VALID_COLOR, 0.35, 1.2, 1.0)
	_ghost_bad_mat = Holo.material(INVALID_COLOR, 0.35, 1.2, 1.0)
	visible = false


func _layout_cells() -> void:
	pass


func begin(ghost_mesh: Mesh, p_validator: Callable, start_cell: Vector2i, p_range_node: Node3D = null) -> Dictionary:
	if _cells_mi == null:
		_build()
	validator = p_validator
	ghost.mesh = ghost_mesh
	if range_node != null and range_node != p_range_node and range_node.get_parent() == self:
		range_node.queue_free()
	range_node = p_range_node
	if range_node != null and range_node.get_parent() == null:
		add_child(range_node)
	active = true
	visible = true
	cell = Vector2i(-99, -99)
	return move_to(start_cell)


func move_to(p_cell: Vector2i) -> Dictionary:
	if not active:
		return {"ok": false, "reason": "not placing"}
	cell = Vector2i(clampi(p_cell.x, 0, grid.nx - 1), clampi(p_cell.y, 0, grid.ny - 1))
	_result = _validate(cell)
	var at: Vector3 = grid.cell_center_board(cell, ground_height)
	ghost.position = at
	ghost.material_override = _ghost_ok_mat if bool(_result["ok"]) else _ghost_bad_mat
	if range_node != null:
		range_node.position = Vector3(at.x, ground_height + grid.cell_size * 0.05, at.z)
	_paint_cells()
	moved.emit(cell, _result)
	return _result


func move_to_point(point: Vector3) -> Dictionary:
	return move_to(grid.cell_at(point))


func result() -> Dictionary:
	return _result


func is_valid() -> bool:
	return active and bool(_result.get("ok", false))


## Re-run the validator (the board changed under the ghost).
func refresh() -> Dictionary:
	if not active:
		return _result
	return move_to(cell)


func end() -> void:
	active = false
	visible = false
	if range_node != null and range_node.get_parent() == self:
		range_node.queue_free()
	range_node = null
	if _cells_mm != null:
		_cells_mm.visible_instance_count = 0


func _validate(c: Vector2i) -> Dictionary:
	if not validator.is_valid():
		return {"ok": true, "reason": ""}
	var r: Variant = validator.call(c)
	if r is Dictionary:
		return r
	return {"ok": bool(r), "reason": ""}


func _paint_cells() -> void:
	var r: int = mini(preview_radius, 8)
	var n: int = 0
	var c: float = grid.cell_size
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var cc := Vector2i(cell.x + dx, cell.y + dy)
			if not grid.in_bounds(cc) or Vector2(dx, dy).length() > r + 0.5:
				continue
			var verdict: Dictionary = _result if cc == cell else _validate(cc)
			var col: Color = VALID_COLOR if bool(verdict.get("ok", false)) else INVALID_COLOR
			var fade: float = 1.0 - Vector2(dx, dy).length() / (r + 1.0)
			col.a = (0.75 if cc == cell else 0.22 * fade + 0.06)
			var xf := Transform3D(Basis().scaled(Vector3(c, 1.0, c)), grid.cell_center_board(cc, ground_height + c * 0.03))
			_cells_mm.set_instance_transform(n, xf)
			_cells_mm.set_instance_color(n, col)
			n += 1
	_cells_mm.visible_instance_count = n


## Number of preview cells drawn (tests).
func preview_cell_count() -> int:
	return _cells_mm.visible_instance_count if _cells_mm != null else 0
