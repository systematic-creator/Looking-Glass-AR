# Looking Glass

A platform for **tabletop AR games**. Point your phone at a table, place a
game board on it, lock it in place, and walk around it to play. The board
stays anchored in the room, so you can see it from any side, any distance.

Looking Glass is a catalog of these board games, Roblox / Fortnite style. The
first games are built in-house. Later, other creators will be able to upload
their own games that follow the same board contract. Multiplayer is the end
goal: players in the same room share one anchored board, and each sees it
from their own phone's position.

**Status:** early. The platform layer (ARCore, calibration, anchoring), the
game contract, the launcher, and two games are in place. *Tic-Tac-Toe* is a
sample that proves the contract. *Competitive Evolution* is a placeholder
board; the full game lives in
[Competitive-evolution-AGR](https://github.com/Systematic-creator/Competitive-evolution-AGR)
and is on hiatus until it gets imported here.

Godot **4.4.1**, typed GDScript, Compatibility renderer, landscape, Android +
ARCore. Desktop and headless runs use a touch / orbit camera instead of AR.

## Architecture

```
platform/
  looking_glass.gd        autoload: game catalog, launcher <-> game navigation
  launcher/               catalog screen (main scene): one card per game
  host/game_host.gd       runs one game: board scene, AR session, input routing
  host/orbit_camera.gd    touch / desktop camera for the non-AR fallback
  host/tap_probe.gd       debug overlay: touch dot + reprojected hit ring
  game/lg_game.gd         LGGame: base class every game extends (the contract)
  game/lg_game_manifest.gd  LGGameManifest: catalog entry resource
  game/play_box.gd        PlayBox: the game's play volume ("simulation box")
  game/game_catalog.gd    registers manifests found in res://games/*/manifest.tres
  ar/ar_session.gd        AR mode, calibration, anchoring, lock / unlock
  ar/calibration_flow.gd  pure state machine: scan -> place -> fit edges -> adjust -> lock
  ar/edge_fitter.gd       Fit edges maths: simplified outline, corner / edge handles
  ar/fit_handles.gd       Fit edges handle overlay (draw only)
  ar/screen_ray.gd        exact screen -> world rays (inverse of the rendered projection)
  ar/calibration_hud.gd   calibration UI (big buttons, status, debug line)
  ar/arcore_bridge.gd     dynamic wrapper around the patched ARCore plugin
  ar/anchor_service.gd    the one world anchor (+ Cloud Anchor stub for multiplayer)
  ar/board_placement.gd   player's offset / rotation / size, saved per game
  ar/gesture_tracker.gd   tap / drag / pinch+twist from raw touches
  ar/surface_region.gd    play-area polygon: fit / clamp the board footprint
  visual/holo.gd          Holo: shared hologram materials, glow base, bars, ripples
  visual/holo_drop.gd     HoloDrop: drop-in animation (fall, squash, flash, ripple)
  visual/play_box_outline.gd  PlayBoxOutline: hologram outline of the play box
  visual/*.gdshader       the two hologram shaders (Compatibility-renderer safe)
games/
  tic_tac_toe/            sample game (hologram board)
  competitive_evolution/  placeholder adapter
addons/ARCorePlugin/      Android export plugin (binaries are built, not committed)
tools/arcore_plugin/      ARCore plugin build script + patch
tests/                    headless test suites
```

Scene tree while a game runs:

```
GameHost
  WorldAnchor          the anchor in the room (ARCore anchor, yaw only)
    BoardPivot         player's offset, rotation, size (+ view magnify)
      Game (LGGame)    the game, in board space
      PlayBoxOutline   play-box outline: bright while adjusting, the game's level while playing
  OrbitCamera          fallback camera (non-AR)
  ARSession            XROrigin3D / XRCamera3D, reticle, scan overlay, calibration HUD
  HostHud              "‹ Games" button + the game's status line
```

**The platform owns** the camera, AR tracking, calibration, anchoring, the
board's place in the room, and input. **A game only renders into board
space** and reacts to lifecycle hooks and board-space taps.

### Calibration (AR)

1. **Find a surface.** Sweep the phone over a textured table. The banner shows
   live tracking status (too dark, too fast, not enough detail...) plus
   feature-point and surface counts, drawn as an overlay on the video. After
   ~12 s without a surface, **Place in front of me** (about 0.6 m ahead, 0.35 m
   down) and **Play without AR** are offered.
2. **Trace the play area (recommended).** Tap **Trace play area** and run a
   finger around the edge of the table / board you want to play on. The first
   touch must land on a detected surface (or, where ARCore has no plane yet,
   within 60 cm of the reticle's surface); that sets the trace height. Every
   later point is projected onto that height (so you can trace right along a
   real edge). Dropped: points over a clearly higher object (> 4 cm), rays
   longer than 2.5 m, single stray jumps (> 30 cm in one step; three in a row
   are followed), and points whose ray hits no surface more than 15 cm from
   the last point that did. Lifting the finger and touching down again within
   15 cm continues the line; farther away starts a new outline (two strokes
   are never joined by a straight line). Feature-point dots are hidden while
   tracing. **Done** (or closing the loop) re-projects the stroke at the
   refined surface height (median of all stroke hits), the board is anchored
   to the detected surface under the outline's centre and auto-fitted (never
   bigger than the game's own size, rotated to the outline's long axis), and
   the outline stays visible while unlocked. The outline is kept for the
   session: the next game offers **Use traced area**.
   *Skip:* tap **Place here** (or the screen) to place on the reticle instead.
   The board is then fitted and kept inside the selected ARCore plane's
   boundary.
3. **Fit the edges.** The play area (the traced outline, or the detected
   surface) is shown with big round **corner handles** and bar-shaped **edge
   handles**. Drag them onto the real table edges where the outline is off: a
   corner moves one corner, an edge slides a whole side straight in or out.
   Drags are relative (the handle moves with the finger's motion on the
   surface), so the finger never has to cover the edge being lined up; the
   white dot marks the exact point. Moves that would fold the outline inside
   out or collapse it are refused. **Reset** starts over, **Done** (or Lock)
   commits it. The fitted outline becomes the play area: it clamps the board
   and box, the game's projector glow is clipped to it (nothing spills past
   the real edge), plane refreshes no longer change it, it survives pause /
   resume, and **Use traced area** reuses it. **Fit edges** in step 4 re-opens
   the stage.
