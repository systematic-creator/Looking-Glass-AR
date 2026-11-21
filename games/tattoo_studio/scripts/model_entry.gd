class_name TattooModelEntry
extends Resource
## One model in Tattoo Studio's picker (see MODELS.md for the contract).
## Add a model: drop a .glb into games/tattoo_studio/models/ and add an
## entry like this to models/model_list.tres.

@export var id: StringName = &""
@export var display_name: String = ""
## "procedural:male" / "procedural:female" / "procedural:lizard", or a model
## file: res://... (.glb / .gltf imported by Godot, or a .tscn / .scn),
## user://... or an absolute path to a .glb / .gltf (loaded at runtime).
@export var source: String = ""
## Expected standing height in metres at scale 1 (the contract checks it).
@export var height_m: float = 1.75
## Display scale (1 = life size) when first shown, and the slider range.
@export var default_scale: float = 1.0
@export var min_scale: float = 0.1
@export var max_scale: float = 1.0
## Skin albedo (sRGB) under the ink, used when the model has no texture.
@export var skin_color: Color = Color(0.8, 0.62, 0.5)
## 0..1: strength of the procedural scale pattern (lizard skin).
@export var scale_pattern: float = 0.0
## Ink atlas resolution (texels per side): 512, 1024 or 2048.
@export var ink_resolution: int = 1024
@export var credits: String = ""
