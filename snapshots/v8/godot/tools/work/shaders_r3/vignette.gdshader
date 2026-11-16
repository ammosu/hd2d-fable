shader_type canvas_item;
uniform float strength = 0.4;
uniform vec4 color : source_color = vec4(0.05, 0.02, 0.08, 1.0);
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.85);
	float v = smoothstep(0.32, 0.86, length(d));
	COLOR = vec4(color.rgb, v * strength);
}
