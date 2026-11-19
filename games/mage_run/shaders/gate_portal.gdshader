// The castle gate's magic portal: an opaque swirl the track comes out of
// (so anything still inside the castle is hidden). Unshaded.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 deep : source_color = vec4(0.07, 0.03, 0.16, 1.0);
uniform vec4 glow : source_color = vec4(0.3, 0.92, 1.0, 1.0);
uniform vec4 violet : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform float aspect = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.62)) * vec2(aspect, 1.0) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * 2.2);
	float core = 1.0 - smoothstep(0.0, 0.9, r);
	vec3 col = mix(deep.rgb, violet.rgb, swirl * 0.45 * (1.0 - r * 0.6));
	col += glow.rgb * core * 0.35 * (0.8 + 0.2 * sin(TIME * 3.0));
	float rim = smoothstep(0.86, 1.0, max(abs(UV.x - 0.5) * 2.0, abs(UV.y - 0.5) * 2.0));
	col = mix(col, glow.rgb, rim * 0.7);
	ALBEDO = col;
}
