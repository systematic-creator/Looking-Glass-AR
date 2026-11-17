class_name LGGameManifest
extends Resource
## Catalog entry for one Looking Glass game. Every game folder under
## res://games/<id>/ ships one of these as `manifest.tres`; the launcher lists
## games from their manifests without loading any game code.

## Unique, stable id (snake_case). Also names the per-game save files.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Square-ish catalog art (optional; the launcher draws a placeholder).
@export var icon: Texture2D
@export_range(1, 16) var min_players: int = 1
@export_range(1, 16) var max_players: int = 1
## Board footprint in metres at placement scale 1: x = width, y = depth.
## The platform frames the camera, sizes the adjust outline and the
## placement from this. Keep it table-sized (about 0.2 to 0.8 m).
@export var board_size: Vector2 = Vector2(0.4, 0.4)
## Tallest point the game draws above the surface, in metres (camera framing).
@export var board_height: float = 0.15
## Entry point: a .tscn whose root script extends LGGame, or a .gd script
## that extends LGGame.
@export_file("*.tscn", "*.gd") var entry: String = ""
@export var version: String = "0.1.0"
@export var author: String = ""
@export var tags: PackedStringArray = PackedStringArray()

const MIN_BOARD_METRES: float = 0.05
const MAX_BOARD_METRES: float = 3.0


## Problems that keep this manifest out of the catalog (empty = valid).
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var key: String = str(id)
	if key.is_empty():
		errors.append("id is empty")
	elif not key.is_valid_identifier() or key != key.to_lower():
		errors.append("id '%s' must be a lower-case identifier (letters, digits, _)" % key)
	if display_name.strip_edges().is_empty():
		errors.append("display_name is empty")
	if min_players < 1 or max_players < min_players:
		errors.append("players must satisfy 1 <= min_players <= max_players")
	for side: float in [board_size.x, board_size.y]:
		if side < MIN_BOARD_METRES or side > MAX_BOARD_METRES:
			errors.append("board_size must be %.2f-%.1f m per side" % [MIN_BOARD_METRES, MAX_BOARD_METRES])
			break
	if board_height < 0.0:
		errors.append("board_height must be >= 0")
	if entry.is_empty():
		errors.append("entry is empty")
	elif not (entry.ends_with(".tscn") or entry.ends_with(".gd")):
		errors.append("entry must be a .tscn or .gd file")
	elif not ResourceLoader.exists(entry):
		errors.append("entry '%s' does not exist" % entry)
	return errors


func is_valid() -> bool:
	return validate().is_empty()


## "1 player", "2 players", "1-4 players".
func players_label() -> String:
	if min_players == max_players:
		return "%d player%s" % [min_players, "" if min_players == 1 else "s"]
	return "%d-%d players" % [min_players, max_players]


## Instantiate the game (null if the entry does not produce an LGGame).
func instantiate_game() -> LGGame:
	if not ResourceLoader.exists(entry):
		return null
	var resource: Resource = load(entry)
	var node: Node = null
	if resource is PackedScene:
		node = (resource as PackedScene).instantiate()
	elif resource is GDScript:
		var instance: Variant = (resource as GDScript).new()
		node = instance as Node
	var game: LGGame = node as LGGame
	if game == null:
		if node != null:
			node.free()
		return null
	game.manifest = self
	return game