4. **Adjust, then lock.** Drag to move, pinch to resize, twist to rotate. Drags
   project onto the selected surface's height only, and the footprint is
   clamped inside the traced area (or the plane): it stops at the edge instead
   of hanging off it. **Lock** starts the game. **Unlock** pauses it to adjust
   again; **Re-place** goes back to step 1. The glowing outline is the game's
   **play box**: floor edges on the surface, corner pillars fading upward and a
   faint top frame. If the game allows a range, the **Airspace** slider on the
   right edge sets the box height (saved per game, kept through pause /
   resume, Unlock and Re-place).

**Staying put once locked.** Lock re-anchors with a **plane-attached**
ARCore anchor (a hit test on the detected surface) right under the board's
centre (or a point of its footprint, if the centre is off screen), with the
board's drag, turn and scale baked into the placement, so the board does not
move and sits exactly at the plane's height. A plane-attached anchor moves
with the table when ARCore refines or relocalizes its map; a free anchor does
not, which is what made the board leave the table in the field (see below).
Only when no plane is hit under the board does Lock fall back to a free
anchor ("lock: no plane under board"); a locked board on a free anchor is
moved onto a plane anchor as soon as a plane is hit under it. After that the
board follows only that anchor's pose: never the camera, never plane
re-estimation (the play area is not re-clamped while locked), and the XR
origin is never moved. If the anchor stops tracking, the board holds its last
pose; when tracking returns, small ARCore corrections (< 3 cm) apply at once
and bigger ones ease in over ~0.1 s. If the *camera* loses tracking for over
0.5 s, the board is hidden ("Tracking lost") instead of sliding along with
the frozen camera, and comes back when tracking does.

**Anchor guard.** An anchor pose that jumps more than 10 cm (or turns more
than 15 degrees) at once is not shown. The board stays at its last trusted
pose ("Re-finding the table…") until the new pose has held still for 0.5 s,
then the detected planes decide:

- the table is still under the board's old spot at its height: the anchor
  alone jumped (ARCore relocalizing it to a wrong spot). The jump is
  rejected and the board is re-anchored on the plane at its old spot;
