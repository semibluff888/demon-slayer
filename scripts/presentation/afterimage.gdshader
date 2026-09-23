shader_type canvas_item;
render_mode unshaded;

varying vec4 trail_tint;

void vertex() {
	trail_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float detail = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	// Retain costume folds, but make dark cloth readable in the cool silhouette.
	vec3 ink = trail_tint.rgb * mix(0.58, 1.0, detail);
	COLOR = vec4(ink, source.a * trail_tint.a);
}
