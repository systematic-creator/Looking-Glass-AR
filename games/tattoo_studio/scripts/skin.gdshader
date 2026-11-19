shader_type spatial;
// Tattoo Studio skin: skin albedo filtered by the ink atlas (Beer-Lambert,
// see TattooInkLayer): colour = skin * exp(-OD), OD = ink.rgb * od_max.
// Optional procedural scales (lizard skin) from the model-space position.

uniform vec4 skin_color : source_color = vec4(0.82, 0.64, 0.52, 1.0);
uniform sampler2D ink_map : hint_default_black, filter_linear, repeat_disable;
uniform float od_max = 6.0;
uniform float scale_pattern = 0.0;
uniform float scale_density = 32.0;
uniform float roughness_value = 0.62;

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// Distance to the nearest and second-nearest cell point (scales).
vec2 cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash3(i + g);
				float d = length(g + o - f);
				if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
			}
		}
	}
	return vec2(d1, d2);
}

void fragment() {
	vec3 base = skin_color.rgb;
	if (scale_pattern > 0.0) {
		vec2 c = cells(model_pos * scale_density);
		float edge = smoothstep(0.02, 0.22, c.y - c.x);
		// Fade the pattern where it would alias (small on screen).
		float fade = 1.0 - smoothstep(0.4, 1.2, fwidth(model_pos.x * scale_density) + fwidth(model_pos.y * scale_density));
		float k = scale_pattern * fade;
		base *= mix(1.0, mix(0.74, 1.05, edge), k);
		base = mix(base, base * vec3(1.08, 1.06, 0.88), 0.25 * k * (1.0 - c.x));
	}
	vec4 ink = texture(ink_map, UV);
	vec3 od = ink.rgb * od_max;
	ALBEDO = base * exp(-od);
	ROUGHNESS = mix(roughness_value, 0.5, ink.a * 0.5);
	SPECULAR = 0.35;
}
