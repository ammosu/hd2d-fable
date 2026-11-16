// 前景失焦的楓葉框景：預先糊好的貼圖，貼在螢幕角落（畫在景深之後），隨風輕輕晃動
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mix;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);      // NDC 中心 x,y、半寬、半高
uniform vec4 tint : source_color = vec4(1.0);
uniform float phase = 0.0;
uniform vec2 corner = vec2(0.0, 0.0);      // 所在角落（螢幕 UV）
uniform vec2 extent = vec2(0.16, 0.2);     // 從角落往內多遠完全淡出（柔和遮罩，沒有卡片切邊）
uniform vec2 flip = vec2(1.0, 1.0);
void vertex() {
	vec2 sway = vec2(sin(TIME * 0.83 + phase), cos(TIME * 0.61 + phase)) * 0.006;
	POSITION = vec4(rect.x + VERTEX.x * rect.z + sway.x, -(rect.y + VERTEX.y * rect.w + sway.y), 1.0, 1.0);
}
void fragment() {
	vec2 uv = UV;
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb * tint.rgb;
	float d = length((SCREEN_UV - corner) / extent);
	ALPHA = c.a * tint.a * (1.0 - smoothstep(0.55, 1.0, d));
}
