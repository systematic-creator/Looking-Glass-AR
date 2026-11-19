# Mage Run (planned)

A medieval fantasy three-lane endless runner for Looking Glass: a wizard
runs down a storybook diorama road toward a castle, dodging carriages, crates
and mine-carts with swipe timing. Two glowing hologram rune-stone **arcane
rows** (3 lanes each, 9 lanes with the road) appear above the road the
further the run gets.

**Status:** design only, with no game code yet. The platform work it needs
(orientation, rotation, swipes: M1-M3) is in place. See the design doc:
[docs/mage-run.md](../../docs/mage-run.md) (style reference:
[docs/mage-run/reference.jpg](../../docs/mage-run/reference.jpg), reference
only, not a shipped asset).

Planned contents of this folder (milestones M4-M8 for the first playable;
audio, M9, comes later):

- `manifest.tres`: `tall_box`, about 0.30 x 0.60 m board, 0.40 m airspace,
  `orientation = "either"` (plays best in portrait; rotating mid-run pauses
  with a countdown), `captures_swipes()` true
- `mage_run.tscn` / `mage_run_game.gd`: the `LGGame`
- `scripts/`: runner state machine, chunk templates + validator + seeded
  generator, procedural props, power-ups, HUD
- `models/` (optional): CC0 glTF props with `LICENSES.md`
