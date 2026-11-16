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
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = floor(wp.xz * ppm + 0.001) / ppm;
	vec4 c = texture(tex, wp.xz * ppm / tex_px);
	float lum = dot(c.rgb, vec3(0.33));
	float n = noise(q * 0.9 + 3.0) * 0.6 + noise(q * 3.1 + 9.0) * 0.4;
	float pud = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 p = puddles[i];
		if (p.z > 0.0) {
			vec2 d = (q - p.xy) / p.zw;
			// 邊緣用雜訊咬一下；石頭亮面（凸起）比較晚淹
			pud = max(pud, step(dot(d, d) + (n - 0.5) * 0.7 + (lum - 0.3) * 0.5, 1.0));
		}
	}
	float damp = smoothstep(0.3, 0.6, n);
	vec3 col = c.rgb * tint.rgb;
	vec2 vp = VIEWPORT_SIZE;
	vec2 sp = (floor(FRAGCOORD.xy / snap_px) + 0.5) * snap_px;      // 倒影對齊 4px 的點陣格
	float row = floor(FRAGCOORD.y / snap_px);
	sp.x += floor(sin(row * 1.7 + TIME * 1.2) * 0.6 + 0.5) * snap_px;
	vec2 uv = vec2(sp.x / vp.x, 1.0 - sp.y / vp.y);
	vec3 r = texture(refl, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
	ALBEDO = mix(col * mix(1.0, 0.7, damp), col * 0.15, pud);
	ROUGHNESS = mix(mix(0.8, 0.5, damp) - lum * 0.15, 0.25, pud);
	SPECULAR = mix(0.3, 0.5, pud);
	EMISSION = r * refl_strength * pud;
}
