// 黃昏天空背板：只在畫面上緣露出一條。暖黃（屋頂線上方）→ 粉紫 → 藍紫（畫面頂端）的漸層，
// 幾條被夕陽從下方照亮的像素雲；全部以 4 px 的點陣格計算、Bayer 抖色。
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
uniform float band = 0.27;      // 天空帶的高度（佔畫面高的比例）
uniform float night = 0.0;      // 1 = 藍調時刻（燈塔站）：天頂深藍、地平線殘留橘光、有星星
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0)); int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 4.0);
	vec2 vp = VIEWPORT_SIZE / 4.0;
	float t = clamp(cell.y / (vp.y * band), 0.0, 1.0);      // 0 = 畫面頂端，1 = 屋頂線
	float sunx = exp(-pow((cell.x / vp.x - 0.22) / 0.4, 2.0));
	vec3 top = mix(vec3(0.17, 0.2, 0.46), vec3(0.05, 0.06, 0.2), night), mid = mix(vec3(0.6, 0.36, 0.52), vec3(0.3, 0.22, 0.5), night), low = mix(vec3(1.0, 0.66, 0.34), vec3(0.95, 0.5, 0.42), night), glow = vec3(1.0, 0.86, 0.5);
	vec3 c = mix(top, mid, smoothstep(0.0, 0.55, t));
	c = mix(c, low, smoothstep(0.4, 0.9, t));
	c = mix(c, glow, smoothstep(0.6, 1.0, t) * sunx);
	c = floor(c * 20.0 + bayer(cell)) / 20.0;
	// 雲：橫向拉長的雜訊帶，底緣被夕陽染成金橘、上半是冷紫
	float n = noise(vec2(cell.x * 0.035 + TIME * 0.012, cell.y * 0.16)) * 0.65 + noise(vec2(cell.x * 0.09 - TIME * 0.008, cell.y * 0.3 + 4.0)) * 0.35;
	float cl = step(0.6, n + (1.0 - t) * 0.06);
	float under = step(0.6, noise(vec2(cell.x * 0.035 + TIME * 0.012, (cell.y - 1.0) * 0.16)) * 0.65 + noise(vec2(cell.x * 0.09 - TIME * 0.008, (cell.y - 1.0) * 0.3 + 4.0)) * 0.35 + (1.0 - t) * 0.06);
	vec3 cc = mix(vec3(0.42, 0.26, 0.5), vec3(0.8, 0.42, 0.44), t);
	if (cl > 0.5) c = mix(cc, vec3(1.0, 0.66, 0.36), (1.0 - under) * (0.5 + 0.5 * sunx));
	if (night > 0.0 && t < 0.6 && cl < 0.5 && hash(cell) > 0.994) c = mix(c, vec3(1.0, 0.95, 0.85), night * (0.6 + 0.4 * sin(TIME * 2.0 + hash(cell + 3.0) * 20.0)));
	ALBEDO = c * c;
}
