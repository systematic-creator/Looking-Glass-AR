// Looking Glass hologram surface: see-through (alpha-blended, so it keeps its
// colour over a bright daylight camera image), unlit, fresnel rim, screen
// scanlines, a slow bright sweep band and a faint flicker. Written for the
// Compatibility renderer (GLES3 / WebGL2); no textures, no screen reads.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.92, 1.0, 1.0);
// Overall brightness (animate for pulses).
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// Body glow facing the viewer.
uniform float fill : hint_range(0.0, 1.0) = 0.18;
// Edge glow where the surface turns away from the viewer.
uniform float rim : hint_range(0.0, 3.0) = 1.1;
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;
// Screen-space scanlines (pixels per line pair ~ 6.28 / scan_frequency).
uniform float scan_frequency = 1.1;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.22;
// A bright band sweeping up through the object (world space).
uniform float sweep_strength : hint_range(0.0, 2.0) = 0.35;
uniform float sweep_speed = 2.2;
uniform float sweep_density = 45.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.06;
// Landing flash: 0 = none, 1 = full white-hot flash (animate it down).
uniform float flash : hint_range(0.0, 2.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, rim_power);
	float lines = 1.0 - scan_strength * (0.5 + 0.5 * sin(FRAGCOORD.y * scan_frequency));
	float band = pow(0.5 + 0.5 * sin(world_pos.y * sweep_density + world_pos.x * 6.0 - TIME * sweep_speed), 10.0);
	float flick = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 31.0 + world_pos.x * 17.0));
	float glow = (fill + rim * fresnel + sweep_strength * band) * lines * flick * intensity;
	ALBEDO = mix(color.rgb, vec3(1.0), clamp(flash * 0.6, 0.0, 1.0));
	ALPHA = clamp(glow + flash * 0.8, 0.0, 1.0);
}
