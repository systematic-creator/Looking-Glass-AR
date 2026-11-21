// Mage Run's solid storybook material (vertex colours, softly lit) with the
// road's clean cut: fragments beyond either cut plane (world space, set every
// frame by MageProps.set_cut) are discarded, so props slice in at the far
// edge of the board and slice out at the near edge. Compatibility-safe.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 cut_near = vec4(0.0, 0.0, 1.0, 1.0e6);
uniform vec4 cut_far = vec4(0.0, 0.0, -1.0, 1.0e6);
uniform float roughness_value = 0.85;
uniform float metallic_value = 0.0;
uniform vec3 emission_color = vec3(0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(cut_near.xyz, world_pos) > cut_near.w || dot(cut_far.xyz, world_pos) > cut_far.w) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = emission_color;
}