- only the new spot is on a plane: the whole world moved (planes too), so the
  jump is accepted and eased in;
- neither, but a plane is under the new spot: accepted and snapped onto that
  plane;
- no planes to judge by: accepted.

A jump that undoes itself is never shown. **Height guard:** a board locked
on a detected plane that then floats or sinks 3-25 cm against that plane for
1.5 s is re-anchored onto it (a board deliberately standing above the plane
at Lock, e.g. on an object ARCore did not map, is left alone).

**The field case (lg-test-d206a6e).** The reading was "anc T free d
0.0/646.6mm lock 647mm surf -12.9cm lost 1". Lock had swapped the reticle's
plane anchor for a free one, because the board was dragged off it (Fit edges
often does this). After a tracking loss, ARCore put that free anchor back
65 cm away and 13 cm low, and the board eased in after it. The board then
looked right only from the placement angle and went under the table from the
other side. `anchor_tests` replays those numbers.

If ARCore is not tracking yet, *Place in front of me* holds the board in front
of the camera (so it never slides away) and turns it into a world anchor
after one second of continuous tracking. To show the AR debug line: tap the
step panel **five times**, or, any time (also while playing), tap the small
**dbg** button under "‹ Games" or **hold the status line** (top right, e.g.
"X to play") for 1.5 s. It also appears by itself after the scan timeout and
in debuggable builds. While it is shown, the **tap probe** is on: every tap
draws a magenta dot where the finger touched and a cyan ring where the
board hit projects back to the screen (they should coincide).
The debug line also shows, once the board is placed:

- `anc T plane (lock: plane under board)`: anchor tracking (T tracking,
  P paused, S stopped), how it was made (`plane` = attached to a detected
  surface, `free` = world pose, `held` = camera-held, not anchored yet) and
  why (`reticle`, `outline on plane`, `lock: plane under board`, `lock: no
  plane under board`, `jump rejected, plane under board`, `height fixed to
  plane (-12.9cm)`, `upgraded free to plane`, ...);
- `d 0.2/3.1mm`: how far the anchor pose moved this frame / at most in the
  last 3 s; `lock 4mm`: how far the *board* has moved since Lock (should stay
  near 0; re-anchoring does not count);
- `anchor x,y,z` / `board x,y,z`: the raw anchor pose and the shown board
  centre in world metres (they coincide after Lock; they differ while a jump
  is held);
