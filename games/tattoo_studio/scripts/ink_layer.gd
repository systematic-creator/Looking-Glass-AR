class_name TattooInkLayer
extends RefCounted
## Ink in a model's UV atlas, and the brush that puts it there.
##
## Shading model (how tattoo ink builds up):
##   Each texel stores pigment LOAD L (0..1, alpha) and optical density OD
##   per colour channel (RGB, 0..OD_MAX). Ink sits under the skin and filters
##   the light the skin reflects, so the shader shows
##       colour = skin * exp(-OD)                  (Beer-Lambert)
##   An ink of colour c (linear reflectance at full saturation) has an
##   absorbance A = -ln(c) per channel. One pass of the needle with coverage
##   w (1 at the brush core, soft at the edge) adds pigment with diminishing
##   returns, like packing ink into skin that already holds some:
##       dL = PASS_STRENGTH * w * (1 - L)
##       L += dL,   OD += dL * A
##   Black: pass 1 L = 0.25 (a grey wash), pass 2 0.44, pass 3 0.58,
##   pass 5 0.76 ... -> 1 (never past it).
##   Colours go from a light tint to deep, saturated ink; different colours
##   over each other mix subtractively (red over blue -> dark violet).
##   A texel takes ink ONCE PER STROKE: within a stroke only the strongest
##   coverage seen counts (recomputed from the stroke's starting state), so
##   holding the needle still or scrubbing back and forth in one stroke does
##   not saturate it; lift and go over it again to deepen it.
##   The eraser scales L and OD by (1 - w), also once per stroke.
##
## Storage: an RGBA8 Image (RGB = OD / OD_MAX, A = L) the model's shader
## samples; uploaded only after painting changed it (the game throttles).
##
## Undo: each finished stroke (press to release, needle or eraser) and each
## Clear all pushes one history step: the BEFORE bytes of only the
## UNDO_TILE x UNDO_TILE tiles it touched (dirty-tile diffs), deflate-
## compressed. At most MAX_UNDO steps and MAX_UNDO_BYTES (compressed) are
## kept; the oldest go first. undo() writes the newest step's tiles back.

const DEFAULT_SIZE: int = 1024
const PASS_STRENGTH: float = 0.25
const OD_MAX: float = 6.0
## Brush profile: full coverage inside (1 - SOFT_EDGE) of the radius.
const SOFT_EDGE: float = 0.35
## Triangles facing away from the stroke's surface normal by more than this
## (cosine) are not painted: a brush on the back of a thin hand stays there.
const FACING_MIN: float = 0.25
## UV edge dilation in texels, so island borders do not show unpainted
## gutter texels through bilinear filtering.
const DILATE_TEXELS: float = 1.5
## Undo history: steps kept, tile size (texels) and memory cap (bytes).
const MAX_UNDO: int = 20
const UNDO_TILE: int = 64
const MAX_UNDO_BYTES: int = 16 * 1024 * 1024

enum Tool { NEEDLE, ERASER }

var size: int = DEFAULT_SIZE
var data: PackedByteArray = PackedByteArray()
var image: Image
var texture: ImageTexture
var dirty: bool = false
## Texels changed since the last upload (for tests / stats).
var texels_changed: int = 0

var _stroke_weight: PackedByteArray = PackedByteArray()
var _snapshot: PackedByteArray = PackedByteArray()
var _in_stroke: bool = false
var _tool: Tool = Tool.NEEDLE
var _absorb: Vector3 = Vector3.ZERO
## Undo steps, oldest first: {tiles: PackedInt32Array, raw: int, bytes: PackedByteArray (deflate)}.
var _history: Array[Dictionary] = []
var _history_bytes: int = 0
## Tiles touched by the current stroke (1 per tile).
var _tile_touched: PackedByteArray = PackedByteArray()
var _tiles_per_row: int = 1


