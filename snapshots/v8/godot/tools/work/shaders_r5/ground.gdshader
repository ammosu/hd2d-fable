// 雨後的石板路：整體微濕＋手擺的積水（鏡面，取樣街面的平面反射）。積水邊緣以點陣為單位。
shader_type spatial;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D refl : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float ppm = 32.0;
uniform float tex_px = 64.0;
uniform float refl_strength = 0.75;
uniform vec4 puddles[8];      // x, z, 半徑x, 半徑z
uniform float snap_px = 4.0;
uniform vec2 hero_xz = vec2(-99.0);
uniform vec4 streaks[8];
uniform vec4 streak_cols[8];
uniform vec2 cam_xz;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// 燈光的倒影光條：每個真實光源一條，沿「光源 → 鏡頭」連線延伸；靠光源處完整，越遠越寬、越碎、越暗
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
			float fi = float(i);
			float wob = floor(sin(qz * 0.9 + t * 2.2 + fi * 1.7) * (0.3 + 2.2 * u) + 0.5) / 32.0;
			float hw = s4.z * (1.0 + u * 1.6);
			float inside = step(abs(qx - xl - wob), hw);
			float seg = step(u * 0.85 - 0.08, hash(vec2(qz + fi * 13.0, floor(t * 3.0 + fi))));
			float fade = (1.0 - smoothstep(0.25, 1.0, u)) * (0.55 + 0.45 * (1.0 - u));
			sk += streak_cols[i].rgb * s4.w * inside * seg * fade;
		}
	}
	return sk;
}

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = floor(wp.xz * ppm + 0.001) / ppm;
	vec4 c = texture(tex, wp.xz * ppm / tex_px);
	float lum = dot(c.rgb, vec3(0.33));
	float n = noise(q * 0.9 + 3.0) * 0.6 + noise(q * 3.1 + 9.0) * 0.4;
	float pud = 0.0; float rimm = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 p = puddles[i];
		if (p.z > 0.0) {
			// 不規則水窪：圓形距離加上兩層雜訊（大的改變輪廓、小的咬邊），石頭亮面晚淹
			vec2 d = (q - p.xy) / p.zw;
			float rr = length(d) + (noise(q * 2.1 + p.xy * 3.0) - 0.5) * 0.9 + (noise(q * 7.0 + 5.0) - 0.5) * 0.3 + (lum - 0.3) * 0.3;
			pud = max(pud, step(rr, 1.0));
			rimm = max(rimm, step(rr, 1.12));
		}
	}
	rimm = rimm * (1.0 - pud);
	float damp = smoothstep(0.3, 0.6, n);
	vec3 col = c.rgb * tint.rgb;
	vec2 vp = VIEWPORT_SIZE;
	vec2 sp = (floor(FRAGCOORD.xy / snap_px) + 0.5) * snap_px;      // 倒影對齊 4px 的點陣格
	float row = floor(FRAGCOORD.y / snap_px);
	sp.x += floor(sin(row * 1.7 + TIME * 1.2) * 0.6 + 0.5) * snap_px;
	vec2 uv = vec2(sp.x / vp.x, 1.0 - sp.y / vp.y);
	vec3 r = texture(refl, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
	float blob = 1.0 - 0.45 * (1.0 - smoothstep(0.1, 0.34, length((q - hero_xz) * vec2(1.0, 1.6))));   // 主角腳下的接地陰影
	ALBEDO = mix(col * mix(1.0, 0.7, damp), col * 0.15, pud) * blob + col * rimm * 0.5;
	ROUGHNESS = mix(mix(0.8, 0.5, damp) - lum * 0.15, 0.25, pud);
	SPECULAR = mix(0.3, 0.5, pud);
	EMISSION = (min(r, vec3(1.2)) * vec3(0.8, 0.85, 1.0) * refl_strength + light_streaks(wp, TIME) * 0.8) * pud;
}
