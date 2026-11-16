// 黃昏天空背板：只在畫面上緣露出一條。暖黃（屋頂線上方）→ 粉紫 → 藍紫（畫面頂端）的漸層，
// 幾條被夕陽從下方照亮的像素雲；全部以 4 px 的點陣格計算、Bayer 抖色。
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
uniform float band = 0.27;      // 天空帶的高度（佔畫面高的比例）
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
	vec2 fine = floor(FRAGCOORD.xy / 2.0);      // 漸層用 2 px 的細抖色＋較多色階，不出現橫向色帶
	vec2 vp = VIEWPORT_SIZE / 4.0;
	float t = clamp(FRAGCOORD.y / (VIEWPORT_SIZE.y * band), 0.0, 1.0);      // 0 = 畫面頂端，1 = 屋頂線
	float sunx = exp(-pow((FRAGCOORD.x / VIEWPORT_SIZE.x - 0.22) / 0.4, 2.0));
	vec3 top = vec3(0.2, 0.22, 0.5), mid = vec3(0.5, 0.33, 0.56), low = vec3(0.98, 0.62, 0.38), glow = vec3(1.0, 0.84, 0.5);
	vec3 c = mix(top, mid, smoothstep(0.0, 0.6, t));
	c = mix(c, low, smoothstep(0.45, 1.0, t));
	c = mix(c, glow, smoothstep(0.6, 1.0, t) * sunx);
	c = floor(c * 56.0 + bayer(fine)) / 56.0;
	// 雲：幾朵成團的像素雲（不是一條條橫紋），底緣被夕陽染成金橘
	vec2 cp = vec2(cell.x * 0.022 + TIME * 0.01, cell.y * 0.075);
	float n = noise(cp) * 0.6 + noise(cp * 2.3 + 7.0) * 0.28 + noise(cp * 5.0 + 3.0) * 0.12;
	vec2 cq = vec2(cell.x * 0.022 + TIME * 0.01, (cell.y + 2.0) * 0.075);
	float nb = noise(cq) * 0.6 + noise(cq * 2.3 + 7.0) * 0.28 + noise(cq * 5.0 + 3.0) * 0.12;
	if (n > 0.63) {
		vec3 cc = mix(vec3(0.36, 0.25, 0.52), vec3(0.72, 0.4, 0.48), t);
		c = mix(cc, vec3(1.0, 0.64, 0.36), step(nb, 0.63) * (0.45 + 0.55 * sunx));
	}
	ALBEDO = c * c;
}
