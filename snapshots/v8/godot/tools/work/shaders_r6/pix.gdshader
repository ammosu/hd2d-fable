// 像素貼圖共用材質：nearest 取樣、alpha 以 discard 處理（走不透明通道 → 會投影、會進倒影與景深）
// 所有擺動都是「整數點陣位移」：草逐列橫移（fragment）、樹葉整團橫移（vertex）＋小塊抖動，怎麼動都是銳利像素。
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 tex_px = vec2(32.0);     // 單格的像素尺寸
uniform float frames = 1.0;
uniform float fps = 0.0;
uniform float frame_fixed = -1.0;
uniform bool tile = false;
uniform float sway_px = 0.0;          // 草：頂端最大橫移（點陣）
uniform float vsway_px = 0.0;
uniform float gust_x = 9999.0;         // 樹：整團葉叢橫移（點陣）
uniform float rustle_px = 0.0;        // 樹葉小塊抖動（點陣）
uniform float emit = 0.0;             // 暖亮色自發光強度（窗、燈）
uniform float glow_all = 0.0;         // 整張自發光（遠景、雲）
uniform float rough = 0.9;
uniform float backlight = 0.0;        // 逆光透光（葉、草）
uniform float lit = 1.0;
uniform float rim = 0.0;              // 逆光描邊強度（只描朝太陽那一側的輪廓點陣）
uniform vec3 rim_col : source_color = vec3(1.0, 0.75, 0.45);
uniform vec2 rim_dir = vec2(-1.0, -1.0);   // 太陽在貼圖上的方向（點陣），由腳本依 sun_dir 設定
uniform float grime = 0.0;            // 牆面：牆腳濕痕、雨水流痕、污漬
uniform float wall_top = 3.0;
uniform float courses = 0.0;         // 山牆朝前的屋頂斜面：程序化的一排排瓦（見 main.gd）
uniform float moss = 0.0;             // 屋頂：瓦片深淺、苔蘚
uniform float water_y = -0.5;
uniform float sprite_scale = 1.0;
varying float phase;
varying vec3 wpos;
varying vec3 wv;
varying float flipx;

