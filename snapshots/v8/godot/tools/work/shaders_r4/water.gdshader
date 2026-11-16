// 運河水面：平面反射（鏡像相機的畫面），取樣對齊 4px 的點陣格，逐列橫移成像素波紋
shader_type spatial;
uniform sampler2D refl : source_color, filter_nearest, repeat_disable;
uniform vec4 deep : source_color = vec4(0.02, 0.035, 0.06, 1.0);
uniform float strength = 0.8;
uniform float snap_px = 4.0;
uniform vec4 streaks[10];        // x、起點 z、半寬、強度
uniform vec3 streak_cols[10];
uniform vec2 cam_xz;
uniform int glitter_idx = 8;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 vp = VIEWPORT_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / snap_px);
	float t = TIME;
	// 離岸越遠（越靠近鏡頭）波紋越大
	float far = clamp((wp.z - 0.6) / 4.5, 0.0, 1.0);
	float amp = mix(0.35, 2.2, far * far);
	float wx = floor(wp.x * 2.0);
	float a = sin(cell.y * 0.9 + t * 1.5 + wx * 0.7) + sin(cell.y * 2.3 - t * 1.0 + wx * 0.3) * 0.6;
	float b = sin(cell.y * 0.6 + cell.x * 0.11 + t * 0.9);
	vec2 sp = (cell + 0.5) * snap_px;
	sp.x += floor(a * amp + 0.5) * snap_px;
	sp.y += floor(b * amp * 0.35 + 0.5) * snap_px;
	vec2 uv = vec2(sp.x / vp.x, 1.0 - sp.y / vp.y);
	vec3 r = texture(refl, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
	float crest = step(1.35, a + b * 0.4);
	float spk = step(0.997, hash(cell + floor(t * 4.0)));
	// 越靠近鏡頭反射越淡、露出深水色；近處只留下亮的東西（燈、窗）的長條倒影
	float near = smoothstep(0.1, 0.5, far);
	float lum = dot(r, vec3(0.3, 0.55, 0.15));
	r = min(r, vec3(1.6)) * mix(1.0, 0.3, near);
	// 燈光的縱向長條倒影：沿「光源 → 鏡頭」的連線拉長，以場景點陣為單位、逐列錯位並斷續閃爍
	vec3 sk = vec3(0.0);
	float qx = floor(wp.x * 32.0) / 32.0;
	float qz = floor(wp.z * 32.0);
	for (int i = 0; i < 10; i++) {
		vec4 s4 = streaks[i];
		if (s4.w > 0.0 && wp.z > s4.y) {
			float tz = (wp.z - s4.y) / (cam_xz.y - s4.y);
			float xl = s4.x + (cam_xz.x - s4.x) * tz;
			float fi = float(i);
			float wob = floor(sin(qz * 0.9 + t * 2.2 + fi * 1.7) * 1.6 + 0.5) / 32.0;
			float hw = s4.z * (1.0 + far * 1.2);
			float inside = step(abs(qx - xl - wob), hw);
			float seg = step(i == glitter_idx ? 0.7 : 0.4, hash(vec2(qz + fi * 13.0, floor(t * 3.0 + fi)) + (i == glitter_idx ? floor(qx * 8.0) : 0.0)));
			float fade = 1.0 - smoothstep(0.0, i == glitter_idx ? 5.5 : 4.2, wp.z - s4.y);
			sk += (i == glitter_idx ? vec3(1.0, 0.6, 0.22) : vec3(1.0, 0.42, 0.1)) * s4.w * inside * seg * fade;
		}
	}
	ALBEDO = deep.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.2;
	float skm = clamp(max(sk.r, max(sk.g, sk.b)) * 1.5, 0.0, 0.9);      // 光條蓋掉底下的藍色水面，顏色才不會被沖淡
	vec3 base = vec3(0.016, 0.034, 0.085) * mix(1.6, 0.8, far) + r * vec3(0.84, 0.94, 1.1) * strength + r * crest * 0.3 + vec3(1.0, 0.8, 0.55) * spk * 0.4 * strength;
	EMISSION = base * (1.0 - skm) + sk;
}
