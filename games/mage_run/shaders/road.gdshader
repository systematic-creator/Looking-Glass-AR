// The storybook road: cobblestones with plank bridges, scrolling with the
// run (the world moves, the wizard stays). Lit, opaque, procedural (no
// textures). scroll = run distance in board metres; offset = wizard z minus
// the mesh centre z; width = road width (board m).
shader_type spatial;
render_mode cull_back;

uniform float scroll = 0.0;
uniform float offset = 0.0;
uniform float width = 0.24;
uniform vec4 stone : source_color = vec4(0.66, 0.61, 0.53, 1.0);
uniform vec4 mortar : source_color = vec4(0.38, 0.34, 0.3, 1.0);
uniform vec4 plank : source_color = vec4(0.74, 0.52, 0.27, 1.0);

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float t = scroll + offset - local.z;
	float x = local.x;
	float section = floor(t / 0.3);
	bool planks = hash2(vec2(section, 3.0)) < 0.28 && fract(t / 0.3) < 0.45;
	vec3 col;
	float rough = 0.9;
	if (planks) {
		float board = floor(t / 0.011);
		float f = fract(t / 0.011);
		float gap = smoothstep(0.0, 0.08, f) * smoothstep(1.0, 0.92, f);
		float tint = 0.85 + 0.25 * hash2(vec2(board, 1.0));
		float grain = 0.93 + 0.07 * sin(x * 260.0 + hash2(vec2(board, 5.0)) * 20.0);
		col = plank.rgb * tint * grain * mix(0.45, 1.0, gap);
		vec2 nail = vec2(abs(abs(x) - width * 0.38), (f - 0.5) * 0.011);
		col *= 1.0 - 0.6 * (1.0 - smoothstep(0.0008, 0.0014, length(nail)));
		rough = 0.8;
	} else {
		float row = floor(t / 0.012);
		float shift = mod(row, 2.0) * 0.5;
		float cx = x / 0.016 + shift;
		vec2 cell = vec2(floor(cx), row);
		vec2 f = vec2(fract(cx), fract(t / 0.012));
		vec2 d = min(f, 1.0 - f) * vec2(0.016, 0.012);
		float m = smoothstep(0.0006, 0.0016, min(d.x, d.y));
		float tint = 0.82 + 0.3 * hash2(cell);
		vec3 c = stone.rgb * tint;
		c = mix(c, c * vec3(0.95, 1.02, 0.92), hash2(cell + 9.0) * 0.5);
		col = mix(mortar.rgb, c, m);
	}
	// Soft darkening toward the road edges (worn wheel ruts in the middle lane lines).
	float edge = smoothstep(width * 0.5, width * 0.42, abs(x));
	col *= mix(0.7, 1.0, edge);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