// 全場共用的陣風（草、樹、落葉粒子同一條式子；main.gd 的 gust() 與此一致）：週期約 3.2 秒，從左往右傳
float gust(float t, float x) {
	return (0.5 + 0.5 * sin(t * 1.96 - x * 0.35)) * (0.65 + 0.35 * sin(t * 0.5 + x * 0.1));
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wpos = MODEL_MATRIX[3].xyz;
	phase = wpos.x * 1.7 + wpos.z * 2.3 + wpos.y * 0.9;
	flipx = sign(MODEL_MATRIX[0].x);
	if (vsway_px > 0.0) {
		float g = gust(TIME, gust_x < 9000.0 ? gust_x : wpos.x);      // 同一棵樹的葉團用同一個陣風相位 → 整棵樹的輪廓一起擺
		float off = floor(g * vsway_px * clamp(wpos.y / 3.5, 0.5, 1.3) + sin(TIME * 2.3 + phase) * 0.7 + 0.5);
		VERTEX.x += off * sprite_scale / 32.0 * flipx;
	}
	wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// 鏡像相機（反射用）不畫反射面以下的東西：水面鏡頭（layer 11）切在水面、街面鏡頭（layer 12）切在 y=0
	if ((CAMERA_VISIBLE_LAYERS & uint(1024)) != uint(0) && wv.y < water_y) discard;
	if ((CAMERA_VISIBLE_LAYERS & uint(2048)) != uint(0) && wv.y < 0.0) discard;
	vec2 uv = UV;
	if (!tile) {
		float h = 1.0 - uv.y;
		if (sway_px > 0.0) {
			float g = gust(TIME, wpos.x);
			float w = g * 1.1 + sin(TIME * 3.1 + phase + h * 2.0) * 0.25;
			uv.x -= floor(w * sway_px * h * h + 0.5) / tex_px.x * flipx;
		}
		if (rustle_px > 0.0) {
			float cx = floor(uv.x * tex_px.x / 3.0);
			float cy = floor(uv.y * tex_px.y / 3.0);
			float g2 = 0.5 + gust(TIME, wpos.x);
			uv.y += floor(sin(TIME * 2.1 + cx * 1.3 + phase) * rustle_px * 0.6 * g2 + 0.5) / tex_px.y;
			uv.x += floor(sin(TIME * 1.6 + cy * 1.1 + phase * 0.7) * rustle_px * g2 + 0.5) / tex_px.x;
		}
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) discard;
		if (frames > 1.0) {
			float f = frame_fixed >= 0.0 ? frame_fixed : floor(mod(TIME * fps + phase, frames));
			uv.x = (uv.x + f) / frames;
		}
	}
	vec4 c = texture(tex, uv);
	if (c.a < 0.5) discard;
	vec3 col = c.rgb * tint.rgb;
	vec3 q = floor(wv * 32.0 + 0.001) / 32.0;
	if (grime > 0.0) {
		float hq = q.x + q.z;
		float base = smoothstep(0.85, 0.05, q.y + noise(vec2(hq * 2.5, 1.0)) * 0.5 - 0.25);
		float st = noise(vec2(hq * 7.0, q.y * 0.6 + 4.0));
		float streak = smoothstep(0.52, 0.8, st) * smoothstep(wall_top - 2.4, wall_top - 0.2, q.y);
		float blot = smoothstep(0.5, 0.78, noise(vec2(hq * 1.4 + 7.0, q.y * 1.4)));
		float g = clamp(base * 0.6 + streak * 0.4 + blot * 0.12, 0.0, 0.75) * grime;
		g = floor(g * 5.0 + 0.5) / 5.0;
		col = mix(col, col * vec3(0.4, 0.4, 0.46), g);
		float ms = step(0.62, noise(vec2(hq * 5.0, q.y * 5.0))) * base;
		col = mix(col, vec3(0.2, 0.3, 0.2), ms * 0.35 * grime);
	}
	if (courses > 0.0) {
		// 山牆朝前的屋頂斜面：沿屋脊方向在畫面上被壓成約 1/9，貼圖怎麼取樣都會拉絲。
		// 改成直接在「畫面上接近正方」的格子裡畫瓦：沿坡向 6 點陣一排，沿屋脊方向 36 點陣一片（畫面上約 4 點陣寬），
		// 隔排錯位、每片深淺不同、下緣陰影線、片與片之間的縫、苔蘚斑塊。
		float vy = UV.y * tex_px.y;
		float ux = UV.x * tex_px.x * 4.0;                 // UV.x 在 main.gd 已乘 0.25，這裡還原成點陣數
		float row = floor(vy / 6.0);
		float inrow = floor(fract(vy / 6.0) * 6.0);
		float tx = ux / 36.0 + mod(row, 2.0) * 0.5;
		float tile_i = floor(tx);
		float intile = floor(fract(tx) * 4.0);            // 片內 4 格（畫面上各約 1 點陣）
		float hc = hash(vec2(row, tile_i));
		col = tint.rgb * 0.095 * (0.6 + 0.7 * hc);
		if (inrow < 1.0) col *= 0.45;                     // 下緣陰影線
		else if (inrow > 4.5) col *= 1.25;                // 上緣受光
		if (intile < 1.0 && inrow < 4.0) col *= 0.6;      // 片與片之間的縫
		if (hc > 0.9) col *= 0.55;                        // 深色補瓦
		float mm = noise(vec2(floor(ux / 9.0) * 0.23, floor(vy) * 0.21) + 3.0);
		float mg = floor(smoothstep(0.5, 0.72, mm) * 3.0 + 0.5) / 3.0;
		col = mix(col, vec3(0.06, 0.1, 0.05) * (0.7 + 0.6 * hc), mg * 0.6);
	}
	if (moss > 0.0) {
		vec2 cell = floor(UV * tex_px / 8.0);
		float hc = hash(cell);
		col *= 0.78 + 0.42 * hc;
		if (hc > 0.93) col *= 0.6;                      // 幾片深色補瓦
		float mm = noise(vec2(q.x + q.z, q.y) * 1.6 + 3.0) * 0.65 + noise(vec2(q.x + q.z, q.y) * 6.0) * 0.35;
		float mg = floor(smoothstep(0.52, 0.72, mm) * 3.0 + 0.5) / 3.0;
		col = mix(col, vec3(0.22, 0.31, 0.17) * (0.7 + 0.6 * hc), mg * 0.55 * moss);
	}
	ALBEDO = col * lit;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	float lum = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	float warm = smoothstep(0.45, 0.7, lum) * smoothstep(1.2, 1.9, c.r / max(c.b, 0.04));
	EMISSION = c.rgb * c.rgb * emit * warm + col * glow_all;
	if (rim > 0.0) {
		// 逆光描邊：只描朝太陽那一側（左、左上）露出來的輪廓點陣，暖金色
		vec2 tp = vec2(tex_px.x * frames, tex_px.y);
		float n1 = texture(tex, uv + vec2(rim_dir.x * flipx, 0.0) / tp).a;
		float n3 = texture(tex, uv + vec2(rim_dir.x * flipx, rim_dir.y) / tp).a;
		float e = step(n1, 0.5) * (0.6 + 0.4 * step(n3, 0.5));
		EMISSION += rim_col * e * rim;
	}
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lc = LIGHT_COLOR * ATTENUATION / PI;
	DIFFUSE_LIGHT += lc * max(ndl, 0.0);
	DIFFUSE_LIGHT += lc * max(-ndl, 0.0) * backlight;
}