func _init(texture_size: int = DEFAULT_SIZE) -> void:
	size = texture_size
	data.resize(size * size * 4)
	data.fill(0)
	_stroke_weight.resize(size * size)
	_tiles_per_row = int(ceil(float(size) / float(UNDO_TILE)))
	_tile_touched.resize(_tiles_per_row * _tiles_per_row)
	image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	texture = ImageTexture.create_from_image(image)


# --- Pure maths (also used by the tests) ----------------------------------------------

## Linear-light absorbance of an ink colour (sRGB colour picked in the UI).
static func absorbance(ink: Color) -> Vector3:
	var lin: Color = ink.srgb_to_linear()
	return Vector3(-log(clampf(lin.r, 0.004, 1.0)), -log(clampf(lin.g, 0.004, 1.0)), -log(clampf(lin.b, 0.004, 1.0)))


## One needle pass: [od: Vector3, load: float] after coverage `w`.
static func needle_pass(od: Vector3, load: float, w: float, absorb: Vector3) -> Array:
	var d_load: float = PASS_STRENGTH * clampf(w, 0.0, 1.0) * (1.0 - load)
	var out: Vector3 = (od + absorb * d_load).clamp(Vector3.ZERO, Vector3.ONE * OD_MAX)
	return [out, load + d_load]


static func erase_pass(od: Vector3, load: float, w: float) -> Array:
	var keep: float = 1.0 - clampf(w, 0.0, 1.0)
	return [od * keep, load * keep]


## The shader's result in linear light (skin = linear albedo).
static func shade(skin: Color, od: Vector3) -> Color:
	return Color(skin.r * exp(-od.x), skin.g * exp(-od.y), skin.b * exp(-od.z), 1.0)


## Brush coverage at `distance` from the brush centre.
static func coverage(distance: float, r: float) -> float:
	if r <= 0.0:
		return 0.0
	return clampf((r - distance) / (r * SOFT_EDGE), 0.0, 1.0)


# --- Texel access -------------------------------------------------------------------

func texel_od(x: int, y: int) -> Vector3:
	var i: int = (y * size + x) * 4
	return Vector3(data[i], data[i + 1], data[i + 2]) * (OD_MAX / 255.0)


func texel_load(x: int, y: int) -> float:
	return float(data[(y * size + x) * 4 + 3]) / 255.0


func texel_at_uv(uv: Vector2) -> Vector2i:
	return Vector2i(clampi(int(uv.x * size), 0, size - 1), clampi(int(uv.y * size), 0, size - 1))


func load_at_uv(uv: Vector2) -> float:
	var t: Vector2i = texel_at_uv(uv)
	return texel_load(t.x, t.y)


func od_at_uv(uv: Vector2) -> Vector3:
	var t: Vector2i = texel_at_uv(uv)
	return texel_od(t.x, t.y)


## Texels with any ink.
func inked_texels() -> int:
	var count: int = 0
	var i: int = 3
	var n: int = data.size()
	while i < n:
		if data[i] > 0:
			count += 1
		i += 4
	return count


## Wipe all ink. With `undoable` the inked tiles go on the undo history
## first, so a Clear all can be taken back.
func clear(undoable: bool = true) -> void:
	if undoable:
		_tile_touched.fill(1)
		_push_step(data, true)
	data.fill(0)
	_snapshot = PackedByteArray()
	dirty = true


## Replace the whole atlas (drops the undo history).
func set_data(bytes: PackedByteArray) -> void:
	if bytes.size() == data.size():
		data = bytes.duplicate()
		clear_history()
		dirty = true


# --- Undo ------------------------------------------------------------------------

func can_undo() -> bool:
	return not _history.is_empty()


func undo_count() -> int:
	return _history.size()


## Compressed bytes held by the history.
func history_bytes() -> int:
	return _history_bytes


func clear_history() -> void:
	_history.clear()
	_history_bytes = 0


