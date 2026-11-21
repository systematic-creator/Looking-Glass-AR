# Mage Run: design doc

Status: **first playable (silent) on the `mage-run` branch**: milestones
M4-M6 plus a first art pass and the staff power-ups are in
`games/mage_run/` (see [section 11](#11-implementation-milestones) and
[11.1](#111-first-playable-as-built)). This document is the
plan for a medieval fantasy three-lane endless runner on the Looking Glass
platform, plus the platform work it needs. That platform work (milestones
M1-M3: per-game screen orientation, smooth rotation, ARCore in portrait,
screen-space swipes) is **implemented on the `mage-run` branch** with
headless tests; the parts only a phone can prove are listed in
[section 10.6](#106-device-checks-still-needed).

**Decisions (answered by the user):**

1. **Rows:** the ground plus **2 holographic "arcane rows"**, each with 3
   lanes: 9 lanes in total. The doc and the UI call them *arcane rows*.
2. **Orientation:** every game works in **either** orientation unless its
   manifest explicitly opts out (`orientation`, default `"either"`).
   Tic-Tac-Toe and Stack Tower are `either` now (portrait HUDs done), and so
   is Tattoo Studio once it gets its portrait layout on the `3d-model-game`
   branch.
3. **Rotating mid-run:** platform rule: every game gets an
   orientation-changed callback; Mage Run **pauses** there and resumes with
   a countdown.
4. **Audio:** not needed for now; **out of scope for the first playable**.

![Style reference](mage-run/reference.jpg)

*`docs/mage-run/reference.jpg` is a **style reference only**, picked by the
user as the target look. It is not a shipped asset and must not be packaged,
traced or used as a texture. Every shipped model, texture and sound is made in
code or comes from a CC0 source (see [Assets and licensing](#assets-and-licensing)).*

![Chosen direction: solid storybook road with arcane (hologram) rows](mage-run/concept-combined.jpg)

*`docs/mage-run/concept-combined.jpg` is a generated concept mockup of the chosen direction (solid storybook world plus hologram-look upper rows, the *arcane rows*). Mood only, not to scale; in-game the arcane rows sit directly above the road lanes.*

---

## 1. Concept

A wizard in a blue robe and a starry pointy hat runs down a cobblestone and
plank road on a small **storybook diorama** that sits on the player's real
table or floor, away from the player. The road has no building at either
end: it is **cut off clean** at the board's far and near edges, and
obstacles slice into view at the far cut. Fences and logs to jump, banners
to slide under, striped barriers to jump or slide, and walls, crates,
barrel mine-carts and royal carriages to dodge stream toward the player. The player dodges them with fast swipes (left / right to change
lane, up to jump, down to slide) and grabs gold star coins. As the run goes
on, **glowing cyan hologram rune-stone platforms** appear *above* the solid
road: the two **arcane rows**. They are new rows of lanes (3 lanes each, so
9 lanes in all), and the run gets taller as well as faster.
Coin lines arc up onto them (risk and reward: the high line pays more but
the platforms can collapse).

The pitch in one line: *Subway Surfers timing, on a tabletop diorama, with
hologram floors that stack up the further you get.*

Pillars:

1. **Swipe timing first.** Inputs are buffered and forgiving, and every
   obstacle shows clearly what it needs by its shape (four classes: jump,
   duck, either, dodge; section 5).
2. **Readable at table size.** The whole run fits in a small play box seen
   from about 0.5-1 m away; silhouettes and colour do the work, not detail.
3. **Solid world, arcane rows.** The opaque warm diorama is the ground
   truth; translucent cyan rows are clearly "magic" and clearly a different
   floor.
4. **The room stays visible.** No side rows of houses, no skybox walls: it is
   a diorama in your room.

---

## 2. Board, box and placement

### Footprint and orientation

- The road runs along the board's **long axis, away from the player**
  (board space -Z is "ahead", toward the far cut; +Z is the near end where the
  wizard runs, toward the player).
- **`board_size`: 0.30 m x 0.90 m** (x = width, z = depth) at placement
  scale 1 (as built; first proposed 0.30 x 0.60 m, lengthened for reaction
  distance). On a table that is a 30 x 90 cm diorama. On the floor the
  player scales it up (the platform's placement scale), for example x3 to
  0.9 x 2.7 m.
- The road (3 lanes) is about 0.22 m wide, on a rounded stone base 0.28 m
  wide, leaving a thin margin of base and grass to the footprint edge.

### Play box

- Manifest uses **`tall_box = true`**: the cap is `min(3.0 m, 4 x long side)`
  = 3.0 m for a 0.9 m board. Mage Run does not need that much; it wants
  headroom for the 2 arcane rows and jump arcs.
- **Airspace: `box_height` 0.40 m, `box_min_height` 0.40 m,
  `box_max_height` 0.70 m** (as built: the minimum is 0.40 m because a jump
  from Arcane II with the hat on reaches 0.20 + 0.11 + 0.072 m above the
  0.008 m base). Rows sit at fixed fractions of the default
  layout (see section 3), so a lower box only trims the sky above the top row
  (jump arcs, particles).
- `board_height` 0.25 m (camera framing in "Play without AR").
- `box_outline_while_playing()` returns about **0.15** (at most a faint
  outline; the brief asks for at most that).

### Streaming and the box edge

- The world is a treadmill: the wizard stays near the **near third** of the
  board (z +0.30 m on the 0.90 m board) and the world scrolls toward +Z.
- **Clean cut (as built):** there is no castle or gate. The stone base and
  road end with a hard edge at the **far cut** (z -0.445 m) and the **near
  cut** (z +0.445 m). Every content material (props, coins, tiles, ramps)
  is a shader that discards fragments beyond the two cut planes (world-space
  planes updated each frame from the board transform), so an item **slices
  in** at the far cut as it scrolls onto the road and **slices out** at the
  near cut, at full size, like a cross-section. Items are created a little
  beyond the far cut (out of sight) and removed after passing the near cut.
  Nothing is drawn outside `PlayBox.contains()` (tests check the clipped
  bounds of every item, as with Stack Tower debris).

### Placement flow

- The standard Looking Glass calibration: trace or pick a surface, fit
  edges, adjust the airspace, lock. Mage Run adds nothing.
- The default rotation puts the far cut **away from the player**:
  the board's -Z faces away from the camera at Lock. If the player rotated
  the board, the game still runs along board -Z (the player chose the view).
- Recommended AR viewing: phone in **portrait**, held at chest height, about
  0.7-1.0 m from a table diorama, looking down 25-40 degrees.

---

## 3. Lanes and rows

### Ground (row 0)

- 3 lanes, x = -0.075, 0, +0.075 m (lane pitch 0.075 m at scale 1).
- The wizard's collision capsule: radius 0.022 m, height 0.06 m (a 6 cm
  wizard on a table).

### Arcane rows (rows 1-2)

- **Decided: ground + 2 arcane rows, 3 lanes each: 9 lanes** (3 lanes x 3
  rows). There is no third arcane row. "Arcane row" is the name in the doc,
  the code and the UI (for example "Arcane I" / "Arcane II" in the HUD's
  row indicator); "hologram" only describes their look.
- Arcane rows are **translucent cyan rune-stone platforms** made of tiles
  (one tile per lane per segment, about 0.075 x 0.10 m), floating above the
  road.
- Heights: row 1 (Arcane I) at **+0.10 m**, row 2 (Arcane II) at
  **+0.20 m**. With jump arcs this fits the 0.40 m default
  box with room to spare.
- **Unlock by distance** (in metres run, world units at scale 1; tuned in
  playtests):

  | Distance | Unlocks |
  | --- | --- |
  | 0 m | Ground only |
  | 150 m | Row 1 segments start appearing (short, 2-4 tiles long) |
  | 400 m | Row 1 long runs; row 2 segments start |
  | 800 m+ | Rows 1-2 common, multi-row coin arcs, collapsing platforms |

- Rows are **not continuous floors**. They are segments over parts of the
  road, so the ground stays the default.

### Reaching and leaving rows

| Way up / down | How it works |
| --- | --- |
| **Swipe up under a row** | A jump from row N reaches row N+1 if a platform tile is overhead in that lane during the jump's top window (the jump apex is tuned to clear exactly one row: about 0.11 m). |
| **Ramps** | A glowing rune ramp on row N leads up to row N+1. Running onto it lifts the wizard automatically, with no input needed. |
| **Levitation power-up** | Lifts to the highest unlocked row for its duration (see power-ups). |
| **Swipe down on a row** | Drops to the row below (a short fall, then a landing squash). On the ground, swipe down is a slide. |
| **Run off the end** | When a segment ends, the wizard falls to the row below and lands safely. Falling is never a death by itself. |
| **Collapsing platforms** | Cracked tiles (a flickering, red-tinted rune) crumble 0.4 s after the wizard steps on them, dropping them a row. They are marked and always used for risk-reward (coins on them). |

Fairness rule: a row segment never ends directly above an obstacle that the
falling wizard cannot avoid. There is at least 0.25 s of clear ground
(at current speed) under every segment end.

### Camera and readability of rows

- In AR the player's own phone is the camera. Rows are spaced 0.10 m apart
  so that, at a typical 30 degree look-down, each row is visibly offset on
  screen.
- A soft cyan **drop shadow / rune ring** is projected onto the road under
  the wizard when on an arcane row, so depth reads.

---

## 4. Controls

### Gestures

| Swipe | Ground | On an arcane row |
| --- | --- | --- |
| Left / right | Change lane (0.12 s lateral move) | Change lane (only onto a tile; otherwise a blocked "bump" and stay) |
| Up | Jump (apex 0.11 m, 0.55 s airtime at base speed) | Jump (can reach the next row) |
| Down | Slide (0.6 s, low capsule) | Drop to the row below |
| Tap | (AR: nothing; see disambiguation) | Same |
| Double-tap / staff button | Fire the staff power-up when the meter is full | Same |

### Swipe detection (screen space)

Swipes are read in **screen space**, not board space: a runner's input must
not depend on where the board is on screen or on the AR camera angle.

- A swipe is a single-finger stroke whose displacement passes
  **`SWIPE_MIN = 0.28 in`** (inches, converted with the screen DPI the way
  GameHost already sizes its tap slop: about 45 px at 160 dpi, about 120 px
  at 420 dpi) **within `SWIPE_MAX_TIME = 0.25 s`** of touch-down.
- The direction is the dominant axis, if it is **at least 1.4x the other
  axis**. Otherwise it waits until it is (diagonal strokes resolve as soon as
  they lean far enough).
- **Fire on threshold, not on release:** the swipe triggers as soon as it
  crosses the threshold, so fast players are not delayed by lift-off. The
  rest of that stroke is ignored (one swipe per stroke), unless the finger
  reverses by another full threshold (an "S" stroke = two swipes, allowed
  for left-right corrections).
- Directions are mapped **relative to the screen in its current
  orientation**: up is toward the top of the screen as held, after rotation
  (see section 9).

### Timing windows and buffering

- **Input buffer: 0.15 s.** A swipe that arrives while an action cannot
  start (mid-jump, mid-lane-change) is queued and fires the moment it can,
  if still within 0.15 s.
- **Coyote time: 0.08 s.** A jump just after running off a platform edge
  still counts as jumping from it.
- **Lane-change cancel:** swiping the opposite way mid-change reverses it
  (no buffer needed).
- **Jump to slide:** swiping down mid-jump "slams" down fast (0.12 s) and
  then slides (Subway Surfers feel).
- All timing is in **game time** (paused with `_on_paused`, scaled by
  speed where noted); swipe detection uses real time.

### Swipe vs AR tap disambiguation

- While playing, Mage Run **captures all single-finger strokes** (a new
  `captures_swipes()` hook, see section 9). The platform does not use them
  for camera orbit.
- A touch that ends within the tap slop and under 0.25 s is a **tap**.
  Taps do nothing in the run (no accidental actions), except on HUD buttons
  (pause, staff), which are game UI (`is_over_game_ui`) and never reach the
  board.
- Two fingers are never a swipe (pinch stays reserved; the run ignores it,
  and outside AR the platform may zoom).
- During calibration, Adjust and the unlocked state, the platform owns touch
  as today; the game sees no input (`is_playing()` is false).
- An optional **"Tap to jump" accessibility setting** (open question)
  would map taps to jump, using the left / right third of the screen for
  lane changes.

---

## 5. Obstacles, coins and power-ups

### Obstacle types

As in Subway Surfers, every ground obstacle belongs to one of **four
classes**, and its shape says which (`MageTrack.obstacle_class()`; the
validator checks each class against the real move set at the base and top
speeds, section 6):

| Class | Obstacle | Answer | Look (board size at scale 1) |
| --- | --- | --- | --- |
| **Jump** | **Wooden fence** (1 lane) | Jump only (it is too low to slide under) | Brown posts and rails, 3.5 cm high |
| **Jump** | **Fallen log** (1 lane) | Jump only | A round log on the road, 3.2 cm high |
| **Duck** | **Hanging banner / beam** (1 lane) | Slide only (the gap is 3.5 cm high; a jump hits the beam) | A wooden beam on two posts with a royal blue banner, top 13 cm |
| **Either** | **Striped barrier** (1 lane) | Jump over **or** slide under | A red and white striped board on two legs, from 3.5 to 6.2 cm |
| **Dodge** | **Stone wall** (1 lane) | Change lane | A grey stone wall section with a blue banner, 14 cm high |
| **Dodge** | **Crate stack** (1-2 lanes, long) | Change lane | Stacked crates, rope-bound, 9 cm high |
| **Dodge** | **Barrel mine-cart** (moving) | Change lane (it rolls toward you at 0.4 run m/s, faster than the road) | Wooden cart full of barrels |
| **Dodge** | **Royal carriage** (2 lanes wide, tall) | Change lane, or jump onto its roof (a "platform" obstacle; reachable from the ground only near top speed) | Gold and white carriage with blue crystals; the roof is walkable |
| **Rune gap** (arcane rows only) | Jump, or drop | A missing tile |
| **Cracked rune tile** | Do not stop on it (crumbles after 0.4 s) | Flickering red-tinted rune |

Collision rule: hitting the front of a blocking obstacle ends the run
(unless shielded). Clipping the side during a lane change "stumbles":
a short slow-down, and two stumbles in 3 s end the run (Subway Surfers'
forgiveness).

### Coin lines and risk-reward

Gold star coins (spinning, about 0.02 m) come in lines of 5-12:

- **Straight line** in a lane (safe, low value).
- **Lane weave** (a curve across lanes) that teaches lane changes.
- **Jump arc** over a fence or log (coins at the apex reward good timing).
- **Ramp arc** from the ground up onto an arcane row (the main risk-reward:
  up there coins are worth **x2 on row 1 and x3 on row 2**, but tiles may
  crack and segments end).
- **Carriage roof run**: coins along a carriage's roof (reached by jumping
  on it).
- **Bait line**: a line ending at an obstacle with a timed escape (only at
  higher difficulty, always escapable with the reaction time below).

Rule: **a coin line never requires an impossible input.** Each line is
built from the same input-timing model as the obstacles (section 6).

### Staff power-up meter

- The HUD's **staff meter** fills with coins (each coin +1, a full meter is
  50) and with "perfect dodges" (a near-miss lane change: +3).
- When full, the staff glows. Double-tap the screen or tap the staff icon to
  cast. The power-up cast is picked by the run state, or the player cycles it
  with a long press (open question).

| Power-up | Effect | Duration |
| --- | --- | --- |
| **Magic shield** | A blue bubble absorbs one crash | 12 s or 1 hit |
| **Coin magnet** | Coins within 1.5 lanes fly to the wizard | 10 s |
| **Levitation** | Floats to the highest unlocked row; tiles cannot crack under the wizard; the drop at the end is safe | 8 s |
| (later) **Blink** | Passes through the next obstacle | 1 use |

Rare **field pickups** (a floating rune) give an instant power-up without the
meter, as in Subway Surfers.

---

## 6. Difficulty and procedural generation

### Speed curve

- Base speed **1.2 m/s** (run metres; with 0.20 board m per run metre the
  road moves 24 cm/s on the board), rising to **2.6 m/s** at about 2000 m:
  `speed = 1.2 + 1.4 * (1 - exp(-distance / 900))`.
- Spawn density, obstacle mix and row frequency step up at the distance
  thresholds in section 3.

### Chunks

- The road is built from **hand-authored chunk templates** (data, not
  scenes), 1.2-2.4 m long each (2-4 board lengths). A chunk is a grid of
  `lane x row x slot` (slot = 0.10 m) with obstacle, coin-line, ramp and
  tile entries.
- Templates are tagged: difficulty band (1-5), rows used (0 / 0-1 / 0-2),
  and an "entry lane set" and "exit lane set" (which lanes are safe to be in
  at its start and end).
- The generator picks the next chunk from the current band, whose entry
  lanes include at least one exit lane of the previous chunk. It also mirrors
  chunks left / right at random, for variety.
- A **seeded RNG** per run (seed shown on the game-over screen, for bug
  reports and a future "daily run").

### Fairness rules (enforced by a validator, unit-tested)

1. There is **always at least one safe path** through every chunk *and*
   across chunk joins. The validator walks a lane x row state machine with
   the player's actual move set and timings at the chunk's max speed.
2. **Reaction time:** a new obstacle is visible (past the far cut) at
   least **1.0 s** before the wizard reaches it at the current speed
   (as built: 1.24 s at 2.6 m/s against a cart; the first proposal was
   0.75 s).
3. **At most two consecutive inputs** required within 0.35 s.
4. **No blind lane changes:** a lane is never blocked in a way only visible
   from directly behind.
5. **Arcane-row segments** end over at least 0.25 s of clear ground.
6. **Cracked tiles** only appear with an intact tile within one lane change.
7. **No unbeatable coin lines** (section 5).
8. **Obstacle classes are honest** (as built): a jump obstacle can be
   jumped and not slid, a duck obstacle slid and not jumped, an either
   obstacle both, and a dodge obstacle neither (only the carriage roof may
   be jumped onto). Templates that break their class are rejected, and
   layouts with no lane free of dodge obstacles at a given moment are
   rejected by the safe-path search.

### World scale vs board scale

The gameplay world is measured in "run metres", and the board shows a
window onto it. **As built: 1 run metre = 0.20 m of board depth** at
placement scale 1 (`MageTrack.RUN_TO_BOARD`; the first build used 0.16,
the first proposal 0.25). Items slice in at the far cut (z -0.445) and the
wizard runs at z +0.30, so 3.7 run metres are visible ahead: at the 2.6 m/s
top speed with a cart rolling at 0.4 m/s that is 1.24 s, over the 1.0 s
reaction rule (a unit test checks it). Obstacles are 25% larger on the
board than in the first build. The speed numbers above are in run
metres per second.

---

## 7. Scoring

- **Score** = distance (run metres) x **multiplier**, plus coin bonuses.
- **Multiplier**: starts at x1; +1 for each mission or "streak" (for
  example 20 coins without a stumble), up to x5 for the run. Also x2 while
  on row 1 and x3 on row 2, applied to coins only.
- **Coins** are counted separately (a currency for future cosmetic unlocks:
  hats, robe colours, trail colours).
- **Session best** and an all-time best (saved to `user://`, unlike the
  session-only bests in the other sample games).
- Game over: distance, coins, score, best, seed, with **Restart** and
  **Back to games**.

---

## 8. Art direction

### Look: solid storybook diorama + arcane rows

- **Solid** (the default for the world): opaque, softly lit, stylized
  low-poly with warm colours: cobblestones (grey-beige), planks (honey
  brown), a rounded grey stone base with moss green edges, a gold and white
  carriage with blue crystals, red-brown crates, dark barrels, grey stone
  walls, red and white striped barriers.
- **Arcane rows**: translucent, additive-glow cyan rune-stone tiles using
  the platform's Holo kit (`Holo.material`, edge lines, scanlines and
  sweep) with carved rune glyphs (procedural decals) and a soft flicker.
  They are the only see-through elements in the scene, which keeps the two
  layers distinct.
- **Wizard**: a blue robe, a dark blue pointy hat with gold stars, a white
  beard, a staff with a glowing tip, and a **blue sparkle trail** (a CPU
  particle ribbon behind the feet, using `HoloSplash`-style additive motes).
- **No side rows of houses**, no walls or skybox. Beyond the stone base it
  is the real room (AR camera image) or the platform's plain backdrop
  outside AR. The road just stops at a clean cut at each end.
- **At most a faint box outline** (about 0.15) while playing.

### Ties to the Hologram / Solid style system

Stack Tower introduced a per-game **Hologram / Solid** style toggle
(`StackTowerGame.Style`, `session_style`). Mage Run reuses the idea with a
different split:

- **World props**: Solid by default. A "Hologram world" option renders
  props with `Holo.material` for players who want the all-hologram look.
- **Arcane rows**: always Hologram (gameplay meaning: "magic floor").
- Proposal: lift the style enum and the material helpers (`solid_material`,
  outline hull, `holo_material`) from Stack Tower into
  `platform/visual/` (for example a `HoloStyle` helper), so both games share
  them.

### Budget (mid-range Android, gl_compatibility)

Target device: a 2021-2022 mid-range phone (Adreno 610-619 / Mali-G57
class) at 60 fps, with ARCore camera passthrough already costing a share
of the GPU.

| Item | Target |
| --- | --- |
| Draw calls (3D, visible) | **<= 120** (hard cap 160) |
| Triangles on screen | **<= 60k** (hard cap 90k) |
| Wizard | <= 2.5k tris, 1 material (vertex colours), simple bone or procedural animation |
| Prop | 100-800 tris, vertex colours, no unique textures |
| Road chunk | Merged into one mesh per chunk (cobbles + planks + base), <= 3k tris |
| Coins | One `MultiMeshInstance3D` for all coins (1 draw call) |
| Hologram tiles | One `MultiMesh` per row (1-2 draw calls), additive, no depth write |
| Particles | CPUParticles3D only (trail <= 40 motes, coin sparkle <= 24) |
| Textures | At most one small shared atlas (256-512 px) for rune glyphs and the star decal; everything else is vertex colours |
| Lights | The host's sun + ambient; no shadows from props (a baked blob shadow quad per moving object) |
| Post-processing | None (no glow pass in gl_compatibility); "glow" comes from additive materials |

### Assets and licensing

- All models are **built in code** (like Tattoo Studio's procedural bodies
  on the `3d-model-game` branch, and Stack Tower's blocks): boxes, cylinders, lathed profiles and
  extrusions with vertex colours.
- Optional **CC0** packs (for example Kenney's CC0 medieval and fantasy
  kits) may be used for props, kept as glTF under
  `games/mage_run/models/` with a `LICENSES.md` entry per file (source URL,
  author, CC0 statement).
- **No copyrighted assets**, no assets from Subway Surfers or other games,
  and the reference image is never shipped.

---

## 9. Audio notes

**Decision: audio is out of scope for the first playable** (milestones
M4-M8 ship silent). The notes below are kept for a later milestone (M9).

- The platform has no audio yet. Mage Run would be the first game with
  sound, so it needs a small `platform/audio/` helper (bus setup, a pause
  hook that mutes on `_on_paused`, and respect for the phone's silent mode
  where possible).
- SFX (CC0 or synthesized in code): footsteps on cobbles and planks
  (alternating), lane whoosh, jump "hup" plus a cloth flap, slide scrape,
  coin chime (pitch rising along a line), arcane row hum and step "ting",
  tile crack, crash thud, power-up cast (staff sparkle), shield pop.
- Music: a short looping medieval folk tune (CC0 or commissioned later) with
  a second layer that fades in on the arcane rows.
- Budget: OGG Vorbis, mono SFX, <= 1.5 MB total; at most 8 voices.

---

## 10. Platform work required

**Status: implemented on the `mage-run` branch (M1-M3)**, covered by the
headless suites `orientation_tests`, `swipe_tests` and the portrait cases in
`view_tests`. Section 10.6 lists what still needs a phone.

### 10.1 Per-game orientation

- **Manifest** (`LGGameManifest`): `@export_enum("either", "landscape",
  "portrait") var orientation: String = "either"`, validated (an unknown
  value keeps the game out of the catalog).
- **Default `either`, opt-out only:** every game follows the phone unless
  its manifest locks one shape. Tic-Tac-Toe, Stack Tower and Competitive
  Evolution declare `either` (their HUDs lay out in portrait; see 10.2).
  Tattoo Studio (on the `3d-model-game` branch, not touched here) becomes
  `either` when its side panels get the portrait bottom-tray layout.
- **Mage Run declares `either` too.** It *plays best in portrait* (a long
  road up the screen): a first-run hint suggests holding the phone upright,
  but landscape works (the road is simply wider on screen). Rotating
  mid-run pauses (decision 3).
- **Launcher / catalog:** `either`; its cards become one centred column of
  wide cards in portrait.
- **Applying it:** `GameHost` asks the app's `OrientationService` (a child
  of the `LookingGlass` autoload) on game load and restores `either` on exit
  (also on any return to the launcher):
  - `either` -> `DisplayServer.SCREEN_SENSOR` (Android `fullSensor`)
  - `landscape` -> `SCREEN_SENSOR_LANDSCAPE` (both landscape directions)
  - `portrait` -> `SCREEN_SENSOR_PORTRAIT` (both portrait directions)
- **Project default:** `window/handheld/orientation=6` (full sensor; it was
  `0`, landscape locked), so the launcher already follows the phone.
- **Activity survives rotation:** Godot's Gradle template declares
  `android:configChanges="...orientation|...|screenSize|smallestScreenSize|density|...|screenLayout|uiMode"`,
  so Android resizes the window instead of restarting the Activity (which
  would kill the ARCore session). Verified in the exported APK's
  `AndroidManifest.xml` (see the branch report).
- **Old plugin builds:** if the ARCore plugin lacks `set_display_rotation`
  (built from the old patch), AR forces `landscape` while it runs.

### 10.2 Smooth rotation

- **Base canvas swap:** the project stretches a 1280 x 720 canvas
  (`canvas_items`, `expand`). In portrait `OrientationService` swaps it to
  **720 x 1280**, so UI keeps its physical size (without the swap a
  portrait phone would scale the 1280-wide canvas to its narrow side:
  about 44 % smaller buttons and text). A 1080 x 2340 phone gets a
  720 x 1560 viewport in portrait and 1560 x 720 in landscape.
- **UI fade:** after the window turns, every top-level UI item fades back
  in over **0.22 s** (`OrientationService.FADE_SECONDS`), hiding the
  one-frame reflow; the camera passthrough never fades. (Android itself
  animates the rotation.)
- **HUD re-layout:** anchored Controls re-layout by themselves; listeners
  of `orientation_changed` move what anchors cannot express:
  - Host HUD: the status line spans the top beside "‹ Games" in portrait
    (top right in landscape).
  - Calibration HUD: the button row is a centred `HFlowContainer` (one line
    in landscape, wrapped lines in portrait), with smaller portrait buttons;
    the step banner narrows and starts below "‹ Games" / "dbg"; the Airspace
    slider and the debug line adjust.
  - Stack Tower: the score moves below the platform status line.
  - Tic-Tac-Toe has no 2D HUD (its scoreboard and options are in 3D).
  - Launcher: one column of wide cards.
  - Touch camera ("Play without AR"): keeps the horizontal field of view in
    portrait, so the board fits the narrow screen.
  The tests assert that every HUD is inside a 1080 x 2340 and a 2340 x 1080
  screen (with a margin) and that nothing overlaps, at every calibration
  step.
- **Callback and pause rule:** after the platform has re-laid out, the game
  gets `LGGame._on_orientation_changed(portrait)` (and the
  `orientation_changed` signal; `is_portrait()` is valid from
  `_on_board_ready()` on). The platform does **not** pause games: a board
  game simply continues. **Mage Run pauses itself** in that callback: it
  freezes the run, shows "Paused" with a Resume button, and resumes with a
  3-2-1 countdown, so a rotation never causes a crash. (An app pause, e.g.
  the phone locking, pauses through `_on_paused` as before.)
- **Anchor preserved:** a rotation changes nothing in the world. The ARCore
  anchor, the world anchor node and the board's pose are untouched; only
  the camera projection and the screen mapping change (tested: the locked
  board's world transform is identical through landscape -> portrait ->
  reverse landscape -> landscape, and no new anchor is made).
- **ARCore display rotation** (patch in `tools/arcore_plugin/lg-arcore.patch`):
  - The upstream plugin hard-codes `ArSession_setDisplayGeometry(ROTATION_90,
    ...)` and Godot 4.4.1's camera-feed background (`feed.glsl`) draws the
    texture with no UV transform, so it cannot show a rotated image.
  - The patch adds `getDisplayRotation()` (Kotlin, `Surface.ROTATION_*`) and
    `ARCoreInterface.set_display_rotation()` /
    `get_background_uvs()` / `uses_custom_background()`. `ARSession` polls
    the rotation every 0.1 s (a 180-degree flip keeps the window size) and
    passes it on.
  - **Landscape (`ROTATION_90`) keeps the original, field-tested path**
    unchanged: the stretched feed with a texture-aspect display.
  - **Any other rotation:** ARCore gets the real rotation and window size;
    its projection, view matrix (display-oriented) and hit tests then
    describe a centre crop of the rotated image. Each frame the plugin
    reports the camera-texture UVs of the four screen corners
    (`ArFrame_transformCoordinates2d`), and `PassthroughBackground` draws
    the external camera texture (`samplerExternalOES` through a
    `CameraTexture`) with those UVs on a background canvas layer
    (`Environment.BG_CANVAS`), so the 3D scene renders on top. Until the
    first rotated UVs arrive the old background stays (no black frame).

### 10.3 Touch and ScreenRay mapping after rotation

- `ScreenRay.ray()` and `GameHost.screen_to_board()` read the camera's
  current projection (ARCore's, refreshed every frame) and the live viewport
  size, so they need no change; the tests tap every tic-tac-toe cell
  through the phone input path (window pixels, content scale) in AR in
  landscape, after turning to portrait and after turning back: all hit,
  with under 1 px of reprojection error (and the touch camera's tap mapping
  is checked in portrait). Taps after a 180-degree flip are only checked on
  the device (10.6).
- Audit: the fit handles, the tap probe and the AR hit tests use the live
  viewport and normalized coordinates (no cached screen sizes). The tap
  slop and the swipe threshold are in inches -> pixels and are recomputed on
  every rotation.

### 10.4 Screen-space swipes

- `LGGame.captures_swipes() -> bool` (default false) and
  `_on_swipe(direction: Vector2i, info: Dictionary)`: `direction` is
  `Vector2i.LEFT` / `RIGHT` / `UP` / `DOWN` as the screen is held; `info`
  has `velocity` (px/s), `time`, `from`, `to`, `distance` and `index`
  (0 = first swipe of the stroke).
- `SwipeDetector` (pure, beside `GestureTracker`): one finger, at least
  **0.28 in** (dpi-based, recomputed per screen) within **0.25 s**, dominant
  axis at least **1.4x** the other, **fires on the threshold** (not on
  lift), one swipe per stroke except a full reversal ("S" strokes), a second
  finger cancels the stroke, slow strokes are drags.
- While a game captures swipes, `GameHost` feeds every touch to the detector
  as well as the gesture tracker: taps still arrive as `_on_box_ray` /
  `_on_board_tap`, and strokes never orbit the touch camera. No swipes while
  the game is not playing.
- `SwipeBuffer`: the 0.15 s input buffer from section 4 (latest swipe wins),
  for Mage Run's state machine.

### 10.5 Tests

| Suite | What |
| --- | --- |
| `swipe_tests` (new) | Thresholds in inches at 160 / 420 dpi and in portrait; dominant axis; fire on threshold; slow strokes; S-strokes; taps not swipes; two fingers; the buffer; routing through `GameHost` (no orbit, taps kept, nothing while paused) |
| `orientation_tests` (new) | Manifest field and validation; apply on load / restore on exit (OS call recorded); simulated rotations (root window 2340x1080 <-> 1080x2340): base swap, one callback per turn, UI fade; every HUD inside the screen without overlaps in both shapes (host, AR calibration steps, debug line, Stack Tower, launcher); AR: ARCore told the rotation, portrait passthrough on the background canvas, board and anchor unmoved, cell taps exact before / after; reverse landscape; landscape-only plugin builds |
| `view_tests` (extended) | Portrait: ARCore's rotated centre crop drawn through the passthrough shader's UV interpolation, content on the video pixel (< 1 px) and taps hitting (< 2 mm); the unrotated landscape feed would be off by more than 100 px |
| `mage_run_tests` (M4+) | Lane / row state machine; jump to row; ramp; drop; collapsing tile; coyote and buffer; collision and stumble; chunk validator (always a safe path, reaction time, join rules, obstacle classes: jump / duck / either / dodge); seeded generation is deterministic; score and multiplier; power-ups; everything inside the box; the clean road cuts (items slice across both cuts); pause / resume and the rotation pause with countdown; Style toggle |

### 10.6 Device checks still needed

Headless tests cannot run ARCore or the GPU path, so on a phone check:

1. Portrait AR: the camera image is upright, not mirrored, fills the screen
   (centre crop) and the board sits on the table without swimming. This
   proves the UV convention of the external texture in our shader and
   `Environment.BG_CANVAS` under XR rendering.
2. Rotate with the board locked: the board stays put, the AR session keeps
   running (no Activity restart), taps land on the right cell in portrait.
3. 180-degree flips (landscape <-> reverse landscape, portrait upside down
   if the phone allows it): the image follows within about 0.1 s.
4. The launcher and each game in portrait and landscape, and the UI fade.
5. Performance: the portrait passthrough is one full-screen textured quad
   (comparable to the landscape feed draw).

---

## 11. Implementation milestones

| # | Milestone | Done when | Status |
| --- | --- | --- | --- |
| **M0** | This doc, reviewed | Open questions answered | **Done** (decisions at the top) |
| **M1** | Platform: orientation in the manifest (default `either`), GameHost apply / restore, full-sensor project default, base-canvas swap + UI fade, HUD re-layout (platform, Tic-Tac-Toe, Stack Tower, launcher), `orientation_changed` hook, `orientation_tests` | Existing games unchanged in landscape and laid out in portrait; a probe game rotates and keeps its anchor | **Done** on `mage-run` (headless); device check 10.6 |
| **M2** | Platform: ARCore display rotation (plugin patch), portrait passthrough, registration, `view_tests` portrait | Taps land on the right cell in portrait AR (field test) | **Done** on `mage-run` (headless); field test pending |
| **M3** | Platform: `SwipeDetector` + `captures_swipes()` / `_on_swipe`, `SwipeBuffer`, `swipe_tests` | Swipes at 160 / 420 dpi pass | **Done** on `mage-run` |
| **M4** | Mage Run greybox: board, box, treadmill, 3 ground lanes, lane change / jump / slide with buffering, boxes for obstacles, collision, game over / restart, score, rotation pause + countdown | Playable on the phone, best in portrait | **Done** on `mage-run` (headless; device check pending) |
| **M5** | Chunks + validator + seeded generator, difficulty curve, coin lines | Validator proves a safe path for every template | **Done** (24 templates; 2 x 1000 m generated per test run) |
| **M6** | Arcane rows (2 rows x 3 lanes): tiles, ramps, jump-to-row, drop, collapsing tiles, row coin multipliers | Rows unlock at the distance thresholds | **Done** |
| **M7** | Art pass: procedural wizard, props, road, sparkle trail, clean cut; budget check on device | <= 120 draw calls, 60 fps on the target phone | **First pass done** (about 50 draw calls, 5-7k triangles in desktop captures); device fps pending |
| **M8** | Staff meter + power-ups, HUD (coins, score, pause, staff, arcane row indicator), Hologram / Solid world toggle | **First playable** (silent) | **Mostly done**: meter, Shield / Magnet / Levitation, HUD in both orientations; the Hologram / Solid world toggle is deferred |
| **M9** | Audio helper + SFX / music (CC0) | | Later: out of scope for the first playable |
| **M10** | Polish, tuning, release build, field test | | |

### 11.1 First playable as built

- **Code:** `games/mage_run/`: `mage_run_game.gd` (the `LGGame`: visuals,
  HUD, flow), `scripts/mage_track.gd` (units, item types, physics
  constants), `mage_run_sim.gd` (the run, no nodes), `mage_chunks.gd`
  (24 templates), `mage_validator.gd` (safe-path search, shape and class
  rules),
  `mage_generator.gd` (seeded, validated chunks, optional worker thread),
  `mage_props.gd` (every model in code), `shaders/` (arcane tiles, the
  cut solid and glow materials, scrolling road, blob shadow).
- **Fairness:** the sim and the validator share one physics model (exact
  jump parabola, so the same 11 cm apex at any frame rate). Every chunk is
  validated with the previous one from the previous chunk's possible lanes;
  rejects fall back to a breather. Each obstacle has a class (jump: fence,
  log; duck: beam; either: barrier; dodge: wall, crates, cart, carriage),
  checked by the validator; the roof of a carriage is walkable but the
  validator never relies on it.
- **Containment:** the road is cut clean at both ends; items slice in at
  the far cut and out at the near cut (shader cut planes). `mage_run_tests` asserts every prop, tile, coin, the
  wizard and the scenery stay inside `PlayBox.contains()`.
- **Flow:** 3-2-1 countdown at start and on every resume; the Pause
  button, a phone turn and the app pausing all pause; game over shows the
  score and session best with "Run again". Double tap or the staff button
  casts.
- **Deferred:** the Hologram / Solid world toggle (the world is always
  solid, the arcane rows always hologram), audio (M9), all-time best and coin
  persistence (session best only), field pickups, cosmetics, a shared
  `HoloStyle` refactor, and the device checks (fps, swipe feel, AR in
  portrait with this game).

---

## 12. Decisions and open questions

### Decided

| # | Question | Decision |
| --- | --- | --- |
| 1 | Rows: ground + 2 or ground + 3? | **Ground + 2 holographic "arcane rows", 3 lanes each (9 lanes).** Named *arcane rows* in the doc and UI. |
| 3 | Orientation of the other games | **All games work in either orientation by default**; a manifest may opt out. Tic-Tac-Toe and Stack Tower are `either` (done); Tattoo Studio follows on its branch. |
| 4 | Rotation mid-run | **Pause** (Resume + 3-2-1 countdown). Platform rule: every game gets `_on_orientation_changed`; Mage Run pauses there. |
| 10 | Audio for the first playable | **Not needed for now**: out of scope for the first playable (M9 later). |

### Still open

2. **World scale** (answered for now by the build: a 30 x 90 cm board at
   0.20 m per run metre, 3.7 run metres visible, see section 6). Still to
   confirm on a phone: is it readable at arm's length, and is 90 cm too
   long for common tables (players can scale the board down)?
5. **Taps**: offer "Tap to jump / side taps to change lane" as an
   accessibility mode?
6. **Power-up choice**: is the cast power-up automatic (chosen by the
   situation), player-cycled (long-press the staff), or fixed per run
   (picked before the run)?
7. **Persistence**: save the all-time best and the coin total to `user://`
   (first game to do so)? Are cosmetics in scope?
8. **Assets**: are fully procedural props OK, or may CC0 kits (for example
   Kenney) be used for crates, barrels and the carriage?
9. **Floor play**: should the game suggest the floor (scaled x3) for a
   "life-size lane" mode, or table only?
11. **Multiplayer**: the platform's shared-anchor goal. Is there a later
    "ghost race" (two phones, one board)? This would affect the seeded
    generator (shared seed) now.
