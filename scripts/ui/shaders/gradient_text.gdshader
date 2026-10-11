shader_type canvas_item;
// Metallic vertical gradient for display text drawn around the node origin.
// `top`/`bottom` are local Y positions; `glint` (0..1, negative = off) sweeps a
// diagonal highlight across `span` pixels of text.
uniform vec4 top_color : source_color = vec4(1.0, 0.94, 0.74, 1.0);
uniform vec4 mid_color : source_color = vec4(0.91, 0.72, 0.39, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.62, 0.43, 0.19, 1.0);
uniform float top = -40.0;
uniform float bottom = 0.0;
uniform float start = 0.0;
uniform float span = 200.0;
uniform float glint = -1.0;
uniform float glint_width = 0.1;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float t = clamp((local_position.y - top) / max(1.0, bottom - top), 0.0, 1.0);
	vec3 color = t < 0.5 ? mix(top_color.rgb, mid_color.rgb, t * 2.0) : mix(mid_color.rgb, bottom_color.rgb, t * 2.0 - 1.0);
	// A crisp horizon just above the middle reads as polished leaf.
	color += vec3(0.16) * smoothstep(0.07, 0.0, abs(t - 0.36));
	color -= vec3(0.08) * smoothstep(0.38, 0.6, t) * (1.0 - smoothstep(0.6, 0.7, t));
	if (glint >= 0.0) {
		float along = (local_position.x - start + (local_position.y - top) * 0.55) / max(1.0, span);
		float shine = smoothstep(glint_width, 0.0, abs(along - glint));
		color = mix(color, vec3(1.0, 0.99, 0.94), shine * 0.75);
	}
	COLOR = vec4(color, COLOR.a);
}
