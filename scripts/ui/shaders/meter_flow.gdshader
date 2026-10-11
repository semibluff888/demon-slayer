shader_type canvas_item;
// Breath gauge energy: scrolling fbm streams in the vertex tint. UV.x runs
// along the whole three-cell gauge from the outer end toward the center.
uniform float phase = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.1;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float y = UV.y;
	float flow = fbm(vec2(UV.x * 7.0 - phase * 1.4, y * 2.2 + phase * 0.35));
	float streak = smoothstep(0.62, 0.92, noise(vec2(UV.x * 26.0 - phase * 5.0, y * 2.5)));
	vec3 color = base * (0.62 + flow * 0.72) + vec3(1.0) * streak * 0.32;
	color = mix(color, vec3(1.0), 0.3 * smoothstep(0.26, 0.0, abs(y - 0.24)));
	color *= 1.0 - 0.3 * smoothstep(0.7, 1.0, y);
	COLOR = vec4(color, COLOR.a);
}
