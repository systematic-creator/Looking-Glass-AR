class_name LGGame
extends Node3D
## Base class for every Looking Glass game: the contract between a game and
## the platform.
##
## The platform (GameHost + ARSession) owns the camera, AR tracking,
## calibration, anchoring and the board's placement in the room. A game only
## renders into BOARD SPACE: this node's local space, where
##   - the origin is the centre of the board, resting on the surface,
##   - +Y is up, the board lies in the XZ plane,
##   - 1 unit = 1 metre at placement scale 1 (the player may resize it),
##   - the footprint is manifest.board_size (x by z), centred on the origin.
## Never touch cameras, XR nodes, the viewport or this node's own transform:
## the platform moves the board, so anything you add as a child follows it.
##
## Lifecycle (override the _on_* hooks; all are optional):
##   _on_board_ready()      added to the board; not placed or playing yet.
##                          Build your scene here.
##   _on_board_locked()     the player locked the board in the room (or the
##                          touch fallback started).
##   _on_board_unlocked()   the player unlocked it to move / resize it.
##   _on_resumed()          is_playing() became true: run your game.
##   _on_paused()           is_playing() became false (unlocked, re-placing,
##                          app in background): freeze timers and AI.
##   _on_exit()             the player is leaving the game; save here.
## is_playing() is true only while the board is locked and the app is in the
## foreground, so a game never runs while it is being placed.
##
## Input arrives in board space, only while playing:
##   _on_board_tap(point)            a tap hit the board plane at `point`.
##   _on_board_drag(from, to)        a one-finger drag, if captures_drag().
## Points are Vector3 in board space with y = 0. The platform finds them by
## casting the finger's ray onto the plane y = board_surface_height(), so a
## raised board (a slab, a table top) takes taps where the player sees its top.
##
## Play volume ("simulation box"): get_box() is a PlayBox in board space:
## floor y = 0 on the chosen surface, footprint = manifest.board_size, height
## = the airspace (game-declared in the manifest, adjustable by the player
## within the game's limits, capped by the platform). Keep the game inside
## it: box_contains(point), clamp_to_box(point). _on_box_changed(box) runs
## when the player changes the height (after _on_board_ready; the first box
## is already set when _on_board_ready runs).
##
## Look: platform/visual/ has the shared hologram kit (Holo, HoloDrop) so
## every game can share the same projected-hologram style.

## Ask the platform to close the game and return to the catalog.
signal exit_requested()
## A short line the platform shows under the game (turn, score, hints).
signal status_changed(text: String)
## is_playing() changed (the platform refreshes its status line).
signal playing_changed(playing: bool)
## The play box changed (after _on_board_ready).
signal box_changed(box: PlayBox)

## Set by the platform before the game enters the tree.
var manifest: LGGameManifest

var _board_locked: bool = false
var _app_paused: bool = false
var _playing: bool = false
var _ready_called: bool = false
var _status: String = ""
var _box: PlayBox


# --- Overridable hooks ---------------------------------------------------------

func _on_board_ready() -> void:
	pass


func _on_board_locked() -> void:
	pass


func _on_board_unlocked() -> void:
	pass


func _on_resumed() -> void:
	pass


func _on_paused() -> void:
	pass


func _on_exit() -> void:
	pass


func _on_board_tap(_point: Vector3) -> void:
	pass


func _on_board_drag(_from: Vector3, _to: Vector3) -> void:
	pass


## The play box changed size (the player picked another airspace height).
func _on_box_changed(_box: PlayBox) -> void:
	pass


## Every tap while playing, as a board-space ray (origin, unit direction),
## before _on_board_tap: pick things in the airspace with
## get_box().intersect_ray() / ray_at_height(), or your own geometry.
func _on_box_ray(_origin: Vector3, _direction: Vector3) -> void:
	pass


## How visible the platform's box outline stays while playing: 0 hidden
## (default), up to 1 (as bright as while adjusting).
func box_outline_while_playing() -> float:
	return 0.0


## Height (board space, metres at scale 1) of the surface players tap, e.g.
## the top of a raised board. Taps are projected onto this plane.
func board_surface_height() -> float:
	return 0.0


## Return true to receive one-finger drags; otherwise the platform uses them
## (e.g. to orbit the touch camera outside AR).
func captures_drag() -> bool:
	return false


# --- Queries ---------------------------------------------------------------------

## Footprint in metres at scale 1 (x = width, y = depth).
func get_board_size() -> Vector2:
	return manifest.board_size if manifest != null else Vector2(0.4, 0.4)


func is_playing() -> bool:
	return _playing


## The play volume (board space, floor y = 0). Never null.
func get_box() -> PlayBox:
	if _box == null:
		_box = PlayBox.from_manifest(manifest)
	return _box


func box_contains(point: Vector3, margin: float = 0.0) -> bool:
	return get_box().contains(point, margin)


func clamp_to_box(point: Vector3, margin: float = 0.0) -> Vector3:
	return get_box().clamp_point(point, margin)


func is_board_locked() -> bool:
	return _board_locked


## True if a board-space point lies on the footprint.
func is_on_board(point: Vector3) -> bool:
	var half: Vector2 = get_board_size() * 0.5
	return absf(point.x) <= half.x and absf(point.z) <= half.y


func set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)


func get_status() -> String:
	return _status


func request_exit() -> void:
	exit_requested.emit()


# --- Platform side (GameHost calls these; games should not) ------------------------

func lg_board_ready() -> void:
	if _ready_called:
		return
	_ready_called = true
	_on_board_ready()


func lg_set_locked(locked: bool) -> void:
	if locked == _board_locked:
		return
	_board_locked = locked
	if locked:
		_on_board_locked()
	else:
		_on_board_unlocked()
	_update_playing()


func lg_set_app_paused(paused: bool) -> void:
	if paused == _app_paused:
		return
	_app_paused = paused
	_update_playing()


func lg_set_box(box: PlayBox) -> void:
	_box = box
	if _ready_called:
		_on_box_changed(box)
		box_changed.emit(box)


func lg_box_ray(origin: Vector3, direction: Vector3) -> bool:
	if not _playing:
		return false
	_on_box_ray(origin, direction)
	return true


func lg_tap(point: Vector3) -> bool:
	if not _playing:
		return false
	_on_board_tap(point)
	return true


func lg_drag(from: Vector3, to: Vector3) -> bool:
	if not _playing or not captures_drag():
		return false
	_on_board_drag(from, to)
	return true


func lg_exit() -> void:
	if _playing:
		_playing = false
		_on_paused()
		playing_changed.emit(false)
	_on_exit()


func _update_playing() -> void:
	var playing: bool = _board_locked and not _app_paused
	if playing == _playing:
		return
	_playing = playing
	if playing:
		_on_resumed()
	else:
		_on_paused()
	playing_changed.emit(playing)
