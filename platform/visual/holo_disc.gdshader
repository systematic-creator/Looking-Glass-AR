// Looking Glass projector glow on a flat PlaneMesh (UV 0..1): soft core,
// an outer ring and an optional faint grid. Also used for landing ripples
// (core 0, ring_radius animated). Alpha-blended, Compatibility-renderer safe.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.92, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float core : hint_range(0.0, 2.0) = 0.45;
uniform float core_power : hint_range(0.5, 6.0) = 1.6;
// 0..1 of the half size.
uniform float ring_radius : hint_range(0.0, 1.0) = 0.9;
uniform float ring_width : hint_range(0.001, 0.5) = 0.035;
uniform float ring : hint_range(0.0, 2.0) = 0.7;
uniform float grid : hint_range(0.0, 1.0) = 0.0;
uniform float grid_cells = 12.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.12;
// 0 = round falloff, 1 = square (board-shaped) falloff.
uniform float square : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = mix(length(p), max(abs(p.x), abs(p.y)), square);
	float fade = clamp(1.0 - r, 0.0, 1.0);
	float glow = core * pow(fade, core_power);
	float ring_glow = ring * (1.0 - smoothstep(0.0, ring_width, abs(r - ring_radius)));
	vec2 g = abs(fract(p * grid_cells * 0.5) - 0.5);
	float grid_glow = grid * (1.0 - smoothstep(0.0, 0.05, min(g.x, g.y))) * fade;
	float beat = 1.0 + pulse * sin(TIME * 2.0);
	ALBEDO = color.rgb;
	ALPHA = clamp((glow + ring_glow + grid_glow) * intensity * beat, 0.0, 1.0);
}
