class_name MageTrack
extends RefCounted
## Mage Run's shared track model: units, the wizard's body and move set, the
## item types on the track (obstacles, arcane-row tiles, ramps, coins) and the
## jump / fall physics. MageRunSim (the game), MageValidator (fairness) and
## the visuals all read these, so the validator's idea of "can the player get
## through" is the game's own.
##
## Units: the track runs along s, in RUN METRES (distance the wizard ran).
## Lateral (lanes) and vertical (rows, jumps) are in BOARD METRES at placement
## scale 1. The board shows the track through RUN_TO_BOARD (board m per run m).

const LANES: int = 3
## Ground is row 0; the two arcane rows are 1 and 2 (no row 3).
const TOP_ROW: int = 2
const LANE_PITCH: float = 0.075
const ROW_HEIGHT: float = 0.10
const RUN_TO_BOARD: float = 0.16

## The wizard: half length along the track (run m), half width and height
## (board m); sliding halves the height.
const BODY_HALF_LEN: float = 0.04
const BODY_HALF_WIDTH: float = 0.02
const BODY_HEIGHT: float = 0.06
const SLIDE_HEIGHT: float = 0.03

## Jump: apex 0.11 m (clears one row), 0.55 s airtime.
const JUMP_APEX: float = 0.11
const JUMP_TIME: float = 0.55
const JUMP_SPEED: float = 4.0 * JUMP_APEX / JUMP_TIME
const GRAVITY: float = 8.0 * JUMP_APEX / (JUMP_TIME * JUMP_TIME)
## Swipe down mid-air slams down at this speed (then slides on the ground).
const SLAM_SPEED: float = 1.1
const SLIDE_TIME: float = 0.6
const LANE_TIME: float = 0.12
## A jump just after running off an edge still counts (s).
const COYOTE_TIME: float = 0.08
const BUFFER_TIME: float = 0.15
## A cracked rune tile crumbles this long after the wizard steps on it (s).
const CRACK_TIME: float = 0.4
## Highest step the wizard walks up without a jump (ramps), board m.
const STEP_UP: float = 0.016
const TILE_THICKNESS: float = 0.008
## A swipe down on a row drops this far first (so the row is left).
const DROP_NUDGE: float = 0.012

## Obstacle shapes. Each needs one answer (see answers in MageValidator):
## fence = jump, beam = slide, crates / cart = change lane, carriage = change
## lane or jump onto its roof.
const FENCE_LEN: float = 0.12
const FENCE_TOP: float = 0.035
const BEAM_LEN: float = 0.10
const BEAM_BASE: float = 0.035
const BEAM_TOP: float = 0.13
const CRATE_TOP: float = 0.09
const CRATE_MIN_LEN: float = 0.6
const CART_LEN: float = 0.65
const CART_TOP: float = 0.09
## Carts roll toward the wizard at this speed (run m / s) once out of the gate.
const CART_SPEED: float = 0.4
const CARRIAGE_LEN: float = 0.6
const CARRIAGE_ROOF: float = 0.07
## Nothing on the track is longer than this (run m): it must fit behind the
## castle gate before it comes out (see MageRunGame).
const MAX_ITEM_LEN: float = 0.656
const TILE_PIECE_LEN: float = 0.6
const COIN_LIFT: float = 0.02
const COIN_RADIUS: float = 0.01

## Speed curve (run m / s).
const BASE_SPEED: float = 1.2
const SPEED_GAIN: float = 1.4
const SPEED_SCALE: float = 900.0
const MAX_SPEED: float = BASE_SPEED + SPEED_GAIN

## Distances that unlock the arcane rows (run m).
const ROW1_AT: float = 150.0
const ROW2_AT: float = 400.0
const COLLAPSE_AT: float = 800.0

## Board layout (board m at scale 1): the wizard runs at WIZARD_Z; content
## comes out of the castle gate at GATE_Z and is gone by NEAR_Z.
const WIZARD_Z: float = 0.175
const GATE_Z: float = -0.19
const FAR_Z: float = -0.296
const NEAR_Z: float = 0.297
const NEAR_FADE: float = 0.03
## Run metres from the wizard to the gate (what the player can see ahead).
const VISIBLE_AHEAD: float = (WIZARD_Z - GATE_Z) / RUN_TO_BOARD
## Content may exist (hidden in the castle) up to this far ahead...
const SPAWN_AHEAD: float = (WIZARD_Z - FAR_Z) / RUN_TO_BOARD
## ... and is removed this far behind the wizard.
const BEHIND: float = (NEAR_Z - WIZARD_Z) / RUN_TO_BOARD
## The fairness rule: everything is in view this long before it arrives.
const REACTION_TIME: float = 0.75


