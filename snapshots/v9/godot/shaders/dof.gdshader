// 自製景深（取代引擎內建的）：全螢幕四邊形，在透明階段讀畫面與深度做圓盤模糊。
// 這樣可以自己決定誰要糊：前景與屋後的遠景照距離漸進模糊（移軸感），但「天空背板」不糊 → 雲與遠山保持清楚的點陣。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float near_start = 18.0;
uniform float near_trans = 3.5;
uniform float far_start = 24.0;
uniform float far_trans = 4.5;
uniform float sky_dist = 150.0;       // 比這更遠的（天空背板）不模糊
uniform float sky_blur = 1.6;
uniform float max_r = 9.0;            // 最大模糊半徑（px）
float lin_depth(vec2 uv, mat4 inv) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}
float coc(float z) {
	if (z > sky_dist) return sky_blur;      // 天空只輕微柔化，雲形仍清楚，和失焦的遠景比較接得上
	return max(clamp((z - far_start) / far_trans, 0.0, 1.0), clamp((near_start - z) / near_trans, 0.0, 1.0)) * max_r;
}
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float zc = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float cc = coc(zc);
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb;
	float wsum = 1.0;
	if (cc > 0.5) {
		for (int i = 0; i < 40; i++) {
			float fi = float(i) + 0.5;
			float r = sqrt(fi / 40.0) * cc;
			float a = fi * 2.399963;
			vec2 uv = SCREEN_UV + vec2(cos(a), sin(a)) * r * px;
			float zs = lin_depth(uv, INV_PROJECTION_MATRIX);
			float cs = coc(zs);
			// 比自己近而且是清楚的東西（焦平面上的屋子、角色）不滲進來；天空可以滲進樹梢
			float w = zs >= zc - 0.5 ? 1.0 : clamp(cs - r + 1.0, 0.0, 1.0);
			acc += texture(screen_tex, uv).rgb * w;
			wsum += w;
		}
	}
	ALBEDO = acc / wsum;
}
