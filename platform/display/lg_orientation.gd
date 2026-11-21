class_name LGOrientation
## Screen orientation rules shared by the platform (pure, unit-tested).
##
## A game's manifest picks "either" (default), "landscape" or "portrait".
## The platform maps that to a sensor-based Android orientation, so the
## phone may still flip within it (both landscape directions, both portrait
## directions). The launcher always runs as "either".
##
## Layout: the project's base canvas is 1280 x 720 (canvas_items stretch,
## expand aspect). In portrait the base swaps to 720 x 1280, so UI keeps the
## same physical size when the phone turns (without the swap a portrait
## phone would scale the 1280-wide base to its narrow side: about 44 %
## smaller buttons and text).

const EITHER: String = "either"
const LANDSCAPE: String = "landscape"
const PORTRAIT: String = "portrait"
const MODES: PackedStringArray = ["either", "landscape", "portrait"]

const LANDSCAPE_BASE: Vector2i = Vector2i(1280, 720)
const PORTRAIT_BASE: Vector2i = Vector2i(720, 1280)


static func is_valid_mode(mode: String) -> bool:
	return mode in MODES


## The DisplayServer orientation for a manifest mode (unknown -> either).
static func screen_orientation_for(mode: String) -> DisplayServer.ScreenOrientation:
	match mode:
		LANDSCAPE:
			return DisplayServer.SCREEN_SENSOR_LANDSCAPE
		PORTRAIT:
			return DisplayServer.SCREEN_SENSOR_PORTRAIT
		_:
			return DisplayServer.SCREEN_SENSOR


## True for a window taller than it is wide.
static func is_portrait_size(size: Vector2) -> bool:
	return size.y > size.x


## The base canvas size (content_scale_size) for an orientation.
static func base_size(portrait: bool) -> Vector2i:
	return PORTRAIT_BASE if portrait else LANDSCAPE_BASE


## Does a manifest mode allow this orientation?
static func allows(mode: String, portrait: bool) -> bool:
	match mode:
		LANDSCAPE:
			return not portrait
		PORTRAIT:
			return portrait
		_:
			return true


## Android Surface.ROTATION_* (0..3) when the device does not report one:
## portrait -> 0, landscape -> 1 (the common, non-reversed directions).
static func fallback_rotation(window: Vector2) -> int:
	return 0 if is_portrait_size(window) else 1
