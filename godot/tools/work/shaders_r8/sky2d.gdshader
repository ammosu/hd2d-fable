// 黃昏天空背板：掛在鏡頭正前方最遠處的一片四邊形，內容以螢幕座標計算（一張會動的 2D 像素畫，4 px 一格）。
// 景深的處理：景深是自製的（dof.gdshader），它把比 150 m 遠的東西（就是這片背板）排除在模糊之外，
// 所以天空、雲、遠山保持銳利的點陣。
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
uniform sampler2D c0 : filter_nearest, repeat_disable;
uniform sampler2D c1 : filter_nearest, repeat_disable;
uniform sampler2D c2 : filter_nearest, repeat_disable;
uniform vec2 s0 = vec2(122.0, 36.0);
uniform vec2 s1 = vec2(122.0, 24.0);
uniform vec2 s2 = vec2(121.0, 31.0);
uniform vec2 sun = vec2(104.0, 80.0);      // 夕陽的位置（格）：在楓樹後面、地平線附近
uniform float horizon = 84.0;
uniform float gain = 1.0;
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
vec4 cloud(sampler2D t, vec2 cell, vec2 pos, float speed, vec2 size, float flip) {
	float wrap = 480.0 + size.x;
	vec2 p = pos; p.x = mod(pos.x + TIME * speed + size.x, wrap) - size.x;
	vec2 uv = (cell - p) / size;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return vec4(0.0);
	if (flip > 0.5) uv.x = 1.0 - uv.x;
	return texture(t, uv);
}
// 一排針葉樹與丘陵的剪影：回傳 1 表示在剪影內
float ridge(vec2 cell, float base, float amp, float seed, float tree_w) {
	float x = cell.x + seed * 37.0;
	float h = base + sin(x * 0.021 + seed) * amp + sin(x * 0.057 + seed * 2.0) * amp * 0.4;
	float i = floor(x / tree_w);
	float cx = (i + 0.5) * tree_w + (hash(i + seed) - 0.5) * tree_w * 0.5;
	float th = step(0.45, hash(i * 1.7 + seed)) * (6.0 + hash(i * 3.1 + seed) * 12.0);
	float dy = cell.y - (h - th);          // 距離樹尖幾格
	float tree = step(0.0, dy) * step(abs(x - cx), 0.6 + floor(dy / 2.0) * 0.7);
	return max(step(h, cell.y), tree);
}
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 4.0);
	float t = clamp(cell.y / horizon, 0.0, 1.0);
	t = floor(t * 16.0 + 0.5) / 16.0;
	vec3 top = vec3(0.2, 0.13, 0.36), mid1 = vec3(0.42, 0.23, 0.5), mid2 = vec3(0.72, 0.36, 0.52), bot = vec3(0.98, 0.56, 0.4);
	vec3 col = t < 0.45 ? mix(top, mid1, t / 0.45) : (t < 0.8 ? mix(mid1, mid2, (t - 0.45) / 0.35) : mix(mid2, bot, (t - 0.8) / 0.2));
	// 夕陽在樹後的光暈（橫向較寬，分階）
	vec2 d = (cell - sun) * vec2(0.5, 1.0);
	float g = floor(exp(-length(d) / 30.0) * 6.0 + 0.5) / 6.0;
	col = mix(col, vec3(1.0, 0.68, 0.36), clamp(g, 0.0, 1.0) * 0.8);
	// 雲：多朵疊成雲堤，各自速度不同（格 / 秒）
	vec4 k;
	k = cloud(c1, cell, vec2(300.0, 2.0), 0.35, s1, 0.0); col = mix(col, k.rgb, k.a);
	k = cloud(c0, cell, vec2(50.0, 6.0), 0.5, s0, 0.0); col = mix(col, k.rgb, k.a);
	k = cloud(c1, cell, vec2(150.0, 26.0), 0.45, s1, 1.0); col = mix(col, k.rgb, k.a);
	k = cloud(c0, cell, vec2(340.0, 46.0), 0.65, s0, 1.0); col = mix(col, k.rgb, k.a);
	k = cloud(c0, cell, vec2(-60.0, 40.0), 0.8, s0, 0.0); col = mix(col, k.rgb, k.a);
	// 遠山與針葉林剪影（兩層，越遠越接近天空色）
	if (ridge(cell, horizon - 16.0, 5.0, 1.0, 13.0) > 0.5) col = mix(col, vec3(0.34, 0.2, 0.42), 0.8);
	if (ridge(cell, horizon - 6.0, 4.0, 5.0, 9.0) > 0.5) col = vec3(0.17, 0.11, 0.26);
	col = mix(vec3(dot(col, vec3(0.3, 0.55, 0.15))), col, 0.85);      // 天空略降飽和，和場景的調色一致
	ALBEDO = col * col * gain;      // 近似轉成線性，再交給色調映射
}
