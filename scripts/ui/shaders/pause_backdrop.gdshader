shader_type canvas_item;
// Pause veil: softened, desaturated battle frame under a cool ink wash.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec2 texel = vec2(0.0016, 0.0028);

void fragment() {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float weight = 1.0 / (1.0 + float(x * x + y * y));
			sum += texture(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * texel * 1.6).rgb * weight;
			total += weight;
		}
	}
	vec3 color = sum / total;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma), 0.7 * amount);
	color = mix(color, color * vec3(0.72, 0.8, 1.0), 0.6 * amount) * mix(1.0, 0.46, amount);
	COLOR = vec4(color, 1.0);
}