static func speed_at(distance: float) -> float:
	return BASE_SPEED + SPEED_GAIN * (1.0 - exp(-maxf(distance, 0.0) / SPEED_SCALE))


static func lane_x(lane: int) -> float:
	return float(lane - 1) * LANE_PITCH


static func row_y(row: int) -> float:
	return float(row) * ROW_HEIGHT


## Lane nearest a lateral position.
static func lane_at(x: float) -> int:
	return clampi(roundi(x / LANE_PITCH) + 1, 0, LANES - 1)


## Highest arcane row unlocked at `distance` (0 = ground only).
static func rows_unlocked(distance: float) -> int:
	if distance >= ROW2_AT:
		return 2
	if distance >= ROW1_AT:
		return 1
	return 0


## Height above the take-off surface t seconds into a jump.
static func jump_height(t: float) -> float:
	return JUMP_SPEED * t - 0.5 * GRAVITY * t * t


## Time to fall `height` from rest.
static func fall_time(height: float) -> float:
	return sqrt(2.0 * maxf(height, 0.0) / GRAVITY)


## How long a run at `speed` (plus a cart's own speed) sees an item before it
## reaches the wizard.
static func reaction_time(speed: float, closing: float = 0.0) -> float:
	return VISIBLE_AHEAD / (speed + closing)


## Track position -> board z (the wizard stays put, the world scrolls).
static func board_z(s: float, distance: float) -> float:
	return WIZARD_Z - (s - distance) * RUN_TO_BOARD


## A cart's blocking interval, in wizard positions, at a steady `speed`: it
## leaves the gate (s0 - distance = VISIBLE_AHEAD) and rolls at CART_SPEED.
static func cart_block(s0: float, length: float, speed: float) -> Vector2:
	var k: float = CART_SPEED / speed
	var start: float = (s0 - BODY_HALF_LEN + k * (s0 - VISIBLE_AHEAD)) / (1.0 + k)
	var end: float = (s0 + length + BODY_HALF_LEN + k * (s0 - VISIBLE_AHEAD)) / (1.0 + k)
	return Vector2(start, end)


class Obstacle:
	extends RefCounted
	var id: int = 0
	var kind: StringName = &"fence"
	var lanes: PackedInt32Array = PackedInt32Array()
	var s0: float = 0.0
	var length: float = 0.1
	var base: float = 0.0
	var top: float = 0.0
	## Walkable top (carriage roof), or -1.
	var roof: float = -1.0
	var moving: bool = false
	var active: bool = false
	## Smashed by the shield.
	var broken: bool = false
	## Already brushed by a stumble (no second hit while bouncing back).
	var grazed: bool = false
	var passed: bool = false

	func s1() -> float:
		return s0 + length

	func has_lane(lane: int) -> bool:
		return lanes.has(lane)

	func min_x() -> float:
		var lo: int = 99
		for l: int in lanes:
			lo = mini(lo, l)
		return MageTrack.lane_x(lo) - MageTrack.LANE_PITCH * 0.42

	func max_x() -> float:
		var hi: int = -99
		for l: int in lanes:
			hi = maxi(hi, l)
		return MageTrack.lane_x(hi) + MageTrack.LANE_PITCH * 0.42


class Tile:
	extends RefCounted
	var id: int = 0
	var lane: int = 1
	var row: int = 1
	var s0: float = 0.0
	var length: float = 0.6
	var cracked: bool = false
	## Seconds since the wizard first stood on it (cracked only), -1 = untouched.
	var crumble: float = -1.0
	var gone: bool = false

	func s1() -> float:
		return s0 + length

	func covers(s: float) -> bool:
		return not gone and s >= s0 and s <= s0 + length

	func height() -> float:
		return MageTrack.row_y(row)


class Ramp:
	extends RefCounted
	var id: int = 0
	var lane: int = 1
	## Leads from this row up to row + 1.
	var row: int = 0
	var s0: float = 0.0
	var length: float = 0.6

	func s1() -> float:
		return s0 + length

	func covers(s: float) -> bool:
		return s >= s0 and s <= s0 + length

	func height_at(s: float) -> float:
		var t: float = clampf((s - s0) / length, 0.0, 1.0)
		return MageTrack.row_y(row) + t * MageTrack.ROW_HEIGHT


class Coin:
	extends RefCounted
	var id: int = 0
	var lane: int = 1
	## The row the coin belongs to (sets its multiplier: x1 / x2 / x3).
	var row: int = 0
	var s: float = 0.0
	var y: float = 0.02
	var taken: bool = false
	## Pulled by the magnet: flies to the wizard over a short time.
	var flying: bool = false
	var fly: float = 0.0

	func value() -> int:
		return row + 1
