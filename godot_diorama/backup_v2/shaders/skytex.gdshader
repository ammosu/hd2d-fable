// 黃昏天空背板：手繪像素雲圖（5 px 一點陣），只在畫面最上緣露出一條；雲慢慢往右飄
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec2 tex_px = vec2(418.0, 235.0);
uniform float row0 = 120.0;
uniform float px = 5.0;
uniform float gain = 1.0;
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / px);
	vec2 uv = vec2((cell.x + floor(TIME * 0.6)) / tex_px.x, clamp((row0 + cell.y) / tex_px.y, 0.0, 0.995));
	vec3 c = texture(tex, uv).rgb;
	// 太陽那一側（左）的地平線附近染成金橘色
	float gl = exp(-pow((SCREEN_UV.x - 0.2) / 0.45, 2.0));
	c = mix(c, vec3(1.0, 0.62, 0.28), gl * 0.55) * (1.0 + gl * 0.6);
	ALBEDO = c * gain;
}
