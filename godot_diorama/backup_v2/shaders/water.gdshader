// 運河水面：平面反射（鏡像相機的畫面），取樣對齊 4px 的點陣格，逐列橫移成像素波紋
shader_type spatial;
uniform sampler2D refl : source_color, filter_nearest, repeat_disable;
uniform vec4 deep : source_color = vec4(0.02, 0.035, 0.06, 1.0);
uniform float strength = 0.8;
uniform float snap_px = 3.0;
uniform float quay_z = 2.4;
global uniform float mask_mode;
uniform vec4 streaks[8];
uniform vec4 streak_cols[8];
uniform vec2 cam_xz;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// 燈光的倒影光條：每個真實光源一條，沿「光源 → 鏡頭」連線延伸。
// 靠岸：短線長、密、亮，接近連續的光柱；越近鏡頭：越短、越散、越暗，最後只剩零星亮點。每條的節奏與相位不同。
vec3 light_streaks(vec3 p3, float t) {
	vec3 sk = vec3(0.0);
	float qx = floor(p3.x * 32.0) / 32.0;
	float qz = floor(p3.z * 32.0);
	for (int i = 0; i < 8; i++) {
		vec4 s4 = streaks[i];
		float d = p3.z - s4.y;
		if (s4.w > 0.0 && d > 0.0) {
			float len = streak_cols[i].a;
			float u = clamp(d / len, 0.0, 1.0);
			float xl = s4.x + (cam_xz.x - s4.x) * d / (cam_xz.y - s4.y);
			float seed = fract(s4.x * 0.731 + s4.y * 0.317) * 50.0;
			float spd = 1.6 + fract(seed * 0.37) * 1.6;
			float h1 = hash(vec2(qz + seed, floor(t * spd + seed)));
			float h2 = hash(vec2(qz * 1.7 + seed, 7.0 + floor(t * spd * 0.7)));
			float wob = floor((h2 - 0.5) * (0.6 + 5.0 * u) + 0.5) / 32.0;       // 橫向散開：越遠越大
			float hw = s4.z * mix(1.5, 0.45, u) * (0.6 + 0.8 * h2);            // 短線長度：越遠越短
			float inside = step(abs(qx - xl - wob), hw);
			float present = step(u * 1.05 - 0.12, h1);                          // 出現機率：靠岸幾乎每列都有，遠處零星
			float fade = pow(1.0 - u, 1.4);
			sk += streak_cols[i].rgb * s4.w * inside * present * fade;
		}
	}
	return sk;
}

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 vp = VIEWPORT_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / snap_px);
	float t = TIME;
	// 離岸越遠（越靠近鏡頭）波紋越大
	float far = clamp((wp.z - quay_z) / 5.0, 0.0, 1.0);
	float amp = mix(0.3, 1.8, far * far);
	float wx = floor(wp.x * 2.0);
	float a = sin(cell.y * 0.9 + t * 1.5 + wx * 0.7) + sin(cell.y * 2.3 - t * 1.0 + wx * 0.3) * 0.6;
	float b = sin(cell.y * 0.6 + cell.x * 0.11 + t * 0.9);
	vec2 sp = (cell + 0.5) * snap_px;
	sp.x += floor(a * amp + 0.5) * snap_px;
	sp.y += floor(b * amp * 0.35 + 0.5) * snap_px;
	vec2 uv = vec2(sp.x / vp.x, 1.0 - sp.y / vp.y);
	vec3 r = texture(refl, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
	float crest = step(1.35, a + b * 0.4);
	float spk = step(0.996, hash(cell + floor(t * 4.0)));
	float lum = dot(r, vec3(0.3, 0.55, 0.15));
	r = min(r, vec3(1.6)) * vec3(0.95, 0.85, 1.05) * mix(1.0, 0.45, far);
	vec3 sk = light_streaks(wp, t);
	// 夕陽碎光：左側（太陽那一邊）水面上一段段橫向的橘金色短線，隨波紋閃動；其餘水面零星幾段粉紫色天光
	float row = cell.y;
	float seg = floor(cell.x / (2.0 + floor(hash(vec2(row, 3.0)) * 4.0)) + hash(vec2(row, 9.0)) * 7.0);
	float hh = hash(vec2(seg, row + floor(t * (1.5 + hash(vec2(row, 5.0))))));
	float sunw = exp(-pow((wp.x + 6.5 - (wp.z - quay_z) * 0.5) / 3.2, 2.0));
	float glit = step(1.0 - 0.34 * sunw, hh) * smoothstep(0.04, 0.2, far);
	float skyd = step(0.975, hh) * (1.0 - sunw) * smoothstep(0.1, 0.4, far);
	vec3 glitter = vec3(1.0, 0.56, 0.22) * glit * 0.75 + vec3(0.75, 0.42, 0.62) * skyd * 0.35;
	ALBEDO = deep.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.2;
	float skm = clamp(max(sk.r, max(sk.g, sk.b)) * 1.5, 0.0, 0.9);
	// 靠堤岸水色最深（牆的倒影與陰影），往鏡頭方向帶一點天空的藍紫
	vec3 body = mix(vec3(0.008, 0.012, 0.04), vec3(0.03, 0.035, 0.1), smoothstep(0.0, 0.5, far));
	vec3 base = body + r * vec3(0.9, 0.95, 1.1) * strength + r * crest * 0.3 + vec3(1.0, 0.8, 0.55) * spk * 0.12 * strength + glitter * strength;
	EMISSION = base * (1.0 - skm) + sk * 1.6;
	if (mask_mode > 0.5) { ALBEDO = vec3(0.0); EMISSION = vec3(0.0); }
}
