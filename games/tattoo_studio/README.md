# Tattoo Studio

Tattoo a humanoid model standing on the board: life-size on the floor, or
a miniature on a table. Three default models (male, female, lizard man),
colour inks, four needle sizes, an eraser, layered shading, a turntable and a
Focus close-up. It is also the test bed for new 3D models (see
[MODELS.md](MODELS.md)).

## Playing

- **Place it.** Floor: trace / pick the floor and lock; the box defaults to
  1.92 m of airspace (the platform's tall-box exception, adjustable up to 3.0 m). Table:
  the platform fits the 1.1 m footprint to the table (placement scale), and
  the in-game **Size** slider (10-100 % of life size) shrinks the model. The
  airspace follows the model (just above its head).
- **Draw / Rotate** (top right). *Draw*: drag a finger on the model to
  tattoo. *Rotate*: drag around the model to spin the turntable. In both
  modes, two-finger pinch resizes the model and twist turns it.
- **Needle / Eraser**, 9 inks (black, grey wash, red, orange, yellow,
  green, blue, purple, brown), needle sizes S / M / L / XL (4, 7, 12 and
  22 mm radius on the body: lines scale with the model).
- **Shading:** go over a line again (lift and stroke again) to deepen it.
  Holding the needle still or scrubbing in one stroke does not add more.
- **Focus** (left): tap Focus, then tap a spot on the model. The model eases
  up 3x around that spot (the spot itself does not move) for close work
  without leaning in; the AR camera clips anything nearer than 0.1 m. Pinch
  changes the magnification (1.5-6x). **True size** eases back.
- **↶ Undo (n)** (under Needle / Eraser) takes back the last stroke: one
  press-to-release with the needle or the eraser, or a Clear all. Up to 20
  steps per model, kept for the session across model switches and leaving
  the game; greyed out when there is nothing to undo. Each step stores only
  the 64x64-texel tiles of the ink atlas the stroke changed (their bytes
  before it), deflate-compressed: a typical stroke costs a few KB, and the
  history is capped at 16 MB per model (the oldest steps go first). A touch
  on the button never paints (`is_over_game_ui`). Undo mid-stroke ends that
  stroke and takes it back.
- **Clear all…** asks before removing every tattoo on the current model (and
  can be undone: the inked tiles go on the undo history first).
- Tattoos persist per model for the app session: switching models, pausing,
  unlocking / re-placing and leaving / reopening the game keep them.

## How painting works

1. The platform sends one-finger **ray strokes** (BEGIN / MOVE / END /
   CANCEL, board-space rays) while Draw mode is on.
2. Each ray is moved into model space and cast against the **real mesh**
   (`TattooPaintMesh.raycast`: triangles grouped into 32-triangle chunks
   with boxes; Möller-Trumbore), giving the hit point, normal, UV.
3. Between two hits the game re-casts rays every 6 mm (so the line hugs the
   surface around curves rather than cutting a chord) and stamps the brush
   every 0.3 x radius along the surface path.
4. A stamp is a **sphere in model space**. For each triangle near it
   (facing the stroke's surface), the triangle's affine UV<->3D map turns
   the sphere into a UV box; texels inside the triangle (dilated 1.5
   texels) get coverage by their 3D distance to the brush centre. Because
   it works in 3D, a stroke crosses **UV seams** cleanly: triangles on both
   sides of a seam are near the brush wherever their islands sit.
5. Ink goes into the model's 1024² RGBA8 atlas, uploaded at most 30 times a
   second and only after it changed.

## Shading model

Per texel: pigment load `L` (alpha) and optical density `OD` per colour
channel (RGB). Ink sits under the skin and filters the light the skin
reflects: `colour = skin * exp(-OD)` (Beer-Lambert). An ink colour `c` has
absorbance `A = -ln(c)` (linear light). One needle pass with coverage `w`:

```
dL = 0.25 * w * (1 - L)     # diminishing returns: skin already holds ink
L  += dL
OD += dL * A                # capped at OD_MAX = 6
```

Black goes 0.25 (a grey wash) → 0.44 → 0.58 → … → 1 and never past it;
colours go from a light tint to deep and saturated, and different colours
over each other mix subtractively. A texel takes ink **once per stroke**
(only the strongest coverage in the stroke counts, recomputed from the
stroke's start), so passes, not dwell time, build depth. The eraser scales
`L` and `OD` by `1 - w`, also once per stroke.

## Files

| | |
| --- | --- |
| `manifest.tres` | catalog entry (tall box, 1.1 m footprint) |
| `tattoo_studio.tscn` / `tattoo_studio_game.gd` | the `LGGame` |
| `scripts/body_builder.gd` | procedural male / female / lizard man + UV atlas |
| `scripts/paint_mesh.gd` | CPU triangles: ray cast, brush neighbourhood, UV maps |
| `scripts/ink_layer.gd` | ink atlas, shading maths, stamping |
| `scripts/skin.gdshader` | skin × exp(-OD), lizard scales |
| `scripts/model_entry.gd`, `model_list.gd`, `models/model_list.tres` | the model picker list |
| `scripts/model_loader.gd`, `model_contract.gd` | loading .glb / scenes, contract checks |
| `scripts/studio_ui.gd` | on-screen tools |

## Model sources and licence

The three default models are **procedural, own work** (`body_builder.gd`,
lofted tubes; no third-party assets), under the project's licence. The
crotch is the closed, rounded end of the body tube: smooth and featureless;
there is no anatomical detail anywhere. The lizard man's tail leaves the
lower back and curls round behind the right leg to the floor (never between
the legs), and his snout is a separate tube.
