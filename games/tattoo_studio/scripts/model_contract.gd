class_name TattooModelContract
extends RefCounted
## Checks a model against the Tattoo Studio model contract (MODELS.md):
##   - triangles, at most MAX_TRIANGLES, every vertex with UV0 in [0, 1]
##   - metres: standing height within HEIGHT_TOLERANCE of entry.height_m
##   - origin on the floor between the feet: min y ~ 0, x / z centred
##   - +Y up: taller than it is wide or deep
##   - UV0 non-overlapping (sampled on a COVERAGE_GRID raster) and almost
##     no zero-UV-area triangles with real 3D area
## validate() returns errors (empty = the model may be painted on).

const MAX_TRIANGLES: int = 120000
const HEIGHT_TOLERANCE: float = 0.15
const FLOOR_TOLERANCE: float = 0.02
const CENTRE_TOLERANCE: float = 0.2
const COVERAGE_GRID: int = 256
## Overlap allowed (fraction of covered raster cells): shared triangle edges
## land on a few cells.
const MAX_OVERLAP: float = 0.01
const MAX_DEGENERATE_UV: float = 0.02


static func validate(mesh: TattooPaintMesh, entry: TattooModelEntry = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if mesh == null or mesh.tri_count == 0:
		errors.append("no triangles")
		return errors
	if mesh.tri_count > MAX_TRIANGLES:
		errors.append("%d triangles (max %d)" % [mesh.tri_count, MAX_TRIANGLES])
	if mesh.uvs.size() != mesh.positions.size():
		errors.append("missing UV0")
		return errors
	var out_of_range: int = 0
	var all_zero: bool = true
	for uv: Vector2 in mesh.uvs:
		if uv.x < -0.0001 or uv.y < -0.0001 or uv.x > 1.0001 or uv.y > 1.0001:
			out_of_range += 1
		if uv != Vector2.ZERO:
			all_zero = false
	if all_zero:
		errors.append("missing UV0 (all zero)")
		return errors
	if out_of_range > 0:
		errors.append("%d UVs outside [0, 1] (UV0 must not tile)" % out_of_range)
	var box: AABB = mesh.aabb
	var height: float = box.size.y
	if absf(box.position.y) > FLOOR_TOLERANCE:
		errors.append("origin must be on the floor at the feet (min y = %.3f m)" % box.position.y)
	var centre := Vector2(box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5)
	if centre.length() > CENTRE_TOLERANCE * maxf(height, 0.1):
		errors.append("origin must be under the model (footprint centre %.2f, %.2f m)" % [centre.x, centre.y])
	if height < maxf(box.size.x, box.size.z) * 0.8:
		errors.append("+Y must be up (height %.2f m vs width %.2f / depth %.2f m)" % [height, box.size.x, box.size.z])
	if entry != null and entry.height_m > 0.0 and absf(height - entry.height_m) > entry.height_m * HEIGHT_TOLERANCE:
		errors.append("height %.3f m, expected %.2f m (units must be metres)" % [height, entry.height_m])
	var degenerate: int = 0
	var solid: int = 0
	for t: int in mesh.tri_count:
		if mesh.e1[t].cross(mesh.e2[t]).length() * 0.5 > TattooPaintMesh.MIN_AREA:
			solid += 1
			if mesh.paintable[t] == 0:
				degenerate += 1
	if solid > 0 and float(degenerate) / float(solid) > MAX_DEGENERATE_UV:
		errors.append("%d triangles have no UV area" % degenerate)
	var overlap: float = uv_overlap(mesh)
	if overlap > MAX_OVERLAP:
		errors.append("UV0 overlaps (%.1f%% of the painted area is shared)" % (overlap * 100.0))
	return errors


## Fraction of covered raster cells claimed by more than one triangle.
static func uv_overlap(mesh: TattooPaintMesh, grid: int = COVERAGE_GRID) -> float:
	var counts := PackedByteArray()
	counts.resize(grid * grid)
	counts.fill(0)
	var fg: float = float(grid)
	for t: int in mesh.tri_count:
		if mesh.paintable[t] == 0:
			continue
		var lo: Vector2 = mesh.uv_min[t]
		var hi: Vector2 = mesh.uv_max[t]
		var x0: int = maxi(int(ceil(lo.x * fg - 0.5)), 0)
		var x1: int = mini(int(floor(hi.x * fg - 0.5)), grid - 1)
		var y0: int = maxi(int(ceil(lo.y * fg - 0.5)), 0)
		var y1: int = mini(int(floor(hi.y * fg - 0.5)), grid - 1)
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				var l: Vector2 = mesh.uv_barycentric(t, Vector2((x + 0.5) / fg, (y + 0.5) / fg))
				# Strictly inside: shared edges do not count twice.
				if l.x > 1e-4 and l.y > 1e-4 and l.x + l.y < 1.0 - 1e-4:
					counts[y * grid + x] = mini(counts[y * grid + x] + 1, 255)
	var covered: int = 0
	var shared: int = 0
	for c: int in counts:
		if c > 0:
			covered += 1
			if c > 1:
				shared += 1
	return 0.0 if covered == 0 else float(shared) / float(covered)
