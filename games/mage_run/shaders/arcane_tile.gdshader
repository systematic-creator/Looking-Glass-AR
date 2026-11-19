// Arcane-row rune-stone tiles and ramps (MultiMesh instances): translucent
// additive cyan glow, glowing edges, carved rune glyphs, a scan sweep and a
// soft flicker. INSTANCE_CUSTOM: x = fade (0..1, the box ends), y = cracked,
// z = crumble progress (0..1), w = piece length (board m, for the glyphs).
// Compatibility-renderer safe (no screen textures, no depth reads).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.92, 1.0, 1.0);
uniform vec4 crack_color : source_color = vec4(1.0, 0.32, 0.28, 1.0);
uniform float intensity = 1.0;
uniform float width = 0.068;

varying vec3 local;
varying vec4 custom;

void vertex() {
	local = VERTEX;
	custom = INSTANCE_CUSTOM;
}

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

// One rune per cell: a ring and up to three strokes picked by the cell id.
float rune(vec2 p, float id) {
	float r = length(p);
	float ring = 1.0 - smoothstep(0.02, 0.05, abs(r - 0.3));
	float a = hash(id) * 3.1416;
	vec2 d = vec2(cos(a), sin(a));
	float s1 = (1.0 - smoothstep(0.015, 0.045, abs(dot(p, vec2(-d.y, d.x))))) * step(r, 0.42);
	float s2 = (1.0 - smoothstep(0.015, 0.045, abs(p.x))) * step(abs(p.y), 0.22) * step(0.5, hash(id + 3.1));
	float s3 = (1.0 - smoothstep(0.015, 0.045, abs(p.y + 0.12))) * step(abs(p.x), 0.18) * step(0.4, hash(id + 7.7));
	return max(ring, max(s1, max(s2, s3)));
}

void fragment() {
	float len = max(custom.w, 0.01);
	vec2 uv = vec2(local.x + 0.5, local.z + 0.5);
	float ex = min(uv.x, 1.0 - uv.x) * width;
	float ez = min(uv.y, 1.0 - uv.y) * len;
	float edge = 1.0 - smoothstep(0.0, 0.0035, min(ex, ez));
	float cells = max(1.0, floor(len / width + 0.5));
	vec2 cell = vec2(uv.x, uv.y * cells);
	float id = floor(cell.y) + floor(len * 997.0);
	vec2 p = vec2(fract(cell.x) - 0.5, fract(cell.y) - 0.5);
	float glyph = rune(p, id);
	float scan = 0.5 + 0.5 * sin(TIME * 3.0 - local.z * 18.0 * len);
	float flicker = 0.94 + 0.06 * sin(TIME * 23.0 + id);
	vec3 col = color.rgb;
	if (custom.y > 0.5) {
		col = mix(color.rgb, crack_color.rgb, 0.65 + 0.35 * sin(TIME * 14.0));
		flicker *= 0.75 + 0.25 * step(0.3, fract(TIME * 6.0 + id * 0.13));
	}
	float v = 0.12 + edge * 0.85 + glyph * 0.5 + scan * 0.08;
	// Crumbling: a noisy dissolve.
	float n = hash(floor(uv.x * 9.0) + floor(uv.y * cells * 6.0) * 13.0);
	float keep = step(custom.z, n);
	ALBEDO = col;
	ALPHA = clamp(v * flicker * intensity * custom.x * keep, 0.0, 1.0);
}
