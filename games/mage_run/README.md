# Mage Run

A medieval fantasy three-lane endless runner for Looking Glass: a wizard in
a blue robe and a starry hat runs down a storybook diorama road toward a
castle, dodging fences, banners, crate stacks, barrel mine-carts and royal
carriages with swipes, and grabbing gold star coins. Two glowing hologram
**arcane rows** (3 lanes each, 9 lanes with the road) appear above the road
from 150 m and 400 m; coins up there are worth x2 / x3.

Design: [docs/mage-run.md](../../docs/mage-run.md). The images in
`docs/mage-run/` are references only and are never packaged.

## Controls

- Swipe left / right: change lane (on an arcane row only onto a tile).
- Swipe up: jump; under an arcane row tile you land on it. Coyote grace
  0.08 s after running off an edge.
- Swipe down: slide on the ground, drop a row from an arcane row, slam down
  mid-air. Swipes are buffered for 0.15 s.
- Double tap or the staff button: cast the staff when its meter is full
  (Shield, Magnet, Levitation in turn).
- Pause button; turning the phone also pauses. Resume counts down 3-2-1.

## Files

- `manifest.tres`: 30 x 60 cm board, tall box 40 cm (adjustable to 70 cm),
  `orientation = "either"` (a first-run hint suggests holding the phone
  upright).
- `mage_run_game.gd`: the `LGGame`: visuals, HUD, pause / countdown, game
  over.
- `scripts/mage_track.gd`: units, the move set, track item types, physics.
- `scripts/mage_run_sim.gd`: the run itself (no nodes; tested headless).
- `scripts/mage_chunks.gd`: hand-authored chunk templates.
- `scripts/mage_validator.gd`: the fairness validator (safe path search and
  shape rules).
- `scripts/mage_generator.gd`: seeded generator (validated chunks only).
- `scripts/mage_props.gd`: every model, built in code.
- `shaders/`: arcane tiles, the castle gate portal, the scrolling road,
  the blob shadow.

No audio yet (out of scope for the first playable).
