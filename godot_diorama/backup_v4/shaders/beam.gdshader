// 光束片（HD-2D 常用手法）：沿太陽方向的梯形四邊形，加法混合、不受光、靠近物體時淡出。
// 橫向是葉縫般的明暗條紋（不是平滑邊），上端漸隱進樹冠，亮度跟著全場共用的陣風起伏。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.76, 0.5, 1.0);
uniform float strength = 0.35;
uniform float seed_v = 0.0;
uniform float wx = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float gust(float t, float x) {
	return (0.5 + 0.5 * sin(t * 1.96 - x * 0.35)) * (0.65 + 0.35 * sin(t * 0.5 + x * 0.1));
}
void fragment() {
	// 葉縫條紋：幾道寬窄不一的亮帶，慢慢左右游移（葉子在動）
	float u = UV.x + (noise(vec2(UV.y * 2.0 + seed_v, TIME * 0.15)) - 0.5) * 0.08;
	float n1 = noise(vec2(u * 3.2 + seed_v * 3.1, seed_v + TIME * 0.07));
	float n2 = noise(vec2(u * 8.0 + seed_v * 7.7, seed_v * 2.0 - TIME * 0.11));
	float gaps = smoothstep(0.25, 0.7, n1) * (0.6 + 0.4 * smoothstep(0.2, 0.8, n2));
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	float along = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.6, UV.y);
	float dust = 0.8 + 0.2 * noise(vec2(UV.x * 5.0 + seed_v, UV.y * 6.0 - TIME * 0.25));
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float prox = clamp((-up.z / up.w + VERTEX.z) / 0.8, 0.0, 1.0);
	float breathe = 0.85 + 0.3 * gust(TIME, wx);
	ALBEDO = color.rgb * gaps * edge * along * dust * prox * strength * breathe * 1.6;
}
