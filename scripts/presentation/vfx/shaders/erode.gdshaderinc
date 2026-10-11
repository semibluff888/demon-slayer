// Shared by the elemental ribbon shaders. Vertex alpha carries presence:
// 1 keeps the strip intact, 0 erodes it completely. The tileable noise turns
// the boundary into ragged foam or flame tongues instead of a soft fade.
uniform sampler2D erosion_noise : repeat_enable, filter_linear;
uniform vec2 noise_scale = vec2(6.0, 0.9);
uniform float edge = 0.1;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float n = texture(erosion_noise, UV * noise_scale).r;
	float keep = smoothstep(n - edge, n + edge, tint.a * (1.0 + 2.0 * edge) - edge);
	COLOR = vec4(base.rgb * tint.rgb, base.a * keep);
}
