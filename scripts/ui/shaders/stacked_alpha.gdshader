shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// Stacked-alpha select videos (tools/build_select_videos.py): one opaque Theora frame holds
// premultiplied colour on top, a black gutter, then the matte as grey. Band edges come
// from the clip's select.json; sampling stays half a texel inside each band.
uniform float colour_end = 0.495413;
uniform float matte_start = 0.504587;
uniform bool mirror = false;
// Feather only the side facing the screen centre: clips touch their outer frame edge,
// which the layout puts on the screen edge.
uniform bool inner_right = true;
uniform float inner_feather : hint_range(0.0, 0.3) = 0.07;
uniform float fade_bottom : hint_range(0.0, 0.5) = 0.16;
// A few hair tips reach the clip's top row (Akaza); a short fade hides the flat cut.
uniform float fade_top : hint_range(0.0, 0.1) = 0.014;
// Codec noise floor of the matte; rescaled so solid stays solid.
uniform float alpha_floor : hint_range(0.0, 0.2) = 0.03;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float x = mirror ? 1.0 - UV.x : UV.x;
	float half_texel = TEXTURE_PIXEL_SIZE.y * 0.5;
	float colour_y = clamp(UV.y * colour_end, half_texel, colour_end - half_texel);
	float matte_y = clamp(matte_start + UV.y * (1.0 - matte_start), matte_start + half_texel, 1.0 - half_texel);
	vec3 rgb = texture(TEXTURE, vec2(x, colour_y)).rgb;
	float raw = texture(TEXTURE, vec2(x, matte_y)).g;
	float a = clamp((raw - alpha_floor) / (1.0 - 2.0 * alpha_floor), 0.0, 1.0);
	rgb = min(rgb * (a / max(raw, 0.001)), vec3(a));
	float inner = inner_right ? 1.0 - UV.x : UV.x;
	float feather = smoothstep(0.0, inner_feather, inner) * smoothstep(0.0, fade_bottom, 1.0 - UV.y)
		* smoothstep(0.0, fade_top, UV.y);
	COLOR = vec4(rgb * tint.rgb, a) * tint.a * feather;
}
