class_name OrientationService
extends Node
## Owns the screen orientation (one per app: a child of the LookingGlass
## autoload, see OrientationService.of()).
##
##   request(mode)      apply a manifest orientation ("either" / "landscape" /
##                      "portrait"); GameHost calls it when a game loads.
##   restore_default()  back to "either" (the launcher / catalog).
##   portrait           the current window shape.
##   orientation_changed(portrait)
##                      after the window turned and the base canvas was
##                      swapped (anchored Controls have already re-laid out
##                      when listeners run; they only move what anchors
##                      cannot express).
##
## Rotation is smooth: Android keeps the Activity (configChanges in the
## export template), Godot resizes the window, this service swaps the base
## canvas (LGOrientation.base_size) and fades the UI back in over
## FADE_SECONDS so the one-frame reflow is not seen. The AR session, the
## anchor and the board are untouched: only the camera projection and the
## screen mapping change (ARSession tells ARCore the display rotation).

signal orientation_changed(portrait: bool)

const FADE_SECONDS: float = 0.22
## Controls in this group (or under a CanvasLayer in it) never fade.
const NO_FADE_GROUP: StringName = &"lg_no_fade"

## The current window shape.
var portrait: bool = false
## The mode last requested (a manifest value).
var requested: String = LGOrientation.EITHER
## How a mode reaches the OS; tests swap in a recorder.
## Signature: func(orientation: DisplayServer.ScreenOrientation) -> void.
var screen_setter: Callable = Callable()
## Every orientation set through request() (DisplayServer values), in order.
var history: Array[int] = []
## Fade the UI in after a rotation (tests may turn it off).
var fade_enabled: bool = true
## Number of rotations seen (diagnostics).
var rotations: int = 0

var _initialized: bool = false
var _tween: Tween


## The app's service: the LookingGlass autoload's, or null outside the app.
static func of(node: Node) -> OrientationService:
	if node == null or not node.is_inside_tree():
		return null
	var looking_glass: Node = node.get_node_or_null(^"/root/LookingGlass")
	if looking_glass == null:
		return null
	return looking_glass.get("orientation") as OrientationService


func _ready() -> void:
	name = "Orientation"
	get_tree().root.size_changed.connect(_on_size_changed)
	apply_window_size(Vector2(get_tree().root.size), false)


## Apply a manifest orientation.
func request(mode: String) -> void:
	if not LGOrientation.is_valid_mode(mode):
		push_warning("Unknown orientation '%s'; using either." % mode)
		mode = LGOrientation.EITHER
	requested = mode
	var value: DisplayServer.ScreenOrientation = LGOrientation.screen_orientation_for(mode)
	history.append(int(value))
	if screen_setter.is_valid():
		screen_setter.call(value)
	elif OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(value)


## The launcher's orientation: either.
func restore_default() -> void:
	request(LGOrientation.EITHER)


## The window is now `size` (pixels): swap the base canvas and tell
## listeners if its shape changed. Called on every viewport resize; tests
## may call it directly.
func apply_window_size(size: Vector2, fade: bool = true) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var now_portrait: bool = LGOrientation.is_portrait_size(size)
	if _initialized and now_portrait == portrait:
		return
	var first: bool = not _initialized
	_initialized = true
	portrait = now_portrait
	var root: Window = get_tree().root if is_inside_tree() else null
	if root != null:
		root.content_scale_size = LGOrientation.base_size(portrait)
	if first:
		return
	rotations += 1
	orientation_changed.emit(portrait)
	if fade and fade_enabled:
		fade_in_ui()


## Fade every top-level UI item (Controls directly under a CanvasLayer or
## the root) from transparent to its own alpha over FADE_SECONDS.
func fade_in_ui() -> void:
	if not is_inside_tree():
		return
	var items: Array[CanvasItem] = fade_targets(get_tree().root)
	if items.is_empty():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for item: CanvasItem in items:
		var base: float = float(item.get_meta(&"lg_fade_base", item.modulate.a))
		item.set_meta(&"lg_fade_base", base)
		item.modulate.a = 0.0
		_tween.tween_property(item, "modulate:a", base, FADE_SECONDS)
	_tween.chain().tween_callback(_clear_fade_meta.bind(items))


## The UI items a rotation fades (skips NO_FADE_GROUP, e.g. the camera
## passthrough, and hidden items).
static func fade_targets(root: Node) -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	_collect_fade_targets(root, out)
	return out


static func _collect_fade_targets(node: Node, out: Array[CanvasItem]) -> void:
	for child: Node in node.get_children():
		if child.is_in_group(NO_FADE_GROUP):
			continue
		if child is CanvasLayer:
			for item: Node in child.get_children():
				if item is Control and (item as Control).visible and not item.is_in_group(NO_FADE_GROUP):
					out.append(item as CanvasItem)
		elif child is Control:
			if (child as Control).visible and (node is Window):
				out.append(child as CanvasItem)
		else:
			_collect_fade_targets(child, out)


func _clear_fade_meta(items: Array[CanvasItem]) -> void:
	for item: CanvasItem in items:
		if is_instance_valid(item) and item.has_meta(&"lg_fade_base"):
			item.modulate.a = float(item.get_meta(&"lg_fade_base"))
			item.remove_meta(&"lg_fade_base")


## The root window's size is the physical window (tests resize it to
## simulate a rotation, also headless).
func _on_size_changed() -> void:
	apply_window_size(Vector2(get_tree().root.size))
