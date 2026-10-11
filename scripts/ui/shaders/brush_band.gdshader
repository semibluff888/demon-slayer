shader_type canvas_item;
// Dry-brush sumi band. UV.x runs along the stroke and UV.y across it; the
// vertex color tints the ink. `reveal` wipes the stroke in with a ragged front.
uniform float seed = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.32;
uniform float bristle : hint_range(0.0, 1.0) = 0.55;
uniform float taper : hint_range(0.0, 1.0) = 0.45;
uniform float softness : hint_range(0.01, 0.5) = 0.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float across = abs(uv.y - 0.5) * 2.0;
	float side = step(0.5, uv.y);
	// Ragged upper and lower edges differ, like a brush pressed unevenly.
	float edge = 1.0 - roughness * fbm(vec2(uv.x * 6.5 + seed * 13.1, seed * 3.7 + side * 5.3));
	float tail = 1.0 - taper * pow(clamp((uv.x - 0.5) / 0.5, 0.0, 1.0), 2.2);
	float head = smoothstep(0.0, 0.04, uv.x) * (0.82 + 0.18 * smoothstep(0.0, 0.18, uv.x));
	float width = edge * tail * head;
	float body = smoothstep(width, width - softness, across);
	// Bristle streaks run along the stroke and open into dry gaps near the tail.
	float streak = noise(vec2(uv.x * 2.6 + seed * 1.3, uv.y * 52.0 + seed * 7.0));
	float dry = mix(1.0, smoothstep(0.22, 0.7, streak), bristle * smoothstep(0.3, 1.0, uv.x));
	float density = 0.86 + 0.14 * fbm(vec2(uv.x * 18.0, uv.y * 4.0 + seed));
	float front = reveal * 1.14 - 0.07 * fbm(vec2(uv.y * 9.0, seed * 2.0));
	float shown = 1.0 - smoothstep(front - 0.06, front, uv.x);
	COLOR = vec4(COLOR.rgb * (0.92 + 0.12 * density), COLOR.a * body * dry * density * shown);
}
