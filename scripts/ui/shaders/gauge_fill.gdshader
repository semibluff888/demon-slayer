shader_type canvas_item;
// Health fill: the vertex color is the base tint. UV.x runs from the outer end
// toward the timer for both players; UV.y spans the bar height.
uniform float phase = 0.0;
uniform float sheen_strength = 0.4;

void fragment() {
	vec3 base = COLOR.rgb;
	float y = UV.y;
	vec3 color = base * mix(1.28, 0.66, smoothstep(0.0, 1.0, y));
	color = mix(color, vec3(1.0, 0.98, 0.92), 0.42 * smoothstep(0.16, 0.0, abs(y - 0.18)));
	color *= 1.0 - 0.28 * smoothstep(0.72, 1.0, y);
	float sweep = fract(phase * 0.21) * 2.2 - 0.6;
	float band = smoothstep(0.075, 0.0, abs(UV.x - sweep + (y - 0.5) * 0.16));
	color += vec3(1.0, 0.97, 0.88) * band * sheen_strength;
	// Fine grain keeps the fill from reading as flat plastic.
	color *= 0.95 + 0.05 * sin(UV.x * 420.0);
	COLOR = vec4(color, COLOR.a);
}
