shader_type canvas_item;
// Anime focus lines radiating from `center` (UV space). `phase` advances in
// discrete steps so the lines flicker like hand-drawn frames.
uniform vec2 center = vec2(0.5, 0.5);
uniform float intensity = 0.0;
uniform float phase = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float inner = 0.2;
uniform float aspect = 1.7778;
uniform float density = 160.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float r = length(p);
	float angle = (atan(p.y, p.x) + PI) / (2.0 * PI);
	float slot = floor(angle * density);
	float frame = floor(phase * 18.0);
	float h = hash(vec2(slot, frame));
	float local = fract(angle * density);
	float thickness = 0.08 + 0.32 * h;
	float line = step(0.55, h) * smoothstep(thickness, 0.0, abs(local - 0.5));
	float start = inner + 0.18 * hash(vec2(slot, frame + 7.0));
	float reach = smoothstep(start, start + 0.22, r);
	COLOR = vec4(tint.rgb, tint.a * line * reach * intensity);
}
