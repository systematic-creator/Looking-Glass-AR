class_name PlayBoxOutline
extends Node3D
## Hologram outline of a game's PlayBox, in board space: glowing floor
## edges, corner pillars that fade as they rise, and a faint top frame.
## Shown bright while the player adjusts the board; while playing the game
## decides (LGGame.box_outline_while_playing(): 0 hidden .. 1 bright).
## 16 thin bars and 5 shared materials: cheap on a phone.

const FLOOR_INTENSITY: float = 1.3
## Pillar segments from the floor up (fading).
const PILLAR_INTENSITY: Array[float] = [0.9, 0.5, 0.22]
const TOP_INTENSITY: float = 0.3

var level: float = 1.0
var box_size: Vector3 = Vector3.ZERO
var _floor_mat: ShaderMaterial
var _pillar_mats: Array[ShaderMaterial] = []
var _top_mat: ShaderMaterial


func _init() -> void:
	name = "PlayBoxOutline"
	_floor_mat = Holo.line_material(Holo.CYAN, FLOOR_INTENSITY)
	for intensity: float in PILLAR_INTENSITY:
		_pillar_mats.append(Holo.line_material(Holo.CYAN, intensity))
	_top_mat = Holo.line_material(Holo.CYAN, TOP_INTENSITY)


## (Re)build the bars for `box`.
func build(box: PlayBox) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	box_size = box.size
	var hx: float = box.size.x * 0.5
	var hz: float = box.size.z * 0.5
	var h: float = box.size.y
	var corners: Array[Vector3] = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for i: int in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		_add(Holo.bar(a + Vector3(0, 0.002, 0), b + Vector3(0, 0.002, 0), 0.004, _floor_mat), "Floor%d" % i)
		_add(Holo.bar(a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.0025, _top_mat), "Top%d" % i)
		var segments: int = PILLAR_INTENSITY.size()
		for k: int in segments:
			var y0: float = h * float(k) / float(segments)
			var y1: float = h * float(k + 1) / float(segments)
			_add(Holo.bar(a + Vector3(0, y0, 0), a + Vector3(0, y1, 0), 0.003, _pillar_mats[k]), "Pillar%d_%d" % [i, k])
	set_level(level)


## Overall brightness: 1 while adjusting, the game's level while playing.
func set_level(value: float) -> void:
	level = clampf(value, 0.0, 1.0)
	_floor_mat.set_shader_parameter("intensity", FLOOR_INTENSITY * level)
	for k: int in _pillar_mats.size():
		_pillar_mats[k].set_shader_parameter("intensity", PILLAR_INTENSITY[k] * level)
	_top_mat.set_shader_parameter("intensity", TOP_INTENSITY * level)


## Height of the top frame (board space).
func top_height() -> float:
	return box_size.y


func _add(bar: MeshInstance3D, bar_name: String) -> void:
	bar.name = bar_name
	add_child(bar)
