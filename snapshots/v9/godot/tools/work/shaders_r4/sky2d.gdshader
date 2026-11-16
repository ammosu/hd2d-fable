// 黃昏天空背板：掛在鏡頭正前方最遠處的一片四邊形，內容以螢幕座標計算（像一張 2D 像素畫）。
// 註：試過畫在 3D 後面的 CanvasLayer（背景透明）讓它不被景深糊掉，但 Godot 的景深不支援透明背景，所以仍在 3D 裡、會跟遠景一起失焦。
// 以 4 px 為一格：三段漸層＋有序抖色、夕陽圓盤與分階光暈、被夕陽從左下照亮的金邊雲（緩慢飄動）
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
uniform float gain = 1.0;
uniform sampler2D c0 : filter_nearest, repeat_disable;
uniform sampler2D c1 : filter_nearest, repeat_disable;
uniform sampler2D c2 : filter_nearest, repeat_disable;
uniform vec2 sun = vec2(66.0, 25.0);      // 夕陽位置（格）
uniform float horizon = 62.0;             // 漸層到這一列變成金色
float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0)); int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}
vec4 cloud(sampler2D t, vec2 cell, vec2 pos, float speed, vec2 size, float wrap) {
	vec2 p = pos; p.x = mod(pos.x + TIME * speed + size.x, wrap + size.x) - size.x;
	vec2 uv = (cell - p) / size;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return vec4(0.0);
	return texture(t, uv);
}
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 4.0);
	float b = bayer(cell);
	float t = clamp(cell.y / horizon, 0.0, 1.0);
	t = floor((t + (b - 0.5) * 0.09) * 14.0 + 0.5) / 14.0;
	vec3 top = vec3(0.17, 0.17, 0.43), mid1 = vec3(0.47, 0.3, 0.62), mid2 = vec3(0.93, 0.5, 0.47), bot = vec3(1.0, 0.8, 0.5);
	vec3 col = t < 0.4 ? mix(top, mid1, t / 0.4) : (t < 0.72 ? mix(mid1, mid2, (t - 0.4) / 0.32) : mix(mid2, bot, (t - 0.72) / 0.28));
	// 夕陽的光暈：橫向較寬，分階＋抖色
	vec2 d = (cell - sun) * vec2(0.55, 1.0);
	float g = exp(-length(d) / 26.0);
	g = floor((g + (b - 0.5) * 0.12) * 7.0 + 0.5) / 7.0;
	col = mix(col, vec3(1.0, 0.78, 0.42), clamp(g, 0.0, 1.0) * 0.85);
	float disc = length(cell - sun);
	if (disc < 16.0) col = mix(col, vec3(1.0, 0.9, 0.6), 0.55);
	if (disc < 9.0) col = vec3(1.0, 0.97, 0.82);
	// 雲：三張貼圖、五朵，各自速度不同（格 / 秒）
	vec4 k;
	k = cloud(c1, cell, vec2(250.0, 6.0), 0.5, vec2(122.0, 24.0) * 1.0, 480.0); col = mix(col, k.rgb, k.a);
	k = cloud(c0, cell, vec2(96.0, 9.0), 0.8, vec2(122.0, 36.0), 480.0); col = mix(col, k.rgb, k.a);
	k = cloud(c2, cell, vec2(330.0, 16.0), 1.1, vec2(121.0, 31.0), 480.0); col = mix(col, k.rgb, k.a);
	k = cloud(c1, cell, vec2(-10.0, 30.0), 1.4, vec2(122.0, 24.0), 480.0); col = mix(col, k.rgb, k.a);
	k = cloud(c2, cell, vec2(170.0, 34.0), 0.65, vec2(121.0, 31.0), 480.0); col = mix(col, k.rgb, k.a);
	// 雲離夕陽越近越亮
	ALBEDO = col * col * gain;      // 近似轉成線性，再交給色調映射
}
