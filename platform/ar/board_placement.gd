class_name BoardPlacement
extends RefCounted
## The player's adjustment of the board relative to its anchor: offset,
## yaw and scale (persisted per game), plus a transient viewing magnification.
##
## Anchor space -> pivot: magnify about the anchor, then offset, yaw, scale.
## The game lives below the pivot in its own board-local space (1 unit = 1 m
## at scale 1), so none of this ever changes what the game logic sees.

## Scale multiplies the game's own footprint (LGGameManifest.board_size).
const MIN_SCALE: float = 0.25
const MAX_SCALE: float = 4.0
const DEFAULT_SCALE: float = 1.0
const MIN_MAGNIFY: float = 1.0
const MAX_MAGNIFY: float = 6.0
const SAVE_PATH: String = "user://lg_placement.cfg"
const SECTION: String = "placement"

## Anchor-space offset of the pivot (y stays 0: the board sits on the plane).
var offset: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var scale: float = DEFAULT_SCALE
var locked: bool = false
## The player's airspace height for this game (board units at scale 1;
## -1 = the game's preferred height). Clamped by the game's PlayBox.
var box_height: float = -1.0
## Viewing aid only, not persisted or shared: scales about the anchor.
var magnify: float = 1.0


## Pivot transform relative to the anchor.
func pivot_transform() -> Transform3D:
	var placed := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), offset)
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * magnify), Vector3.ZERO) * placed


func total_scale() -> float:
	return scale * magnify


## Move by an anchor-space delta (unlocked only). Returns true if applied.
func drag(anchor_delta: Vector3) -> bool:
	if locked:
		return false
	offset += Vector3(anchor_delta.x, 0.0, anchor_delta.z) / magnify
	return true


## Multiply the persisted scale (unlocked only).
func pinch(factor: float) -> bool:
	if locked or factor <= 0.0:
		return false
	scale = clampf(scale * factor, MIN_SCALE, MAX_SCALE)
	return true


## Rotate about the pivot's up axis (unlocked only).
func twist(delta_yaw: float) -> bool:
	if locked:
		return false
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	return true


## Viewing magnification about the anchor; allowed while locked.
func magnify_by(factor: float) -> void:
	if factor > 0.0:
		magnify = clampf(magnify * factor, MIN_MAGNIFY, MAX_MAGNIFY)


## Put the board back on its anchor and drop magnification.
## Scale and rotation are kept (they are the player's saved preference).
func recenter() -> void:
	offset = Vector3.ZERO
	magnify = 1.0


func to_dict() -> Dictionary:
	return {
		"offset_x": offset.x,
		"offset_z": offset.z,
		"yaw": yaw,
		"scale": scale,
		"locked": locked,
		"box_height": box_height,
	}


func from_dict(data: Dictionary) -> void:
	offset = Vector3(float(data.get("offset_x", 0.0)), 0.0, float(data.get("offset_z", 0.0)))
	yaw = float(data.get("yaw", 0.0))
	scale = clampf(float(data.get("scale", DEFAULT_SCALE)), MIN_SCALE, MAX_SCALE)
	locked = bool(data.get("locked", false))
	box_height = float(data.get("box_height", -1.0))


func save(path: String = SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	var data: Dictionary = to_dict()
	for key: String in data:
		config.set_value(SECTION, key, data[key])
	return config.save(path)


func load_from(path: String = SAVE_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	var data: Dictionary = {}
	for key: String in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	from_dict(data)
	return true
