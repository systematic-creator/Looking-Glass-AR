class_name GameCatalog
extends RefCounted
## The list of games the launcher offers. Games register through a manifest
## (LGGameManifest); scan() picks up every res://games/<folder>/manifest.tres.
## Later, downloaded creator games can register the same way from user://.

const GAMES_DIR: String = "res://games"
const MANIFEST_FILE: String = "manifest.tres"

## Why manifests were rejected during the last scan / register calls.
var errors: PackedStringArray = PackedStringArray()
var _manifests: Dictionary = {}


## Add a game. Rejects invalid manifests and duplicate ids.
func register(manifest: LGGameManifest) -> bool:
	if manifest == null:
		errors.append("null manifest")
		return false
	var problems: PackedStringArray = manifest.validate()
	if not problems.is_empty():
		errors.append("%s: %s" % [manifest.resource_path if not manifest.resource_path.is_empty() else str(manifest.id), "; ".join(problems)])
		return false
	if _manifests.has(manifest.id):
		errors.append("duplicate game id '%s'" % manifest.id)
		return false
	_manifests[manifest.id] = manifest
	return true


func unregister(id: StringName) -> void:
	_manifests.erase(id)


func clear() -> void:
	_manifests.clear()
	errors.clear()


## Register every <dir>/<folder>/manifest.tres. Returns how many were added.
func scan(dir: String = GAMES_DIR) -> int:
	var added: int = 0
	for folder: String in DirAccess.get_directories_at(dir):
		var path: String = "%s/%s/%s" % [dir, folder, MANIFEST_FILE]
		if not ResourceLoader.exists(path):
			continue
		var manifest: LGGameManifest = load(path) as LGGameManifest
		if manifest == null:
			errors.append("%s is not an LGGameManifest" % path)
			continue
		if register(manifest):
			added += 1
	return added


func has_game(id: StringName) -> bool:
	return _manifests.has(id)


func get_manifest(id: StringName) -> LGGameManifest:
	return _manifests.get(id, null) as LGGameManifest


func size() -> int:
	return _manifests.size()


## All games, sorted by display name.
func list() -> Array[LGGameManifest]:
	var out: Array[LGGameManifest] = []
	for manifest: Variant in _manifests.values():
		out.append(manifest as LGGameManifest)
	out.sort_custom(func(a: LGGameManifest, b: LGGameManifest) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return out


## A fresh instance of a registered game (null if unknown or broken).
func instantiate(id: StringName) -> LGGame:
	var manifest: LGGameManifest = get_manifest(id)
	return manifest.instantiate_game() if manifest != null else null
