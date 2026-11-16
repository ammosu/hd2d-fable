// 廣場地面：整片專用的不重複石板貼圖（UV 由世界座標對應），少量積水（低粗糙度＋天光），角色腳下的接觸陰影。
shader_type spatial;
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 puddles[8];      // x, z, 半徑x, 半徑z
uniform vec4 blobs[8];        // x, z, 半徑x, 半徑z（接觸陰影）
uniform vec3 lamps[4];        // x, z, 強度：積水裡映出附近的燈
uniform vec3 sky_col : source_color = vec3(0.3, 0.26, 0.5);
global uniform float mask_mode;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = floor(wp.xz * 32.0 + 0.001) / 32.0;
	vec4 c = texture(tex, UV);
	float lum = dot(c.rgb, vec3(0.33));
	float pud = 0.0; float rimm = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 p = puddles[i];
		if (p.z > 0.0) {
			// 不規則水窪：石縫（暗）先淹、石面亮處晚淹
			vec2 d = (q - p.xy) / p.zw;
			float rr = length(d) + (noise(q * 2.1 + p.xy * 3.0) - 0.5) * 0.9 + (noise(q * 7.0 + 5.0) - 0.5) * 0.3 + (lum - 0.42) * 1.2;
			pud = max(pud, step(rr, 1.0));
			rimm = max(rimm, step(rr, 1.15));
		}
	}
	rimm *= 1.0 - pud;
	float blob = 1.0;
	for (int i = 0; i < 8; i++) {
		vec4 b = blobs[i];
		if (b.z > 0.0) {
			float r = length((q - b.xy) / b.zw);
			blob *= 1.0 - 0.5 * (1.0 - smoothstep(0.35, 1.0, r));
		}
	}
	vec3 col = c.rgb * tint.rgb;
	ALBEDO = mix(col, col * 0.3, pud) * blob * (1.0 - 0.25 * rimm);
	ROUGHNESS = mix(0.85 - lum * 0.2, 0.08, pud);
	SPECULAR = mix(0.25, 0.6, pud);
	EMISSION = sky_col * pud * 0.1 * blob * (0.7 + 0.6 * noise(q * 3.0 + vec2(TIME * 0.2, 0.0)));
	for (int i = 0; i < 4; i++) {
		float dl = length(q - lamps[i].xy);
		float rip = step(0.78, fract(q.y * 5.0 + sin(q.x * 6.0 + TIME * 1.2) * 0.25));
		EMISSION += vec3(1.0, 0.55, 0.2) * pud * lamps[i].z * smoothstep(2.2, 0.3, dl) * (0.5 + 0.5 * rip) * 0.3;
	}
	if (mask_mode > 0.5) { ALBEDO = vec3(0.0); EMISSION = vec3(1.0); SPECULAR = 0.0; ROUGHNESS = 1.0; }
}
