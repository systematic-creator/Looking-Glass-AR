# Mage Run (planned)

A medieval fantasy three-lane endless runner for Looking Glass: a wizard
runs down a storybook diorama road toward a castle, dodging carriages, crates
and mine-carts with swipe timing. Glowing hologram rune-stone rows appear
above the road the further the run gets.

**Status:** design only, with no game code yet. See the design doc:
[docs/mage-run.md](../../docs/mage-run.md) (style reference:
[docs/mage-run/reference.jpg](../../docs/mage-run/reference.jpg), reference
only, not a shipped asset).

Planned contents of this folder (milestones M4-M9 in the doc):

- `manifest.tres`: `tall_box`, about 0.30 x 0.60 m board, 0.40 m airspace,
  `orientation = "portrait"` (new manifest field)
- `mage_run.tscn` / `mage_run_game.gd`: the `LGGame`
- `scripts/`: runner state machine, chunk templates + validator + seeded
  generator, procedural props, power-ups, HUD
- `models/` (optional): CC0 glTF props with `LICENSES.md`