## Take back the newest step (stroke or Clear all). False if none.
func undo() -> bool:
	if _in_stroke:
		end_stroke()
	if _history.is_empty():
		return false
	var step: Dictionary = _history.pop_back()
	_history_bytes -= (step["bytes"] as PackedByteArray).size()
	var raw: PackedByteArray = (step["bytes"] as PackedByteArray).decompress(int(step["raw"]), FileAccess.COMPRESSION_DEFLATE)
	# Native blits: the atlas as an Image, each saved tile written back.
	var atlas: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	var at: int = 0
	for t: int in step["tiles"] as PackedInt32Array:
		var r: Rect2i = tile_rect(t)
		var n: int = r.size.x * r.size.y * 4
		var tile: Image = Image.create_from_data(r.size.x, r.size.y, false, Image.FORMAT_RGBA8, raw.slice(at, at + n))
		atlas.blit_rect(tile, Rect2i(Vector2i.ZERO, r.size), r.position)
		at += n
	data = atlas.get_data()
	dirty = true
	return true


## Texel rectangle of tile `t`.
func tile_rect(t: int) -> Rect2i:
	var tx: int = (t % _tiles_per_row) * UNDO_TILE
	var ty: int = (t / _tiles_per_row) * UNDO_TILE
	return Rect2i(tx, ty, mini(UNDO_TILE, size - tx), mini(UNDO_TILE, size - ty))


func tile_count() -> int:
	return _tile_touched.size()


## Record the touched tiles' bytes from `before` as one undo step. Tiles a
## stroke did not actually change are left out; with `skip_empty` (Clear
## all, recorded before wiping) tiles that are all zero are left out instead.
func _push_step(before: PackedByteArray, skip_empty: bool = false) -> bool:
	var src: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, before)
	var now: Image = null if skip_empty else Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	var tiles := PackedInt32Array()
	var raw := PackedByteArray()
	var zero := PackedByteArray()
	for t: int in _tile_touched.size():
		if _tile_touched[t] == 0:
			continue
		var bytes: PackedByteArray = src.get_region(tile_rect(t)).get_data()
		if skip_empty:
			if zero.size() != bytes.size():
				zero.resize(bytes.size())
				zero.fill(0)
			if bytes == zero:
				continue
		elif now.get_region(tile_rect(t)).get_data() == bytes:
			continue
		tiles.append(t)
		raw.append_array(bytes)
	_tile_touched.fill(0)
	if tiles.is_empty():
		return false
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	_history.append({"tiles": tiles, "raw": raw.size(), "bytes": packed})
	_history_bytes += packed.size()
	while _history.size() > MAX_UNDO or (_history_bytes > MAX_UNDO_BYTES and _history.size() > 1):
		var old: Dictionary = _history.pop_front()
		_history_bytes -= (old["bytes"] as PackedByteArray).size()
	return true


## Push changes to the GPU texture (call at most a few dozen times a second).
func upload() -> void:
	if not dirty:
		return
	image.set_data(size, size, false, Image.FORMAT_RGBA8, data)
	texture.update(image)
	dirty = false
	texels_changed = 0


# --- Strokes ---------------------------------------------------------------------

func begin_stroke(tool: Tool, ink: Color) -> void:
	_tool = tool
	_absorb = absorbance(ink)
	_snapshot = data.duplicate()
	_stroke_weight.fill(0)
	_tile_touched.fill(0)
	_in_stroke = true


## Finish the stroke; one undo step if it changed any ink. Returns true then.
func end_stroke() -> bool:
	var recorded: bool = false
	if _in_stroke and not _snapshot.is_empty():
		recorded = _push_step(_snapshot)
	_in_stroke = false
	_snapshot = PackedByteArray()
	return recorded


func in_stroke() -> bool:
	return _in_stroke


