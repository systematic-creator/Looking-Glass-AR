extends Node
## Autoload `LookingGlass`: the platform singleton. Holds the game catalog,
## the screen orientation service and moves between the launcher and a
## running game.

const LAUNCHER_SCENE: String = "res://platform/launcher/launcher.tscn"
const HOST_SCENE: String = "res://platform/host/game_host.tscn"

signal game_launched(id: StringName)
signal returned_to_launcher()

var catalog: GameCatalog = GameCatalog.new()
## The game the next GameHost loads.
var selected_game_id: StringName = &""
## Screen orientation (per-game manifest orientation, rotation, base canvas).
var orientation: OrientationService


func _ready() -> void:
	orientation = OrientationService.new()
	add_child(orientation)
	refresh_catalog()


func refresh_catalog() -> void:
	catalog.clear()
	catalog.scan()
	print("Looking Glass: %d game(s) in the catalog" % catalog.size())
	for problem: String in catalog.errors:
		push_warning("Game catalog: %s" % problem)


## Open a game: the host runs calibration, then puts it on the locked board.
func launch(id: StringName) -> bool:
	if not catalog.has_game(id):
		push_warning("Unknown game '%s'" % id)
		return false
	selected_game_id = id
	game_launched.emit(id)
	get_tree().change_scene_to_file(HOST_SCENE)
	return true


func return_to_launcher() -> void:
	selected_game_id = &""
	# The catalog follows the phone (GameHost already restored it on exit;
	# this covers any other way back).
	orientation.restore_default()
	returned_to_launcher.emit()
	get_tree().change_scene_to_file(LAUNCHER_SCENE)
