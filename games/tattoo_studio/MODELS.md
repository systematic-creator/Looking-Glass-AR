# Tattoo Studio model contract

Any model that meets this contract can be dropped in, viewed, scaled and
tattooed. `TattooModelContract.validate()` checks it when the model loads
(errors show in the status line and the model is not offered).

## The model

| Rule | Why | Checked |
| --- | --- | --- |
| **Format:** glTF 2.0 (`.glb` preferred, `.gltf` ok), or a Godot scene / mesh | Godot imports it; runtime glTF works on Android | loader |
| **Triangles**, at most 120 000 (aim for 20-40 k) | ray casts and stamps run on the CPU | yes |
| **Units: metres.** Standing height within 15 % of the entry's `height_m` | brush sizes are in body metres | yes |
| **Origin on the floor between the feet** (min y = 0 ± 2 cm, footprint centred) | the model stands on the board's surface and spins on the turntable about its origin | yes |
| **+Y up, facing +Z** (glTF default) | upright on the surface | +Y yes |
| **UV0 present, inside [0, 1], non-overlapping** (no mirrored / stacked / tiled islands); < 1 % shared area | each texel must be one place on the skin | yes (256² raster) |
| Every real triangle has UV area (≤ 2 % degenerate) | unpainted slivers | yes |
| Gutters of ≥ 4 px (at 1024) between UV islands | the brush dilates 1.5 texels over island edges | no (recommended) |
| Closed, outward-facing surfaces; no hidden inner shells | the nearest hit is what the player sees | no |
| Private regions smooth and featureless | keep it general and tasteful | review |
| Avoid parts thinner than ~1 cm with skin on both sides | the brush skips triangles facing away from the stroke, but very thin parts can still catch both sides | no |

The skin colour comes from the entry (`skin_color`); textures on the model
are not used yet. Several meshes / surfaces in one file are merged (their
transforms baked in). Skinned / animated meshes are read in their rest pose.

## Adding a model

1. Put the file in `res://games/tattoo_studio/models/` (e.g.
   `models/orc.glb`; Godot imports it) or, for a quick test on a device
   without rebuilding, anywhere the app can read (`user://…`).
2. Add an entry to `models/model_list.tres` (in the editor: open it and add a
   `TattooModelEntry` to `models`; or copy a `[sub_resource]` block):

```
[sub_resource type="Resource" id="Resource_orc"]
script = ExtResource("2_entry")
id = &"orc"
display_name = "Orc"
source = "res://games/tattoo_studio/models/orc.glb"
height_m = 1.9
default_scale = 1.0
min_scale = 0.1
max_scale = 1.0
skin_color = Color(0.4, 0.55, 0.35, 1)
scale_pattern = 0.0
ink_resolution = 1024
credits = "Name, licence, link"
```

   and append `SubResource("Resource_orc")` to the `models` array.
3. Run the tests (`tests/tattoo_tests.tscn` builds every listed model through
   the contract) and the game. `credits` must name the licence for any
   third-party asset (CC0 / CC-BY with attribution; verify it at the
   source).

`ink_resolution` is 512, 1024 (default) or 2048 texels per side: 2048 gives
sharper fine lines but uses ~4x the memory and stamp time.
