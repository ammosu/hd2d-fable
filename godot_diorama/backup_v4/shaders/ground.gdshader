// 雨後的石板路：整體微濕＋手擺的積水（鏡面，取樣街面的平面反射）。積水邊緣以點陣為單位。
shader_type spatial;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D refl : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float ppm = 32.0;
uniform vec2 tex_size = vec2(768.0, 109.0);
uniform vec2 origin = vec2(-14.0, -3.0);
uniform float refl_strength = 0.75;
uniform vec4 puddles[8];      // x, z, 半徑x, 半徑z
uniform float snap_px = 4.0;
uniform vec2 hero_xz = vec2(-99.0);
uniform float glow_len = 1.3;
uniform vec4 streaks[8];
uniform vec4 streak_cols[8];
uniform vec2 cam_xz;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

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

// 路燈在積水裡的倒影：沿「燈 → 鏡頭」方向拉長的暖金色光暈，上窄下寬、三階淡出，逐列隨波紋錯位並閃動，再疊幾條水平亮線
vec3 lamp_glow(vec3 p3, float t) {
	vec3 g = vec3(0.0);
	vec2 q = floor(p3.xz * 32.0 + 0.001) / 32.0;
	float rowz = floor(p3.z * 32.0);
	for (int i = 0; i < 2; i++) {
		vec4 s4 = streaks[i];
		vec2 dir = normalize(cam_xz - s4.xy);
		vec2 rel = q - s4.xy;
		float along = dot(rel, dir);
		float lat = dot(rel, vec2(dir.y, -dir.x));
		float u = clamp(along / glow_len, 0.0, 1.0);
		lat += floor(sin(rowz * 1.3 + t * 2.4 + float(i) * 2.0) * (0.3 + 0.9 * u) + 0.5) / 32.0;
		// 直立的光柱：寬度固定（核心 2 點陣、外圈 4 點陣），兩端淡出；逐列隨波紋錯位，並有幾列暗下去（水平階梯紋）
		float inner = step(abs(lat), 0.033);
		float outer = step(abs(lat), 0.066);
		float ends = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.7, 1.0, u));
		float gap = 1.0 - 0.6 * step(0.75, hash(vec2(rowz, floor(t * 3.0) + float(i))));
		g += vec3(1.0, 0.5, 0.12) * (inner * 1.15 + (outer - inner) * 0.4) * ends * gap * step(0.02, along);
	}
	return g;
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = floor(wp.xz * ppm + 0.001) / ppm;
	vec4 c = texture(tex, (wp.xz - origin) * ppm / tex_size);      // 這條街專用的大張貼圖，不平鋪
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
	EMISSION = (min(r, vec3(1.2)) * vec3(0.8, 0.85, 1.0) * refl_strength + lamp_glow(wp, TIME)) * pud;
}
