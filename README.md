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
  game/lg_game.gd         LGGame: base class every game extends (the contract)
  game/lg_game_manifest.gd  LGGameManifest: catalog entry resource
  game/game_catalog.gd    registers manifests found in res://games/*/manifest.tres
  ar/ar_session.gd        AR mode, calibration, anchoring, lock / unlock
  ar/calibration_flow.gd  pure state machine: scan -> place -> adjust -> lock
  ar/calibration_hud.gd   calibration UI (big buttons, status, debug line)
  ar/arcore_bridge.gd     dynamic wrapper around the patched ARCore plugin
  ar/anchor_service.gd    the one world anchor (+ Cloud Anchor stub for multiplayer)
  ar/board_placement.gd   player's offset / rotation / size, saved per game
  ar/gesture_tracker.gd   tap / drag / pinch+twist from raw touches
  ar/surface_region.gd    play-area polygon: fit / clamp the board footprint
games/
  tic_tac_toe/            sample game
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
      BoardFrame       footprint outline, shown while adjusting
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
   touch must land on a detected surface; that sets the trace height. Every
   later point is projected onto that height (so you can trace right along a
   real edge), and points over a clearly higher object are dropped. **Done**
   closes the outline (at least 3 points), the board is auto-fitted (size up to
   2x the game's native size, rotated to the outline's long axis) and the
   outline stays visible while unlocked. The outline is kept for the session:
   the next game offers **Use traced area**.
   *Skip:* tap **Place here** (or the screen) to place on the reticle instead.
   The board is then fitted and kept inside the selected ARCore plane's
   boundary.
3. **Adjust, then lock.** Drag to move, pinch to resize, twist to rotate. Drags
   project onto the selected surface's height only, and the footprint is
   clamped inside the traced area (or the plane): it stops at the edge instead
   of hanging off it. **Lock** starts the game. **Unlock** pauses it to adjust
   again; **Re-place** goes back to step 1.

If ARCore is not tracking yet, *Place in front of me* holds the board in front
of the camera (so it never slides away) and turns it into a world anchor
after one second of continuous tracking. Tap the step panel **five times** to
show the AR debug line (it also appears by itself after the scan timeout and
in debuggable builds).
The debug line also shows the play-area source and size (`area traced 0.42m²`
/ `area plane ...`) and tap counters (`taps N/M last x,z`: taps that hit the board / taps
seen, last board-space point). Every tap on the board shows a
short white ring where it landed.

The game does not play while the board is being placed: `LGGame.is_playing()`
is true only when the board is locked and the app is in the foreground.

## The game contract

A game is a folder under `res://games/<id>/` with a `manifest.tres`
(`LGGameManifest`) and an entry scene whose root script extends `LGGame`.

**Manifest fields:** `id` (lower-case identifier), `display_name`,
`description`, `icon`, `min_players` / `max_players`, `board_size` (metres at
scale 1, x by z), `board_height` (tallest point, for camera framing), `entry`
(.tscn or .gd), `version`, `author`, `tags`.

**Board space** is the `LGGame` node's local space: the origin is the centre of
the board resting on the surface, +Y is up, 1 unit = 1 metre at placement
scale 1, and the footprint is `board_size` centred on the origin. Never move
cameras, XR nodes or the game node itself; the platform moves the board.

**Hooks** (all optional):

| Hook | When |
| --- | --- |
| `_on_board_ready()` | Added to the board, not placed or playing yet. Build your scene. |
| `_on_board_locked()` / `_on_board_unlocked()` | Player locked / unlocked the board (fallback counts as locked). |
| `_on_resumed()` / `_on_paused()` | `is_playing()` changed: run or freeze timers, AI, animation. |
| `_on_board_tap(point: Vector3)` | A tap hit the board plane (board space, y = 0). Only while playing. |
| `_on_board_drag(from, to)` | One-finger drag in board space, if `captures_drag()` returns true. |
| `_on_exit()` | Player is leaving the game. Save here. |

**Helpers:** `is_playing()`, `is_board_locked()`, `get_board_size()`,
`is_on_board(point)`, `set_status(text)` (shown by the platform),
`request_exit()` (back to the catalog).

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
camera). Leaked-RID messages at exit are harmless.

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
