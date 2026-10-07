shader_type canvas_item;
render_mode blend_add, unshaded;
uniform float phase = 0.0;
varying vec4 layer_tint;
void vertex() { layer_tint = COLOR; }
void fragment() {
    vec2 uv = UV;
    float edge = sin(UV.x * 3.14159265) * sin(UV.y * 3.14159265);
    uv.x += sin(UV.y * 12.0 - phase * 4.1) * 0.009 * edge;
    uv.y += sin(UV.x * 9.0 + phase * 3.2) * 0.006 * edge;
    COLOR = layer_tint * texture(TEXTURE, uv);
}
