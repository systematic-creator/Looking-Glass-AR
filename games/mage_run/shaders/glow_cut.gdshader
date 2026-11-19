// Unshaded vertex-colour glow (staff tip, crystals) with the road's cut
// planes (see solid_cut.gdshader).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 cut_near = vec4(0.0, 0.0, 1.0, 1.0e6);
uniform vec4 cut_far = vec4(0.0, 0.0, -1.0, 1.0e6);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(cut_near.xyz, world_pos) > cut_near.w || dot(cut_far.xyz, world_pos) > cut_far.w) {
		discard;
	}
	ALBEDO = COLOR.rgb;
}
