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
uniform vec3 steps_box = vec3(5.9, 1.0, 1.28);      // 石階：中心 x、半寬、伸進水裡的長度
uniform vec4 floaters[2];      // 船、浮標：x, z, 半長, 半寬
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// 燈光的倒影光條：每個真實光源一條，沿「光源 → 鏡頭」連線延伸。
// 靠岸：短線長、密、亮，接近連續的光柱；越近鏡頭：越短、越散、越暗，最後只剩零星亮點。每條的節奏與相位不同。
vec3 light_streaks(vec3 p3, float t) {
	// 每個光源一條倒影光柱：從堤岸邊開始、沿「光源 → 鏡頭」的連線往鏡頭方向延伸（畫面上是對齊光源的垂直光條）。
	// 靠岸：寬、密、亮；越往鏡頭：一段一段斷開、左右錯位、漸暗。
	vec3 sk = vec3(0.0);
	float qx = floor(p3.x * 32.0) / 32.0;
	float qz = floor(p3.z * 32.0);
	for (int i = 0; i < 8; i++) {
		vec4 s4 = streaks[i];
		float z0 = max(s4.y, quay_z);
		float d = p3.z - z0;
		if (s4.w > 0.0 && d > 0.0) {
			float len = streak_cols[i].a;
			float u = clamp(d / len, 0.0, 1.0);
			float xl = s4.x + (cam_xz.x - s4.x) * (p3.z - s4.y) / (cam_xz.y - s4.y);
			float seed = fract(s4.x * 0.731 + s4.y * 0.317) * 50.0;
			float spd = 1.4 + fract(seed * 0.37) * 1.4;
			float h1 = hash(vec2(qz + seed, floor(t * spd + seed)));
			float h2 = hash(vec2(qz * 1.7 + seed, 7.0 + floor(t * spd * 0.7)));
			float wob = floor((h2 - 0.5) * (1.0 + 5.0 * u) + 0.5) / 32.0;
			float hw = s4.z * mix(1.1, 0.45, u) * (0.5 + 0.8 * h2);
			float inside = step(abs(qx - xl - wob), hw);
			float present = step(u * 1.0 - 0.12, h1);
			float fade = pow(1.0 - u, 0.9);
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
	float spk = step(0.997, hash(cell + floor(t * 4.0)));
	r = min(r, vec3(1.3)) * mix(0.3, 1.0, smoothstep(0.1, 0.8, far));      // 靠岸暗（映到的是堤岸牆）、往鏡頭方向漸亮（映到天空）
	vec3 sk = light_streaks(wp, t);
	// 夕陽碎光：只在左側（太陽那邊）一小片，短橫線隨波閃動
	float row = cell.y;
	float seg = floor(cell.x / (2.0 + floor(hash(vec2(row, 3.0)) * 4.0)) + hash(vec2(row, 9.0)) * 7.0);
	float hh = hash(vec2(seg, row + floor(t * (1.5 + hash(vec2(row, 5.0))))));
	float sunw = exp(-pow((wp.x + 7.5 - (wp.z - quay_z) * 0.5) / 2.4, 2.0));
	float glit = step(1.0 - 0.2 * sunw, hh) * smoothstep(0.06, 0.25, far);
	vec3 glitter = vec3(1.0, 0.58, 0.24) * glit * 0.6;
	// 船與浮標四周：接觸暗部＋一圈圈往外擴的像素漣漪
	vec2 q = floor(wp.xz * 32.0) / 32.0;
	float ring = 0.0; float contact = 1.0;
	for (int i = 0; i < 2; i++) {
		vec4 e = floaters[i];
		if (e.z > 0.0) {
			float dd = length((q - e.xy) / e.zw);
			contact *= mix(0.35, 1.0, smoothstep(0.95, 1.35, dd));
			float ph = fract(dd * (i == 0 ? 2.2 : 1.2) - t * 0.35);
			ring += step(0.86, ph) * smoothstep(2.6, 1.05, dd) * step(1.02, dd);
		}
	}
	// 石階與石墩入水處：一圈斷斷續續的白色水沫＋外圍一圈暗（濕、有倒影）
	vec2 sd2 = vec2(abs(q.x - steps_box.x) - (steps_box.y + (q.y - quay_z < 1.0 ? 0.33 : 0.0)), (q.y - quay_z) - steps_box.z);
	float sdist = length(max(sd2, vec2(0.0))) + min(max(sd2.x, sd2.y), 0.0);
	float foam = step(0.0, sdist) * step(sdist, 0.05) * step(0.4, hash(floor(q * 32.0) + floor(t * 2.0)));
	foam += step(0.08, sdist) * step(sdist, 0.14) * step(0.9, hash(floor(q * 32.0) + floor(t * 1.3) + 5.0));
	contact *= mix(0.45, 1.0, smoothstep(0.0, 0.45, sdist));
	ALBEDO = deep.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.2;
	float skm = clamp(max(sk.r, max(sk.g, sk.b)) * 1.5, 0.0, 0.9);
	// 水體：靠堤岸最深（牆的陰影），往鏡頭方向反射天空（由暖粉過渡到藍紫的漸層），整體壓暗讓廣場是主角
	vec3 skyrefl = mix(vec3(0.085, 0.055, 0.075), vec3(0.03, 0.04, 0.095), smoothstep(0.15, 0.9, far));
	vec3 body = mix(vec3(0.006, 0.01, 0.028), skyrefl, smoothstep(0.0, 0.35, far));
	vec3 base = (body + r * vec3(0.85, 0.9, 1.0) * strength * 0.55 + r * crest * 0.2 + vec3(1.0, 0.8, 0.55) * spk * 0.1 * strength) * contact + glitter * strength + vec3(0.5, 0.42, 0.55) * ring * 0.16 + vec3(0.75, 0.72, 0.8) * foam * 0.32;
	EMISSION = base * (1.0 - skm * 0.8) + sk * 0.8 * contact;
	if (mask_mode > 0.5) { ALBEDO = vec3(0.0); EMISSION = vec3(0.0); }
}
