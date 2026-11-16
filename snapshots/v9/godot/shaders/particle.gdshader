// 粒子（落葉、煙、光塵）：像素貼圖多格動畫，依粒子年齡翻面
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform float frames = 4.0;
uniform float flips = 10.0;
uniform bool by_age = false;      // 依粒子年齡播放（煙：小 → 大 → 散）
uniform float glow_all = 0.0;
uniform float backlight = 0.6;
uniform vec4 tint : source_color = vec4(1.0);
uniform float vary = 0.0;      // 每片亮度的差異（落葉：有的在光裡、有的在陰影裡）
varying float fr;
varying float rnd;
void vertex() {
	float r = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	rnd = fract(r * 7.31);
	fr = by_age ? min(floor(INSTANCE_CUSTOM.y * frames), frames - 1.0) : floor(mod(INSTANCE_CUSTOM.y * flips * (0.6 + r) + r * frames, frames));
}
void fragment() {
	vec4 c = texture(tex, vec2((UV.x + fr) / frames, UV.y));
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * tint.rgb * mix(1.0, 0.45 + 0.55 * rnd, vary);
	ROUGHNESS = 0.9;
	BACKLIGHT = c.rgb * backlight;
	EMISSION = c.rgb * tint.rgb * glow_all;
}
