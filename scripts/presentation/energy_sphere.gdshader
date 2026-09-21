shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 element_color : source_color = vec4(0.25,0.75,1.0,1.0);
uniform float progress = 0.0;
uniform float fade = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y,p.x);
	float body = smoothstep(0.65,0.18,r);
	float edge = exp(-pow((r - 0.51) * 19.0, 2.0));
	float curl = pow(max(0.0,sin(a*4.0-r*23.0+progress*13.0)),7.0);
	float veil = exp(-r*r*4.3);
	float filaments = curl * smoothstep(0.86,0.3,r) * smoothstep(0.13,0.44,r);
	float heart = exp(-dot(p-vec2(-0.10,-0.09),p-vec2(-0.10,-0.09))*75.0);
	vec3 light = element_color.rgb * (body*0.42 + edge*0.56 + filaments*0.70 + veil*0.09);
	light += vec3(1.0,0.98,0.90) * heart * 0.95;
	COLOR = vec4(light, fade * smoothstep(1.0,0.78,r));
}
