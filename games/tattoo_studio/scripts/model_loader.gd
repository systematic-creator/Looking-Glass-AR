class_name TattooModelLoader
extends RefCounted
## Turns a TattooModelEntry into a paintable model:
##   {mesh: ArrayMesh, paint: TattooPaintMesh, errors: PackedStringArray, height: float}
## Procedural sources build in code; model files (glTF / .glb or scenes) are
## merged into one mesh (every MeshInstance3D, with its transform baked in)
## and checked against TattooModelContract.

const LIST_PATH: String = "res://games/tattoo_studio/models/model_list.tres"

## Built models for this session (id -> result), so switching models or
## re-entering the game does not rebuild them.
static var cache: Dictionary = {}


static func load_list(path: String = LIST_PATH) -> Array[TattooModelEntry]:
	var out: Array[TattooModelEntry] = []
	var list: TattooModelList = load(path) as TattooModelList if ResourceLoader.exists(path) else null
	if list == null:
		return out
	for entry: TattooModelEntry in list.models:
		if entry != null and entry.id != &"":
			out.append(entry)
	return out


static func load_model(entry: TattooModelEntry, use_cache: bool = true) -> Dictionary:
	if use_cache and cache.has(entry.id):
		return cache[entry.id]
	var result: Dictionary = build(entry)
	if use_cache and (result["errors"] as PackedStringArray).is_empty():
		cache[entry.id] = result
	return result


static func build(entry: TattooModelEntry) -> Dictionary:
	var errors := PackedStringArray()
	var mesh: ArrayMesh = null
	var src: String = entry.source
	if src.begins_with("procedural:"):
		var kind: String = src.trim_prefix("procedural:")
		if not TattooBodyBuilder.KINDS.has(kind):
			errors.append("unknown procedural model '%s'" % kind)
		else:
			mesh = TattooBodyBuilder.build_mesh(kind)
	else:
		var root: Node = load_scene(src)
		if root == null:
			errors.append("could not load '%s'" % src)
		else:
			mesh = merge_meshes(root)
			root.free()
			if mesh == null:
				errors.append("'%s' has no meshes" % src)
	if mesh == null:
		return {"mesh": null, "paint": null, "errors": errors, "height": 0.0}
	var paint: TattooPaintMesh = TattooPaintMesh.from_mesh(mesh)
	errors.append_array(TattooModelContract.validate(paint, entry))
	return {"mesh": mesh, "paint": paint, "errors": errors, "height": paint.aabb.size.y}


## A model file as a node tree (imported resources first, then runtime glTF).
static func load_scene(path: String) -> Node:
	if path.is_empty():
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is PackedScene:
			return (res as PackedScene).instantiate()
		if res is Mesh:
			var holder := MeshInstance3D.new()
			holder.mesh = res as Mesh
			return holder
	var lower: String = path.to_lower()
	if lower.ends_with(".glb") or lower.ends_with(".gltf"):
		if not FileAccess.file_exists(path):
			return null
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			return null
		return doc.generate_scene(state)
	return null


## Every MeshInstance3D under `root`, transforms baked, as one triangle
## surface (vertices, normals, UV0, indices).
static func merge_meshes(root: Node) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tex := PackedVector2Array()
	var idx := PackedInt32Array()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var m: Mesh = (node as MeshInstance3D).mesh
			for s: int in m.get_surface_count():
				if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var arrays: Array = m.surface_get_arrays(s)
				var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var sn: Variant = arrays[Mesh.ARRAY_NORMAL]
				var su: Variant = arrays[Mesh.ARRAY_TEX_UV]
				var si: Variant = arrays[Mesh.ARRAY_INDEX]
				var offset: int = verts.size()
				for k: int in sv.size():
					verts.append(xf * sv[k])
					if sn is PackedVector3Array and (sn as PackedVector3Array).size() == sv.size():
						norms.append((xf.basis * (sn as PackedVector3Array)[k]).normalized())
					else:
						norms.append(Vector3.UP)
					if su is PackedVector2Array and (su as PackedVector2Array).size() == sv.size():
						tex.append((su as PackedVector2Array)[k])
					else:
						tex.append(Vector2.ZERO)
				if si is PackedInt32Array and (si as PackedInt32Array).size() > 0:
					for k: int in si as PackedInt32Array:
						idx.append(k + offset)
				else:
					for k: int in sv.size():
						idx.append(k + offset)
		for child: Node in node.get_children():
			stack.append([child, xf])
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = tex
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
