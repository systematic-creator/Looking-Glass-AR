// A soft round contact shadow (unshaded, transparent).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.45;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.35, 1.0, r));
}