- `surf +0.3cm`: board height above the detected surface under its centre
  (once locked, against the plane it was locked on), `pl#0 h0.12`: that
  plane (index in ARCore's plane list this frame, and its height). A few cm
  off means the board floats over / sinks into the real surface, which looks
  like drifting as you walk around;
- `jump held 628mm`: an anchor jump being held back; `fix rej1 acc0 h0 up0`:
  jumps rejected / accepted, height fixes, free-to-plane upgrades; `lost N`:
  camera tracking losses;
- `area traced 0.42m²` / `area plane ...` / `area fitted ...`: the play area;
- `taps N/M · tap px 812,433 vp 1560x720 win 2340x1080 cs 1.50 xr-ray hit
  0.031,-0.046 err 0.2px cell 4`: taps that hit the board / taps seen, then
  the last tap: touch position (viewport px), viewport and window size,
  content scale, which ray maths was used, the board-space hit, how far the
  hit projects back from the touch, and what the game says is there. Every
  tap on the board also shows a short white ring where it landed.

**Screen rays.** All screen -> world rays (taps, drags, tracing, handles)
go through `ScreenRay`, which inverts the projection the frame is actually
rendered with. Do not use `Camera3D.project_ray_normal()` on the AR camera:
in Godot 4.4 `XRCamera3D` builds it from the XR projection's near-plane
extents but the camera's own `near` (the ARCore plugin fixes near at 0.1 m),
and assumes a symmetric frustum; with near 0.01 m that put rays ~50 degrees
off at the screen edges.

The game does not play while the board is being placed: `LGGame.is_playing()`
is true only when the board is locked and the app is in the foreground.

## The game contract

A game is a folder under `res://games/<id>/` with a `manifest.tres`
(`LGGameManifest`) and an entry scene whose root script extends `LGGame`.

**Manifest fields:** `id` (lower-case identifier), `display_name`,
`description`, `icon`, `min_players` / `max_players`, `board_size` (metres at
scale 1, x by z), `board_height` (tallest point, for camera framing), `entry`
(.tscn or .gd), `version`, `author`, `tags`, and the play box height:
`box_height` (preferred; 0 = `board_height`), `box_min_height` /
`box_max_height` (the range the player may pick; 0 = 2 cm / the platform cap).

**Board space** is the `LGGame` node's local space: the origin is the centre of
the board resting on the surface, +Y is up, 1 unit = 1 metre at placement
scale 1, and the footprint is `board_size` centred on the origin. Never move
cameras, XR nodes or the game node itself; the platform moves the board.

**The play box ("simulation box").** Every game plays inside a box in board
space: the floor is the chosen surface (y = 0), the footprint is `board_size`
(so the traced area, fit and the player's pinch-resize decide its real size
and rotation, through the placement scale), and the height is the game's
airspace. `get_box()` returns the `PlayBox` (never null; already set in
`_on_board_ready()`):

| `PlayBox` | |
| --- | --- |
| `size` | `Vector3(width, height, depth)`; `height()`, `footprint()` |
| `bounds()` / `center()` | `AABB` from `(-w/2, 0, -d/2)`; centre of the volume |
| `min_height` / `max_height` / `preferred_height`, `is_adjustable()` | the resolved, capped range |
| `contains(point, margin)` / `clamp_point(point, margin)` | inside test / nearest inside point |
| `intersect_ray(origin, dir)` | where a board-space ray enters the box (or null) |
| `ray_at_height(origin, dir, h)` | where it crosses y = h inside the footprint (or null) |

Shortcuts on `LGGame`: `box_contains(point)`, `clamp_to_box(point)`.
**Caps:** the height is clamped to `min(0.6 m, 1.5 x the footprint's long
side)` (board units, so it scales with the board) and is at least 2 cm. The
player's choice (the Airspace slider, shown only if min < max) stays within
the game's range; it is saved with the placement (`box_height`, -1 = the
game's preferred height).

**Hooks** (all optional):

| Hook | When |
| --- | --- |
| `_on_board_ready()` | Added to the board, not placed or playing yet. Build your scene. |
| `_on_board_locked()` / `_on_board_unlocked()` | Player locked / unlocked the board (fallback counts as locked). |
| `_on_resumed()` / `_on_paused()` | `is_playing()` changed: run or freeze timers, AI, animation. |
| `_on_board_tap(point: Vector3)` | A tap hit the board's tap surface (board space; returned with y = 0). Only while playing. |
| `_on_board_drag(from, to)` | One-finger drag in board space, if `captures_drag()` returns true. |
| `_on_box_ray(origin, direction)` | Every tap while playing, as a board-space ray, just before `_on_board_tap`: pick things in the airspace (`get_box().intersect_ray()`, `ray_at_height()`, your own geometry). |
| `_on_box_changed(box: PlayBox)` | The player changed the airspace height (after `_on_board_ready`; also the `box_changed` signal). Re-fit anything tied to the top. |
| `_on_exit()` | Player is leaving the game. Save here. |

**Helpers:** `is_playing()`, `is_board_locked()`, `get_board_size()`,
`is_on_board(point)`, `set_status(text)` (shown by the platform while
playing; hidden during AR calibration, prefixed "Paused" otherwise),
`request_exit()` (back to the catalog).

**Raised boards:** override `board_surface_height() -> float` (board space,
metres at scale 1) when the surface players tap is above the table, e.g. a
floating slab. The platform casts the finger's ray onto that plane (kept
inside the box); at a low phone angle, a 2.6 cm slab tapped on the table
plane would be off by about a third of a tic-tac-toe cell.

**Box outline while playing:** hidden by default; override
**Debug naming:** `describe_point(point) -> String` names a board-space point
for the debug line / tap probe (Tic-Tac-Toe returns "cell 4").

**Glow clipping:** every `Holo.disc_material` (glow bases, ripples) is
clipped by the platform to the play area's real outline (`Holo.set_clip`);
games need do nothing.

`box_outline_while_playing() -> float` (0 hidden .. 1 as bright as while
adjusting) to keep it on dimly. Tic-Tac-Toe uses 0.35.

