shader_type canvas_item;
// Slow sumi smoke for menu backdrops: two tints drift over deep ink, with a
// vignette and fixed paper grain. `phase` is advanced by script so it freezes.
uniform vec4 base_color : source_color = vec4(0.024, 0.031, 0.051, 1.0);
uniform vec4 tint_left : source_color = vec4(0.12, 0.32, 0.42, 1.0);
uniform vec4 tint_right : source_color = vec4(0.42, 0.1, 0.16, 1.0);
uniform float tint_strength = 0.6;
uniform float phase = 0.0;
uniform float vignette = 0.75;
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
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
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p = p * 2.02 + vec2(1.7, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y) * 2.4;
	vec2 drift = vec2(phase * 0.03, -phase * 0.018);
	float warp = fbm(p * 1.6 - drift * 1.4);
	float smoke = fbm(p + drift + warp * 0.9);
	float wisps = smoothstep(0.42, 0.86, smoke);
	float veins = smoothstep(0.015, 0.0, abs(smoke - 0.58)) * 0.5;
	float side = smoothstep(0.3, 0.7, uv.x + (smoke - 0.5) * 0.25);
	vec3 tint = mix(tint_left.rgb, tint_right.rgb, side);
	vec3 color = base_color.rgb + tint * (wisps * tint_strength + veins * tint_strength * 0.6);
	vec2 v = (uv - 0.5) * vec2(1.1, 1.4);
	color *= clamp(1.0 - dot(v, v) * vignette * 1.6, 0.0, 1.0);
	color += (hash(floor(FRAGCOORD.xy)) - 0.5) * 0.022;
	COLOR = vec4(color, COLOR.a);
}