## One brush stamp at model-space `point` (surface normal `facing`), radius
## `r` (model metres). Returns the texels whose ink changed.
func stamp(mesh: TattooPaintMesh, point: Vector3, facing: Vector3, r: float, chunks: PackedInt32Array = PackedInt32Array()) -> int:
	if not _in_stroke:
		begin_stroke(_tool, Color.BLACK)
	var changed: int = 0
	var fw: float = float(size)
	var pad: float = DILATE_TEXELS / fw
	for tri: int in mesh.triangles_near(point, r, chunks):
		if mesh.paintable[tri] == 0 or mesh.normal[tri].dot(facing) < FACING_MIN:
			continue
		var base: Vector3 = mesh.p0[tri]
		var a: Vector3 = mesh.dpdu[tri]
		var b: Vector3 = mesh.dpdv[tri]
		var g: int = tri * 3
		var i00: float = mesh.ginv[g]
		var i01: float = mesh.ginv[g + 1]
		var i11: float = mesh.ginv[g + 2]
		var d: Vector3 = point - base
		var da: float = a.dot(d)
		var db: float = b.dot(d)
		var o: Vector2 = mesh.uv0[tri]
		var cu: float = o.x + i00 * da + i01 * db
		var cv: float = o.y + i01 * da + i11 * db
		var hu: float = r * sqrt(maxf(i00, 0.0))
		var hv: float = r * sqrt(maxf(i11, 0.0))
		var umin: float = maxf(cu - hu, mesh.uv_min[tri].x - pad)
		var umax: float = minf(cu + hu, mesh.uv_max[tri].x + pad)
		var vmin: float = maxf(cv - hv, mesh.uv_min[tri].y - pad)
		var vmax: float = minf(cv + hv, mesh.uv_max[tri].y + pad)
		if umin > umax or vmin > vmax:
			continue
		var x0: int = maxi(int(ceil(umin * fw - 0.5)), 0)
		var x1: int = mini(int(floor(umax * fw - 0.5)), size - 1)
		var y0: int = maxi(int(ceil(vmin * fw - 0.5)), 0)
		var y1: int = mini(int(floor(vmax * fw - 0.5)), size - 1)
		var m: int = tri * 4
		var m00: float = mesh.bary[m]
		var m01: float = mesh.bary[m + 1]
		var m10: float = mesh.bary[m + 2]
		var m11: float = mesh.bary[m + 3]
		var eps: float = DILATE_TEXELS / (fw * maxf(mesh.uv_altitude[tri], 1e-9))
		var r2: float = r * r
		var offset: Vector3 = base - point
		for y: int in range(y0, y1 + 1):
			var qy: float = (float(y) + 0.5) / fw - o.y
			for x: int in range(x0, x1 + 1):
				var qx: float = (float(x) + 0.5) / fw - o.x
				var l1: float = m00 * qx + m01 * qy
				var l2: float = m10 * qx + m11 * qy
				if l1 < -eps or l2 < -eps or l1 + l2 > 1.0 + eps:
					continue
				var rel: Vector3 = offset + a * qx + b * qy
				var dist2: float = rel.length_squared()
				if dist2 >= r2:
					continue
				var w: float = coverage(sqrt(dist2), r)
				if w > 0.0 and _apply(y * size + x, w):
					changed += 1
	if changed > 0:
		dirty = true
		texels_changed += changed
	return changed


## Apply coverage `w` to texel `t` (once per stroke: the strongest counts).
func _apply(t: int, w: float) -> bool:
	var wq: int = clampi(int(round(w * 255.0)), 0, 255)
	if wq <= _stroke_weight[t]:
		return false
	_stroke_weight[t] = wq
	_tile_touched[((t / size) / UNDO_TILE) * _tiles_per_row + (t % size) / UNDO_TILE] = 1
	var wf: float = float(wq) / 255.0
	var i: int = t * 4
	var scale: float = OD_MAX / 255.0
	var od := Vector3(_snapshot[i], _snapshot[i + 1], _snapshot[i + 2]) * scale
	var load: float = float(_snapshot[i + 3]) / 255.0
	var result: Array = erase_pass(od, load, wf) if _tool == Tool.ERASER else needle_pass(od, load, wf, _absorb)
	var out: Vector3 = (result[0] as Vector3) / scale
	data[i] = clampi(int(round(out.x)), 0, 255)
	data[i + 1] = clampi(int(round(out.y)), 0, 255)
	data[i + 2] = clampi(int(round(out.z)), 0, 255)
	data[i + 3] = clampi(int(round(float(result[1]) * 255.0)), 0, 255)
	return true