**The sample games:** Tic-Tac-Toe declares a small airspace (20 cm, 12-30 cm)
and its pieces drop from inside the box top (a lower box means a shorter
drop). It plays on a **3x3, 4x4 or 5x5** board, needing **3, 4 and 4 in a
row** (`TicTacToeRules.win_length_for`; three in a row on the bigger boards is
a quick first-player win, five on 5x5 nearly always a draw). The size is
picked on a hologram **options strip** lying on the table at the player's
edge of the board (3×3 · 4×4 · 5×5 · Reset score; it moves to whichever side
you stand on). Sizes change between rounds only: before the first move or
after a round ends. The grid always fills 27 cm of the 30 cm board, so the
cells, pieces, ripples and win line shrink with the size (9 / 6.75 / 5.4 cm
cells); the board footprint, play box and drop heights stay the same. A
hologram **scoreboard** (X wins / O wins / draws) floats at the far edge
beside the turn token. It counts every finished round for the whole app
session (across rounds, sizes and leaving / re-opening the game) until
**Reset score** is tapped. Competitive Evolution declares a tall box for its 42 cm globe (58 cm,
50-60 cm) and keeps its label under the top.

### Hologram look (`platform/visual/`)

Games share one projected-hologram style ("Card Wars" style) through `Holo`
and `HoloDrop`. Everything is unlit, alpha-blended without depth writes (keeps
its colour over a bright camera image, never needs lights), uses two small
Compatibility-renderer shaders and no textures, so it stays cheap on a
mid-range phone.

| Helper | What |
| --- | --- |
| `Holo.material(color, fill, rim, intensity)` | See-through body: faint fill, fresnel rim, screen scanlines, a sweep band, faint flicker; `flash` parameter for hits. |
| `Holo.line_material(color, intensity)` | Solid glowing lines and edges. |
| `Holo.glow_base(board_size)` | Soft projector glow (with a faint grid) on the table under the board. |
| `Holo.bar(from, to, thickness, material)` | A glowing bar between two points (grid lines, frames, win lines). |
| `Holo.ripple(color, radius)` | Landing ring, animated by `HoloDrop`. |
| `PlayBoxOutline` | The platform's box outline (16 thin bars, 5 shared materials); `set_level(0..1)`. |
| `HoloDrop.start(body, height, ripple)` | Drop-in: gravity fall, squash and spring on landing, flash, ripple; signals `landed` / `finished`. `HoloDrop.curve(t, height)` is pure for tests. |
| `Holo.CYAN`, `MAGENTA`, `GOLD`, `GREEN` | The palette. |

Materials are new instances, so animating one piece (flash, intensity) never
touches another. Shaders: `holo.gdshader` (surfaces) and `holo_disc.gdshader`
(flat glows, ripples). Tic-Tac-Toe is the worked example: a slab floating
2.6 cm over the glow, emissive grid, 3D X (crossed bars) and O (torus) that
drop in, a gold win line, and a small spinning turn token on the far edge.

### Add a game

1. Create `games/my_game/my_game.gd`:

   ```gdscript
   class_name MyGame
   extends LGGame

   func _on_board_ready() -> void:
       var tile := MeshInstance3D.new()
       tile.mesh = BoxMesh.new()
       (tile.mesh as BoxMesh).size = Vector3(0.1, 0.02, 0.1)
       tile.position.y = 0.01   # rest on the surface
       add_child(tile)
       set_status("Tap the board")

   func _on_board_tap(point: Vector3) -> void:
       set_status("Tapped %.2f, %.2f m from the centre" % [point.x, point.z])
   ```

2. Create `games/my_game/my_game.tscn` with a `Node3D` root using that script
   (or point `entry` straight at the `.gd`).
3. Create `games/my_game/manifest.tres` (an `LGGameManifest`): set `id`,
   `display_name`, `board_size`, `entry`, players. See
   `games/tic_tac_toe/manifest.tres`.
4. Run the project. The launcher picks it up automatically. Invalid manifests
   are skipped with a warning that explains why.

## Running and testing

Open the project in Godot 4.4.1 and run it: on desktop the launcher opens and
games play with an orbit camera (drag to orbit, wheel / pinch to zoom). If the
editor warns that Vulkan is not supported, use the Compatibility renderer.

