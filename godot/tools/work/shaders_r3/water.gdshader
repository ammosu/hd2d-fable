// 運河水面：平面反射（鏡像相機的畫面），取樣對齊 4px 的點陣格，逐列橫移成像素波紋
shader_type spatial;
uniform sampler2D refl : source_color, filter_nearest, repeat_disable;
uniform vec4 deep : source_color = vec4(0.02, 0.035, 0.06, 1.0);
uniform float strength = 0.8;
uniform float snap_px = 4.0;
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
	r *= mix(1.0, smoothstep(1.0, 2.6, lum) * 0.8, near);
	ALBEDO = deep.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.2;
	EMISSION = vec3(0.016, 0.034, 0.085) + r * vec3(0.84, 0.94, 1.1) * strength + r * crest * 0.3 + vec3(1.0, 0.8, 0.55) * spk * 0.4 * strength;
}
