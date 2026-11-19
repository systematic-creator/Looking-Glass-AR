# 3D Model Game: Tattoo Studio

Status: planned (branch `3d-model-game`). Requested 2026-11-18.

## Purpose
A Looking Glass game that is fun on its own and doubles as a test bed for future 3D models: any humanoid model that drops into the slots below should work for viewing, scaling and painting.

## Core experience
- A humanoid model stands anchored on the selected surface (table or floor).
- The play box gets a large vertical cap so a full-height model fits (game-declared airspace, floor placement allowed).
- The player walks around the anchored model and views it from any angle.
- The player draws ("tattoos") anywhere on the body; strokes follow the surface curvature.
- Tattoos are permanent, with an eraser tool to remove ink.

## Default models
Three very general base models, scale-adjustable:
1. Male
2. Female
3. Lizard man

- Private regions are smoothed over (no anatomical detail).
- Placeholder models first (simple, low-poly, procedurally built or CC0); swappable later.

## Tools
- Needle/brush with colour options (palette).
- Brush size.
- Eraser.
- Shading: ink deepens when an area is gone over more than once, approximating real tattooing (layered passes increase saturation/opacity toward a cap rather than linear blending; lighter first passes, darker built-up layers).

## Technical plan
- Painting: raycast taps/drags (platform `_on_box_ray`) against the model's mesh, convert hits to UV, paint into a per-model ink texture (SubViewport or Image-based) with brush stamps spaced along the stroke so lines follow curves.
- Ink accumulation: separate "ink density" channel per texel; each pass adds density with diminishing returns; colour = mix(skin, ink colour, f(density)). Eraser reduces density.
- Models need clean, non-overlapping UVs; the model contract documents this.
- Model contract (for future models): mesh + skin albedo, UV0 non-overlapping, height in metres, upright +Y, origin at feet; optional manifest entry (name, default scale, scale range).
- Scale slider within the game; box height follows the model.
- Persist tattoos per model during the session; optional save/export of the ink texture later.
- Mobile performance: ink texture 1024-2048 px, paint updates only on stroke.

## Order of work
1. Tattoo Studio game skeleton (manifest, LGGame, tall airspace, floor/table placement).
2. Placeholder male, female and lizard man models with smoothed private regions.
3. Surface painting with colours, brush size and eraser.
4. Layered shading model and tests.
5. Model contract docs so new 3D models can be dropped in and tested.

## Depends on
The anchoring/stability work on main (lock stability, slide, tracking-loss recovery) should land first.