Headless tests (no device needed; a fake ARCore bridge drives calibration):

```bash
GODOT=/path/to/godot-4.4.1 tools/run_tests.sh
# or one suite:
godot --headless --path . res://tests/ar_tests.tscn
```

Suites: `smoke_test` (boot, launcher, every game launches), `platform_tests`
(manifests, catalog, LGGame contract, launching onto the board, input
routing in board space, AR launch lifecycle), `ar_tests` (AR layer ported from
AGR: anchors, placement, gestures, calibration, the board not following the
camera), `surface_tests` (play area: plane selection, tracing, clamping, a
plywood-on-driveway scene model, screen-touch taps), `field_tests` (phone
field-test regressions: Android touch sequences, trace robustness, world lock
under camera motion / plane refinement / tracking loss, drift readout, the
hologram board), `touch_tests` (the phone touch path: an ARCore-style XR
projection, a 2340x1080 window with content scale, touches as window pixels,
every cell from several poses; tap slop, tap probe, in-game debug access),
`fit_tests` (Fit edges: handle maths, the stage, touch drags onto the real
edge, Reset / Done, board clamping, glow clipping, persistence),
`anchor_tests` (plane-attached re-anchoring at Lock with drag / turn /
scale, the free fallback and upgrade, the field relocalization jump, real
world shifts, self-undoing jumps, the height guard, the debug readout),
`ttt_tests` (tic-tac-toe 3x3 / 4x4 / 5x5 rules and win lengths, the options
strip, scoreboard and reset, session persistence, taps and drops on every
cell at every size, AR taps on 5x5), `box_tests` (the play box: maths and caps, manifest limits,
the game API and hooks, the Airspace slider, persistence across pause /
resume / re-place / sessions, outline levels, tap rays, the games' boxes).
Leaked-RID messages at exit are harmless.

## Android build

### 1. Build the ARCore plugin (once)

The plugin is GodotVR's [godot_arcore](https://github.com/GodotVR/godot_arcore)
patched with plane hit tests, anchors, diagnostics, and a projection fix that
matches the camera image Godot stretches over the screen
(`tools/arcore_plugin/lg-arcore.patch`). Its binaries are gitignored.

Needs git, python3 + scons, JDK 17, and an Android SDK with
`platforms;android-33`, `build-tools;33.0.2`, `cmake;3.22.1`,
`ndk;23.2.8568313`.

```bash
ANDROID_HOME=/path/to/sdk GODOT_BIN=/path/to/godot-4.4.1 \
  tools/arcore_plugin/build_arcore_plugin.sh
```

This installs `addons/ARCorePlugin/bin/` and `plugin.gdextension`. The Linux /
Windows editor then logs "No GDExtension library found for current OS" for
this Android-only plugin; that is expected.

### 2. Export a release (non-debuggable) APK

Install the Godot 4.4.1 export templates and set the Android SDK and JDK in
Editor Settings. Export with the **Android AR** preset (Gradle build, min SDK
24, arm64-v8a, camera permission, ARCore *required*).

**Always export release builds for phones.** On Samsung phones with Google
Play Services for AR 1.52+, ARCore barely tracks in a *debuggable* app: no
feature points, no planes, drifting anchors
(google-ar/arcore-android-sdk#1750, #1757). A Godot debug export is always
debuggable. For sideloaded test builds, sign the release export with the
Godot debug keystore through environment variables, so no secrets go in the
repo:

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/.local/share/godot/keystores/debug.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android
godot --headless --path . --install-android-build-template \
  --export-release "Android AR" build/looking-glass-ar.apk
```

Hold the phone sideways: the app is landscape only (it matches the plugin's
camera rotation).

## Roadmap

- Confirm the anchoring fix on a phone (board on the table, not following
  the camera).
- Import Competitive Evolution's simulation and views into its adapter.
- Multiplayer: share the anchor through ARCore Cloud Anchors
  (`AnchorService.host_anchor()` / `resolve_anchor()` are stubbed) plus the
  anchor-relative placement; games stay in board space, so nothing else in
  the scene has to be shared.
- Creator uploads: register downloaded manifests through `GameCatalog`
  (sandboxing and review still to be designed).

## License

Not chosen yet.
