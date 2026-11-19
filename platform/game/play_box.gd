class_name PlayBox
extends RefCounted
## The game's "simulation box": the volume a game may use above its board,
## in BOARD SPACE (the LGGame node's local space, 1 unit = 1 m at scale 1).
##
##   floor  y = 0 (the chosen / traced surface)
##   footprint  x in [-size.x/2, size.x/2], z in [-size.z/2, size.z/2]
##              (manifest.board_size; the player's placement scale, rotation
##              and position act on the whole box, never on these numbers)
##   top    y = size.y (the airspace height)
##
## The height is game-declared (LGGameManifest.box_height / box_min_height /
## box_max_height, metres at scale 1), optionally adjusted by the player in
## the adjust step, and always capped by the platform: at most
## MAX_HEIGHT_RATIO (3x) the footprint's longer side and at most
## ABSOLUTE_MAX_HEIGHT (1.0 m), so a box is never a tower over a small board.
##
## Tall-box exception: a manifest with `tall_box = true` (games that stand
## life-size things on the floor, e.g. Tattoo Studio's humanoid models) is
## capped at TALL_HEIGHT_RATIO (4x) the longer side and at most
## TALL_MAX_HEIGHT (3.0 m) instead. The placement scale still shrinks the
## whole box on a table.

## Hard cap on the airspace at placement scale 1 (metres).
const ABSOLUTE_MAX_HEIGHT: float = 1.0
## ... and relative to the footprint's longer side.
const MAX_HEIGHT_RATIO: float = 3.0
## Smallest airspace a game can ask for (metres at scale 1).
const MIN_HEIGHT: float = 0.02
## Tall-box exception (LGGameManifest.tall_box): hard cap and footprint ratio.
const TALL_MAX_HEIGHT: float = 3.0
const TALL_HEIGHT_RATIO: float = 4.0

## Width (x), height (y), depth (z) in board units.
var size: Vector3 = Vector3(0.4, 0.15, 0.4)
## Allowed height range (after platform caps) and the game's preferred height.
var min_height: float = MIN_HEIGHT
var max_height: float = ABSOLUTE_MAX_HEIGHT
var preferred_height: float = 0.15


## The platform cap for a footprint (metres at scale 1); `tall` = the
## manifest's tall-box exception.
static func height_cap(footprint: Vector2, tall: bool = false) -> float:
	var longer: float = maxf(footprint.x, footprint.y)
	if tall:
		return minf(TALL_MAX_HEIGHT, longer * TALL_HEIGHT_RATIO)
	return minf(ABSOLUTE_MAX_HEIGHT, longer * MAX_HEIGHT_RATIO)


## Box for a manifest: limits resolved and capped, height = `height` (e.g. the
## player's saved choice) or the game's preferred height if `height` < 0.
static func from_manifest(manifest: LGGameManifest, height: float = -1.0) -> PlayBox:
	var box := PlayBox.new()
	var footprint: Vector2 = manifest.board_size if manifest != null else Vector2(0.4, 0.4)
	var cap: float = height_cap(footprint, manifest != null and manifest.tall_box)
	var preferred: float = 0.15
	var lo: float = MIN_HEIGHT
	var hi: float = cap
	if manifest != null:
		preferred = manifest.box_height if manifest.box_height > 0.0 else maxf(manifest.board_height, MIN_HEIGHT)
		if manifest.box_min_height > 0.0:
			lo = manifest.box_min_height
		if manifest.box_max_height > 0.0:
			hi = manifest.box_max_height
	hi = clampf(hi, MIN_HEIGHT, cap)
	lo = clampf(lo, MIN_HEIGHT, hi)
	box.min_height = lo
	box.max_height = hi
	box.preferred_height = clampf(preferred, lo, hi)
	box.size = Vector3(footprint.x, box.preferred_height, footprint.y)
	box.set_height(height if height >= 0.0 else box.preferred_height)
	return box


## Set the airspace height, clamped to the allowed range. Returns the result.
func set_height(height: float) -> float:
	size.y = clampf(height, min_height, max_height)
	return size.y


func height() -> float:
	return size.y


## True if the player may change the height (the range is not a single value).
func is_adjustable() -> bool:
	return max_height - min_height > 0.001


func footprint() -> Vector2:
	return Vector2(size.x, size.z)


## The box as an AABB in board space (floor at y = 0).
func bounds() -> AABB:
	return AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)


func center() -> Vector3:
	return Vector3(0.0, size.y * 0.5, 0.0)


## True if a board-space point is inside the box (`margin` shrinks it).
func contains(point: Vector3, margin: float = 0.0) -> bool:
	var half := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	return (
		absf(point.x) <= half.x - margin and absf(point.z) <= half.z - margin
		and point.y >= margin and point.y <= size.y - margin
	)


## The nearest point inside the box (`margin` keeps it that far from walls).
func clamp_point(point: Vector3, margin: float = 0.0) -> Vector3:
	var hx: float = maxf(0.0, size.x * 0.5 - margin)
	var hz: float = maxf(0.0, size.z * 0.5 - margin)
	var lo_y: float = minf(margin, size.y * 0.5)
	var hi_y: float = maxf(size.y - margin, lo_y)
	return Vector3(clampf(point.x, -hx, hx), clampf(point.y, lo_y, hi_y), clampf(point.z, -hz, hz))


## Where a board-space ray first enters the box (or its start, if it starts
## inside), or null if it misses the box.
func intersect_ray(origin: Vector3, direction: Vector3) -> Variant:
	if contains(origin):
		return origin
	return bounds().intersects_ray(origin, direction)


## Where a board-space ray crosses the horizontal plane y = `height` inside
## the footprint (height clamped into the box), or null.
func ray_at_height(origin: Vector3, direction: Vector3, height: float) -> Variant:
	var h: float = clampf(height, 0.0, size.y)
	var hit: Variant = Plane(Vector3.UP, h).intersects_ray(origin, direction)
	if hit == null:
		return null
	var p: Vector3 = hit as Vector3
	if absf(p.x) > size.x * 0.5 or absf(p.z) > size.z * 0.5:
		return null
	return p


func duplicate_box() -> PlayBox:
	var copy := PlayBox.new()
	copy.size = size
	copy.min_height = min_height
	copy.max_height = max_height
	copy.preferred_height = preferred_height
	return copy
