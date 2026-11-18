extends Node3D
# HD-2D 俯角箱庭：黃昏的運河小鎮廣場。場景全部由這支腳本程序化組出來（真 3D 幾何＋像素貼圖＋即時光影）。
# 正常啟動：持續執行。 `-- --shots`：截 full_1..3（間隔 2 秒）＋特寫後離開。
# 對照／除錯： --tag=xxx（只截一張 compare_xxx.png） --no-dof --no-fog --no-shadow --no-refl --no-leaves --mask --top

const PPM := 32.0          # 全場統一點陣密度：32 點陣 / 公尺（牆、地、屋頂、sprite 都一樣）
const PAD := 4.0           # sprite 四周的透明邊（點陣）
const WATER_Y := -0.95
const QUAY_Z := 2.4
const BACK_Z := -9.2       # 廣場後緣：再往後地勢往下（後排房子蓋在低一階的地上，屋頂上方才露得出天空）
const LOW_Y := -3.3        # 堤岸邊緣
const HERO := Vector3(-1.5, 0.0, 0.0)
const FOV := 28.0
const PITCH := 33.0        # 俯角
const K_PX := 3.2          # 主角所在深度上 1 點陣 = 3.4 螢幕像素（1080p）
const SUN_EL := 22.0       # 夕陽仰角

var meta: Dictionary
var _tex := {}
var _mat := {}
var _quad := {}
var sh_pix: Shader = load("res://shaders/pix.gdshader")
var sh_pix_mip: Shader
var sh_part: Shader = load("res://shaders/particle.gdshader")
var sh_beam: Shader = load("res://shaders/beam.gdshader")
var rng := RandomNumberGenerator.new()
var args: PackedStringArray
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var sun_dir: Vector3       # 光的行進方向：夕陽在左後方，往右前方照
var depth0 := 0.0
var cam_fwd: Vector3
var cam_right: Vector3
var cam_up: Vector3
var cam_pos: Vector3
var mirrors: Array = []
var flyers: Array = []
var flickers: Array = []
var leaf_emitters: Array = []
var hide_in_mask: Array = []
var boat: Node3D
var parent_node: Node3D
var ground_mat: ShaderMaterial
var t := 0.0
var frames_n := 0
# pilot：四件手修素材的開關（預設全開）；`--old=ground,roof,wall,hero` 可逐件退回原本的素材
var old_list := ""
var hero_m: ShaderMaterial
var fisher_m: ShaderMaterial
# 第二階段留證用：`--p1=ground,wall,roof` 讓該表面改用第一階段的貼圖（tex/pilot_*_p1.png），方便逐步並排比較
var p1_list := ""
func ptex(name: String, key: String) -> String:
	return name + "_p1" if key in p1_list.split(",") else name
func pilot(name: String) -> bool:
	return not (name in old_list.split(","))

func has(a: String) -> bool:
	return a in args

func argf(name: String, def: float) -> float:
	for a in args:
		if a.begins_with("--" + name + "="): return float(a.get_slice("=", 1))
	return def

func gust(time: float, x: float) -> float:
	return (0.5 + 0.5 * sin(time * 1.96 - x * 0.35)) * (0.65 + 0.35 * sin(time * 0.5 + x * 0.1))

# ------------------------------------------------------------------ 資源
func tex(name: String, mip := false) -> ImageTexture:
	var key := name + ("#mip" if mip else "")
	if not _tex.has(key):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://tex/%s.png" % name))
		if mip: img.generate_mipmaps()
		_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]

func px_size(name: String) -> Vector2:
	var m: Array = meta[name]
	var fr: float = meta.get(name + "_frames", 1)
	return Vector2(m[0] / fr, m[1])

func mat(name: String, o: Dictionary = {}) -> ShaderMaterial:
	var key := name + str(o)
	if _mat.has(key): return _mat[key]
	var m := ShaderMaterial.new()
	var use_mip: bool = o.get("mip", false)
	m.shader = sh_pix_mip if use_mip else sh_pix
	m.set_shader_parameter("tex", tex(name, use_mip))
	m.set_shader_parameter("tex_px", px_size(name))
	m.set_shader_parameter("frames", float(meta.get(name + "_frames", 1)))
	m.set_shader_parameter("rim_dir", Vector2(-1.0, -1.0))
	m.set_shader_parameter("water_y", WATER_Y)
	for k in o:
		if k != "mip": m.set_shader_parameter(k, o[k])
	_mat[key] = m
	return m

const MAT_KEYS := ["blink", "breathe", "gust_x", "frame_fixed", "rim", "sway_px", "vsway_px", "rustle_px", "emit", "glow_all", "backlight", "tint", "rough", "fps", "lit", "flat_lit", "rim_col", "vshade", "lift_x"]

# 像素 sprite（底邊對齊 pos.y），尺寸 = 像素數 / PPM × scale。
# 預設直立（和牆一樣）；tilt = true：以腳為軸往後仰到正對鏡頭（角色、樹冠），另放一份直立的「只投影」分身。
func sprite(name: String, pos: Vector3, o: Dictionary = {}) -> MeshInstance3D:
	var s := px_size(name)
	var sc: float = o.get("scale", 1.0)
	var key := name + str(sc) + str(o.get("center", false))
	if not _quad.has(key):
		var q := QuadMesh.new()
		q.size = s / PPM * sc
		if not o.get("center", false):
			q.center_offset = Vector3(0, (s.y * 0.5 - PAD) / PPM * sc, 0)
		_quad[key] = q
	var mi := MeshInstance3D.new()
	mi.mesh = _quad[key]
	var mo := {}
	for k in MAT_KEYS:
		if o.has(k): mo[k] = o[k]
	if not mo.has("flat_lit") and not o.get("lambert", false): mo["flat_lit"] = 0.2
	if sc != 1.0: mo["sprite_scale"] = sc
	mi.material_override = mat(name, mo)
	mi.position = pos
	if o.has("yaw"): mi.rotation.y = deg_to_rad(o["yaw"])
	if o.get("flip", false): mi.scale.x = -1
	var want_shadow: bool = o.get("shadow", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if o.has("layer"): mi.layers = o["layer"]
	parent_node.add_child(mi)
	if o.get("tilt", false): mi.rotation.x = -deg_to_rad(PITCH)
	if o.get("shadow_only", false): mi.visible = false
	if want_shadow:
		# 只投影的分身：直立、沿光的方向退一點（本體就不會被自己的影子蓋住）
		var sh := MeshInstance3D.new()
		sh.mesh = mi.mesh
		sh.material_override = mi.material_override
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sh.position = pos + Vector3(sun_dir.x, 0, sun_dir.z) * o.get("shadow_off", 0.08)
		if o.has("yaw"): sh.rotation.y = deg_to_rad(o["yaw"])
		sh.scale = mi.scale
		add_child(sh)
		mi.set_meta("shadow", sh)
	return mi

# ------------------------------------------------------------------ 幾何（UV = 公尺 × PPM / 貼圖像素 → 點陣密度固定）
class Geo:
	var st := SurfaceTool.new()
	var tp: Vector2
	var uo := Vector2.ZERO
	func _init(tex_px: Vector2) -> void:
		tp = tex_px
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a=左下 b=右下 c=右上 d=左上（從正面看）
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var n := (b - a).cross(d - a).normalized()
		var ul := (b - a).length() * 32.0 / tp.x
		var vl := (d - a).length() * 32.0 / tp.y
		var pts := [a, d, c, a, c, b]
		var uvs := [Vector2(0, vl), Vector2(0, 0), Vector2(ul, 0), Vector2(0, vl), Vector2(ul, 0), Vector2(ul, vl)]
		for i in 6:
			st.set_normal(n); st.set_uv(uvs[i] + uo); st.add_vertex(pts[i])
	# 三角形（山牆）：a、b 是底邊，c 是頂點
	func tri(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		var ul := (b - a).length() * 32.0 / tp.x
		var hgt := (c - (a + b) * 0.5).length() * 32.0 / tp.y
		var pts := [a, c, b]
		var uvs := [Vector2(0, 0), Vector2(ul * 0.5, -hgt), Vector2(ul, 0)]
		for i in 3:
			st.set_normal(n); st.set_uv(uvs[i] + uo); st.add_vertex(pts[i])
	# 盒子：c = 底面中心
	# pilot：整片專屬貼圖用——UV 直接給（不是依長度平鋪）
	func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
		var n := (b - a).cross(d - a).normalized()
		var pts := [a, d, c, a, c, b]
		var uvs := [ua, ud, uc, ua, uc, ub]
		for i in 6:
			st.set_normal(n); st.set_uv(uvs[i]); st.add_vertex(pts[i])
	func tri_uv(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		var n := (b - a).cross(c - a).normalized()
		var pts := [a, c, b]
		var uvs := [ua, uc, ub]
		for i in 3:
			st.set_normal(n); st.set_uv(uvs[i]); st.add_vertex(pts[i])
	# faces：1 正面(+z) 2 背面 4 左 8 右 16 頂（pilot：正面改用專屬貼圖時可略過）
	func box(c: Vector3, s: Vector3, rand_uv := true, faces := 31) -> void:
		var x0 := c.x - s.x * 0.5; var x1 := c.x + s.x * 0.5
		var y0 := c.y; var y1 := c.y + s.y
		var z0 := c.z - s.z * 0.5; var z1 := c.z + s.z * 0.5
		if rand_uv: uo = Vector2(floorf(c.x * 7.0) * 0.137, floorf(c.z * 5.0) * 0.211)      # 每個盒子的貼圖起點錯開，避免同一塊花紋重複
		if faces & 1: quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1))
		if faces & 2: quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0))
		if faces & 4: quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0))
		if faces & 8: quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1))
		if faces & 16: quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0))
		uo = Vector2.ZERO
	# 多邊形柱（木桶、原木）：側面 n 片
	func prism(c: Vector3, r: float, h: float, n := 8) -> void:
		for i in n:
			var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
			var p0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r); var p1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
			uo = Vector2(float(i) * 0.25, 0)
			quad(p1, p0, p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0))
		uo = Vector2.ZERO
	# 多邊形頂蓋（貼圖攤平在頂面）
	func disc(c: Vector3, r: float, n := 8) -> void:
		for i in n:
			var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
			var pts := [c, c + Vector3(cos(a1) * r, 0, sin(a1) * r), c + Vector3(cos(a0) * r, 0, sin(a0) * r)]
			for p in pts:
				st.set_normal(Vector3.UP); st.set_uv(Vector2((p.x - c.x + r) / (2.0 * r), (p.z - c.z + r) / (2.0 * r))); st.add_vertex(p)
	func mesh() -> ArrayMesh:
		return st.commit()

func geo(name: String) -> Geo:
	return Geo.new(px_size(name))

func put(g: Geo, name: String, o: Dictionary = {}, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = g.mesh()
	var mo := {"tile": true}
	mo.merge(o)
	mi.material_override = mat(name, mo)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(mi)
	return mi

func omni(pos: Vector3, col: Color, energy: float, rng_m: float, shadow := false, fog := 1.0, flicker := 0.0, spec := 0.15) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.6
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = fog
	l.light_specular = spec
	add_child(l)
	if flicker > 0.0:
		flickers.append({"l": l, "e": energy, "a": flicker, "p": rng.randf() * 10.0})
	return l

# ------------------------------------------------------------------ 房屋（有體積的低模：石基、牆、山牆、斜屋頂、封簷板、煙囪）
# 規格：x0 x1 zb（背面）zf（正面）h 牆高 rh 屋頂高 ridge "x"（屋脊橫向）或 "z"（山牆朝前）
func house(h: Dictionary) -> void:
	var x0: float = h.x0; var x1: float = h.x1; var zb: float = h.zb; var zf: float = h.zf
	var wh: float = h.h; var rh: float = h.rh
	var x := (x0 + x1) * 0.5; var zc := (zf + zb) * 0.5
	var w := x1 - x0; var d := zf - zb
	if reg_on and parent_node == self: zone_rects.append([x0, zb, x1, zf])
	var cast: bool = h.get("cast", true)
	var wall_tex: String = h.get("wall", "plaster2")
	var wtint: Color = h.get("tint", Color(1, 0.9, 0.78))
	var base_h := 0.3
	# pilot：中央屋正面改用整張專屬立面貼圖（139×147，依世界座標對應：u = (x − 左緣)·32/139、v = 1 − y·32/147），正面的面從原本的盒子裡拿掉
	var pw: bool = h.get("pilot_wall", false) and pilot("wall")
	var ff := 30 if pw else 31
	var wtx := ptex("pilot_wallB", "wall")
	var gf := geo(wtx)      # 牆面（石基、磚、灰泥、山牆）
	var gft := geo(wtx)     # 木構架的正面
	var fx0 := x0 - 0.07
	var fuv := func(p: Vector3) -> Vector2: return Vector2(clampf((p.x - fx0) * 32.0 / 139.0, 0.002, 0.998), clampf(1.0 - p.y * 32.0 / 147.0, 0.002, 0.998))
	var fq := func(g: Geo, xa: float, xb: float, ya: float, yb: float, z: float) -> void:
		var a := Vector3(xa, ya, z); var b := Vector3(xb, ya, z); var c := Vector3(xb, yb, z); var dd := Vector3(xa, yb, z)
		g.quad_uv(a, b, c, dd, fuv.call(a), fuv.call(b), fuv.call(c), fuv.call(dd))
	var gb := geo("stonewall")
	gb.box(Vector3(x, 0, zc), Vector3(w + 0.1, base_h, d + 0.1), true, ff)
	if pw: fq.call(gf, x - (w + 0.1) * 0.5, x + (w + 0.1) * 0.5, 0.0, base_h, zf + 0.05)
	put(gb, "stonewall", {"tint": Color(0.95, 0.88, 0.85), "grime": 0.6, "wall_top": 3.0}, cast)
	var gw := geo(wall_tex)
	gw.box(Vector3(x, base_h, zc), Vector3(w, wh - base_h, d), true, ff)
	if pw: fq.call(gf, x0, x1, base_h, h.upper, zf)
	var ov := 0.25
	if not h.has("upper"):
		if h.ridge == "z":
			gw.tri(Vector3(x0, wh, zf), Vector3(x1, wh, zf), Vector3(x, wh + rh, zf))
			gw.tri(Vector3(x1, wh, zb), Vector3(x0, wh, zb), Vector3(x, wh + rh, zb))
		else:
			gw.tri(Vector3(x0, wh, zb), Vector3(x0, wh, zf), Vector3(x0, wh + rh, zc))
			gw.tri(Vector3(x1, wh, zf), Vector3(x1, wh, zb), Vector3(x1, wh + rh, zc))
	put(gw, wall_tex, {"tint": wtint, "grime": 0.7, "wall_top": wh}, cast).layers = 17
	if h.has("upper"):
		# 二樓：灰泥＋木骨架（half-timber），比一樓略外凸
		var uy: float = h.upper
		var e := 0.07
		var gu := geo("plaster2")
		gu.box(Vector3(x, uy, zc), Vector3(w + e * 2, wh - uy, d + e * 2), true, ff)
		if pw:
			fq.call(gf, x0 - e, x1 + e, uy, wh, zf + e)
			var ta := Vector3(x0 - e, wh, zf + e); var tb := Vector3(x1 + e, wh, zf + e); var tc := Vector3(x, wh + rh - 0.02, zf + e)
			gf.tri_uv(ta, tb, tc, fuv.call(ta), fuv.call(tb), fuv.call(tc))
		if h.ridge == "z":
			if not pw: gu.tri(Vector3(x0 - e, wh, zf + e), Vector3(x1 + e, wh, zf + e), Vector3(x, wh + rh - 0.02, zf + e))
			gu.tri(Vector3(x1 + e, wh, zb - e), Vector3(x0 - e, wh, zb - e), Vector3(x, wh + rh - 0.02, zb - e))
		else:
			gu.tri(Vector3(x0 - e, wh, zb - e), Vector3(x0 - e, wh, zf + e), Vector3(x0 - e, wh + rh - 0.02, zc))
			gu.tri(Vector3(x1 + e, wh, zf + e), Vector3(x1 + e, wh, zb - e), Vector3(x1 + e, wh + rh - 0.02, zc))
		put(gu, "plaster2", {"tint": h.get("upper_tint", Color(1, 0.93, 0.8)), "grime": 0.8, "wall_top": wh + rh * 0.5}, cast).layers = 17
		var gt := geo("planks")
		var bw := 0.1
		# 正面與左側面的木骨架（鏡頭看得到的兩面）
		var zt := zf + e
		gt.box(Vector3(x, uy - 0.05, zt), Vector3(w + e * 2 + 0.08, 0.14, 0.1), true, ff)
		gt.box(Vector3(x, wh - 0.1, zt), Vector3(w + e * 2 + 0.04, 0.1, 0.1), true, ff)
		for bx in [x0 - e + 0.02, x1 + e - 0.02, x - w * 0.17, x + w * 0.17]:
			gt.box(Vector3(bx, uy, zt), Vector3(bw, wh - uy, 0.1), true, ff)
			if pw: fq.call(gft, bx - bw * 0.5, bx + bw * 0.5, uy + 0.09, wh - 0.1, zt + 0.05)
		if pw:
			fq.call(gft, x - (w + e * 2 + 0.08) * 0.5, x + (w + e * 2 + 0.08) * 0.5, uy - 0.05, uy + 0.09, zt + 0.05)
			fq.call(gft, x - (w + e * 2 + 0.04) * 0.5, x + (w + e * 2 + 0.04) * 0.5, wh - 0.1, wh, zt + 0.05)
			put(gf, wtx, {"tint": Color(1, 1, 1)}, cast).layers = 17      # 手繪貼圖：不疊 grime，tint 設白（顏色都畫在貼圖裡）
			put(gft, wtx, {"tint": Color(1, 1, 1)}, false)
		for sx in [x0 - e, x1 + e]:
			gt.box(Vector3(sx, uy - 0.05, zc), Vector3(0.1, 0.14, d + e * 2 + 0.08))
			gt.box(Vector3(sx, wh - 0.1, zc), Vector3(0.1, 0.1, d + e * 2 + 0.04))
			for bz in [zb + 0.02, zc - d * 0.17, zc + d * 0.17]:
				gt.box(Vector3(sx, uy, bz), Vector3(0.1, wh - uy, bw))
		put(gt, "planks", {"tint": Color(0.5, 0.38, 0.34)}, false)
	# 屋頂：兩片斜面（UV 沿屋脊與坡向各自以實際長度計 → 瓦片不拉絲），下緣與山牆側有深色封簷板
	var roof_tex: String = h.get("roof", "roof2")
	var gr := geo(roof_tex)
	var ge := geo("planks")
	var grd := geo("planks")
	var rt: Color = h.get("roof_tint", Color(0.5, 0.48, 0.7))
	var th := 3.0 / PPM
	var dn := Vector3(0, -th, 0)
	if h.ridge == "x":
		var k := rh / (d * 0.5)
		var ey := wh - ov * k
		var e0 := Vector3(x0 - ov, ey, zf + ov); var e1 := Vector3(x1 + ov, ey, zf + ov)
		var r0 := Vector3(x0 - ov, wh + rh, zc); var r1 := Vector3(x1 + ov, wh + rh, zc)
		var b0 := Vector3(x0 - ov, ey, zb - ov); var b1 := Vector3(x1 + ov, ey, zb - ov)
		if h.get("pilot_roof", false) and pilot("roof"):
			# pilot：麵包店朝鏡頭的那片斜面用整片專屬貼圖（198×89，剛好鋪滿，不平鋪）
			var rtx := ptex("pilot_roof", "roof")
			var gpr := geo(rtx)
			gpr.quad_uv(e0, e1, r1, r0, Vector2(0.001, 0.999), Vector2(0.999, 0.999), Vector2(0.999, 0.001), Vector2(0.001, 0.001))
			put(gpr, rtx, {"tint": Color(1, 1, 1), "rough": 0.8, "moss": 0.0}, cast).layers = 33
		else:
			gr.quad(e0, e1, r1, r0)
		gr.uo = Vector2(0.37, 0.0)
		gr.quad(b1, b0, r0, r1)
		ge.quad(e0 + dn, e1 + dn, e1, e0)
		ge.quad(b1 + dn, b0 + dn, b0, b1)
		grd.box(Vector3(x, wh + rh - 0.03, zc), Vector3(w + ov * 2 + 0.04, 0.1, 0.16))
		for sx in [x0 - ov - 0.005, x1 + ov + 0.005]:
			var sg := 1.0 if sx < x else -1.0
			if sg > 0:
				ge.quad(Vector3(sx, wh + rh, zc) + dn, Vector3(sx, ey, zf + ov) + dn, Vector3(sx, ey, zf + ov), Vector3(sx, wh + rh, zc))
				ge.quad(Vector3(sx, ey, zb - ov) + dn, Vector3(sx, wh + rh, zc) + dn, Vector3(sx, wh + rh, zc), Vector3(sx, ey, zb - ov))
			else:
				ge.quad(Vector3(sx, ey, zf + ov) + dn, Vector3(sx, wh + rh, zc) + dn, Vector3(sx, wh + rh, zc), Vector3(sx, ey, zf + ov))
				ge.quad(Vector3(sx, wh + rh, zc) + dn, Vector3(sx, ey, zb - ov) + dn, Vector3(sx, ey, zb - ov), Vector3(sx, wh + rh, zc))
	else:
		var k2 := rh / (w * 0.5)
		var zf2 := zf + ov; var zb2 := zb - ov
		var ey2 := wh - ov * k2
		var l0 := Vector3(x0 - ov, ey2, zf2); var l1 := Vector3(x0 - ov, ey2, zb2)
		var q0 := Vector3(x1 + ov, ey2, zf2); var q1 := Vector3(x1 + ov, ey2, zb2)
		var t0 := Vector3(x, wh + rh, zf2); var t1 := Vector3(x, wh + rh, zb2)
		gr.quad(l1, l0, t0, t1)
		gr.uo = Vector2(0.37, 0.0)
		gr.quad(q0, q1, t1, t0)
		var fz := Vector3(0, 0, 0.005)
		ge.quad(l0 + dn + fz, t0 + dn + fz, t0 + fz, l0 + fz)
		ge.quad(t0 + dn + fz, q0 + dn + fz, q0 + fz, t0 + fz)
		ge.quad(l1 + dn, l0 + dn, l0, l1)
		ge.quad(q0 + dn, q1 + dn, q1, q0)
		grd.box(Vector3(x, wh + rh - 0.03, zc), Vector3(0.16, 0.1, d + ov * 2 + 0.04))
	put(gr, roof_tex, {"tint": rt, "rough": 0.8, "moss": h.get("moss", 0.0 if roof_tex.begins_with("w_") else 0.5)}, cast).layers = 33
	put(grd, "planks", {"tint": Color(1.7, 1.15, 0.8), "glow_all": 0.1}, false)      # 屋脊：受光的亮邊
	put(ge, "planks", {"tint": Color(0.36, 0.27, 0.27)}, false)
	if h.has("chimney"):
		var c: Vector2 = h.chimney      # 相對屋子中心的 x、z
		var gc := geo("brick")
		var cy := wh + rh * 0.3
		gc.box(Vector3(x + c.x, cy, zc + c.y), Vector3(0.45, rh * 0.7 + 0.5, 0.45))
		put(gc, "brick", {"tint": Color(0.9, 0.8, 0.78), "grime": 0.8, "wall_top": cy + 1.0}, cast)
		var gcap := geo("stonewall")
		gcap.box(Vector3(x + c.x, cy + rh * 0.7 + 0.5, zc + c.y), Vector3(0.56, 0.09, 0.56))
		put(gcap, "stonewall", {}, cast)
	# 牆上的門窗（sprite 貼在牆面上）：[名稱, 面 "f"/"l"/"r", 沿牆位置, 高度, 發光]
	for it in h.get("items", []):
		var nm: String = it[0]
		var face: String = it[1]
		var up: bool = h.has("upper") and it[3] > h.upper - 0.4
		var off := 0.015 + (0.07 if up else 0.0)
		var p: Vector3
		var yaw := 0.0
		if face == "f": p = Vector3(x + it[2], it[3], zf + off)
		elif face == "l": p = Vector3(x0 - off, it[3], zc + it[2]); yaw = -90.0
		else: p = Vector3(x1 + off, it[3], zc + it[2]); yaw = 90.0
		var em: float = it[4] if it.size() > 4 else 0.0
		sprite(nm, p, {"emit": em * (1.0 if h.get("lights", true) else 2.2), "shadow": false, "yaw": yaw, "lambert": true, "layer": 17})
		if em > 0.0 and h.get("lights", true):
			var s := px_size(nm) / PPM
			var out := Vector3(0, 0, 0.5) if face == "f" else (Vector3(-0.5, 0, 0) if face == "l" else Vector3(0.5, 0, 0))
			omni(p + Vector3(0, s.y * 0.45, 0) + out, Color(1.0, 0.62, 0.28), 0.55, 3.0, false, 0.8, 0.06)

# 蓋在別的高度（後排地勢較低的房子）
func house_at(h: Dictionary, y0: float) -> void:
	var n := Node3D.new()
	n.position.y = y0
	add_child(n)
	parent_node = n
	house(h)
	parent_node = self

# ------------------------------------------------------------------ 樹：樹幹 sprite ＋ 前後錯開的多團葉叢（真的有體積 → 葉隙漏光、地上有斑駁的影子）
var tree_tint := Color(1, 1, 1)      # 東區紅楓：樹冠整體偏深紅（使用者照片）
func tree(pos: Vector3, kinds: Array, n: int, spread: Vector3, cy: float, gap := 0.9, trunk_shadow := true, flip := false) -> void:
	if reg_on: zone_circles.append([pos.x, pos.z, 0.35])
	sprite("trunk", pos, {"flat_lit": 0.3, "shadow": trunk_shadow, "flip": flip})
	# 樹冠：葉團排在一個圓頂殼面上（頂部在中央、越靠外越低），所以前面較低的葉團會蓋住後面葉團的底緣，疊成一整團；
	# 每團依位置給明暗：頂部與朝太陽那側亮、內側與下層暗（自陰影），朝太陽的邊緣透出橘紅。
	var sunh := Vector3(-sun_dir.x, 0, -sun_dir.z).normalized()
	var perp := Vector3(sun_dir.z, 0, -sun_dir.x).normalized()
	var c := pos + Vector3(0, cy, 0)
	for i in n:
		var a := rng.randf() * TAU
		var tt := deg_to_rad(lerpf(8.0, 112.0, sqrt((i + 0.5) / n)))
		var rr := lerpf(0.72, 1.0, rng.randf())
		var p := c + Vector3(cos(a) * sin(tt) * spread.x, cos(tt) * spread.y, sin(a) * sin(tt) * spread.z) * rr
		# 樹冠留一道缺口：夕陽穿過缺口，在主角腳邊落下一塊光池（缺口寬度以垂直光線方向的距離計）
		if absf((p - HERO).dot(perp)) < gap: continue
		var up := clampf(0.5 + 0.5 * cos(tt), 0.0, 1.0)
		var sunside := clampf(0.5 + 0.5 * (p - c).dot(sunh) / maxf(spread.x, spread.z), 0.0, 1.0)
		var lightv := clampf(up * 0.65 + sunside * 0.45 - (1.0 - rr) * 0.8, 0.0, 1.0)
		var tint := Color(0.72, 0.42, 0.4).lerp(Color(1.15, 1.02, 0.82), lightv) * tree_tint
		sprite(kinds[i % kinds.size()], p, {"center": true, "tilt": true, "yaw": rng.randf_range(-22.0, 22.0), "vsway_px": 3.0, "gust_x": pos.x, "rustle_px": 1.0, "flat_lit": 0.22 * (0.55 + 0.6 * lightv), "glow_all": 0.05, "tint": tint, "vshade": 0.45, "rim": 0.3 * sunside, "rim_col": Color(1.0, 0.5, 0.18), "flip": rng.randf() < 0.5, "shadow_off": 0.0})

# ------------------------------------------------------------------ 3D 小道具（方塊＋像素貼圖 → 有受光面與陰影面）
func barrel(pos: Vector3) -> void:
	if reg_on: zone_circles.append([pos.x, pos.z, 0.3])
	var g := geo("barrel")
	g.prism(pos, 0.28, 0.625, 10)
	put(g, "barrel", {"tint": Color(1.0, 0.92, 0.88)})
	var gt := geo("barreltop")
	gt.disc(pos + Vector3(0, 0.6, 0), 0.26, 10)
	put(gt, "barreltop", {}, false)

func crate(pos: Vector3, s := 0.6875, yaw := 0.0) -> void:
	if reg_on: zone_rects.append([pos.x - s * 0.6, pos.z - s * 0.6, pos.x + s * 0.6, pos.z + s * 0.6])
	var g := geo("crate")
	g.box(Vector3.ZERO, Vector3(s, s, s), false)
	var mi := put(g, "crate", {"tint": Color(1.0, 0.95, 0.9)})
	mi.position = pos; mi.rotation.y = deg_to_rad(yaw)

func bench(pos: Vector3, yaw := 0.0) -> void:
	if reg_on: zone_rects.append([pos.x - 0.7, pos.z - 0.3, pos.x + 0.7, pos.z + 0.25])
	var g := geo("wood")
	g.box(Vector3(0, 0.34, 0), Vector3(1.3, 0.07, 0.42))
	g.box(Vector3(0, 0.5, -0.2), Vector3(1.3, 0.34, 0.06))
	for sx in [-0.56, 0.56]:
		g.box(Vector3(sx, 0, 0.14), Vector3(0.08, 0.34, 0.08))
		g.box(Vector3(sx, 0, -0.2), Vector3(0.08, 0.5, 0.08))
	var mi := put(g, "wood", {"tint": Color(0.95, 0.82, 0.78)})
	mi.position = pos; mi.rotation.y = deg_to_rad(yaw)

# 石砌花台：石框＋土＋一排排花草 sprite
func planter(c: Vector3, w: float, d: float, kinds: Array, hgt := 0.34, sink := 0.42) -> void:
	if reg_on: zone_rects.append([c.x - w * 0.5, c.z - d * 0.5, c.x + w * 0.5, c.z + d * 0.5])
	var g := geo("stonewall")
	g.box(c, Vector3(w, hgt, d))
	put(g, "stonewall", {"tint": Color(1.3, 1.16, 1.3)}).layers = 17
	var gs := geo("grass")
	gs.box(c + Vector3(0, hgt, 0), Vector3(w - 0.14, 0.02, d - 0.14))
	put(gs, "grass", {"tint": Color(0.3, 0.26, 0.26)}, false)
	var n := int(w / 0.42)
	for row in 2:
		for i in n:
			var nm: String = kinds[rng.randi() % kinds.size()]
			var p := c + Vector3(-w * 0.5 + 0.3 + i * (w - 0.6) / maxf(n - 1, 1) + rng.randf_range(-0.06, 0.06), hgt - sink, -d * 0.2 + row * d * 0.38)
			sprite(nm, p, {"sway_px": 2.0, "flat_lit": 0.3, "glow_all": 0.04, "flip": rng.randf() < 0.5, "shadow_off": 0.02})

func bollard(p: Vector3) -> void:
	var g := geo("stonewall")
	g.box(p, Vector3(0.2, 0.52, 0.2))
	g.box(p + Vector3(0, 0.52, 0), Vector3(0.27, 0.08, 0.27))
	put(g, "stonewall", {"tint": Color(0.5, 0.46, 0.62), "rough": 0.6})

# 點陣鐵鍊／電線：沿懸鏈線一格一格排（th 點陣粗），可掛小燈泡
func pixel_wire(p0: Vector3, p1: Vector3, sag: float, bulbs: Array, th := 1.0, col := Color(0.16, 0.12, 0.16), step := 14) -> void:
	var gl := geo("planks")
	var n := int(absf(p1.x - p0.x) * PPM)
	var px := 1.0 / PPM
	for i in n:
		var u := float(i) / n
		var pt := p0.lerp(p1, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
		var x := p0.x + i * px * signf(p1.x - p0.x)
		var y := floorf(pt.y * PPM) / PPM
		if th > 1.0 and i % 3 == 2: continue      # 鐵鍊：每 3 格空 1 格，看得出一節一節
		gl.quad(Vector3(x, y, pt.z), Vector3(x + px, y, pt.z), Vector3(x + px, y + px * th, pt.z), Vector3(x, y + px * th, pt.z))
		if i % step == step / 2 and bulbs.size() > 0:
			var c: Color = bulbs[(i / step) % bulbs.size()]
			sprite("bulb", Vector3(x, y - 2.0 * px, pt.z + 0.01), {"center": true, "glow_all": 2.2, "tint": c, "lit": 0.0, "shadow": false})
			if (i / step) % 3 == 1:
				omni(Vector3(x, y - 0.15, pt.z + 0.1), c, 0.3, 2.0, false, 0.6, 0.08)
	put(gl, "planks", {"tint": col}, th > 1.0)

func lamp_post(p: Vector3, hgt := 2.1) -> void:
	if reg_on: zone_circles.append([p.x, p.z, 0.15]); zone_streaks.append([Vector4(p.x, p.z + 0.35, 0.09, 0.8), Vector4(1.0, 0.5, 0.14, 4.0)])
	var g := geo("stonewall")
	g.box(p, Vector3(0.16, 0.2, 0.16))
	g.box(p, Vector3(0.1, hgt, 0.1))
	g.box(p + Vector3(0, hgt, 0), Vector3(0.24, 0.04, 0.24))
	put(g, "stonewall", {"tint": Color(0.3, 0.27, 0.4), "rough": 0.5})
	sprite("lantern", p + Vector3(0, hgt - 0.02, 0.0), {"tilt": true, "emit": 3.2, "glow_all": 0.5, "lit": 0.0, "shadow": false})
	omni(p + Vector3(0, hgt - 0.35, 0.35), Color(1.0, 0.6, 0.24), 3.0, 5.0, false, 0.8, 0.05, 0.5)

func wall_lantern(p: Vector3, yaw := 0.0, e := 0.8, r := 3.4) -> void:
	sprite("street2_2", p, {"emit": 3.0, "shadow": false, "yaw": yaw, "lambert": true})
	var out := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw))) * 0.35
	omni(p + Vector3(0, 0.6, 0) + out, Color(1.0, 0.6, 0.24), e * 1.5, r, false, 0.8, 0.07, 0.3)

# 水井：八角石井欄、木柱與小屋頂、橫樑與吊桶
func well(p: Vector3) -> void:
	if reg_on: zone_circles.append([p.x, p.z, 0.7])
	var g := geo("w_stone")
	g.prism(p, 0.62, 0.55, 8)
	put(g, "w_stone", {"tint": Color(1.15, 1.08, 1.15)}).layers = 17
	var gt := geo("stonewall")
	gt.disc(p + Vector3(0, 0.55, 0), 0.66, 8)
	put(gt, "stonewall", {"tint": Color(1.2, 1.1, 1.2)}, false)
	var gw := geo("stonewall")
	gw.disc(p + Vector3(0, 0.56, 0), 0.44, 8)
	put(gw, "stonewall", {"tint": Color(0.06, 0.07, 0.14)}, false)
	var gp := geo("wood")
	for sx in [-0.56, 0.56]:
		gp.box(p + Vector3(sx, 0.5, 0), Vector3(0.1, 1.35, 0.1))
	gp.box(p + Vector3(0, 1.6, 0), Vector3(1.3, 0.08, 0.08))
	gp.box(p + Vector3(0.1, 1.0, 0), Vector3(0.2, 0.22, 0.2))
	gp.box(p + Vector3(0.1, 1.2, 0), Vector3(0.03, 0.42, 0.03))
	put(gp, "wood", {"tint": Color(0.85, 0.72, 0.7)})
	var gr := geo("w_roof_red2")
	var a := p + Vector3(-0.8, 1.75, 0.55); var b := p + Vector3(0.8, 1.75, 0.55)
	var r0 := p + Vector3(-0.8, 2.15, 0.0); var r1 := p + Vector3(0.8, 2.15, 0.0)
	var c := p + Vector3(0.8, 1.75, -0.55); var d := p + Vector3(-0.8, 1.75, -0.55)
	gr.quad(a, b, r1, r0)
	gr.quad(c, d, r0, r1)
	put(gr, "w_roof_red2", {"tint": Color(1.0, 0.85, 0.8)}).layers = 33

# 小船：真 3D 的木殼（斷面內插），有船舷、船底、兩條橫板
func build_boat(pos: Vector3) -> void:
	boat = Node3D.new()
	boat.position = pos
	add_child(boat)
	parent_node = boat
	var g := geo("wood")
	var gi := geo("wood")
	var n := 9
	var L := 3.0
	var sec: Array = []
	for i in n + 1:
		var u := float(i) / n
		var hw := 0.56 * pow(sin(PI * (0.14 + 0.83 * u)), 0.7)
		var top := 0.4 + 0.2 * u * u * u + 0.05 * (1.0 - u) * (1.0 - u)
		sec.append([-L * 0.5 + L * u, hw, top])
	for i in n:
		var a: Array = sec[i]; var b: Array = sec[i + 1]
		g.uo = Vector2(float(i) * (L / n) * 32.0 / 64.0, 0.0); gi.uo = g.uo      # 貼圖沿船身連續（木板是長條，不是一段一段重來）
		for sg in [-1.0, 1.0]:
			var a0 := Vector3(a[0], 0.0, sg * a[1] * 0.55); var b0 := Vector3(b[0], 0.0, sg * b[1] * 0.55)
			var a1 := Vector3(a[0], a[2], sg * a[1]); var b1 := Vector3(b[0], b[2], sg * b[1])
			var ai := Vector3(a[0], a[2], sg * (a[1] - 0.05)); var bi := Vector3(b[0], b[2], sg * (b[1] - 0.05))
			var af := Vector3(a[0], 0.17, sg * a[1] * 0.5); var bf := Vector3(b[0], 0.17, sg * b[1] * 0.5)
			if sg > 0:
				g.quad(a0, b0, b1, a1); g.quad(a1, b1, bi, ai); gi.quad(bf, af, ai, bi)
			else:
				g.quad(b0, a0, a1, b1); g.quad(b1, a1, ai, bi); gi.quad(af, bf, bi, ai)
		gi.quad(Vector3(a[0], 0.17, a[1] * 0.5), Vector3(b[0], 0.17, b[1] * 0.5), Vector3(b[0], 0.17, -b[1] * 0.5), Vector3(a[0], 0.17, -a[1] * 0.5))
	# 船尾板
	var s0: Array = sec[0]
	g.quad(Vector3(s0[0], 0, -s0[1] * 0.55), Vector3(s0[0], 0, s0[1] * 0.55), Vector3(s0[0], s0[2], s0[1]), Vector3(s0[0], s0[2], -s0[1]))
	put(g, "wood", {"tint": Color(1.0, 0.86, 0.8), "glow_all": 0.05})
	put(gi, "wood", {"tint": Color(0.7, 0.6, 0.62), "glow_all": 0.04}, false)
	var gb := geo("wood")
	gb.box(Vector3(-0.45, 0.27, 0), Vector3(0.24, 0.05, 0.96))
	gb.box(Vector3(0.5, 0.29, 0), Vector3(0.24, 0.05, 0.86))
	put(gb, "wood", {"tint": Color(1.1, 0.95, 0.85), "glow_all": 0.05})
	parent_node = self
	var bl := sprite("lantern", pos + Vector3(1.05, 0.42, 0.0), {"tilt": true, "emit": 3.0, "glow_all": 0.6, "lit": 0.0, "shadow": false})
	boat.set_meta("lantern", bl)
	omni(pos + Vector3(1.0, 0.75, 0.1), Color(1.0, 0.6, 0.26), 1.3, 3.0, false, 1.0, 0.1)

# ------------------------------------------------------------------ 場景
func _ready() -> void:
	rng.seed = 11
	parent_node = self
	args = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--old="): old_list = a.substr(6)
		if a.begins_with("--p1="): p1_list = a.substr(5)
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://tex/meta.json"))
	sh_pix_mip = Shader.new()
	sh_pix_mip.code = sh_pix.code.replace("source_color, filter_nearest, repeat_enable", "source_color, filter_nearest_mipmap_anisotropic, repeat_enable")
	var az := deg_to_rad(argf("az", 28.0))      # 光在地面上的行進方向，與 +z（朝鏡頭）的夾角，往 +x 偏
	var el := deg_to_rad(argf("el", SUN_EL))
	sun_dir = Vector3(sin(az) * cos(el), -sin(el), cos(az) * cos(el)).normalized()
	setup_camera()
	build_env()
	build_ground()
	build_town()
	build_props()
	build_plants()
	build_cast()
	build_life()
	build_sky()
	build_post()
	if not has("--top") and not has("--no-zones"):
		var rs := rng.state
		build_zones()
		build_route()
		rng.state = rs
	if has("--probe"):      # pilot 量測：1 點陣棋盤在 1x / 0.8x / 0.667x 下的取樣結果
		var i := 0
		for sc in [1.0, 0.8, 0.75, 0.6667]:
			sprite("pilot_probe", HERO + Vector3(1.0 + i * 1.2, 0, 0.3), {"tilt": true, "scale": sc, "shadow": false, "flat_lit": 0.3, "layer": 128})
			i += 1
	if has("--no-leaves"):
		for e in leaf_emitters: e.visible = false
	if has("--mask"): set_mask()
	if has("--shots"): run_shots()

func setup_camera() -> void:
	depth0 = 1080.0 / (2.0 * tan(deg_to_rad(FOV * 0.5)) * PPM * K_PX)
	var p := deg_to_rad(PITCH)
	cam_fwd = Vector3(0, -sin(p), -cos(p)).normalized()
	cam_right = Vector3(1, 0, 0)
	cam_up = cam_right.cross(cam_fwd).normalized()
	# 主角在畫面左中；位移都垂直於視線，所以主角深度仍是 depth0
	var aim := HERO + Vector3(0, 0.6, 0) + cam_right * argf("ox", 1.7) + cam_up * argf("oy", 1.0)
	cam_pos = aim - cam_fwd * depth0
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)
	cam.look_at_from_position(cam_pos, cam_pos + cam_fwd, Vector3.UP)
	cam.current = true
	cam.cull_mask = 0x3FF
	if has("--top"):      # 除錯：從正上方看受光範圍
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 26.0
		cam.look_at_from_position(Vector3(0, 40, -3), Vector3(0, 0, -3), Vector3(0, 0, -1))
		return
	if not has("--no-dof") and not has("--mask"):
		# 自製景深（移軸）：全螢幕四邊形掛在鏡頭前；焦點在主角所在的廣場中段，上緣（遠）與下緣（近）漸進模糊
		var dq := MeshInstance3D.new()
		var qm := QuadMesh.new(); qm.size = Vector2(2, 2)
		dq.mesh = qm
		var dm := ShaderMaterial.new(); dm.shader = load("res://shaders/dof.gdshader")
		dm.set_shader_parameter("near_start", depth0 - argf("dn", 2.0))
		dm.set_shader_parameter("near_trans", 2.6)
		dm.set_shader_parameter("far_start", depth0 + argf("df", 6.5))
		dm.set_shader_parameter("far_trans", 8.0)
		dm.set_shader_parameter("max_r", 13.0)
		dm.set_shader_parameter("far_r", 3.5)
		dm.render_priority = 0
		dq.material_override = dm
		dq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dq.layers = 512
		dq.extra_cull_margin = 16384.0
		dof_node = dq
		cam.add_child(dq)
		dq.position = Vector3(0, 0, -1.0)

func build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.13, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.46, 0.68)      # 陰影區：冷紫藍
	env.ambient_light_energy = argf("amb", 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = argf("exp", 1.0)
	env.tonemap_white = 6.0
	env.glow_enabled = not has("--no-glow")      # pilot 除錯旗標（預設不動）：只用來驗證「牆面發糊是不是 bloom 造成的」
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.3
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.set_glow_level(0, 0.0); env.set_glow_level(1, 0.5); env.set_glow_level(2, 0.9); env.set_glow_level(3, 0.6); env.set_glow_level(4, 0.2); env.set_glow_level(5, 0.0); env.set_glow_level(6, 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 2.2
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 1.3
	if not has("--no-fog"):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0015
		env.volumetric_fog_albedo = Color(1.0, 0.88, 0.8)
		env.volumetric_fog_anisotropy = 0.5
		env.volumetric_fog_length = 46.0
		env.volumetric_fog_detail_spread = 1.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.0
		env.volumetric_fog_temporal_reprojection_enabled = true
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 1.04
	# 分離色調：暗部偏藍紫、亮部偏暖
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	gr.colors = PackedColorArray([Color(0.028, 0.032, 0.06), Color(0.225, 0.24, 0.29), Color(0.59, 0.61, 0.58), Color(1.0, 0.99, 0.88)])
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	gt.width = 256
	env.adjustment_color_correction = gt
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# 主光：一顆低角度夕陽（左後方）
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.36)
	sun.light_energy = argf("sun", 9.0)
	sun.light_specular = 0.3
	sun.shadow_enabled = not has("--no-shadow")
	sun.light_volumetric_fog_energy = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 46.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.light_cull_mask = 0xFFFFF & ~32
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, sun_dir, Vector3.UP)
	# 立面補光：只照牆面（layer 5），模擬被夕陽照亮的地面與天空反彈回來的光；遠低於主光、不投影
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.92, 0.86, 0.82)
	fill.light_energy = argf("fill", 0.3)
	fill.light_specular = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.light_cull_mask = 16
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.3, -0.35, -0.9), Vector3.UP)
	# 屋頂的天光：黃昏天空從上方照下來，只照屋頂（layer 6）；朝太陽的斜面另有主光，所以受光面與背光面差一階以上
	var rf := DirectionalLight3D.new()
	rf.light_color = Color(0.9, 0.74, 0.86)
	rf.light_energy = argf("roof", 0.65)
	rf.light_specular = 0.0
	rf.light_volumetric_fog_energy = 0.0
	rf.light_cull_mask = 32
	add_child(rf)
	rf.look_at_from_position(Vector3.ZERO, Vector3(0.0, -0.85, -0.5), Vector3.UP)
	if not has("--no-fog"):
		# 大氣霧：只從廣場後緣開始，越遠越淡（暖紫色），前景不受影響
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color(0.42, 0.42, 0.62)
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.0
		env.fog_density = argf("haze", 0.16)
		env.fog_depth_begin = depth0 + 11.0
		env.fog_depth_end = depth0 + 30.0
		env.fog_depth_curve = 0.8
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.0

func make_mirror(plane_y: float, flag_bit: int, exclude: int) -> ViewportTexture:
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rc := Camera3D.new()
	rc.fov = FOV; rc.near = 0.5; rc.far = 300.0
	rc.cull_mask = (0x1FF & ~exclude) | flag_bit
	var renv: Environment = env.duplicate()
	var sky := Sky.new()
	var sm := ShaderMaterial.new(); sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("top", Color(0.16, 0.14, 0.4)); sm.set_shader_parameter("mid", Color(0.6, 0.3, 0.5)); sm.set_shader_parameter("horizon", Color(1.0, 0.56, 0.32))
	sky.sky_material = sm
	renv.sky = sky
	renv.background_mode = Environment.BG_SKY
	renv.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	renv.glow_enabled = false
	renv.ssao_enabled = false
	renv.ssil_enabled = false
	renv.adjustment_enabled = false
	renv.volumetric_fog_enabled = false
	rc.environment = renv
	vp.add_child(rc)
	rc.current = true
	mirrors.append({"cam": rc, "y": plane_y})
	return vp.get_texture()

func sync_mirrors() -> void:
	if has("--top"): return
	var p := cam.global_position
	var f := -cam.global_transform.basis.z
	for m in mirrors:
		var rc: Camera3D = m.cam
		var y: float = m.y
		var mp := Vector3(p.x, 2.0 * y - p.y, p.z)
		rc.look_at_from_position(mp, mp + Vector3(f.x, -f.y, f.z), Vector3.UP)

func build_ground() -> void:
	# 廣場：整片專用的不重複石板貼圖（tools/plaza.py），x -16..16、z -15..2.5
	var pg := SurfaceTool.new()
	pg.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z1 := QUAY_Z
	var crn := [Vector3(-16, 0, z1), Vector3(-16, 0, BACK_Z), Vector3(16, 0, BACK_Z), Vector3(-16, 0, z1), Vector3(16, 0, BACK_Z), Vector3(16, 0, z1)]
	for p in crn:
		pg.set_normal(Vector3.UP); pg.set_uv(Vector2((p.x + 16.0) / 32.0, (p.z + 15.0 + (2.5 - QUAY_Z)) / 17.5)); pg.add_vertex(p)
	var gm := MeshInstance3D.new()
	gm.mesh = pg.commit()
	ground_mat = ShaderMaterial.new(); ground_mat.shader = load("res://shaders/plaza.gdshader")
	ground_mat.set_shader_parameter("tex", tex(ptex("pilot_plaza", "ground") if pilot("ground") else "plaza"))
	ground_mat.set_shader_parameter("hand_puddles", pilot("ground"))      # pilot：水窪形狀改讀貼圖 alpha（手繪），不用程序化雜訊
	ground_mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
	var pud: Array = [Vector4(7.6, 1.6, 0.6, 0.26), Vector4(5.3, -0.2, 0.7, 0.34), Vector4(1.0, -3.45, 0.6, 0.24), Vector4(-6.2, 1.3, 0.55, 0.26), Vector4(9.4, 0.4, 0.55, 0.3), Vector4(2.0, 1.7, 0.6, 0.22)]
	ground_mat.set_shader_parameter("lamps", [Vector3(7.1, 1.9, 1.0), Vector3(-0.95, -4.3, 0.8), Vector3(6.2, -3.6, 0.8), Vector3(10.6, 1.0, 0.7)])
	while pud.size() < 8: pud.append(Vector4(0, 0, 0, 0))
	ground_mat.set_shader_parameter("puddles", pud)
	ground_mat.set_shader_parameter("sky_col", Color(0.62, 0.42, 0.6))
	gm.material_override = ground_mat
	gm.layers = 1
	add_child(gm)
	# 後方低一階的地面與擋土牆
	var gl := geo("cobble")
	gl.quad(Vector3(-40, LOW_Y, BACK_Z), Vector3(40, LOW_Y, BACK_Z), Vector3(40, LOW_Y, -15.0), Vector3(-40, LOW_Y, -15.0))
	put(gl, "cobble", {"tint": Color(0.5, 0.45, 0.6)}, false)
	var gr2 := geo("stonewall")
	gr2.quad(Vector3(16, LOW_Y, BACK_Z), Vector3(-16, LOW_Y, BACK_Z), Vector3(-16, 0, BACK_Z), Vector3(16, 0, BACK_Z))
	put(gr2, "stonewall", {"tint": Color(0.8, 0.75, 0.9)}, false)
	# 堤岸牆（砌石、苔、水線污痕）
	var gq := geo("quaywall")
	gq.quad(Vector3(-12, WATER_Y - 0.3, QUAY_Z), Vector3(12, WATER_Y - 0.3, QUAY_Z), Vector3(12, 0, QUAY_Z), Vector3(-12, 0, QUAY_Z))
	put(gq, "quaywall", {"tint": Color(1.0, 1.04, 1.12), "ground_mask": 1.0})
	# 垂在堤岸邊的藤蔓（打破那條水平線）
	for v in [["w_vines_3", -9.4], ["w_vines_1", -6.9], ["w_vines_2", -0.1], ["w_vines_0", 1.6], ["w_vines_3", 3.4], ["w_vines_1", 8.4], ["w_vines_2", 10.3]]:
		var vh: float = (px_size(v[0]).y - PAD) / PPM
		sprite(v[0], Vector3(v[1], 0.06 - vh, QUAY_Z + 0.012), {"shadow": false, "lambert": true, "rustle_px": 0.4})
	# 石階（從堤岸往鏡頭方向下到水邊，兩側有石墩）
	var gs := geo("w_stone")
	var sx := 5.9
	for i in 5:
		gs.box(Vector3(sx, WATER_Y - 0.3, QUAY_Z + 0.16 + i * 0.32), Vector3(2.0, 1.25 - 0.2 * (i + 1), 0.32))
	put(gs, "w_stone", {"tint": Color(1.1, 1.05, 1.15), "ground_mask": 1.0}).layers = 17
	var gs2 := geo("w_stone")
	for ex in [sx - 1.16, sx + 1.16]:
		gs2.box(Vector3(ex, WATER_Y - 0.3, QUAY_Z + 0.5), Vector3(0.32, 1.25, 1.0))
	put(gs2, "w_stone", {"tint": Color(1.0, 0.96, 1.08), "ground_mask": 1.0}).layers = 17
	# 運河：平面反射（鏡像相機 → SubViewport）＋像素波紋
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(130, 12)      # 運河延長到兩端水門（x ±60）
	water.mesh = wm
	var wmat := ShaderMaterial.new(); wmat.shader = load("res://shaders/water.gdshader")
	water_mat = wmat
	wmat.set_shader_parameter("refl", make_mirror(WATER_Y, 1024, 2 | 256))
	if has("--no-refl"): wmat.set_shader_parameter("strength", 0.0)
	# 倒影光柱的光源（x、z、半寬、強度；顏色＋長度）：船燈、堤岸路燈、中央屋兩扇窗、麵包店櫥窗、左屋的窗、巷口路燈、右屋門燈
	var ss: Array = [Vector4(-1.55, QUAY_Z + 1.05, 0.05, 0.9), Vector4(7.1, 1.9, 0.09, 1.0), Vector4(0.45, -4.6, 0.09, 0.6), Vector4(2.35, -4.6, 0.09, 0.6), Vector4(5.6, -4.3, 0.17, 0.7), Vector4(-5.3, -0.9, 0.08, 0.6), Vector4(-0.95, -4.3, 0.07, 0.8), Vector4(10.7, 1.0, 0.1, 0.8)]
	var sc: Array = [Vector4(1.0, 0.45, 0.1, 2.4), Vector4(1.0, 0.52, 0.13, 4.5), Vector4(1.0, 0.5, 0.14, 4.0), Vector4(1.0, 0.5, 0.14, 4.0), Vector4(1.0, 0.48, 0.12, 4.2), Vector4(1.0, 0.5, 0.15, 3.6), Vector4(1.0, 0.55, 0.16, 4.4), Vector4(1.0, 0.5, 0.13, 4.0)]
	while ss.size() < 8: ss.append(Vector4(0, 0, 0, 0)); sc.append(Vector4(0, 0, 0, 1))
	wmat.set_shader_parameter("streaks", ss)
	wmat.set_shader_parameter("streak_cols", sc)
	for i in ss.size():
		if ss[i].w > 0.0: zone_streaks.append([ss[i], sc[i]])
	wmat.set_shader_parameter("cam_xz", Vector2(cam_pos.x, cam_pos.z))
	wmat.set_shader_parameter("quay_z", QUAY_Z)
	wmat.set_shader_parameter("floaters", [Vector4(-2.6, QUAY_Z + 1.05, 1.6, 0.62), Vector4(3.93, QUAY_Z + 0.07, 0.14, 0.14)])
	water.material_override = wmat
	water.position = Vector3(0, WATER_Y, QUAY_Z + 6.0)
	water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	hide_in_mask.append(water)
	# 繫船柱＋鐵鍊
	var bz := QUAY_Z - 0.34
	var bxs := [-8.3, -5.6, -3.0, -0.4, 2.2, 4.5, 7.3, 9.6]
	for bx in bxs: bollard(Vector3(bx, 0, bz))
	for i in bxs.size() - 1:
		if i == 4: continue      # 石階前留缺口
		pixel_wire(Vector3(bxs[i] + 0.1, 0.47, bz), Vector3(bxs[i + 1] - 0.1, 0.47, bz), 0.2, [], 2.0, Color(0.2, 0.18, 0.26))

func build_town() -> void:
	var W := 0.62
	# A：左側矮屋（屋脊橫向，正面朝鏡頭）
	house({"x0": -12.5, "x1": -6.6, "zb": -4.6, "zf": -0.9, "h": 1.9, "rh": 1.35, "ridge": "x", "tint": Color(1.0, 0.9, 0.78), "roof": "w_roof_slate2", "roof_tint": Color(0.82, 0.95, 1.12), "chimney": Vector2(-1.0, -0.6),
		"items": [["windows_3", "f", 1.3, 0.5, W], ["doors_0", "f", -0.6, 0.3, 0.0], ["windows_1", "r", 0.5, 0.55, W]]})
	# B：紅磚＋半木造的兩層樓（山牆朝前），廣場後方正中
	house({"x0": -0.7, "x1": 3.5, "zb": -8.4, "zf": -4.6, "h": 3.0, "rh": 1.6, "ridge": "z", "wall": "brick", "tint": Color(0.95, 0.82, 0.8), "upper": 1.55, "upper_tint": Color(0.9, 0.8, 0.7), "roof_tint": Color(0.6, 0.66, 0.86), "chimney": Vector2(0.9, -0.8), "pilot_wall": true,
		"items": [["doors_1", "f", 0.95, 0.3, W], ["windows_3", "f", -0.85, 0.42, W], ["windows_2", "f", -0.95, 1.72, W], ["windows_2", "f", 0.95, 1.72, W], ["windows_0", "f", 0.0, 3.0, W], ["windows_1", "l", 0.9, 1.75, W], ["windows_0", "l", -0.9, 1.75, 0.0]]})
	# C：麵包店（矮、屋脊橫向、大片屋頂朝鏡頭）
	house({"x0": 4.5, "x1": 10.2, "zb": -8.2, "zf": -4.3, "h": 2.0, "rh": 1.5, "ridge": "x", "tint": Color(1.0, 0.88, 0.76), "roof": "w_roof_red2", "roof_tint": Color(1.05, 0.86, 0.78), "chimney": Vector2(1.2, 0.5), "pilot_roof": true,
		"items": [["w_win_c", "f", -1.0, 0.42, 0.6], ["w_door_open", "f", 0.75, 0.3, 0.6], ["w_win_a2", "f", 2.0, 0.5, W], ["w_win_b", "l", 0.6, 0.7, W]]})
	# D：右側的屋子（屋脊縱向，側牆朝廣場）
	house({"x0": 10.7, "x1": 15.0, "zb": -2.6, "zf": 3.0, "h": 2.6, "rh": 1.5, "ridge": "z", "wall": "stonewall", "tint": Color(1.0, 0.92, 0.9), "upper": 1.4, "roof": "w_roof_slate2", "roof_tint": Color(0.95, 1.0, 0.92),
		"items": [["windows_0", "l", 1.3, 0.3, W], ["windows_3", "l", -0.3, 0.3, W], ["windows2_0", "l", 1.2, 1.5, W], ["windows2_2", "l", -1.0, 1.5, W]]})
	# 後排（地勢低一階）：巷子兩側與麵包店後面的房子，窗亮著、煙囪露在屋頂上
	var L := LOW_Y
	house_at({"x0": -12.6, "x1": -8.3, "zb": -13.4, "zf": -9.8, "h": 3.5, "rh": 1.5, "ridge": "z", "tint": Color(0.92, 0.88, 0.84), "roof": "w_roof_red2", "roof_tint": Color(0.95, 0.8, 0.8), "cast": false, "lights": false, "chimney": Vector2(1.0, 0.4),
		"items": [["w_win_b2", "f", -0.9, 2.1, W], ["w_win_a", "f", 0.0, 2.9, W]]}, L)
	house_at({"x0": -7.5, "x1": -3.7, "zb": -13.6, "zf": -9.9, "h": 3.3, "rh": 1.4, "ridge": "z", "tint": Color(0.98, 0.84, 0.72), "roof": "w_roof_slate2", "roof_tint": Color(0.9, 0.95, 1.1), "cast": false, "lights": false, "chimney": Vector2(-0.9, -0.3),
		"items": [["w_win_a2", "r", 0.9, 1.9, W], ["w_win_b", "f", 0.5, 2.0, W], ["w_win_d", "f", 0.0, 3.5, W]]}, L)
	house_at({"x0": -0.5, "x1": 3.3, "zb": -13.6, "zf": -9.9, "h": 4.3, "rh": 1.4, "ridge": "z", "tint": Color(0.9, 0.86, 0.82), "roof": "w_roof_red2", "roof_tint": Color(1.0, 0.85, 0.8), "lights": false, "cast": false, "chimney": Vector2(0.9, 0.5),
		"items": [["w_win_a3", "l", 0.6, 2.0, W], ["w_win_a", "l", -0.9, 2.0, W], ["w_win_a2", "f", 0.0, 3.7, W]]}, L)
	house_at({"x0": 4.1, "x1": 8.6, "zb": -13.8, "zf": -10.2, "h": 4.0, "rh": 1.5, "ridge": "z", "tint": Color(1.0, 0.82, 0.7), "roof": "w_roof_slate2", "roof_tint": Color(0.85, 0.95, 1.05), "lights": false, "cast": false, "chimney": Vector2(1.2, -0.5),
		"items": [["w_win_a2", "f", -1.0, 2.9, W], ["w_win_a", "f", 1.0, 2.9, W], ["w_win_d", "f", 0.0, 4.3, W]]}, L)
	house_at({"x0": 9.6, "x1": 14.0, "zb": -13.4, "zf": -9.8, "h": 3.6, "rh": 1.5, "ridge": "z", "tint": Color(0.94, 0.86, 0.8), "roof": "w_roof_red2", "roof_tint": Color(0.9, 0.78, 0.8), "lights": false, "cast": false, "chimney": Vector2(-1.0, 0.4),
		"items": [["w_win_b2", "f", -0.9, 2.5, W], ["w_win_a3", "f", 0.0, 3.1, W]]}, L)
	# 樹下花圃的矮石牆（L 形）
	var gwall := geo("stonewall")
	gwall.box(Vector3(-5.3, 0, -4.75), Vector3(2.6, 0.34, 0.3))
	gwall.box(Vector3(-3.85, 0, -6.4), Vector3(0.3, 0.34, 3.0))
	put(gwall, "stonewall", {"tint": Color(0.9, 0.86, 0.94), "grime": 0.5, "wall_top": 1.5})
	var gdirt := geo("grass")
	gdirt.quad(Vector3(-6.6, 0.02, -4.9), Vector3(-4.0, 0.02, -4.9), Vector3(-4.0, 0.02, -8.2), Vector3(-6.6, 0.02, -8.2))
	put(gdirt, "grass", {"tint": Color(0.42, 0.46, 0.34)}, false)
	# 麵包店：遮雨棚（斜的條紋布）、招牌、攤位桌
	var ga := geo("awning")
	ga.quad(Vector3(5.3, 1.45, -3.55), Vector3(7.3, 1.45, -3.55), Vector3(7.3, 1.95, -4.28), Vector3(5.3, 1.95, -4.28))
	put(ga, "awning", {"rough": 0.9})
	sprite("w_sign", Vector3(8.75, 1.0, -4.28), {"shadow": false, "lambert": true, "layer": 17})
	wall_lantern(Vector3(4.85, 0.8, -4.26), 0.0, 0.7)
	omni(Vector3(6.2, 1.0, -3.0), Color(1.0, 0.62, 0.28), 2.4, 4.6, false, 0.6, 0.04, 0.2)      # 麵包店櫥窗灑到地上的暖光（配角光池）
	var gt := geo("cloth")
	gt.box(Vector3(7.5, 0, -1.9), Vector3(1.5, 0.55, 0.75))
	put(gt, "cloth", {})
	sprite("street2_3", Vector3(7.15, 0.5, -1.9), {"flat_lit": 0.3, "shadow_off": 0.02})
	sprite("w_props7_3", Vector3(7.9, 0.5, -1.9), {"flat_lit": 0.3, "shadow_off": 0.02})
	sprite("w_cart", Vector3(4.5, 0, -2.2), {"flat_lit": 0.3, "tilt": true})      # 南瓜推車
	sprite("street2_0", Vector3(9.3, 0.0, -4.1), {"flat_lit": 0.5})
	# 牆上的提燈、信箱、常春藤
	wall_lantern(Vector3(-0.72, 1.0, -5.2), -90.0, 0.8)
	wall_lantern(Vector3(3.3, 0.75, -4.5), 0.0, 0.7)
	wall_lantern(Vector3(-6.58, 0.9, -1.6), 90.0, 0.7)
	wall_lantern(Vector3(10.68, 0.9, 1.0), -90.0, 0.8)
	sprite("street2_1", Vector3(0.15, 0.35, -4.58), {"shadow": false, "lambert": true, "layer": 17})
	sprite("ivy_0", Vector3(-8.6, -1.75, -0.88), {"shadow": false, "lambert": true, "rustle_px": 0.4, "layer": 17})
	sprite("ivy_0", Vector3(10.68, -1.0, -1.4), {"shadow": false, "lambert": true, "rustle_px": 0.4, "yaw": -90.0, "layer": 17})
	sprite("ivy_1", Vector3(10.0, -1.3, -4.28), {"shadow": false, "lambert": true, "rustle_px": 0.4, "layer": 17, "flip": true})
	# 巷子：兩側牆上的提燈＋橫跨巷子的串燈，一路往深處
	for lz in [-6.9, -10.6, -12.6]:
		wall_lantern(Vector3(-0.72 if lz > -9.0 else -0.52, 1.0 if lz > -9.0 else LOW_Y + 1.6, lz), -90.0, 0.7, 3.0)
	for lz in [-10.4, -12.4]:
		wall_lantern(Vector3(-3.68, LOW_Y + 1.6, lz), 90.0, 0.7, 3.0)
	var cols := [Color(1.0, 0.75, 0.35), Color(1.0, 0.55, 0.3), Color(1.0, 0.9, 0.55)]
	pixel_wire(Vector3(-3.7, 2.1, -6.2), Vector3(-0.75, 2.5, -6.2), 0.35, cols, 1.0, Color(0.16, 0.12, 0.16), 12)
	pixel_wire(Vector3(-3.7, LOW_Y + 3.1, -10.3), Vector3(-0.5, LOW_Y + 3.3, -10.3), 0.35, cols, 1.0, Color(0.16, 0.12, 0.16), 12)
	pixel_wire(Vector3(-3.7, LOW_Y + 3.0, -12.6), Vector3(-0.5, LOW_Y + 3.2, -12.6), 0.3, cols, 1.0, Color(0.16, 0.12, 0.16), 12)
	# 堤岸上的兩盞路燈
	lamp_post(Vector3(7.1, 0, 1.9))
	lamp_post(Vector3(-0.95, 0, -4.3), 2.3)

func build_props() -> void:
	# A 屋前：木桶、柴堆、長椅
	barrel(Vector3(-6.95, 0, -0.45))
	barrel(Vector3(-7.55, 0, -0.5))
	sprite("props2_3", Vector3(-9.0, 0, -0.75), {"flat_lit": 0.5})
	bench(Vector3(-5.6, 0, 0.9), 12.0)
	# B 屋前：兩座石砌花台、木桶
	planter(Vector3(0.0, 0, -4.05), 1.5, 0.6, ["flowers_0", "flowers_1", "flowers_4", "flowers_5", "plants2_1"])
	planter(Vector3(2.75, 0, -4.05), 1.3, 0.6, ["flowers_2", "flowers_3", "flowers_0", "plants2_3"])
	barrel(Vector3(-0.35, 0, -3.5))
	barrel(Vector3(3.95, 0, -4.0))
	crate(Vector3(4.05, 0, -3.3), 0.5, 20.0)
	# 麵包店前：長椅、木箱
	bench(Vector3(5.75, 0, -3.3), 0.0)
	crate(Vector3(10.0, 0, -3.6))
	crate(Vector3(10.05, 0.6875, -3.65), 0.5, 15.0)
	barrel(Vector3(10.2, 0, -2.75))
	# 右側屋前：花台、木桶
	planter(Vector3(10.2, 0, 0.6), 0.6, 1.8, ["flowers_1", "flowers_4", "bushes_1", "flowers_5"], 0.4)
	barrel(Vector3(10.25, 0, 2.0))
	# 左下：花台
	planter(Vector3(-3.6, 0, 1.55), 1.5, 0.5, ["flowers_0", "flowers_4", "flowers_2", "plants2_5"], 0.28)
	planter(Vector3(-8.6, 0, 1.2), 1.3, 0.6, ["bushes_2", "flowers_3", "flowers_1"], 0.3)
	# 碼頭石墩上釣魚的老人；廣場右側的水井
	# pilot 第二階段：手修釣魚老人（0.75x ≈ 42.7 PPM；釣竿 4 格由 _process 選格）——換入後不如原本（見 shots/godot_pilot/10_fisher/compare.png），已退回：預設用原本的，只有加 `--new-fisher` 才換上
	if pilot("fisher") and has("--new-fisher"):
		fisher_m = sprite("pilot_fisher_anim", Vector3(4.5, 0, QUAY_Z + 0.75), {"flat_lit": 0.3, "tilt": true, "glow_all": 0.09, "scale": 0.75, "frame_fixed": 0.0}).material_override
	else:
		sprite("w_fisher", Vector3(4.6, 0, QUAY_Z + 0.75), {"flat_lit": 0.3, "tilt": true, "glow_all": 0.09, "lift_x": 0.42})
	# 釣線（從竿尖垂到水面）與浮標
	var gline := geo("planks")
	gline.box(Vector3(3.93, WATER_Y, QUAY_Z + 0.07), Vector3(1.0 / PPM, 2.0, 1.0 / PPM))
	put(gline, "planks", {"tint": Color(0.5, 0.5, 0.6), "glow_all": 0.2}, false)
	var gbob := geo("planks")
	gbob.box(Vector3(3.93, WATER_Y, QUAY_Z + 0.07), Vector3(3.0 / PPM, 3.0 / PPM, 3.0 / PPM))
	put(gbob, "planks", {"tint": Color(3.0, 0.5, 0.4), "glow_all": 0.3}, false)
	well(Vector3(8.3, 0, 0.1))
	# 小船（繫在堤岸邊）
	build_boat(Vector3(-2.6, WATER_Y - 0.1, QUAY_Z + 1.05))
	pixel_wire(Vector3(-1.0, WATER_Y + 0.4, QUAY_Z + 0.9), Vector3(-0.4, 0.3, QUAY_Z - 0.34), -0.25, [], 2.0, Color(1.6, 1.2, 0.7))

func build_plants() -> void:
	var kinds := ["maple_0", "maple_1", "maple_2", "maple_3", "maple_4", "maple_5"]
	tree(Vector3(argf("tx", -6.3), 0, argf("tz", -5.4)), kinds, 64, Vector3(2.5, 1.25, 2.1), 2.95, 1.6)
	# 花圃後角的第二棵小楓樹（樹幹在後、枝葉伸到巷口上方）
	rng.seed = 23
	tree(Vector3(-4.5, 0, -8.1), kinds, 36, Vector3(1.7, 0.95, 1.5), 3.0, 0.9, false, true)      # 樹幹不投影：它的影子正好會蓋住主角的光池
	# 往右伸出去的幾團枝葉：影子落在光池右邊，把受光區切成一道道光帶與長影（位置由「影子要落在哪」反推）
	var sd := Vector3(sun_dir.x, 0, sun_dir.z).normalized()
	var perp := Vector3(sun_dir.z, 0, -sun_dir.x).normalized()
	var reach := 1.0 / tan(deg_to_rad(argf("el", SUN_EL)))
	var k := 0
	for b in [[2.5, -1.9, 2.9], [2.7, 0.3, 3.3], [2.45, 2.3, 2.8], [-1.9, 1.6, 2.6], [0.9, -1.8, 2.4], [0.3, -3.8, 2.8], [1.1, -4.4, 3.0]]:      # 後三團遮住主角身後（畫面上方）那段，光池落在她腳邊與前方
		var land: Vector3 = HERO + perp * b[0] + sd * b[1]
		var cp: Vector3 = land - sd * (b[2] * reach) + Vector3(0, b[2], 0)
		sprite(kinds[k % kinds.size()], cp, {"center": true, "tilt": true, "shadow_only": true, "shadow_off": 0.0})      # 只投影、不顯示：把光池切成光帶的「遮光片」（看不見的枝葉）
		k += 1
	# 花圃裡的灌木與花
	for bp in [["bushes_0", -4.5, -5.3], ["bushes_3", -5.4, -5.2], ["bushes_1", -4.4, -6.6], ["bushes_3", -4.5, -7.8], ["flowers_5", -5.0, -5.6], ["flowers_1", -4.3, -6.0], ["flowers_0", -4.4, -7.2]]:
		sprite(bp[0], Vector3(bp[1], 0.02, bp[2]), {"rustle_px": 0.6, "vsway_px": 1.0, "flat_lit": 0.2, "glow_all": 0.03})
	# 牆腳的草與花
	var foot := [[-12.0, -6.7, -0.82], [-0.6, 3.4, -4.52], [9.3, 10.1, -4.22]]
	for i in 46:
		var seg: Array = foot[i % 3]
		var x := rng.randf_range(seg[0], seg[1])
		if i % 3 == 0:
			sprite("grasses_%d" % (i % 5), Vector3(x, 0, seg[2] + rng.randf_range(0.02, 0.1)), {"sway_px": 3.0, "flat_lit": 0.45, "glow_all": 0.03, "tint": Color(0.7, 0.86, 0.66), "flip": i % 2 == 0, "shadow": false, "layer": 17})
		else:
			sprite("plants2_%d" % (rng.randi() % 8), Vector3(x, 0, seg[2] + rng.randf_range(0.02, 0.1)), {"sway_px": 2.0, "flat_lit": 0.45, "glow_all": 0.03, "flip": i % 2 == 0, "shadow": false, "layer": 17})
	for i in 14:
		var z := rng.randf_range(-2.4, 2.6)
		sprite("plants2_%d" % (rng.randi() % 8), Vector3(10.62, 0, z), {"sway_px": 2.0, "flat_lit": 0.45, "yaw": -90.0, "shadow": false})
	# 地上的落葉堆（平躺）：樹下、牆腳、堤岸邊
	var piles := [[-5.0, -3.9, 0], [-6.1, -0.2, 2], [1.9, -3.4, 1], [6.9, 1.7, 3], [-7.9, 1.7, 1], [9.7, -1.3, 2], [-1.5, -5.8, 3]]
	for pl in piles:
		var lp := sprite("leafpile_%d" % pl[2], Vector3(pl[0], 0.012, pl[1]), {"center": true, "shadow": false, "lambert": true})
		lp.rotation = Vector3(-PI / 2, rng.randf_range(-0.5, 0.5), 0)
	# 零星落葉（平躺）
	for i in 150:
		var near_tree := i < 80
		var lp2 := Vector3(rng.randf_range(-7.0, 2.0) if near_tree else rng.randf_range(-10.0, 10.5), 0.01, rng.randf_range(-4.4, 2.2) if near_tree else rng.randf_range(-4.0, 2.2))
		var lf := sprite("leaf_o" if i % 3 else "leaf_r", lp2, {"center": true, "frame_fixed": float(i % 4), "shadow": false, "lambert": true})
		lf.rotation = Vector3(-PI / 2, rng.randf() * TAU, 0)
	# 漂在運河上的落葉
	for i in 22:
		var wl := sprite("leaf_o" if i % 2 else "leaf_r", Vector3(rng.randf_range(-11.0, 11.0), WATER_Y + 0.012, rng.randf_range(QUAY_Z + 0.3, QUAY_Z + 3.4)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "glow_all": 0.3, "lambert": true})
		wl.rotation = Vector3(-PI / 2, 0, 0)
		flyers.append({"n": wl, "kind": "float", "v": rng.randf_range(0.05, 0.12)})
	# 飄落的葉子（粒子）：從樹冠往右前方飄過廣場
	leaf_emitters.append(particles(Vector3(-5.6, 3.4, -4.6), Vector3(2.4, 0.8, 2.0), 30, "leaf_o", {"vary": 1.0, "smin": 0.55}))
	leaf_emitters.append(particles(Vector3(-1.0, 2.6, -2.5), Vector3(4.0, 0.6, 2.0), 14, "leaf_r", {"vary": 1.0, "smin": 0.55}))
	leaf_emitters.append(particles(Vector3(5.0, 2.4, -2.5), Vector3(5.0, 0.5, 2.0), 9, "leaf_o", {"vary": 1.0, "smin": 0.5}))
	# 樹下的光束片（沿太陽方向，從樹冠缺口落到光池）
	if not has("--no-fog"):
		beam(HERO + sd * 0.6 + Vector3(0.1, 0, 0), 7.5, 1.3, 0.11, 1.0)
		beam(HERO + sd * 1.8 + Vector3(-0.5, 0, 0), 8.0, 0.9, 0.08, 4.0)
		beam(HERO + sd * 2.6 + Vector3(0.7, 0, 0), 8.5, 0.8, 0.08, 7.0)

func particles(pos: Vector3, box: Vector3, amount: int, tex_name: String, o: Dictionary = {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = o.get("dir", Vector3(0.6, -0.4, 0.6))
	pm.spread = o.get("spread", 40.0)
	pm.initial_velocity_min = o.get("v0", 0.1); pm.initial_velocity_max = o.get("v1", 0.5)
	pm.gravity = o.get("gravity", Vector3(0.4, -0.42, 0.3))
	pm.damping_min = 0.3; pm.damping_max = 0.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = o.get("turb", 0.9)
	pm.turbulence_noise_scale = 2.2
	pm.turbulence_influence_min = 0.08; pm.turbulence_influence_max = 0.2
	p.process_material = pm
	var life: float = o.get("life", 9.0)
	p.amount = amount; p.lifetime = life; p.preprocess = life
	var fr: float = meta.get(tex_name + "_frames", 1)
	var q := QuadMesh.new(); q.size = px_size(tex_name) / PPM
	if o.has("size_px"): q.size = Vector2.ONE * o["size_px"] / PPM
	var m := ShaderMaterial.new(); m.shader = sh_part
	m.set_shader_parameter("tex", tex(tex_name)); m.set_shader_parameter("frames", fr)
	m.set_shader_parameter("glow_all", o.get("glow", 0.06))
	m.set_shader_parameter("tint", o.get("tint", Color.WHITE))
	m.set_shader_parameter("vary", o.get("vary", 0.0))
	if o.has("smin"):
		pm.scale_min = o["smin"]; pm.scale_max = 1.0
	q.material = m
	p.draw_pass_1 = q
	p.position = pos
	p.rotation.x = -deg_to_rad(PITCH)      # 粒子的四邊形面向鏡頭
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 256
	p.visibility_aabb = AABB(Vector3(-20, -14, -14), Vector3(40, 28, 28))
	add_child(p)
	hide_in_mask.append(p)
	return p

func smoke(pos: Vector3) -> void:
	var p := particles(pos, Vector3(0.03, 0.02, 0.03), 6, "smoke", {"dir": Vector3(0.3, 1, 0.2), "spread": 8.0, "v0": 0.28, "v1": 0.36, "gravity": Vector3(0.12, 0.02, 0.06), "turb": 0.15, "life": 4.5, "glow": 0.2})
	var m: ShaderMaterial = (p.draw_pass_1 as QuadMesh).material
	m.set_shader_parameter("by_age", true)
	m.set_shader_parameter("backlight", 0.3)

# 光束片：從 bottom 逆著太陽方向往上 length 公尺；上窄下寬的梯形，面向鏡頭
func beam(bottom: Vector3, length: float, width: float, strength: float, seed_v: float) -> void:
	var top := bottom - sun_dir * length
	var wax := sun_dir.cross((cam_pos - bottom).normalized()).normalized() * width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [top - wax * 0.67, top + wax * 0.67, bottom + wax, top - wax * 0.67, bottom + wax, bottom - wax]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in 6:
		st.set_uv(uvs[i]); st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new(); m.shader = sh_beam
	m.render_priority = 1
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("seed_v", seed_v)
	m.set_shader_parameter("wx", bottom.x)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 512
	add_child(mi)
	hide_in_mask.append(mi)

var hero_n: MeshInstance3D
var water_mat: ShaderMaterial
# 註：BAKER／CHILD 在廣場上的攤位旁（往畫面中間拉近）
var baker_n: MeshInstance3D
var child_n: MeshInstance3D
var baker_m: ShaderMaterial
var child_m: ShaderMaterial
var cat_n: MeshInstance3D
var cat_m: ShaderMaterial
var bfly_n: MeshInstance3D
const BAKER := Vector3(6.45, 0, -1.75)
const CHILD := Vector3(5.6, 0, -1.7)
const CAT_C := Vector3(3.1, 0, 0.75)

func build_cast() -> void:
	# 主角：2 頭身，站在樹冠缺口落下的光池裡（靜止，有呼吸與眨眼）
	if pilot("hero"):
		# pilot：手修主角，42.67 點陣 / 公尺（scale 0.75，世界大小不變）；4 格（睜眼／閉眼／下沉睜眼／下沉閉眼）由 _process 選格，不用 shader 位移
		hero_n = sprite("pilot_hero_anim", HERO, {"tilt": true, "scale": 0.75, "layer": 128, "flat_lit": 0.16, "rim": 0.5, "frame_fixed": 0.0})
		hero_m = hero_n.material_override
	else:
		hero_n = sprite("hero_anim", HERO, {"tilt": true, "breathe": 1.0, "blink": 1.0, "layer": 128, "flat_lit": 0.16, "rim": 0.5})
	# 事件一：麵包店店員把麵包遞給小孩（兩人面對面，三格手部動作）
	# pilot 第二階段：店員、小孩、貓改用手修 sprite（密度與主角相近：0.705x / 0.718x / 0.75x，世界大小不變）；`--old=baker,child,cat,fisher` 可逐一退回
	if pilot("baker"): baker_n = sprite("pilot_baker_anim", BAKER, {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0, "scale": 0.705})
	else: baker_n = sprite("baker_anim", BAKER, {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0})
	baker_m = baker_n.material_override
	if pilot("child"): child_n = sprite("pilot_child_anim", CHILD, {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0, "scale": 0.718})
	else: child_n = sprite("child4_anim", CHILD, {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0})
	child_m = child_n.material_override
	# 事件二：貓在廣場上追蝴蝶
	if pilot("cat"): cat_n = sprite("pilot_cat_anim", CAT_C, {"tilt": true, "flat_lit": 0.15, "frame_fixed": 0.0, "scale": 0.75})
	else: cat_n = sprite("catrun_anim", CAT_C, {"tilt": true, "flat_lit": 0.15, "frame_fixed": 0.0})
	cat_m = cat_n.material_override
	bfly_n = sprite("bflyL_y", CAT_C + Vector3(0.8, 0.5, 0), {"fps": 9.0, "shadow": false, "center": true, "tilt": true, "flat_lit": 0.6, "glow_all": 0.12, "layer": 256})

func build_life() -> void:
	# 煙囪的煙
	smoke(Vector3(2.3, 5.0, -7.3))
	smoke(Vector3(8.55, 4.1, -5.75))
	# 飛鳥：一小群從右往左橫越屋頂上方
	for i in 6:
		var s := sprite("bird", Vector3.ZERO, {"lit": 0.0, "glow_all": 1.0, "tint": Color(0.1, 0.07, 0.13), "fps": 6.0 + rng.randf() * 3.0, "shadow": false, "center": true, "tilt": true})
		flyers.append({"n": s, "kind": "bird", "x0": rng.randf_range(0.0, 9.0), "y": rng.randf_range(4.0, 4.9), "z": rng.randf_range(-3.5, 0.5), "v": rng.randf_range(0.8, 1.4), "p": rng.randf() * 6.0, "bob": rng.randf_range(0.08, 0.2)})
	# 其他蝴蝶：花台附近
	for sp in [[Vector3(0.1, 0.9, -3.8), "bflyL_b"], [Vector3(-3.6, 0.8, 1.6), "bflyL_o"], [Vector3(-4.7, 0.9, -5.4), "bflyL_y"], [Vector3(10.0, 1.0, 0.6), "bflyL_b"]]:
		var p: Vector3 = sp[0]
		var s2 := sprite(sp[1], p, {"fps": 9.0, "shadow": false, "center": true, "tilt": true, "flat_lit": 0.6, "glow_all": 0.35, "layer": 256})
		flyers.append({"n": s2, "kind": "bfly", "c": p, "p": rng.randf() * 20.0})
	# 光塵（光池裡）
	particles(HERO + Vector3(-0.6, 1.5, -1.0), Vector3(1.6, 1.2, 2.2), 30, "mote", {"dir": Vector3(1, 0.3, 0), "spread": 180.0, "v0": 0.03, "v1": 0.12, "gravity": Vector3(0.03, 0.01, 0), "turb": 0.4, "life": 8.0, "glow": 0.0, "size_px": 1.0})

func build_sky() -> void:
	if has("--top"): return
	# 天空背板：掛在鏡頭前最遠處的四邊形（黃昏漸層、雲、遠山剪影；只在畫面最上緣露出一條）
	var d := 300.0
	var hh := d * tan(deg_to_rad(FOV * 0.5)) * 1.1
	var q := QuadMesh.new()
	q.size = Vector2(hh * 2.0 * 16.0 / 9.0, hh * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/skytex.gdshader")
	m.set_shader_parameter("band", argf("skyband", 0.17))
	# 遠景屋頂剪影兩層（像素畫，掛在鏡頭前固定深度；3 px 一點陣）：遠的淡、近的暗，屋脊有背光亮邊
	# 最遠：秋山瀑布（使用者照片當參考、codex 重畫；art/build_bg_falls.py）。預設關閉，--falls 開啟
	var sky_layers := [["skyline_b", 110.0, argf("sb", 300.0), 3.0, 0.0], ["skyline_a", 80.0, argf("sa", 400.0), 3.0, 37.0]]
	if has("--falls") and FileAccess.file_exists("res://tex/pilot_bg_falls.png"): sky_layers[0] = ["pilot_bg_falls", 110.0, argf("sf", 275.0), 3.0, argf("fx", -92.0)]      # 取代遠方屋頂那層
	for ly in sky_layers:
		var ld: float = ly[1]
		var lh := ld * tan(deg_to_rad(FOV * 0.5))
		var tp := px_size(ly[0])
		var wpt: float = ly[3] * 2.0 * lh / 1080.0      # 一點陣的世界大小
		var lq := QuadMesh.new(); lq.size = tp * wpt
		var lm := MeshInstance3D.new(); lm.mesh = lq
		lm.material_override = mat(ly[0], {"lit": 0.0, "glow_all": 1.0})
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lm.layers = 512
		cam.add_child(lm)
		sky_nodes.append(lm)
		var bottom_y: float = (1.0 - 2.0 * ly[2] / 1080.0) * lh
		lm.position = Vector3(ly[4] * wpt, bottom_y + tp.y * wpt * 0.5, -ld)
		hide_in_mask.append(lm)
	mi.material_override = m
	sky_mat = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 512
	cam.add_child(mi)
	mi.position = Vector3(0, 0, -d)
	hide_in_mask.append(mi)

func build_post() -> void:
	if has("--top") or has("--mask"): return
	# 前景失焦的楓葉框景（左上、左下、右下角）
	if not has("--no-frame"):
		var sh: Shader = load("res://shaders/frame.gdshader")
		for f in [["frame_tl", Vector4(-0.86, 0.76, 0.22, 0.3), 0.0], ["frame_bl", Vector4(-0.84, -0.78, 0.24, 0.3), 2.0], ["frame_br", Vector4(0.88, -0.84, 0.18, 0.24), 4.0]]:
			var fq := MeshInstance3D.new()
			var qm := QuadMesh.new(); qm.size = Vector2(2, 2)
			fq.mesh = qm
			var fm := ShaderMaterial.new(); fm.shader = sh
			fm.set_shader_parameter("tex", tex(f[0]))
			fm.set_shader_parameter("rect", f[1])
			fm.set_shader_parameter("phase", f[2])
			fm.set_shader_parameter("tint", Color(0.78, 0.5, 0.5, 1.0))
			fm.render_priority = 3
			fq.material_override = fm
			fq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fq.layers = 512
			fq.extra_cull_margin = 16384.0
			cam.add_child(fq)
			fq.position = Vector3(0, 0, -1.0)
			frame_nodes.append([fq, fm])
	# 暗角
	var layer := CanvasLayer.new()
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/vignette.gdshader")
	m.set_shader_parameter("strength", 0.56)
	r.material = m
	layer.add_child(r)
	add_child(layer)

func set_mask() -> void:
	RenderingServer.global_shader_parameter_set("mask_mode", 1.0)
	for n in hide_in_mask: n.visible = false
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = false
	env.background_color = Color.BLACK
	for c in get_children():
		if c is Light3D: c.visible = false
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED

func move_sprite(n: MeshInstance3D, p: Vector3) -> void:
	n.position = p
	if n.has_meta("shadow"):
		var sh: MeshInstance3D = n.get_meta("shadow")
		sh.position = p + Vector3(sun_dir.x, 0, sun_dir.z) * 0.08
		sh.scale = n.scale

func _process(dt: float) -> void:
	t += dt
	frames_n += 1
	# pilot：截圖模式下，視窗被別的視窗蓋住時引擎會跳過算繪（frame_post_draw 永遠不來，截圖卡住）→ 這種時候自己強制畫一格。只影響 --shots，畫面內容不變。
	if has("--shots") and not DisplayServer.window_can_draw(): RenderingServer.force_draw(true, dt)
	if has("--fps") and int(t) != int(t - dt): print("fps=", Engine.get_frames_per_second(), " window=", DisplayServer.window_get_size(), " mode=", DisplayServer.window_get_mode())
	if not has("--shots") or arg_s("walk") != "" or has("--tour"):
		play_update(dt)
	sync_mirrors()
	var px := 1.0 / PPM
	for f in flyers:
		var n: MeshInstance3D = f.n
		match f.kind:
			"float":
				n.position.x += f.v * dt
				if n.position.x > f.get("x1", 11.5): n.position.x = f.get("x0", -11.5)
			"bird":
				var u := fmod(f.x0 + t * f.v + 4.0, 30.0)
				n.position = Vector3(13.0 - u, f.y + sin(t * 1.1 + f.p) * f.bob, f.z)
				n.scale.x = -1.0
			"gull":
				var a: float = t * f.v + f.p
				n.position = f.c + Vector3(cos(a) * f.r, sin(a * 2.3) * 0.25, sin(a) * f.r * 0.4)
				n.scale.x = -1.0 if sin(a) > 0.0 else 1.0
			"bfly":
				var c: Vector3 = f.c
				var p: float = f.p
				var x := sin(t * 0.7 + p) * 0.5 + sin(t * 1.9 + p * 2.0) * 0.2
				var y := sin(t * 1.3 + p * 1.7) * 0.2 + sin(t * 3.1 + p) * 0.07
				var z := cos(t * 0.5 + p) * 0.3
				var np := c + Vector3(x, y, z)
				n.scale.x = 1.0 if np.x >= n.position.x else -1.0
				n.position = Vector3(snappedf(np.x, px), snappedf(np.y, px), np.z)
	if wheel_pivot: wheel_pivot.rotation.z = t * 0.55
	if lh_beam: lh_beam.rotation.y = t * 0.7
	if boat:      # 小船隨水起伏、輕輕搖晃
		boat.position.y = WATER_Y - 0.1 + snappedf(sin(t * 1.37) * 1.5 * px, px)
		boat.rotation.x = sin(t * 0.9) * 0.018
		boat.rotation.z = sin(t * 0.63 + 1.0) * 0.02
	for fl in flickers:
		var l: OmniLight3D = fl.l
		l.light_energy = fl.e * (1.0 + fl.a * (sin(t * 9.0 + fl.p) * 0.6 + sin(t * 23.0 + fl.p * 3.0) * 0.4))
	for e in leaf_emitters:
		var pm: ParticleProcessMaterial = e.process_material
		var gs := gust(t, e.position.x)
		pm.gravity = Vector3(0.15 + 0.9 * gs, -0.42, 0.1 + 0.6 * gs)
	if hero_m:      # 與原本 shader 相同的節奏：眨眼 = fract(t·0.3+0.4) < 0.15，下沉 = fract(t·0.25) ≥ 0.5
		if not hero_walking and walk_dir == "front": hero_m.set_shader_parameter("frame_fixed", (1.0 if fposmod(t * 0.3 + 0.4, 1.0) < 0.15 else 0.0) + (2.0 if fposmod(t * 0.25, 1.0) >= 0.5 else 0.0))
	if fisher_m:      # 與原本 shader 的 lift_x 相同的節奏：平常 0/1 點陣輕晃；每 7 秒有魚咬餌 → 0/2 連續抖動 → 提竿 3 點陣
		var tug := fposmod(t / 7.0, 1.0)
		var lf := 1.0 if fposmod(t * 0.6, 1.0) >= 0.5 else 0.0
		if tug > 0.7 and tug < 0.84: lf = floorf(fposmod(t * 5.0, 1.0) * 2.0) * 2.0
		elif tug >= 0.84 and tug < 0.97: lf = 3.0
		fisher_m.set_shader_parameter("frame_fixed", lf)
	# 事件一：遞麵包（週期 6 秒）：店員 抱著 → 遞出一半 → 伸直遞出（停 2 秒）→ 收回；小孩 抬頭看 → 伸手 → 舉高去接（停）→ 放下
	var ph := fmod(t, 6.0)
	var bf := 0.0; var cf := 0.0
	if ph >= 1.5 and ph < 2.3: bf = 1.0
	elif ph >= 2.3 and ph < 4.4: bf = 2.0
	elif ph >= 4.4 and ph < 4.9: bf = 1.0
	if ph >= 1.7 and ph < 2.4: cf = 1.0
	elif ph >= 2.4 and ph < 4.5: cf = 2.0
	elif ph >= 4.5 and ph < 5.0: cf = 1.0
	if baker_m: baker_m.set_shader_parameter("frame_fixed", bf)
	if child_m: child_m.set_shader_parameter("frame_fixed", cf)
	# 動作幅度加大：店員遞出時整個人往小孩那邊探（1 → 3 點陣）；小孩伸手時踮腳小跳（2 點陣）
	if baker_n: move_sprite(baker_n, BAKER + Vector3(-px * (3.0 if bf == 2.0 else bf), 0, 0))
	if child_n: move_sprite(child_n, CHILD + Vector3(px * cf * 0.5, px * 2.0 * (1.0 if cf == 2.0 and fmod(t, 0.5) < 0.25 else 0.0), 0))
	# 事件二：貓追蝴蝶。蝴蝶沿 8 字形飛，貓落後一小段追著跑，接近時撲跳
	if cat_n:
		var w := 0.83
		var bp := bfly_path(t)
		var cp := bfly_path(t - 0.55)
		var vel := (bfly_path(t - 0.5) - bfly_path(t - 0.6)) / 0.1
		var hop := maxf(0.0, sin(t * 2.9)) * maxf(0.0, sin(t * 0.47)) * 0.22
		cat_n.scale.x = 1.0 if vel.x >= 0.0 else -1.0
		move_sprite(cat_n, Vector3(snappedf(cp.x, px), snappedf(hop, px), cp.z))
		var spd := Vector2(vel.x, vel.z).length()
		cat_m.set_shader_parameter("frame_fixed", float(int(t * (5.0 + spd * 4.0)) % 4) if hop < 0.03 else 0.0)
		bfly_n.position = Vector3(snappedf(bp.x, px), snappedf(0.42 + sin(t * 3.3) * 0.1 + sin(t * 7.1) * 0.04, px), bp.z)
		bfly_n.scale.x = 1.0 if vel.x >= 0.0 else -1.0
	if ground_mat:
		var hp0: Vector3 = hero_n.position if hero_n else HERO
		var bl: Array = [Vector4(hp0.x, hp0.z, 0.36, 0.2), Vector4(BAKER.x, BAKER.z, 0.34, 0.2), Vector4(CHILD.x, CHILD.z, 0.32, 0.18)]
		if cat_n: bl.append(Vector4(cat_n.position.x, cat_n.position.z, 0.36, 0.15))
		while bl.size() < 8: bl.append(Vector4(0, 0, 0, 0))
		ground_mat.set_shader_parameter("blobs", bl)

func bfly_path(tt: float) -> Vector3:
	return CAT_C + Vector3(sin(tt * 0.83) * 2.3, 0, sin(tt * 1.66 + 0.6) * 0.75)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_tree().quit()

# ------------------------------------------------------------------ 截圖模式
func grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func screen_rect(p: Vector3, w: float, h: float) -> Rect2i:
	var a := cam.unproject_position(p + Vector3(-w * 0.5, 0, 0))
	var b := cam.unproject_position(p + Vector3(w * 0.5, 0, 0))
	var hh := (b.x - a.x) / w * h
	return Rect2i(int(a.x), int(a.y - hh), int(b.x - a.x), int(hh))

func run_shots() -> void:
	if has("--tour"):
		await get_tree().create_timer(2.0).timeout
		await run_tour()
		return
	var tag := ""
	for a in args:
		if a.begins_with("--tag="): tag = a.substr(6)
	var dir := ProjectSettings.globalize_path("res://").path_join("../shots/godot_pilot").simplify_path()
	for a in args:
		if a.begins_with("--out="): dir = dir.path_join(a.substr(6))
	if has("--work"): dir = ProjectSettings.globalize_path("res://tools/work")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(argf("wait", 3.0)).timeout
	var f0 := frames_n
	await get_tree().create_timer(1.0).timeout
	print("fps(1s)=", frames_n - f0)
	if has("--spec"): print_spec()
	if tag != "":
		var im: Image = await grab()
		im.save_png(dir.path_join("compare_%s.png" % tag))
		print("saved compare_", tag, " ", im.get_size())
		print("done")
		get_tree().quit()
		return
	var rh := screen_rect(HERO, 1.2, 1.5)
	var re := screen_rect((BAKER + CHILD) * 0.5, 2.2, 1.5)
	var rc := screen_rect(CAT_C + Vector3(0, 0, 0.8), 6.6, 2.6)
	print("R:hero=%d,%d,%d,%d R:event=%d,%d,%d,%d R:cat=%d,%d,%d,%d" % [rh.position.x, rh.position.y, rh.size.x, rh.size.y, re.position.x, re.position.y, re.size.x, re.size.y, rc.position.x, rc.position.y, rc.size.x, rc.size.y])
	for i in 3:
		var img: Image = await grab()
		img.save_png(dir.path_join("full_%d.png" % (i + 1)))
		print("saved full_", i + 1, " ", img.get_size(), " t=", snappedf(t, 0.01), " cat=", cam.unproject_position(cat_n.position))
		if i == 2:
			var hp := cam.unproject_position(HERO + Vector3(0, 0.7, 0))
			img.get_region(Rect2i(clampi(int(hp.x) - 420, 0, 960), clampi(int(hp.y) - 330, 0, 540), 960, 540)).save_png(dir.path_join("closeup_hero_lightpool.png"))
			var bp := cam.unproject_position(BAKER + Vector3(-0.4, 0.7, 0))
			img.get_region(Rect2i(clampi(int(bp.x) - 480, 0, 960), clampi(int(bp.y) - 300, 0, 540), 960, 540)).save_png(dir.path_join("closeup_bakery_event.png"))
			img.get_region(Rect2i(0, 540, 960, 540)).save_png(dir.path_join("closeup_quay_boat.png"))
		else:
			await get_tree().create_timer(2.0).timeout
	print("done")
	get_tree().quit()


# 量測（pilot）：各表面 1 點陣（1/32 m）在螢幕上佔幾個像素。 ./shoot.sh --out=xx --tag=spec --spec
func spec_at(label: String, p: Vector3, du: Vector3, dv: Vector3) -> void:
	var o := cam.unproject_position(p)
	var a := (cam.unproject_position(p + du) - o).length() / 32.0
	var b := (cam.unproject_position(p + dv) - o).length() / 32.0
	var depth := (p - cam_pos).dot(cam_fwd)
	print("SPEC %s screen=(%d,%d) depth=%.2f texel_u=%.3f texel_v=%.3f" % [label, o.x, o.y, depth, a, b])

func print_spec() -> void:
	print("SPEC K_PX=", K_PX, " depth0=", depth0, " cam_pos=", cam_pos)
	spec_at("hero_sprite", HERO + cam_up * 0.7, Vector3(1, 0, 0), cam_up)
	if pilot("hero"):      # 新主角 42.67 PPM：1 點陣 = 0.75/32 m
		var o := cam.unproject_position(HERO + cam_up * 0.7)
		print("SPEC hero_pilot texel_u=%.3f texel_v=%.3f" % [(cam.unproject_position(HERO + cam_up * 0.7 + Vector3(1, 0, 0)) - o).length() / 32.0 * 0.75, (cam.unproject_position(HERO + cam_up * 1.7) - o).length() / 32.0 * 0.75])
	for pp in [Vector3(5.3, 0, -0.2), Vector3(7.6, 0, 1.6), Vector3(1.0, 0, -3.45), Vector3(2.0, 0, 1.7)]:
		print("SPEC puddle ", pp, " -> ", cam.unproject_position(pp))
	spec_at("ground_at_hero", HERO, Vector3(1, 0, 0), Vector3(0, 0, 1))
	spec_at("ground_far_z-4", Vector3(-1.5, 0, -4.0), Vector3(1, 0, 0), Vector3(0, 0, 1))
	spec_at("ground_near_z2", Vector3(-1.5, 0, 2.0), Vector3(1, 0, 0), Vector3(0, 0, 1))
	spec_at("wallB_brick", Vector3(1.4, 1.0, -4.6), Vector3(1, 0, 0), Vector3(0, 1, 0))
	spec_at("wallB_plaster", Vector3(1.4, 2.3, -4.53), Vector3(1, 0, 0), Vector3(0, 1, 0))
	var sl := Vector3(0, 1.5, -1.95).normalized()
	spec_at("bakery_roof_mid", Vector3(7.35, 2.75, -5.275), Vector3(1, 0, 0), sl)
	for c in [Vector3(-0.77, 0, -4.53), Vector3(3.57, 0, -4.53), Vector3(-0.77, 4.6, -4.53), Vector3(1.4, 4.6, -4.53), Vector3(4.25, 1.808, -4.05), Vector3(10.45, 1.808, -4.05), Vector3(4.25, 3.5, -6.25), Vector3(10.45, 3.5, -6.25), Vector3(-16, 0, BACK_Z), Vector3(16, 0, BACK_Z), Vector3(-12, 0, QUAY_Z), Vector3(12, 0, QUAY_Z)]:
		print("SPEC corner ", c, " -> ", cam.unproject_position(c))

# ------------------------------------------------------------------ 簡易操作（只在非截圖模式）：WASD／方向鍵走動，Shift 跑
# 走路格：tex/pilot_hero_walk_{front,side,back}.png（各 4 格，art/build_walk.py）；側面圖朝左，往右走時水平翻轉。
# 格數依「走過的距離」推進（不是時間），腳才不會滑。
const HERO_R := 0.22                       # 主角腳下的碰撞半徑
# 碰撞：x/z 平面上的矩形 [x0, z0, x1, z1]（房子、花圃、花台、長椅、桌子）與圓 [x, z, r]（木桶、井、燈柱、人）。數值抄自 build_town／build_props 的擺放
const BLOCK_RECTS := [
	[-12.5, -4.6, -6.6, -0.9],    # A 左側矮屋
	[-0.7, -8.4, 3.5, -4.6],      # B 紅磚兩層樓
	[4.5, -8.2, 10.2, -4.3],      # C 麵包店
	[10.7, -2.6, 15.0, 3.0],      # D 右側屋
	[-6.6, -8.2, -3.7, -4.6],     # 大樹花圃（L 形矮牆＋樹）
	[-0.75, -4.35, 0.75, -3.75], [2.1, -4.35, 3.4, -3.75],     # B 屋前兩座花台
	[9.9, -0.3, 10.5, 1.5],       # 右側屋前花台
	[-4.35, 1.3, -2.85, 1.8], [-9.25, 0.9, -7.95, 1.5],         # 左下花台
	[-6.3, 0.65, -4.9, 1.15],     # 長椅（左）
	[5.1, -3.55, 6.4, -3.05],     # 長椅（麵包店前）
	[6.75, -2.3, 8.25, -1.5],     # 攤位桌
	[3.9, -2.55, 5.1, -1.85],     # 南瓜推車
	[9.6, -4.0, 10.4, -3.2],      # 木箱
	[-4.5, -9.2, -0.7, -8.4],     # 巷底（往後是低一階的地，不能走下去）
]
const BLOCK_CIRCLES := [
	[-6.95, -0.45, 0.3], [-7.55, -0.5, 0.3], [-0.35, -3.5, 0.3], [3.95, -4.0, 0.3], [10.2, -2.75, 0.3], [10.25, 2.0, 0.3],   # 木桶
	[-9.0, -0.75, 0.35], [4.05, -3.3, 0.3], [9.3, -4.1, 0.25],   # 柴堆、小木箱、雜物
	[8.3, 0.1, 0.7],              # 水井
	[7.1, 1.9, 0.15], [-0.95, -4.3, 0.15],                      # 燈柱
	[6.45, -1.75, 0.25], [5.6, -1.7, 0.22],                     # 店員、小孩
]
func blocked(x: float, z: float) -> bool:
	var inside := false
	for a in WALK_AREAS:
		if x >= a[0] and x <= a[2] and z >= a[1] and z <= a[3]: inside = true; break
	if not inside: return true
	for r in zone_rects:
		if x > r[0] - HERO_R and x < r[2] + HERO_R and z > r[1] - HERO_R and z < r[3] + HERO_R: return true
	for c in zone_circles:
		if Vector2(x - c[0], z - c[1]).length() < c[2] + HERO_R: return true
	for r in BLOCK_RECTS:
		if x > r[0] - HERO_R and x < r[2] + HERO_R and z > r[1] - HERO_R and z < r[3] + HERO_R: return true
	for c in BLOCK_CIRCLES:
		if Vector2(x - c[0], z - c[1]).length() < c[2] + HERO_R: return true
	return false
const STRIDE := 0.16                       # 每格走多少公尺
var hero_walking := false
var walk_dist := 0.0
var walk_dir := "front"
var walk_flip := false
var hero_pos := Vector3.INF          # 未取整的位置（畫面上的位置取整到點陣）
func hero_tex(name: String) -> void:
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % name)): name = "pilot_hero_walk_front"
	hero_m.set_shader_parameter("tex", tex(name))
func walk(dt: float) -> void:
	if not hero_n or not hero_m: return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1.0
	if tour_on: v = vin_dir
	match arg_s("walk"):
		"front": v = Vector2(0, 1) if fposmod(t, 4.0) < 2.0 else Vector2(0, -1)
		"side": v = Vector2(-1, 0) if fposmod(t, 4.0) < 2.0 else Vector2(1, 0)
		"back": v = Vector2(0, -1)
		"fl": v = Vector2(-1, 1) if fposmod(t, 4.0) < 2.0 else Vector2(1, 1)
		"bl": v = Vector2(-1, -1)
	var px := 1.0 / 32.0
	if hero_pos == Vector3.INF: hero_pos = hero_n.position
	var p := hero_pos
	if v == Vector2.ZERO:
		if hero_walking:
			hero_walking = false
			# 停下：朝正面的話回到待機（眨眼、呼吸）；朝側面／背面就停在該方向的站姿格
			if walk_dir == "front":
				hero_m.set_shader_parameter("tex", tex("pilot_hero_anim"))
				hero_n.scale.x = absf(hero_n.scale.x)
			else:
				hero_m.set_shader_parameter("frame_fixed", 1.0)
		return
	var spd := 3.2 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.8
	v = v.normalized()
	# 8 方向：斜向（兩軸都有）用 3/4 圖 fl（斜前）／bl（斜後）；圖都朝左，往右時水平翻轉
	var nd := ""
	if absf(v.x) > 0.3 and absf(v.y) > 0.3: nd = "bl" if v.y < 0.0 else "fl"
	elif absf(v.x) > absf(v.y): nd = "side"
	else: nd = "back" if v.y < 0.0 else "front"
	if nd != walk_dir or not hero_walking:
		walk_dir = nd
		hero_tex("pilot_hero_walk_" + nd)
	hero_walking = true
	if nd in ["side", "fl", "bl"]: walk_flip = v.x > 0.0
	hero_n.scale.x = absf(hero_n.scale.x) * (-1.0 if (nd in ["side", "fl", "bl"] and walk_flip) else 1.0)
	var step := v * spd * dt
	# 先試整步，撞到就分軸試（沿牆滑動）
	var nx := p.x + step.x
	var nz := p.z + step.y
	if blocked(nx, nz):
		if not blocked(nx, p.z): nz = p.z
		elif not blocked(p.x, nz): nx = p.x
		else: nx = p.x; nz = p.z
	walk_dist += Vector2(nx - p.x, nz - p.z).length()
	hero_m.set_shader_parameter("frame_fixed", float(int(walk_dist / STRIDE) % 4))
	hero_pos = Vector3(nx, 0.0, nz)
	move_sprite(hero_n, Vector3(snappedf(nx, px), 0.0, snappedf(nz, px)))

# 鏡頭跟隨：鏡頭只平移（角度不變），跟著主角相對起始位置的偏移；限制範圍，免得拍到場景外的空地
const CAM_PAN_X := Vector2(-49.0, 49.0)      # 運河兩端各擴建到 ±60（world 外緣），鏡頭中心最多到約 ±50
const CAM_PAN_Z := Vector2(-3.5, 0.6)
var cam_base := Vector3.INF
var cam_off := Vector3.ZERO
func follow_cam(dt: float) -> void:
	if not hero_n or has("--top"): return
	if cam_base == Vector3.INF: cam_base = cam.global_position
	var hp := hero_pos if hero_pos != Vector3.INF else hero_n.position
	if mode == "sail": hp = Vector3(boat.position.x, 0.0, boat.position.z)
	var zmax := 4.8 if mode == "sail" else CAM_PAN_Z.y      # 開船時鏡頭往前移到船上（景深的焦點跟著船）
	var want := Vector3(clampf(hp.x - HERO.x, STAGES[stage].cam.x, STAGES[stage].cam.y), 0.0, clampf(hp.z - HERO.z, CAM_PAN_Z.x, zmax))
	cam_off = cam_off.lerp(want, 1.0 - exp(-dt * 3.0))
	cam.global_position = cam_base + cam_off
	if water_mat: water_mat.set_shader_parameter("cam_xz", Vector2(cam.global_position.x, cam.global_position.z))

func arg_s(k: String) -> String:
	for a in args:
		if a.begins_with("--%s=" % k): return a.substr(k.length() + 3)
	return ""

# ================================================================== 擴建：運河兩端（西區市集碼頭、東區石階廣場）＋開船
# 房子與道具都重用原本的建造函式；碰撞由各函式在 reg_on 時自動登記到 zone_rects／zone_circles。
const LANE_Z := QUAY_Z + 2.35              # 航道（避開原廣場石階：石階伸到 QUAY_Z+1.6）
const WALK_AREAS := [
	[-12.8, -9.0, 10.6, 1.85],              # 原廣場＋大樹右側的巷子
	[-58.0, -0.7, -12.0, 1.85],             # 西側沿岸步道
	[-50.0, -7.4, -27.0, 1.85],             # 西區市集廣場
	[-40.0, 1.8, -37.0, 3.75],              # 西區木棧橋
	[15.3, -7.4, 58.0, 1.85],               # 東區（D 屋右側起；只能搭船過去）
	[288.2, -7.9, 312.3, 1.85],             # 水車磨坊院子
	[309.1, 1.8, 312.1, 3.75],              # 磨坊棧橋
	[579.5, -1.8, 624.0, 2.0],              # 溪谷：岩台下的步道
	[589.6, 1.8, 592.4, 3.75],              # 溪谷棧橋
	[866.0, -7.4, 903.6, 1.85],             # 漁港
	[903.6, 0.9, 925.5, 2.7],               # 防波堤（通往燈塔）
]
# 碼頭：岸上點、船停的位置
const DOCKS := [
	{"name": "原廣場繫船處", "land": Vector2(-2.2, 1.7), "boat": Vector2(-2.6, QUAY_Z + 1.05)},
	{"name": "原廣場石階", "land": Vector2(5.9, 1.7), "boat": Vector2(5.9, LANE_Z)},
	{"name": "西區棧橋", "land": Vector2(-38.5, 3.5), "boat": Vector2(-38.5, LANE_Z + 0.2)},
	{"name": "東區石階", "land": Vector2(34.0, 1.7), "boat": Vector2(34.0, LANE_Z)},
	{"name": "磨坊碼頭", "land": Vector2(310.6, 3.5), "boat": Vector2(310.6, LANE_Z + 0.2)},
	{"name": "溪谷棧橋", "land": Vector2(591.0, 3.4), "boat": Vector2(591.0, LANE_Z + 0.2)},
	{"name": "漁港石階", "land": Vector2(894.0, 1.7), "boat": Vector2(894.0, LANE_Z)},
]
var zone_rects: Array = []
var zone_circles: Array = []
var zone_streaks: Array = []
var zone_fronts: Array = []
var zone_npcs: Array = []
var zone_ground_mats: Array = []
var reg_on := false
var mode := "walk"                          # walk／sail
var boat_dock := 0
var boat_vel := 0.0
var boat_face := 1.0
var e_pressed := false
var prompt: Label
var tour_on := false
var vin_dir := Vector2.ZERO
var vin_sail := 0.0
var streak_cam_x := INF

func build_zones() -> void:
	rng.seed = 4242
	parent_node = self
	# 地面：原廣場網格只到 x ±16，兩側補上平鋪石板（色調接近廣場）
	for xr in [[-62.0, -16.0], [16.0, 62.0]]:
		var g := geo("cobble")
		g.quad(Vector3(xr[0], 0, QUAY_Z), Vector3(xr[1], 0, QUAY_Z), Vector3(xr[1], 0, BACK_Z), Vector3(xr[0], 0, BACK_Z))
		put(g, "cobble", {"tint": Color(0.92, 0.84, 0.86)}, false)
		# 新區專屬地面（codex 分塊拼成，art/build_zone_ground.py）：z −7.6..2.4，蓋在平鋪石板上
		var zt := "pilot_zone_" + ("w" if xr[0] < 0.0 else "e")
		if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % zt)):
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var zx0: float = xr[0]; var zx1: float = xr[1]
			for c in [Vector3(zx0, 0.004, QUAY_Z), Vector3(zx0, 0.004, -7.6), Vector3(zx1, 0.004, -7.6), Vector3(zx0, 0.004, QUAY_Z), Vector3(zx1, 0.004, -7.6), Vector3(zx1, 0.004, QUAY_Z)]:
				st.set_normal(Vector3.UP); st.set_uv(Vector2((c.x - zx0) / (zx1 - zx0), (c.z + 7.6) / (QUAY_Z + 7.6))); st.add_vertex(c)
			var gmi := MeshInstance3D.new(); gmi.mesh = st.commit()
			var zm := ShaderMaterial.new(); zm.shader = load("res://shaders/plaza.gdshader")
			zm.set_shader_parameter("tex", tex(zt))
			zm.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
			var pud: Array = []
			for i in 4: pud.append(Vector4(rng.randf_range(zx0 + 4.0, zx1 - 4.0), rng.randf_range(-2.0, 1.5), rng.randf_range(0.45, 0.7), rng.randf_range(0.2, 0.32)))
			while pud.size() < 8: pud.append(Vector4(0, 0, 0, 0))
			zm.set_shader_parameter("puddles", pud)
			var lamps: Array = []
			for lx in ([-42.0, -33.0, -24.0, -15.0] if xr[0] < 0.0 else [24.0, 31.0, 40.0, 49.0]): lamps.append(Vector3(lx, 1.9, 0.9))
			zm.set_shader_parameter("lamps", lamps)
			zm.set_shader_parameter("sky_col", ground_mat.get_shader_parameter("sky_col") if ground_mat else Color(0.3, 0.26, 0.5))
			var bl: Array = []
			while bl.size() < 8: bl.append(Vector4(0, 0, 0, 0))
			zm.set_shader_parameter("blobs", bl)
			gmi.material_override = zm
			gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(gmi)
			zone_ground_mats.append(zm)
		var gq := geo("quaywall")
		gq.quad(Vector3(xr[0], WATER_Y - 0.3, QUAY_Z), Vector3(xr[1], WATER_Y - 0.3, QUAY_Z), Vector3(xr[1], 0, QUAY_Z), Vector3(xr[0], 0, QUAY_Z))
		put(gq, "quaywall", {"tint": Color(1.0, 1.04, 1.12)})
		var gr := geo("stonewall")
		gr.quad(Vector3(xr[1], LOW_Y, BACK_Z), Vector3(xr[0], LOW_Y, BACK_Z), Vector3(xr[0], 0, BACK_Z), Vector3(xr[1], 0, BACK_Z))
		put(gr, "stonewall", {"tint": Color(0.8, 0.75, 0.9)}, false)
	# 原廣場左右兩段堤岸牆（原本只到 ±12）
	for xr in [[-16.0, -12.0], [12.0, 16.0]]:
		var gq2 := geo("quaywall")
		gq2.quad(Vector3(xr[0], WATER_Y - 0.3, QUAY_Z), Vector3(xr[1], WATER_Y - 0.3, QUAY_Z), Vector3(xr[1], 0, QUAY_Z), Vector3(xr[0], 0, QUAY_Z))
		put(gq2, "quaywall", {"tint": Color(1.0, 1.04, 1.12)})
	# 運河兩端的水門（石牆橫過水面，封住世界邊緣）
	for ex in [-60.5]:
		var gw := geo("w_stone")
		gw.box(Vector3(ex, WATER_Y - 0.3, QUAY_Z + 6.0), Vector3(1.0, 2.6, 12.0))
		put(gw, "w_stone", {"tint": Color(0.95, 0.9, 1.0)})
	reg_on = true
	var W := 0.62
	var roofs := ["w_roof_red2", "w_roof_slate2", "w_roof_red2"]
	var walls := ["plaster2", "brick", "stonewall", "plaster"]
	var wins := ["w_win_a", "w_win_a2", "w_win_b", "w_win_b2", "w_win_c", "w_win_d", "windows_0", "windows_1", "windows_3"]
	var doors := ["w_door_a", "w_door_b", "doors_0", "doors_1", "doors_2"]
	var mk := func(x0: float, x1: float, zb: float, zf: float, hgt: float, ridge: String, lights: bool) -> void:
		var w := x1 - x0
		var items := [[doors[rng.randi() % doors.size()], "f", rng.randf_range(-w * 0.3, w * 0.3), 0.3, 0.0]]
		for k in int(w / 1.6):
			var ox := -w * 0.5 + 0.9 + k * 1.6
			if absf(ox - items[0][2]) > 0.8: items.append([wins[rng.randi() % wins.size()], "f", ox, 0.55, W if (lights and rng.randf() < 0.5) else 0.0])
			if hgt > 2.4: items.append([wins[rng.randi() % wins.size()], "f", ox, hgt - 0.9, W if (lights and rng.randf() < 0.4) else 0.0])
		var rh := rng.randf_range(1.3, 1.6)
		var chx := rng.randf_range(-1.0, 1.0)
		zone_fronts.append({"x0": x0, "x1": x1, "zf": zf, "h": hgt, "chim": Vector3((x0 + x1) * 0.5 + chx, hgt + rh * 0.7 + 0.62, (zb + zf) * 0.5 - 0.5)})
		house({"x0": x0, "x1": x1, "zb": zb, "zf": zf, "h": hgt, "rh": rh, "ridge": ridge,
			"tint": Color(rng.randf_range(0.9, 1.0), rng.randf_range(0.82, 0.92), rng.randf_range(0.74, 0.86)),
			"wall": walls[rng.randi() % walls.size()], "roof": roofs[rng.randi() % roofs.size()],
			"roof_tint": Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.82, 0.98), rng.randf_range(0.85, 1.1)),
			"chimney": Vector2(chx, -0.5), "lights": lights, "items": items})
	var maples := ["maple_0", "maple_1", "maple_2", "maple_3", "maple_4", "maple_5"]
	# ---------------- 西側連接段＋西區「市集碼頭」
	mk.call(-26.0, -20.5, -4.8, -1.0, 2.2, "x", true)
	mk.call(-19.5, -16.6, -5.0, -1.1, 2.8, "z", false)
	mk.call(-31.5, -27.0, -8.6, -7.6, 3.0, "z", true)
	mk.call(-39.0, -32.5, -8.4, -7.6, 2.2, "x", true)
	mk.call(-46.5, -40.5, -8.6, -7.6, 2.8, "x", false)
	mk.call(-58.5, -51.0, -4.8, -0.9, 2.4, "x", true)
	mk.call(-50.5, -47.0, -8.6, -5.0, 2.6, "z", false)
	# 市集攤位：桌子（布）＋貨物、推車、木箱、木桶
	for st in [[-44.0, -3.0], [-40.5, -3.4], [-35.5, -3.0], [-31.5, -3.2]]:
		var gt := geo("cloth")
		gt.box(Vector3(st[0], 0, st[1]), Vector3(1.5, 0.55, 0.75))
		put(gt, "cloth", {"tint": Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.8, 1.0), rng.randf_range(0.8, 1.1))})
		zone_rects.append([st[0] - 0.75, st[1] - 0.38, st[0] + 0.75, st[1] + 0.38])
		sprite(["street2_3", "w_props7_3"][rng.randi() % 2], Vector3(st[0] - 0.35, 0.5, st[1]), {"flat_lit": 0.3, "shadow_off": 0.02})
		sprite(["street2_3", "w_props7_3"][rng.randi() % 2], Vector3(st[0] + 0.4, 0.5, st[1]), {"flat_lit": 0.3, "shadow_off": 0.02})
		crate(Vector3(st[0] + 1.1, 0, st[1] - 0.6), 0.5, rng.randf_range(-20, 20))
	sprite("w_cart", Vector3(-46.8, 0, -1.0), {"flat_lit": 0.3, "tilt": true})
	zone_rects.append([-47.4, -1.35, -46.2, -0.65])
	for b in [[-29.5, -5.2], [-30.1, -5.0], [-48.3, -4.4], [-37.0, -6.6]]: barrel(Vector3(b[0], 0, b[1]))
	bench(Vector3(-33.5, 0, 0.9), 0.0)
	bench(Vector3(-23.0, 0, 0.9), 0.0)
	planter(Vector3(-27.5, 0, 1.5), 1.4, 0.5, ["flowers_0", "flowers_4", "flowers_2"], 0.28)
	planter(Vector3(-52.5, 0, 1.4), 1.4, 0.5, ["flowers_3", "flowers_1", "bushes_2"], 0.3)
	tree(Vector3(-28.6, 0, -6.2), maples, 40, Vector3(1.9, 1.0, 1.6), 2.8, 0.0)
	for lp in [-42.0, -33.0, -24.0, -15.0]: lamp_post(Vector3(lp, 0, 1.9))
	wall_lantern(Vector3(-36.0, 0.9, -7.58), 0.0, 0.7)
	wall_lantern(Vector3(-43.0, 0.9, -7.58), 0.0, 0.7)
	# 西區木棧橋（從堤岸往運河伸出去）
	# 一塊塊木板（MengTo 3d-wood-material 的原則：每塊板子自己的紋路與色調、板縫、錯開的接縫、底下有暗的托梁）
	var gp := geo("wood")
	for px in [-39.8, -37.2]:
		for pz in [QUAY_Z + 0.2, QUAY_Z + 1.3]:
			gp.box(Vector3(px, WATER_Y - 0.4, pz), Vector3(0.18, 1.3, 0.18))
	for pz in [QUAY_Z + 0.12, QUAY_Z + 1.36]:
		gp.box(Vector3(-38.5, -0.2, pz), Vector3(3.0, 0.12, 0.1))          # 橫向托梁（從前面看得到木板下的暗邊）
	put(gp, "wood", {"tint": Color(0.55, 0.45, 0.42)})
	var gk := geo("pilot_planks")
	var prng := RandomNumberGenerator.new(); prng.seed = 4411
	for bi in 6:
		var bz: float = QUAY_Z + 0.075 + 0.25 * bi + 0.125
		var cut: float = prng.randf_range(-39.3, -37.7)                     # 接縫錯開
		for seg in [[-40.0, cut - 0.01], [cut + 0.01, -37.0]]:
			var x0: float = seg[0]; var x1: float = seg[1]
			gk.uo = Vector2(prng.randf(), float(prng.randi_range(0, 7)) * 0.125)
			gk.box(Vector3((x0 + x1) * 0.5, -0.07 + prng.randf_range(-0.01, 0.01), bz), Vector3(x1 - x0, 0.07, 0.245), false, 1 | 16)
	put(gk, "pilot_planks", {"tint": Color(0.8, 0.72, 0.7), "rough": 0.9})
	# ---------------- 東區「石階廣場」（D 屋右側；只能搭船到）
	mk.call(16.0, 21.0, -4.8, -1.0, 2.4, "x", true)
	mk.call(22.5, 27.0, -8.6, -7.6, 3.0, "z", true)
	mk.call(28.5, 35.0, -8.4, -7.6, 2.2, "x", true)
	mk.call(36.5, 41.5, -8.6, -7.6, 2.8, "z", false)
	mk.call(43.0, 49.5, -8.4, -7.6, 2.4, "x", true)
	mk.call(51.0, 58.5, -4.8, -0.9, 2.6, "x", true)
	well(Vector3(37.5, 0, -2.8))
	planter(Vector3(30.0, 0, -4.2), 1.5, 0.6, ["flowers_0", "flowers_1", "flowers_4", "flowers_5"])
	planter(Vector3(44.5, 0, -4.2), 1.5, 0.6, ["flowers_2", "flowers_3", "flowers_0"])
	bench(Vector3(26.0, 0, 0.9), 0.0)
	bench(Vector3(42.0, 0, 0.9), 0.0)
	tree(Vector3(47.5, 0, -6.0), maples, 40, Vector3(1.9, 1.0, 1.6), 2.8, 0.0)
	for b in [[21.8, -3.6], [22.4, -3.4], [50.3, -3.8]]: barrel(Vector3(b[0], 0, b[1]))
	for lp in [24.0, 29.2, 40.0, 49.0]: lamp_post(Vector3(lp, 0, 1.9))
	# 東區的用途：運河邊「停留＋地標」——水邊一棵大紅楓（使用者照片的意象）、井邊有燈、手推花車與木箱讓中段有人氣
	tree_tint = Color(1.12, 0.62, 0.66)
	tree(Vector3(31.6, 0, 0.9), maples, 52, Vector3(2.3, 1.1, 1.5), 3.1, 0.0)
	tree_tint = Color(1, 1, 1)
	var gr := geo("w_stone")      # 樹下一圈矮石（樹根處的石砌樹圍）
	for k in 10:
		var a := TAU * k / 10.0
		gr.box(Vector3(31.6 + cos(a) * 0.62, 0, 0.9 + sin(a) * 0.42), Vector3(0.34, 0.16 + 0.05 * (k % 3), 0.22))
	put(gr, "w_stone", {"tint": Color(1.0, 0.95, 1.05)})
	zone_circles.append([31.6, 0.9, 0.7])
	lamp_post(Vector3(39.3, 0, -1.9))      # 井邊的燈（原本井邊那盞光沒有光源）
	sprite("w_cart", Vector3(45.6, 0, -2.0), {"flat_lit": 0.3, "tilt": true})
	zone_rects.append([45.0, -2.35, 46.2, -1.65])
	crate(Vector3(46.7, 0, -2.6), 0.5, 12.0); crate(Vector3(23.6, 0, -6.9), 0.55, -8.0); crate(Vector3(24.2, 0, -7.0), 0.45, 20.0)
	# 東區石階（同原廣場的做法）
	var gs := geo("w_stone")
	for i in 5:
		gs.box(Vector3(34.0, WATER_Y - 0.3, QUAY_Z + 0.16 + i * 0.32), Vector3(2.0, 1.25 - 0.2 * (i + 1), 0.32))
	put(gs, "w_stone", {"tint": Color(1.1, 1.05, 1.15)})
	reg_on = false
	# 後排（低一階）的房子，讓屋頂後面還有層次
	for xs in [[-30.0, -25.0], [-44.0, -38.0], [-56.0, -50.0], [20.0, 25.5], [33.0, 38.0], [46.0, 52.0]]:
		house_at({"x0": xs[0], "x1": xs[1], "zb": -13.5, "zf": -9.9, "h": 3.4, "rh": 1.5, "ridge": "z", "tint": Color(0.92, 0.86, 0.82), "roof": roofs[rng.randi() % roofs.size()], "roof_tint": Color(0.9, 0.85, 0.95), "cast": false, "lights": false,
			"items": [[wins[rng.randi() % wins.size()], "f", 0.0, 2.6, W]]}, LOW_Y)
	parent_node = self
	dress_zones()
	# 新區 NPC（codex 生成＋還原，art/build_zone_npc.py）：[貼圖, 位置, scale, 每格秒數]
	for npc in [["pilot_npc_veg_anim", Vector3(-42.2, 0, -2.5), 0.886, 0.9], ["pilot_npc_girl_anim", Vector3(-36.3, 0, -2.25), 0.78, 1.1], ["pilot_npc_accordion_anim", Vector3(35.6, 0, -1.7), 0.8, 0.35], ["pilot_npc_painter_anim", Vector3(42.4, 0, -1.4), 0.8, 1.0]]:
		var nn := sprite(npc[0], npc[1], {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0, "scale": npc[2]})
		zone_npcs.append({"m": nn.material_override, "n": int(meta.get(npc[0] + "_frames", 1)), "dt": npc[3]})
		zone_circles.append([npc[1].x, npc[1].z, 0.25])
	# 提示文字
	if not has("--shots") or has("--tour"):
		var cl := CanvasLayer.new(); add_child(cl)
		prompt = Label.new()
		prompt.add_theme_font_size_override("font_size", 30)
		prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
		prompt.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.1))
		prompt.add_theme_constant_override("outline_size", 8)
		prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prompt.anchor_left = 0.0; prompt.anchor_right = 1.0; prompt.anchor_top = 0.92; prompt.anchor_bottom = 0.98
		cl.add_child(prompt)

func play_update(dt: float) -> void:
	if tour_on: tour_step(dt)
	if tun_on:
		tunnel_update(dt)
		route_update(dt)
		update_water()
		return
	if mode == "walk":
		walk(dt)
		var d: Dictionary = DOCKS[boat_dock]
		var hp := hero_pos if hero_pos != Vector3.INF else hero_n.position
		var near := Vector2(hp.x, hp.z).distance_to(d.land) < 1.6
		set_prompt("E 上船" if near else "")
		if near and e_pressed: board()
	else:
		sail(dt)
	e_pressed = false
	for z in zone_npcs:
		var fi: int = int(t / z.dt) % int(z.n)
		if int(z.n) == 3: fi = [0, 1, 0, 2][int(t / z.dt) % 4]      # 老爺爺：中、左、中、右
		z.m.set_shader_parameter("frame_fixed", float(fi))
	if zone_ground_mats.size() > 0:
		var hp2 := hero_pos if hero_pos != Vector3.INF else hero_n.position
		var bl: Array = [Vector4(hp2.x, hp2.z, 0.36, 0.2) if mode == "walk" else Vector4(0, 0, 0, 0), Vector4(-42.2, -2.5, 0.36, 0.2), Vector4(-36.3, -2.25, 0.3, 0.17), Vector4(35.6, -1.7, 0.4, 0.2), Vector4(42.4, -1.4, 0.4, 0.2)]
		while bl.size() < 8: bl.append(Vector4(0, 0, 0, 0))
		for zm in zone_ground_mats: zm.set_shader_parameter("blobs", bl)
	route_update(dt)
	follow_cam(dt)
	update_water()

func set_prompt(s: String) -> void:
	if prompt and prompt.text != s: prompt.text = s

func board() -> void:
	mode = "sail"
	boat_vel = 0.0
	hero_walking = false
	walk_dir = "side"
	hero_tex("pilot_hero_walk_side")
	hero_m.set_shader_parameter("frame_fixed", 1.0)

func sail(dt: float) -> void:
	var inp := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): inp -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): inp += 1.0
	if tour_on: inp = vin_sail
	var vmax := 4.0
	if inp != 0.0: boat_vel = move_toward(boat_vel, inp * vmax, 2.5 * dt)
	else: boat_vel = move_toward(boat_vel, 0.0, 1.6 * dt)
	var bp := boat.position
	var lim := route_sail_limits()
	bp.x = clampf(bp.x + boat_vel * dt, lim.x, lim.y)
	if (bp.x <= lim.x or bp.x >= lim.y) and passage == 0.0: boat_vel = 0.0      # 過場中保持速度，換站後船繼續往前滑
	# 離開碼頭後慢慢滑到航道上
	bp.z = move_toward(bp.z, LANE_Z, 0.8 * dt)
	boat.position.x = bp.x; boat.position.z = bp.z
	if absf(boat_vel) > 0.3: boat_face = signf(boat_vel)
	boat.rotation.y = 0.0 if boat_face > 0.0 else PI
	# 主角站在船中央，朝船頭
	hero_n.scale.x = absf(hero_n.scale.x) * (-1.0 if boat_face > 0.0 else 1.0)
	move_sprite(hero_n, Vector3(bp.x, boat.position.y + 0.32, bp.z))
	hero_pos = Vector3(bp.x, 0.0, bp.z)
	# 靠近碼頭、速度夠慢 → 可以下船
	var di := -1
	for i in DOCKS.size():
		if absf(bp.x - DOCKS[i].boat.x) < 1.6: di = i
	if di >= 0 and absf(boat_vel) < 1.2:
		set_prompt("E 在「%s」下船　　A／D 開船" % DOCKS[di].name)
		if e_pressed: disembark(di)
	else:
		set_prompt("A／D 開船")

func disembark(di: int) -> void:
	var d: Dictionary = DOCKS[di]
	boat_dock = di
	boat_vel = 0.0
	boat.position.x = d.boat.x; boat.position.z = d.boat.y
	mode = "walk"
	hero_pos = Vector3(d.land.x, 0.0, d.land.y)
	move_sprite(hero_n, Vector3(d.land.x, 0.0, d.land.y))
	walk_dir = "front"
	hero_m.set_shader_parameter("tex", tex("pilot_hero_anim"))
	hero_n.scale.x = absf(hero_n.scale.x)

# 水面：船的位置（接觸暗部與漣漪）、鏡頭位置、最近的 8 條燈光倒影
func update_water() -> void:
	if not water_mat: return
	water_mat.set_shader_parameter("floaters", [Vector4(boat.position.x, boat.position.z, 1.6, 0.62), Vector4(3.93, QUAY_Z + 0.07, 0.14, 0.14)])
	var cx := cam.global_position.x
	if absf(cx - streak_cam_x) < 2.0: return
	streak_cam_x = cx
	var all := zone_streaks.duplicate()
	all.sort_custom(func(a, b): return absf(a[0].x - cx) < absf(b[0].x - cx))
	var ss := []; var sc := []
	for i in 8:
		if i < all.size(): ss.append(all[i][0]); sc.append(all[i][1])
		else: ss.append(Vector4(0, 0, 0, 0)); sc.append(Vector4(0, 0, 0, 1))
	water_mat.set_shader_parameter("streaks", ss)
	water_mat.set_shader_parameter("streak_cols", sc)

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_E: e_pressed = true

# ------------------------------------------------------------------ 腳本測試：--tour（走到碼頭→上船→往東開→下船→走幾步→上船→往西開→下船）
var tour_phase := 0
var tour_t := 0.0
func tour_step(dt: float) -> void:
	tour_t += dt
	vin_dir = Vector2.ZERO; vin_sail = 0.0
	var hp := hero_pos if hero_pos != Vector3.INF else hero_n.position
	var goto := func(p: Vector2) -> bool:
		var dv := p - Vector2(hp.x, hp.z)
		if dv.length() < 0.3: return true
		vin_dir = dv.normalized()
		return false
	var steer := func(x: float) -> bool:
		var dx := x - boat.position.x
		vin_sail = clampf(dx * 0.35, -1.0, 1.0)
		return absf(dx) < 0.8 and absf(boat_vel) < 0.8
	if has("--route"):      # 路線測試：上船 → 一路往東穿過水門 → 磨坊碼頭下船 → 走進院子
		match tour_phase:
			0: if goto.call(DOCKS[0].land): e_pressed = true; tour_phase = 1
			1:
				vin_sail = 1.0
				if stage == int(argf("to", 1.0)) and fade_a < 0.05: tour_phase = 4 if has("--back") else 2
			4:
				vin_sail = -1.0
				if stage == 0 and fade_a < 0.05: tour_phase = 5
			5: if steer.call(DOCKS[1].boat.x): e_pressed = true; tour_phase = 3; tour_t = 0.0
			2: if steer.call(DOCKS[3 + int(argf("to", 1.0))].boat.x): e_pressed = true; tour_phase = 3; tour_t = 0.0
			3:
				vin_dir = Vector2(-0.4, -1.0)
				if tour_t > 3.0: tour_phase = 6
		return
	match tour_phase:
		0: if goto.call(DOCKS[0].land): e_pressed = true; tour_phase = 1
		1: if steer.call(DOCKS[3].boat.x): e_pressed = true; tour_phase = 2; tour_t = 0.0
		2:
			vin_dir = Vector2(0.3, -1.0)
			if tour_t > 2.0: tour_phase = 3
		3: if goto.call(DOCKS[3].land): e_pressed = true; tour_phase = 4
		4: if steer.call(DOCKS[2].boat.x): e_pressed = true; tour_phase = 5; tour_t = 0.0
		5:
			vin_dir = Vector2(0.2, -1.0)
			if tour_t > 2.5: tour_phase = 6

func run_tour() -> void:
	tour_on = true
	var dir := ProjectSettings.globalize_path("res://tools/work")
	for k in int(argf("tn", 40.0)):
		await get_tree().create_timer(argf("tdt", 2.5)).timeout
		var im: Image = await grab()
		im.save_png(dir.path_join("tour_%02d.png" % k))
		print("tour %02d phase=%d mode=%s hero=%s boat=(%.1f,%.1f) vel=%.1f fps=%d" % [k, tour_phase, mode, str(hero_pos), boat.position.x, boat.position.z, boat_vel, Engine.get_frames_per_second()])
		if tour_phase >= 6: break
	print("done")
	get_tree().quit()


# ------------------------------------------------------------------ 新區佈置：把原廣場的手法搬過去（牆腳草花、藤蔓、招牌、落葉、遮雨棚、燈串、光池、光束、煙、繫船柱）
func dress_zones() -> void:
	rng.seed = 5151
	var sd := Vector3(sun_dir.x, 0, sun_dir.z).normalized()
	var perp := Vector3(sun_dir.z, 0, -sun_dir.x).normalized()
	var k := 0
	for f in zone_fronts:
		var x0: float = f.x0; var x1: float = f.x1; var zf: float = f.zf
		# 牆腳的草與花
		for i in int((x1 - x0) * 1.6):
			var x := rng.randf_range(x0 + 0.1, x1 - 0.1)
			if i % 3 == 0:
				sprite("grasses_%d" % (i % 5), Vector3(x, 0, zf + rng.randf_range(0.03, 0.1)), {"sway_px": 3.0, "flat_lit": 0.45, "glow_all": 0.03, "tint": Color(0.7, 0.86, 0.66), "flip": i % 2 == 0, "shadow": false, "layer": 17})
			else:
				sprite("plants2_%d" % (rng.randi() % 8), Vector3(x, 0, zf + rng.randf_range(0.03, 0.1)), {"sway_px": 2.0, "flat_lit": 0.45, "glow_all": 0.03, "flip": i % 2 == 0, "shadow": false, "layer": 17})
		# 藤蔓、招牌、壁燈（輪流分配，避免每棟都一樣）
		if k % 3 == 0: sprite("ivy_%d" % (k % 2), Vector3(x0 + 0.5, -1.3, zf + 0.01), {"shadow": false, "lambert": true, "rustle_px": 0.4, "layer": 17, "flip": k % 2 == 1})
		if k % 3 == 1: sprite("w_sign", Vector3(x1 - 0.55, 1.05, zf + 0.02), {"shadow": false, "lambert": true, "layer": 17})
		if k % 2 == 0: wall_lantern(Vector3(x0 + 0.35, 0.95, zf + 0.02), 0.0, 0.7)
		if k % 2 == 1: smoke(f.chim)
		k += 1
	for zr in [[-57.0, -14.0], [15.5, 57.0]]:
		var zx0: float = zr[0]; var zx1: float = zr[1]
		# 地上的葉堆與零星落葉（平躺）
		for i in 7:
			var lp := sprite("leafpile_%d" % (i % 4), Vector3(rng.randf_range(zx0, zx1), 0.012, rng.randf_range(-6.5, 1.6)), {"center": true, "shadow": false, "lambert": true})
			lp.rotation = Vector3(-PI / 2, rng.randf_range(-0.5, 0.5), 0)
		for i in 120:
			var lf := sprite("leaf_o" if i % 3 else "leaf_r", Vector3(rng.randf_range(zx0, zx1), 0.01, rng.randf_range(-7.0, 2.2)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "lambert": true})
			lf.rotation = Vector3(-PI / 2, rng.randf() * TAU, 0)
		# 漂在運河上的落葉
		for i in 14:
			var wl := sprite("leaf_o" if i % 2 else "leaf_r", Vector3(rng.randf_range(zx0, zx1), WATER_Y + 0.012, rng.randf_range(QUAY_Z + 0.3, QUAY_Z + 3.4)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "glow_all": 0.3, "lambert": true})
			wl.rotation = Vector3(-PI / 2, 0, 0)
			flyers.append({"n": wl, "kind": "float", "v": rng.randf_range(0.05, 0.12), "x0": zx0, "x1": zx1})
		# 堤岸：繫船柱＋鐵鍊（西區棧橋 x -40..-37 留缺口）、垂下的藤蔓
		var bz := QUAY_Z - 0.34
		var bx := zx0 + 1.0
		var prev := -999.0
		while bx < zx1:
			if bx > -40.6 and bx < -36.4: prev = -999.0; bx += 2.7; continue
			bollard(Vector3(bx, 0, bz))
			if prev > -900.0: pixel_wire(Vector3(prev + 0.1, 0.47, bz), Vector3(bx - 0.1, 0.47, bz), 0.2, [], 2.0, Color(0.2, 0.18, 0.26))
			prev = bx; bx += 2.7
		for i in 8:
			var vn := "w_vines_%d" % (i % 4)
			var vh: float = (px_size(vn).y - PAD) / PPM
			sprite(vn, Vector3(rng.randf_range(zx0, zx1), 0.06 - vh, QUAY_Z + 0.012), {"shadow": false, "lambert": true, "rustle_px": 0.4})
	# 樹：飄落的葉子＋樹下的光束片
	for tp in [Vector3(-28.6, 0, -6.2), Vector3(47.5, 0, -6.0)]:
		leaf_emitters.append(particles(tp + Vector3(0.5, 3.0, 0.8), Vector3(2.2, 0.7, 1.8), 18, "leaf_o", {"vary": 1.0, "smin": 0.55}))
		if not has("--no-fog"):
			beam(tp + sd * 2.2 + perp * 0.4, 7.5, 1.1, 0.09, tp.x)
			beam(tp + sd * 3.4 - perp * 0.6, 8.0, 0.8, 0.07, tp.x + 3.0)
	# 西區市集：攤位遮雨棚（斜的條紋布）、燈串、攤位的暖色光池
	var cols := [Color(1.0, 0.75, 0.35), Color(1.0, 0.55, 0.3), Color(1.0, 0.9, 0.55)]      # 與原廣場燈串同色
	for st in [[-44.0, -3.0], [-40.5, -3.4], [-35.5, -3.0], [-31.5, -3.2]]:
		var sx: float = st[0]; var sz: float = st[1]
		var ga := geo("awning")
		ga.quad(Vector3(sx - 0.9, 1.4, sz + 0.5), Vector3(sx + 0.9, 1.4, sz + 0.5), Vector3(sx + 0.9, 1.75, sz - 0.45), Vector3(sx - 0.9, 1.75, sz - 0.45))
		put(ga, "awning", {"rough": 0.9, "tint": Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.05), rng.randf_range(0.85, 1.1))})
		var gp := geo("wood")
		for px in [sx - 0.85, sx + 0.85]:
			gp.box(Vector3(px, 0, sz - 0.45), Vector3(0.06, 1.75, 0.06))
			gp.box(Vector3(px, 0, sz + 0.5), Vector3(0.06, 1.4, 0.06))
		put(gp, "wood", {"tint": Color(0.8, 0.66, 0.6)})
		omni(Vector3(sx, 1.1, sz + 0.7), Color(1.0, 0.62, 0.3), 1.6, 3.4, false, 0.6, 0.04, 0.2)
	pixel_wire(Vector3(-44.9, 1.78, -3.45), Vector3(-30.6, 1.8, -3.65), 0.35, cols, 1.0, Color(0.16, 0.12, 0.16), 12)
	pixel_wire(Vector3(-46.4, 2.3, -6.9), Vector3(-39.1, 2.2, -6.9), 0.3, cols, 1.0, Color(0.16, 0.12, 0.16), 12)
	# 東區：井邊與長椅旁的光池、沿屋前的燈串
	pixel_wire(Vector3(22.6, 2.3, -6.9), Vector3(34.9, 2.2, -6.9), 0.4, cols, 1.0, Color(0.16, 0.12, 0.16), 12)
	pixel_wire(Vector3(36.6, 2.3, -6.9), Vector3(49.4, 2.2, -6.9), 0.4, cols, 1.0, Color(0.16, 0.12, 0.16), 12)


# ================================================================== 搭船路線（2026-11-18）：小鎮 → 水門涵洞（過場）→ 水車磨坊 → 楓林溪谷 → 出海口燈塔
# 每一站蓋在遠處的 x（彼此看不到），船駛進水門時畫面變黑，換站（船、鏡頭、遠景一起移過去）再亮起來。
const MILL_X := 300.0
const VALLEY_X := 600.0
const LIGHT_X := 900.0
var STAGES := [
	{"name": "小鎮", "x0": -57.0, "x1": 57.0, "gate1": 60.0, "cam": Vector2(-49.0, 52.5), "sky": true},
	{"name": "水車磨坊", "x0": MILL_X - 21.0, "x1": MILL_X + 22.0, "gate0": MILL_X - 24.0, "gate1": MILL_X + 25.0, "cam": Vector2(MILL_X - 19.0, MILL_X + 18.0), "sky": false,
		"frames": [null, ["pilot_frame_wheat", Vector4(-0.8, -0.74, 0.28, 0.34), Color(0.8, 0.62, 0.42, 1.0), Vector2(1, 1)], ["pilot_frame_wheat", Vector4(0.86, -0.82, 0.2, 0.26), Color(0.72, 0.56, 0.4, 1.0), Vector2(-1, 1)]]},
	{"name": "楓林溪谷", "x0": VALLEY_X - 21.0, "x1": VALLEY_X + 24.0, "gate0": VALLEY_X - 24.0, "gate1": VALLEY_X + 27.0, "cam": Vector2(VALLEY_X - 19.0, VALLEY_X + 21.0), "sky": false},
	{"name": "出海口燈塔", "x0": LIGHT_X - 33.0, "x1": LIGHT_X + 40.0, "gate0": LIGHT_X - 36.0, "cam": Vector2(LIGHT_X - 31.0, LIGHT_X + 30.0), "sky": false, "night": 1.0,
		"frames": [["pilot_frame_net", Vector4(-0.8, 0.72, 0.26, 0.34), Color(0.42, 0.42, 0.55, 1.0), Vector2(1, 1)], null, null]},
]
var stage := 0
var passage := 0.0           # 0 = 沒有在過場；>0 往後一站、<0 往前一站
var fade_a := 0.0
var fade_rect: ColorRect
var sky_nodes: Array = []
var wheel_pivot: Node3D
var sky_mat: ShaderMaterial
var frame_nodes: Array = []
var dof_node: MeshInstance3D
var cam_basis0 := Basis()
var cam_basis_set := false
var lh_beam: Node3D

# 水門：跨在運河上的石造門樓，船從 x 方向駛進去（只看得到正面與左/右側面的拱口）。dir = +1：拱口朝 -x（船從左邊進去）
func water_gate(gx: float, dir: float, gtex := "w_stone", gtint := Color(0.78, 0.72, 0.84)) -> void:
	var g := geo(gtex)
	var lo := WATER_Y - 0.4
	var zo0 := LANE_Z - 1.05; var zo1 := LANE_Z + 0.75          # 拱口（航道）的 z 範圍
	var w := 3.2
	var cx := gx + dir * w * 0.5
	g.box(Vector3(cx, lo, (QUAY_Z - 1.6 + zo0) * 0.5), Vector3(w, 3.3 - lo, zo0 - QUAY_Z + 1.6))           # 岸側的門樓
	g.box(Vector3(cx + dir * 0.3, LOW_Y, (-16.0 + QUAY_Z - 1.6) * 0.5), Vector3(w - 0.6, 2.9 - LOW_Y, QUAY_Z - 1.6 + 16.0))      # 往後延伸的城牆（封住世界邊緣）
	for k in 12:
		g.box(Vector3(cx + dir * 0.3, 2.9, QUAY_Z - 2.2 - k * 1.2), Vector3(w - 0.6, 0.3, 0.5))
	g.box(Vector3(cx, lo, (zo1 + zo1 + 0.8) * 0.5), Vector3(w, 2.9 - lo, 0.8))                             # 水側的門柱
	g.box(Vector3(cx, 1.05, (zo0 + zo1) * 0.5), Vector3(w, 1.85, zo1 - zo0))                               # 拱頂
	for k in 4:                                                                                              # 女兒牆
		g.box(Vector3(cx - w * 0.5 + 0.3 + k * 0.85, 3.3, QUAY_Z - 1.2), Vector3(0.45, 0.35, 0.4))
	put(g, gtex, {"tint": gtint})
	# 拱口裡面是暗的（深處一片暗牆），拱口上緣一圈拱石
	var gd := geo("stonewall")
	gd.box(Vector3(cx + dir * 0.4, lo, (zo0 + zo1) * 0.5), Vector3(w - 1.0, 1.05 - lo, zo1 - zo0 - 0.02))
	put(gd, "stonewall", {"tint": Color(0.12, 0.1, 0.16)}, false)
	var ga := geo("w_stone")
	for k in 7:
		var a := PI * (k + 0.5) / 7.0
		var r := (zo1 - zo0) * 0.5
		ga.box(Vector3(gx - dir * 0.02, 0.35 + sin(a) * 0.55, (zo0 + zo1) * 0.5 - cos(a) * r), Vector3(0.12, 0.2, 0.26))
	put(ga, "w_stone", {"tint": Color(1.05, 0.98, 1.08)})
	wall_lantern(Vector3(gx - dir * 0.05, 1.5, zo1 + 0.4), 0.0, 0.9, 3.6)
	omni(Vector3(gx - dir * 0.6, 0.2, LANE_Z), Color(1.0, 0.6, 0.3), 0.8, 2.6, false, 0.5, 0.05)

# 斜放的方塊（繞 z 軸轉 a）：水車的輪輻與葉片
func rbox(g: Geo, c: Vector3, hs: Vector3, a: float) -> void:
	var ux := Vector3(cos(a), sin(a), 0) * hs.x; var uy := Vector3(-sin(a), cos(a), 0) * hs.y; var uz := Vector3(0, 0, hs.z)
	var p := func(sx: float, sy: float, sz: float) -> Vector3: return c + ux * sx + uy * sy + uz * sz
	g.quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1))
	g.quad(p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1))
	g.quad(p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1))
	g.quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1))
	g.quad(p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1))
	g.quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1))

func build_route() -> void:
	rng.seed = 7070
	parent_node = self
	# 小鎮東端：原本的封牆換成水門（往磨坊）
	water_gate(STAGES[0].gate1, 1.0)
	build_mill(MILL_X)
	build_valley(VALLEY_X)
	build_lighthouse(LIGHT_X)
	build_tunnel()
	# 換場用的黑幕
	var cl := CanvasLayer.new(); cl.layer = 5; add_child(cl)
	fade_rect = ColorRect.new(); fade_rect.color = Color(0.02, 0.01, 0.03, 0.0)
	fade_rect.anchor_right = 1.0; fade_rect.anchor_bottom = 1.0; fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade_rect)
	var st := int(argf("stage", 0.0))
	if st > 0: enter_stage(st, 1.0, true)

func build_mill(MX: float) -> void:
	var x0 := MX - 40.0; var x1 := MX + 40.0
	# 水面、堤岸
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(x1 - x0, 12)
	water.mesh = wm; water.material_override = water_mat
	water.position = Vector3(MX, WATER_Y, QUAY_Z + 6.0); water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water); hide_in_mask.append(water)
	var gq := geo("quaywall")
	gq.quad(Vector3(x0, WATER_Y - 0.3, QUAY_Z), Vector3(x1, WATER_Y - 0.3, QUAY_Z), Vector3(x1, 0, QUAY_Z), Vector3(x0, 0, QUAY_Z))
	put(gq, "quaywall", {"tint": Color(1.0, 1.04, 1.12)})
	water_gate(STAGES[1].gate0, -1.0)
	water_gate(STAGES[1].gate1, 1.0)
	# 地面：磨坊前的石板院子＋其他是秋天的草地（之後換成專屬貼圖）
	var gy := geo("cobble")
	gy.quad(Vector3(MX - 12.0, 0, QUAY_Z), Vector3(MX + 12.5, 0, QUAY_Z), Vector3(MX + 12.5, 0, -8.0), Vector3(MX - 12.0, 0, -8.0))
	put(gy, "cobble", {"tint": Color(0.92, 0.84, 0.86)}, false)
	var gg := geo("grass")
	for r in [[x0, MX - 12.0, QUAY_Z, -8.0], [MX + 12.5, x1, QUAY_Z, -8.0]]:
		gg.quad(Vector3(r[0], -0.005, r[2]), Vector3(r[1], -0.005, r[2]), Vector3(r[1], -0.005, r[3]), Vector3(r[0], -0.005, r[3]))
	put(gg, "grass", {"tint": Color(0.5, 0.38, 0.26)}, false)
	for i in 260:      # 田邊草地：秋天的枯草叢、野花，院子邊緣多一些（蓋住石板與草地的直線交界）
		var gxp := rng.randf_range(x0, x1)
		if gxp > MX - 12.6 and gxp < MX + 13.1 and not (absf(gxp - (MX - 12.0)) < 0.6 or absf(gxp - (MX + 12.5)) < 0.6): continue
		var gp2 := Vector3(gxp, 0, rng.randf_range(-7.9, QUAY_Z - 0.4))
		if i % 4 == 0: sprite("plants2_%d" % (i % 8), gp2, {"sway_px": 2.0, "flat_lit": 0.3, "flip": i % 2 == 0, "shadow": false})
		else: sprite("grasses_%d" % (i % 5), gp2, {"sway_px": 3.0, "gust_x": gp2.x, "flat_lit": 0.3, "tint": Color(1.0, 0.78, 0.5), "flip": i % 2 == 0, "shadow": false})
	var gso := geo("pilot_mill_soil")      # 田（codex 生成的田畦地面，平鋪）
	gso.quad(Vector3(x0, -0.005, -8.0), Vector3(x1, -0.005, -8.0), Vector3(x1, -0.005, -40.0), Vector3(x0, -0.005, -40.0))
	put(gso, "pilot_mill_soil", {"tint": Color(0.7, 0.62, 0.6)}, false)
	reg_on = true
	# 磨坊：石砌一樓＋木骨灰泥二樓、山牆朝前；旁邊一間木造倉庫
	var wins := ["w_win_a", "w_win_b", "w_win_c", "windows_0"]
	house({"x0": MX - 3.4, "x1": MX + 2.8, "zb": -7.6, "zf": -3.0, "h": 3.2, "rh": 1.9, "ridge": "z", "upper": 1.6,
		"tint": Color(0.95, 0.9, 0.86), "wall": "stonewall", "roof": "w_roof_red2", "roof_tint": Color(1.0, 0.9, 0.9),
		"chimney": Vector2(1.6, -0.6), "lights": true,
		"items": [["w_door_a", "f", 0.6, 0.3, 0.0], ["w_win_a", "f", -1.8, 0.55, 0.62], ["w_win_b", "f", -1.4, 2.2, 0.62], ["w_win_b", "f", 1.4, 2.2, 0.62]]})
	house({"x0": MX + 3.4, "x1": MX + 7.4, "zb": -7.0, "zf": -3.6, "h": 2.2, "rh": 1.1, "ridge": "x",
		"tint": Color(0.8, 0.68, 0.6), "wall": "planks", "roof": "w_roof_red2", "roof_tint": Color(0.95, 0.85, 0.85), "lights": true,
		"items": [["w_door_b", "f", -0.6, 0.3, 0.0], ["windows_0", "f", 1.0, 0.6, 0.62]]})
	smoke(Vector3(MX + 1.6, 5.4, -5.9))
	# 水車：在堤岸前的水裡，輪面朝鏡頭；兩側石墩，上方木水槽從磨坊牆伸出來
	var wx := MX - 5.8; var wz := QUAY_Z + 0.6; var wy := -0.05; var R := 1.5
	var gpi := geo("w_stone")
	for px in [wx - R - 0.38, wx + R + 0.38]:
		gpi.box(Vector3(px, WATER_Y - 0.4, wz), Vector3(0.5, 0.9 + 0.4 + wy + 0.15, 1.1))
	put(gpi, "w_stone", {"tint": Color(0.95, 0.9, 1.0)})
	wheel_pivot = Node3D.new(); wheel_pivot.position = Vector3(wx, wy, wz); add_child(wheel_pivot)
	parent_node = wheel_pivot
	var gwh := geo("wood")
	var nseg := 16
	for i in nseg:
		var a := TAU * i / nseg
		var am := a + PI / nseg
		for side in [-0.27, 0.27]:
			rbox(gwh, Vector3(cos(am) * R, sin(am) * R, side), Vector3(R * sin(PI / nseg) + 0.03, 0.08, 0.04), am + PI / 2)      # 輪框
		rbox(gwh, Vector3(cos(a) * (R - 0.08), sin(a) * (R - 0.08), 0), Vector3(0.24, 0.03, 0.3), a)                             # 葉片（徑向）
	for i in 8:
		var a := TAU * i / 8.0
		for side in [-0.27, 0.27]:
			rbox(gwh, Vector3(cos(a) * R * 0.5, sin(a) * R * 0.5, side), Vector3(R * 0.5, 0.045, 0.035), a)                       # 輪輻
	rbox(gwh, Vector3.ZERO, Vector3(0.16, 0.16, 0.42), 0.0)                                                                    # 軸心
	put(gwh, "wood", {"tint": Color(0.82, 0.62, 0.5), "rough": 0.9})
	parent_node = self
	var gax := geo("wood")
	gax.box(Vector3(wx, wy - 0.07, (wz + QUAY_Z - 0.4) * 0.5), Vector3(0.14, 0.14, wz - QUAY_Z + 0.4))      # 軸伸進堤岸
	# 引水槽：從田邊的石砌水塔沿 z 架到水車頂上（木架撐著），水從槽口落到左上方的葉片
	var fx := wx - 0.45; var fy := wy + R + 0.55
	var zs := -9.0
	gax.box(Vector3(fx, fy, (zs + wz) * 0.5), Vector3(0.46, 0.22, wz - zs))
	gax.box(Vector3(fx - 0.21, fy + 0.22, (zs + wz) * 0.5), Vector3(0.05, 0.1, wz - zs))
	gax.box(Vector3(fx + 0.21, fy + 0.22, (zs + wz) * 0.5), Vector3(0.05, 0.1, wz - zs))
	var qz := zs + 1.2
	while qz < QUAY_Z - 0.3:
		gax.box(Vector3(fx, 0, qz), Vector3(0.1, fy, 0.1))
		gax.box(Vector3(fx, fy - 0.5, qz), Vector3(0.5, 0.07, 0.08))
		zone_circles.append([fx, qz, 0.12])
		qz += 1.7
	put(gax, "wood", {"tint": Color(0.7, 0.55, 0.48)})
	var gt := geo("w_stone")
	gt.box(Vector3(fx, 0, zs - 0.3), Vector3(1.3, fy + 0.4, 1.2))
	put(gt, "w_stone", {"tint": Color(0.95, 0.9, 1.0)})
	# 落水（4 格循環）、輪下水花、少量水沫
	sprite("pilot_fall", Vector3(fx, fy - 1.28, wz), {"fps": 10.0, "glow_all": 0.0, "flat_lit": 0.25, "tint": Color(0.62, 0.7, 0.85), "shadow": false})
	sprite("pilot_splash", Vector3(wx - 0.5, WATER_Y - 0.08, wz + 0.62), {"fps": 7.0, "glow_all": 0.3, "flat_lit": 0.6, "shadow": false})
	sprite("pilot_splash", Vector3(wx + 0.7, WATER_Y - 0.08, wz + 0.55), {"fps": 6.0, "glow_all": 0.3, "flat_lit": 0.6, "shadow": false, "flip": true})
	particles(Vector3(wx - 0.4, WATER_Y + 0.1, wz + 0.2), Vector3(0.7, 0.02, 0.3), 24, "mote", {"dir": Vector3(0, 1, 0.2), "spread": 50.0, "v0": 0.5, "v1": 1.0, "gravity": Vector3(0, -3.0, 0), "turb": 0.2, "life": 0.6, "glow": 0.5, "tint": Color(0.85, 0.9, 1.0)})
	# 院子裡的東西：麵粉袋、木桶、木箱、推車、柴堆、長椅、路燈
	for sp in [[MX + 3.9, -3.2], [MX + 4.3, -3.25], [MX + 4.1, -3.0], [MX - 2.6, -2.7], [MX - 2.25, -2.75], [MX + 8.0, -1.0], [MX + 8.35, -1.1]]:
		sprite("w_props7_5", Vector3(sp[0], 0, sp[1]), {"flat_lit": 0.3, "tilt": true, "scale": 1.6, "flip": rng.randf() < 0.5})
		contact_shadow(Vector3(sp[0], 0, sp[1] - 0.05), 0.32, 0.2, 0.5)
	zone_rects.append([MX + 3.6, -3.5, MX + 4.6, -2.8])
	for b in [[MX + 5.2, -3.1], [MX + 5.8, -3.0], [MX - 3.1, -2.6], [MX + 9.5, -3.6]]: barrel(Vector3(b[0], 0, b[1]))
	crate(Vector3(MX + 6.6, 0, -3.1), 0.6, 10.0); crate(Vector3(MX + 9.0, 0, -4.0), 0.55, -15.0)
	sprite("w_cart", Vector3(MX + 8.6, 0, -1.6), {"flat_lit": 0.3, "tilt": true})
	zone_rects.append([MX + 8.0, -1.95, MX + 9.2, -1.25])
	sprite("street2_4", Vector3(MX - 7.8, 0, -3.6), {"flat_lit": 0.3, "tilt": true})
	zone_circles.append([MX - 7.8, -3.6, 0.5])
	bench(Vector3(MX - 1.0, 0, 1.0), 0.0)
	for i in 70:
		var lf := sprite("leaf_o" if i % 3 else "leaf_r", Vector3(rng.randf_range(MX - 12.0, MX + 12.0), 0.01, rng.randf_range(-7.5, 2.2)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "lambert": true})
		lf.rotation = Vector3(-PI / 2, rng.randf() * TAU, 0)
	for lpp in [[MX - 8.6, -6.2], [MX - 10.6, -4.6], [MX + 0.6, 1.6], [MX + 11.0, -6.4]]:
		var lp := sprite("leafpile_%d" % (rng.randi() % 4), Vector3(lpp[0], 0.012, lpp[1]), {"center": true, "shadow": false, "lambert": true})
		lp.rotation = Vector3(-PI / 2, rng.randf_range(-0.5, 0.5), 0)
	leaf_emitters.append(particles(Vector3(MX - 9.0, 3.0, -4.8), Vector3(2.2, 0.7, 1.8), 18, "leaf_o", {"vary": 1.0, "smin": 0.55}))
	planter(Vector3(MX + 2.5, 0, 1.5), 1.4, 0.5, ["flowers_0", "flowers_4", "flowers_2"], 0.28)
	for lp in [MX - 10.0, MX + 5.0]: lamp_post(Vector3(lp, 0, 1.9))
	wall_lantern(Vector3(MX + 0.0, 1.0, -2.98), 0.0, 0.8)
	# 磨坊左邊一棵大楓樹
	tree(Vector3(MX - 9.5, 0, -5.6), ["maple_0", "maple_1", "maple_2", "maple_3", "maple_4", "maple_5"], 40, Vector3(1.9, 1.0, 1.6), 2.8, 0.0)
	# 碼頭：木棧橋
	var gp := geo("wood")
	for px in [MX + 9.3, MX + 11.9]:
		for pz in [QUAY_Z + 0.2, QUAY_Z + 1.3]:
			gp.box(Vector3(px, WATER_Y - 0.4, pz), Vector3(0.18, 1.3, 0.18))
	put(gp, "wood", {"tint": Color(0.55, 0.45, 0.42)})
	var gk := geo("pilot_planks")
	for bi in 6:
		gk.uo = Vector2(rng.randf(), float(rng.randi_range(0, 7)) * 0.125)
		gk.box(Vector3(MX + 10.6, -0.07, QUAY_Z + 0.2 + 0.25 * bi), Vector3(3.0, 0.07, 0.245), false, 1 | 16)
	put(gk, "pilot_planks", {"tint": Color(0.8, 0.72, 0.7), "rough": 0.9})
	reg_on = false
	# 院子後面的木柵欄（留一個缺口通往田）
	var gf := geo("wood")
	var fcx := MX - 12.0
	while fcx < MX + 12.5:
		if absf(fcx - (MX + 10.0)) > 1.0:
			gf.box(Vector3(fcx, 0, -8.1), Vector3(0.08, 0.7, 0.08))
			gf.box(Vector3(fcx + 0.6, 0.45, -8.1), Vector3(1.2, 0.06, 0.05))
			gf.box(Vector3(fcx + 0.6, 0.2, -8.1), Vector3(1.2, 0.06, 0.05))
		fcx += 1.2
	put(gf, "wood", {"tint": Color(0.75, 0.6, 0.52)})
	# 麥田：左邊已收割（田畦＋乾草堆），右邊還沒收割（一排排麥子，留一條通往田裡的小路）
	var zr := -9.6
	while zr > -30.0:
		var xr := MX - 4.0 + rng.randf_range(-3.0, 0.0)
		while xr < x1:
			if absf(xr - (MX + 10.0)) > 1.3:
				sprite("pilot_mill_wheat", Vector3(xr, 0, zr + rng.randf_range(-0.08, 0.08)), {"sway_px": 2.0, "gust_x": xr, "flat_lit": 0.12, "tint": Color(0.72, 0.62, 0.56), "flip": rng.randf() < 0.5, "shadow": zr > -14.0})
			xr += rng.randf_range(4.6, 5.6)
		zr -= 0.85
	for i in 16:
		var hp := Vector3(rng.randf_range(x0 + 2.0, MX - 8.0), 0, rng.randf_range(-10.0, -28.0))
		var hs := rng.randf_range(0.85, 1.05)
		sprite("pilot_hay_a" if i % 3 else "pilot_hay_b", hp, {"flat_lit": 0.3, "flip": rng.randf() < 0.5, "scale": hs})
		contact_shadow(hp + Vector3(0, 0, -0.2), 0.9 * hs, 0.5 * hs, 0.5)
	tree_tint = Color(1.25, 1.1, 0.55)
	var px2 := x0 + 2.0
	while px2 < x1:
		tree(Vector3(px2, 0, -31.0 + rng.randf_range(-0.6, 0.6)), ["canopy_autumn_0", "canopy_autumn_1", "canopy_autumn_2", "canopy_autumn_3"], 16, Vector3(0.6, 2.2, 0.6), 3.6, 0.0, false)
		px2 += rng.randf_range(3.2, 4.6)
	tree_tint = Color(1, 1, 1)
	# 磨坊工人：扛著麵粉袋站在倉庫前
	var mn := sprite("pilot_npc_miller_anim", Vector3(MX + 5.0, 0, -2.4), {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0, "scale": 0.8})
	contact_shadow(Vector3(MX + 5.0, 0, -2.45), 0.38, 0.2, 0.55)
	zone_npcs.append({"m": mn.material_override, "n": 2, "dt": 1.0})
	zone_circles.append([MX + 5.0, -2.4, 0.25])
	# 繫船柱
	var bx := x0 + 2.0
	while bx < x1 - 2.0:
		if absf(bx - (MX + 10.6)) > 2.2 and absf(bx - (MX - 5.8)) > 2.6: bollard(Vector3(bx, 0, QUAY_Z - 0.34))
		bx += 3.1

# 換站：船（或主角）移到新站的入口，鏡頭直接跳過去，遠景換掉
func enter_stage(i: int, dirn: float, on_land := false) -> void:
	stage = i
	var s: Dictionary = STAGES[i]
	var nx: float = (s.x0 + 1.0) if dirn > 0.0 else (s.x1 - 1.0)
	if on_land:
		var lx: float = (s.x0 + s.x1) * 0.5 + argf("hx", 2.0)
		hero_pos = Vector3(lx, 0, argf("hz", 0.6))
		move_sprite(hero_n, hero_pos)
	else:
		boat.position.x = nx
		boat.position.z = LANE_Z
		hero_pos = Vector3(nx, 0, LANE_Z)
		move_sprite(hero_n, Vector3(nx, boat.position.y + 0.32, LANE_Z))
	var hp := hero_pos
	if cam_base == Vector3.INF: cam_base = cam.global_position
	var zmax := 4.8 if mode == "sail" else CAM_PAN_Z.y
	cam_off = Vector3(clampf(hp.x - HERO.x, s.cam.x, s.cam.y), 0.0, clampf(hp.z - HERO.z, CAM_PAN_Z.x, zmax))
	if cam_basis_set: cam.global_transform.basis = cam_basis0
	cam.global_position = cam_base + cam_off
	for n in sky_nodes: n.visible = s.sky
	var fr: Array = s.get("frames", [])
	for k in frame_nodes.size():
		var fq: MeshInstance3D = frame_nodes[k][0]; var fm: ShaderMaterial = frame_nodes[k][1]
		if fr.is_empty():
			fq.visible = true
			fm.set_shader_parameter("tex", tex(["frame_tl", "frame_bl", "frame_br"][k]))
			fm.set_shader_parameter("rect", [Vector4(-0.86, 0.76, 0.22, 0.3), Vector4(-0.84, -0.78, 0.24, 0.3), Vector4(0.88, -0.84, 0.18, 0.24)][k])
			fm.set_shader_parameter("tint", Color(0.78, 0.5, 0.5, 1.0)); fm.set_shader_parameter("flip", Vector2(1, 1))
		elif k < fr.size() and fr[k] != null and FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % fr[k][0])):
			fq.visible = true
			fm.set_shader_parameter("tex", tex(fr[k][0])); fm.set_shader_parameter("rect", fr[k][1])
			fm.set_shader_parameter("tint", fr[k][2]); fm.set_shader_parameter("flip", fr[k][3])
		else:
			fq.visible = false
	var nt: float = s.get("night", 0.0)
	if sky_mat: sky_mat.set_shader_parameter("night", nt)
	sun.light_energy = lerpf(argf("sun", 9.0), 2.2, nt)
	sun.light_color = Color(1.0, 0.8, 0.36).lerp(Color(1.0, 0.7, 0.5), nt)
	env.ambient_light_color = Color(0.4, 0.46, 0.68).lerp(Color(0.34, 0.44, 0.9), nt)
	env.ambient_light_energy = lerpf(argf("amb", 0.6), 0.85, nt)
	streak_cam_x = INF

func route_sail_limits() -> Vector2:
	var s: Dictionary = STAGES[stage]
	return Vector2(s.get("gate0", s.x0 - 1.5) - 1.6 if s.has("gate0") else s.x0, s.get("gate1", s.x1 + 1.5) + 1.6 if s.has("gate1") else s.x1)

# 過場：船頭進到門樓裡就開始變黑，全黑時換站，再亮起來
func route_update(dt: float) -> void:
	if not fade_rect: return
	var s: Dictionary = STAGES[stage]
	if passage == 0.0 and mode == "sail" and not tun_on:
		if s.has("gate1") and boat.position.x > s.gate1 + 0.4 and boat_vel > 0.0 and stage + 1 < STAGES.size(): passage = 1.0
		if s.has("gate0") and boat.position.x < s.gate0 - 0.4 and boat_vel < 0.0 and stage > 0: passage = -1.0
	if passage != 0.0:
		fade_a = minf(fade_a + dt / (0.6 if absf(passage) > 1.5 else 0.35), 1.0)
		if fade_a >= 1.0:
			if absf(passage) > 1.5: tunnel_end()
			elif has("--no-tunnel"): enter_stage(stage + int(passage), passage)
			else: tunnel_start(stage + int(passage), passage)
			passage = 0.0
	else:
		fade_a = maxf(fade_a - dt / 0.8, 0.0)
	fade_rect.color.a = fade_a


# ------------------------------------------------------------------ 第三站：楓林溪谷（岩台一層層往後升高，中間一道峽谷，瀑布從最上層落下匯進溪流）
func tex_or(name: String, fb: String) -> String:
	return name if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % name)) else fb

func build_valley(VX: float) -> void:
	rng.seed = 8080
	parent_node = self
	var x0 := VX - 34.0; var x1 := VX + 34.0
	var rock := tex_or("pilot_valley_rock", "stonewall")
	var moss := tex_or("pilot_valley_moss", "grass")
	var rtint := Color(1.0, 0.94, 1.04)
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(x1 - x0, 12)
	water.mesh = wm; water.material_override = water_mat
	water.position = Vector3(VX, WATER_Y, QUAY_Z + 6.0); water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water); hide_in_mask.append(water)
	water_gate(STAGES[2].gate0, -1.0, rock, Color(0.7, 0.64, 0.76))
	water_gate(STAGES[2].gate1, 1.0, rock, Color(0.7, 0.64, 0.76))
	# 峽谷（瀑布與流進溪的小溪）的範圍
	var gx0 := VX + 1.4; var gx1 := VX + 5.0
	# 岸邊：天然岩塊（高低、前後錯開）
	var gb := geo(rock)
	var bx := x0
	while bx < x1:
		var bw := rng.randf_range(1.2, 2.6)
		if bx >= gx0 - 0.01 and bx < gx1: bx = gx1; continue
		if bx + bw > gx0 and bx < gx0: bw = gx0 - bx
		gb.box(Vector3(bx + bw * 0.5, WATER_Y - 0.4, QUAY_Z - 0.3 + rng.randf_range(-0.15, 0.2)), Vector3(bw + 0.1, 0.4 - WATER_Y + rng.randf_range(-0.12, 0.12), 0.9))
		bx += bw
	put(gb, rock, {"tint": rtint})
	# 岩台：每層 [前緣 z, 頂高, 後緣 z]，前緣立面是岩壁、頂上是苔蘚地；在峽谷處斷開
	var tiers := [[-1.9, 1.5, -5.8], [-5.8, 3.4, -10.4], [-10.4, 6.2, -24.0]]
	var gt := geo(moss)
	var gw := geo(rock)
	for ti in tiers.size():
		var zf: float = tiers[ti][0]; var hy: float = tiers[ti][1]; var zb: float = tiers[ti][2]
		var sx := x0
		while sx < x1:
			var sw := rng.randf_range(1.6, 3.4)
			var cut0 := sx; var cut1 := minf(sx + sw, x1)
			if cut1 > gx0 and cut0 < gx1 and ti < 2:
				if cut0 < gx0: cut1 = gx0
				else: sx = gx1; continue
			var dz := rng.randf_range(-0.35, 0.35); var dh := 0.0
			var y0 := 0.0 if ti == 0 else float(tiers[ti - 1][1])
			gw.box(Vector3((cut0 + cut1) * 0.5, y0 - 0.2, (zf + dz + zb) * 0.5), Vector3(cut1 - cut0 + 0.02, hy + dh - y0 + 0.2, zf + dz - zb), true, 1 | 4 | 8)
			gt.quad(Vector3(cut0, hy + dh, zf + dz), Vector3(cut1, hy + dh, zf + dz), Vector3(cut1, hy + dh, zb), Vector3(cut0, hy + dh, zb))
			sx = cut1
	# 峽谷兩側的岩壁（跟著岩台一階階往後升高）
	for side in [gx0, gx1]:
		for ti in 2:
			var zf: float = tiers[ti][0]; var hy: float = tiers[ti][1]; var zb: float = tiers[ti][2]
			gw.box(Vector3(side, WATER_Y - 0.4, (zf + zb) * 0.5 + 0.2), Vector3(0.6, hy - WATER_Y + 0.4, zf - zb + 0.4), true, 31)
			if ti == 0: gw.box(Vector3(side, WATER_Y - 0.4, (zf + QUAY_Z) * 0.5), Vector3(0.6, -WATER_Y + 0.4, QUAY_Z - zf))
	gw.box(Vector3((gx0 + gx1) * 0.5, WATER_Y - 0.4, -10.9), Vector3(gx1 - gx0 + 0.4, 6.6 - WATER_Y + 0.4, 1.0))      # 峽谷底的岩壁（瀑布背後）
	put(gw, rock, {"tint": rtint})
	# 步道層（y=0）的苔蘚地，峽谷處斷開
	for r in [[x0, gx0], [gx1, x1]]:
		gt.quad(Vector3(r[0], 0, QUAY_Z - 0.3), Vector3(r[1], 0, QUAY_Z - 0.3), Vector3(r[1], 0, -1.9), Vector3(r[0], 0, -1.9))
	put(gt, moss, {"tint": Color(1.05, 1.0, 0.95)}, false)
	# 峽谷裡的小溪水面＋木橋
	var sw2 := MeshInstance3D.new()
	var sm := PlaneMesh.new(); sm.size = Vector2(gx1 - gx0, 10.4 + QUAY_Z)
	var dwm: ShaderMaterial = water_mat.duplicate()
	dwm.set_shader_parameter("strength", 0.15)
	sw2.mesh = sm; sw2.material_override = dwm
	sw2.position = Vector3((gx0 + gx1) * 0.5, WATER_Y, (QUAY_Z - 10.4) * 0.5); sw2.layers = 2
	sw2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sw2); hide_in_mask.append(sw2)
	var gbr := geo("pilot_planks")
	for bi in 7:
		gbr.uo = Vector2(rng.randf(), float(rng.randi_range(0, 7)) * 0.125)
		gbr.box(Vector3((gx0 + gx1) * 0.5, -0.07, -1.5 + 0.25 * bi), Vector3(gx1 - gx0 + 0.6, 0.07, 0.245), false, 1 | 16)
	put(gbr, "pilot_planks", {"tint": Color(0.75, 0.66, 0.64), "rough": 0.9})
	var gbp := geo("wood")
	for pz in [-1.55, 0.2]:
		gbp.box(Vector3((gx0 + gx1) * 0.5, 0.0, pz), Vector3(gx1 - gx0 + 0.6, 0.55, 0.06), true, 1 | 16)
		for px in [gx0 - 0.25, (gx0 + gx1) * 0.5, gx1 + 0.25]: gbp.box(Vector3(px, 0.0, pz), Vector3(0.08, 0.62, 0.08))
	put(gbp, "wood", {"tint": Color(0.6, 0.48, 0.44)})
	zone_rects.append([gx0 - 0.3, -1.65, gx1 + 0.3, -1.45]); zone_rects.append([gx0 - 0.3, 0.12, gx1 + 0.3, 0.3])
	zone_rects.append([gx0 - 0.3, 0.3, gx1 + 0.3, QUAY_Z + 0.2])      # 橋前面是小溪，不能走
	# 瀑布：貼在最上層岩壁前，從頂端落到小溪；底部水霧
	var fs := (6.2 - WATER_Y + 0.2) / ((px_size("pilot_falls_big").y - 8.0) / PPM)
	sprite("pilot_falls_big", Vector3((gx0 + gx1) * 0.5, WATER_Y - 0.12, -10.1), {"fps": 9.0, "glow_all": 0.18, "flat_lit": 0.45, "tint": Color(0.85, 0.88, 0.97), "shadow": false, "scale": fs})
	particles(Vector3((gx0 + gx1) * 0.5, WATER_Y + 0.3, -9.6), Vector3(1.2, 0.2, 0.5), 30, "puff", {"dir": Vector3(0, 1, 0.3), "spread": 40.0, "v0": 0.2, "v1": 0.5, "gravity": Vector3(0.05, 0.05, 0.05), "turb": 0.4, "life": 3.0, "glow": 0.25, "tint": Color(0.9, 0.92, 1.0, 0.5)})
	sprite("pilot_splash", Vector3((gx0 + gx1) * 0.5, WATER_Y - 0.08, -9.7), {"fps": 7.0, "glow_all": 0.2, "flat_lit": 0.5, "shadow": false, "scale": 1.6})
	# 楓樹：各層岩台上
	var maples := ["maple_0", "maple_1", "maple_2", "maple_3", "maple_4", "maple_5"]
	tree_tint = Color(1.12, 0.66, 0.6)
	reg_on = true
	for tp in [[VX - 15.0, -0.9, 0], [VX - 4.0, -1.0, 0], [VX + 9.5, -1.1, 0], [VX + 19.0, -0.8, 0],
			[VX - 18.0, -4.2, 1.5], [VX - 9.0, -4.0, 1.5], [VX + 8.0, -4.4, 1.5], [VX + 15.0, -4.0, 1.5],
			[VX - 13.0, -8.4, 3.4], [VX - 1.5, -8.6, 3.4], [VX + 11.0, -8.4, 3.4], [VX + 21.0, -8.0, 3.4],
			[VX - 21.0, -13.5, 6.2], [VX - 7.0, -13.0, 6.2], [VX + 3.2, -14.0, 6.2], [VX + 14.0, -13.4, 6.2], [VX + 25.0, -13.0, 6.2]]:
		var py: float = tp[2]
		var big: float = 1.0 if py < 1.0 else 0.85
		tree(Vector3(tp[0], py, tp[1]), maples, int(34 * big), Vector3(1.9, 1.0, 1.4) * big, 2.6 * big, 0.0, py < 1.0)
		if rng.randf() < 0.5: tree_tint = Color(1.15, 0.9, 0.55)
		else: tree_tint = Color(1.12, 0.66, 0.6)
	tree_tint = Color(1, 1, 1)
	reg_on = false
	for lx in [VX - 12.0, VX + 2.0, VX + 15.0]:
		leaf_emitters.append(particles(Vector3(lx, 3.5, -2.0), Vector3(3.0, 0.8, 2.0), 22, "leaf_r", {"vary": 1.0, "smin": 0.55}))
	if not has("--no-fog"):
		var sd := Vector3(sun_dir.x, 0, sun_dir.z).normalized()
		for bp in [Vector3(VX - 9.0, 0, -0.5), Vector3(VX + 7.0, 0, -0.2)]:
			beam(bp + sd * 1.5, 9.0, 1.2, 0.08, bp.x)
	# 棧橋＋石燈籠
	var gp := geo("wood")
	for px in [VX - 10.3, VX - 7.7]:
		for pz in [QUAY_Z + 0.2, QUAY_Z + 1.3]:
			gp.box(Vector3(px, WATER_Y - 0.4, pz), Vector3(0.18, 1.3, 0.18))
	put(gp, "wood", {"tint": Color(0.55, 0.45, 0.42)})
	var gk := geo("pilot_planks")
	for bi in 9:
		gk.uo = Vector2(rng.randf(), float(rng.randi_range(0, 7)) * 0.125)
		gk.box(Vector3(VX - 9.0, -0.07, QUAY_Z - 0.55 + 0.25 * bi), Vector3(3.0, 0.07, 0.245), false, 1 | 16)
	put(gk, "pilot_planks", {"tint": Color(0.75, 0.66, 0.64), "rough": 0.9})
	if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/pilot_stone_lantern.png")):
		for sl in [[VX - 11.2, -0.6], [VX + 6.4, -0.6]]:
			sprite("pilot_stone_lantern", Vector3(sl[0], 0, sl[1]), {"flat_lit": 0.25, "tilt": true, "scale": 0.75})
			contact_shadow(Vector3(sl[0], 0, sl[1] - 0.05), 0.45, 0.28, 0.55)
			omni(Vector3(sl[0], 1.1, sl[1] + 0.4), Color(1.0, 0.62, 0.3), 1.4, 3.2, false, 0.6, 0.05)
			zone_circles.append([sl[0], sl[1], 0.35])
	# 溪裡的石頭（航道前後）與漂流的楓葉
	for i in 9:
		var rz: float = [QUAY_Z + 0.9, QUAY_Z + 1.4, LANE_Z + 1.6, LANE_Z + 2.3][i % 4]
		var rx := VX - 18.0 + i * 4.6 + rng.randf_range(-1.0, 1.0)
		if absf(rx - (VX - 9.0)) < 2.2: continue
		var rn: String = ["pilot_rock_a", "pilot_rock_b", "pilot_rock_c"][i % 3]
		if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % rn)):
			sprite(rn, Vector3(rx, WATER_Y - 0.12, rz), {"flat_lit": 0.25, "tilt": true, "flip": rng.randf() < 0.5})
	for i in 40:
		var wl := sprite("leaf_r" if i % 3 else "leaf_o", Vector3(rng.randf_range(x0, x1), WATER_Y + 0.012, rng.randf_range(QUAY_Z + 0.3, QUAY_Z + 6.0)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "glow_all": 0.3, "lambert": true})
		wl.rotation = Vector3(-PI / 2, rng.randf() * TAU, 0)
		flyers.append({"n": wl, "kind": "float", "v": rng.randf_range(0.08, 0.16), "x0": x0, "x1": x1})
	for i in 50:
		var lf := sprite("leaf_o" if i % 2 else "leaf_r", Vector3(rng.randf_range(x0, x1), 0.01, rng.randf_range(-1.8, QUAY_Z - 0.4)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "lambert": true})
		lf.rotation = Vector3(-PI / 2, rng.randf() * TAU, 0)


# ------------------------------------------------------------------ 第四站：出海口燈塔（藍調時刻）：漁港小鎮＋往海裡伸出去的防波堤，盡頭是燈塔
func build_lighthouse(LX: float) -> void:
	rng.seed = 9090
	parent_node = self
	var x0 := LX - 40.0; var x1 := LX + 60.0
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(x1 - x0, 70.0)
	water.mesh = wm; water.material_override = water_mat
	water.position = Vector3((x0 + x1) * 0.5, WATER_Y, QUAY_Z + 12.0 - 35.0); water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water); hide_in_mask.append(water)
	water_gate(STAGES[3].gate0, -1.0)
	var lx1 := LX + 4.0
	# 漁港地面、堤岸
	var gy := geo("cobble")
	gy.quad(Vector3(x0, 0, QUAY_Z), Vector3(lx1, 0, QUAY_Z), Vector3(lx1, 0, -14.0), Vector3(x0, 0, -14.0))
	put(gy, "cobble", {"tint": Color(0.86, 0.82, 0.9)}, false)
	var gq := geo("quaywall")
	gq.quad(Vector3(x0, WATER_Y - 0.3, QUAY_Z), Vector3(lx1, WATER_Y - 0.3, QUAY_Z), Vector3(lx1, 0, QUAY_Z), Vector3(x0, 0, QUAY_Z))
	put(gq, "quaywall", {"tint": Color(1.0, 1.04, 1.12)})
	var gs := geo("w_stone")
	gs.box(Vector3(lx1 + 0.3, WATER_Y - 0.4, (-14.0 + QUAY_Z - 1.7) * 0.5), Vector3(0.6, 0.4 - WATER_Y, QUAY_Z - 1.7 + 14.0))      # 港區東側的岸壁
	# 防波堤：沿 x 往海裡伸
	var jz0 := QUAY_Z - 1.7; var jz1 := QUAY_Z + 0.5; var jx1 := LX + 26.0
	gs.box(Vector3((lx1 + jx1) * 0.5, WATER_Y - 0.4, (jz0 + jz1) * 0.5), Vector3(jx1 - lx1, 0.4 - WATER_Y, jz1 - jz0))
	gs.box(Vector3((lx1 + jx1) * 0.5, 0.0, jz0 + 0.12), Vector3(jx1 - lx1, 0.35, 0.24))       # 外側的矮護牆
	gs.box(Vector3(LX + 28.0, WATER_Y - 0.4, (jz0 + jz1) * 0.5), Vector3(5.0, 0.7 - WATER_Y, 4.6))   # 燈塔的圓台（方塊近似）
	# 漁港石階（碼頭）
	for i in 5:
		gs.box(Vector3(LX - 6.0, WATER_Y - 0.3, QUAY_Z + 0.16 + i * 0.32), Vector3(2.0, 1.25 - 0.2 * (i + 1), 0.32))
	put(gs, "w_stone", {"tint": Color(0.9, 0.86, 0.98)})
	# 燈塔
	var lamp_y := 0.0
	if has("--lh-sprite") and FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/pilot_lighthouse.png")):
		sprite("pilot_lighthouse", Vector3(LX + 28.0, 0.7, (jz0 + jz1) * 0.5 - 0.4), {"flat_lit": 0.3, "tilt": true})
		lamp_y = 0.7 + (px_size("pilot_lighthouse").y - 8.0) / PPM * 0.86
	else:
		lamp_y = lighthouse3d(Vector3(LX + 28.0, WATER_Y + 0.4 + 0.3, (jz0 + jz1) * 0.5)) + WATER_Y + 0.7
	omni(Vector3(LX + 28.0, lamp_y, (jz0 + jz1) * 0.5), Color(1.0, 0.78, 0.45), 4.0, 9.0, false, 1.0, 0.03)
	# 旋轉的光束：從燈室往外的長梯形（加法混色），繞 y 軸轉
	lh_beam = Node3D.new(); lh_beam.position = Vector3(LX + 28.0, lamp_y, (jz0 + jz1) * 0.5); add_child(lh_beam)
	var bst := SurfaceTool.new(); bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 26.0
	for side in [1.0, -1.0]:
		var pts := [Vector3(0, -0.12, 0), Vector3(side * L, -1.6, 0), Vector3(side * L, 1.4, 0), Vector3(0, -0.12, 0), Vector3(side * L, 1.4, 0), Vector3(0, 0.12, 0)]
		var uvs := [Vector2(0, 0.5), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0.5), Vector2(1, 1), Vector2(0, 0.5)]
		for i in 6: bst.set_uv(uvs[i]); bst.add_vertex(pts[i])
	var bmi := MeshInstance3D.new(); bmi.mesh = bst.commit()
	var bm := ShaderMaterial.new(); bm.shader = Shader.new()
	bm.shader.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;\nvoid fragment() { float a = (1.0 - UV.x) * (1.0 - abs(UV.y - 0.5) * 2.0); ALBEDO = vec3(1.0, 0.82, 0.55) * 0.35 * a * a; }"
	bmi.material_override = bm; bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; bmi.layers = 512
	lh_beam.add_child(bmi); hide_in_mask.append(bmi)
	# 防波堤上的燈、繫船柱、岩石
	for jx in [LX + 9.0, LX + 16.0, LX + 23.0]: lamp_post(Vector3(jx, 0, jz0 + 0.45))
	var bx := lx1 + 1.5
	while bx < jx1 - 1.0:
		bollard(Vector3(bx, 0, jz1 - 0.3)); bx += 3.4
	for i in 14:
		var rn: String = ["pilot_rock_a", "pilot_rock_b", "pilot_rock_c"][i % 3]
		if not FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % rn)): continue
		var rx := rng.randf_range(lx1 + 1.0, LX + 32.0)
		var rz := jz0 - rng.randf_range(0.3, 1.4) if i % 2 == 0 else jz1 + rng.randf_range(0.3, 0.9)
		sprite(rn, Vector3(rx, WATER_Y - 0.15, rz), {"flat_lit": 0.25, "tilt": true, "flip": rng.randf() < 0.5, "scale": rng.randf_range(1.0, 1.4)})
	# 港邊的房子（板岩屋頂、窗戶亮燈）
	reg_on = true
	var wins := ["w_win_a", "w_win_a2", "w_win_b", "w_win_c", "windows_0", "windows_1"]
	for hs in [[LX - 34.0, LX - 28.0, -8.6, -4.2, 2.6, "z"], [LX - 26.5, LX - 20.0, -8.4, -5.0, 3.0, "x"], [LX - 18.0, LX - 12.5, -8.6, -4.6, 2.4, "z"], [LX - 10.5, LX - 3.5, -8.4, -5.2, 2.8, "x"], [LX - 1.5, LX + 3.4, -8.6, -4.8, 2.2, "z"]]:
		var w: float = hs[1] - hs[0]
		var items := [["w_door_a" if rng.randf() < 0.5 else "doors_1", "f", rng.randf_range(-w * 0.25, w * 0.25), 0.3, 0.0]]
		for k in int(w / 1.6):
			var ox := -w * 0.5 + 0.9 + k * 1.6
			if absf(ox - items[0][2]) > 0.8: items.append([wins[rng.randi() % wins.size()], "f", ox, 0.55, 0.9 if rng.randf() < 0.7 else 0.0])
			if hs[4] > 2.4: items.append([wins[rng.randi() % wins.size()], "f", ox, hs[4] - 0.9, 0.9 if rng.randf() < 0.6 else 0.0])
		house({"x0": hs[0], "x1": hs[1], "zb": hs[2], "zf": hs[3], "h": hs[4], "rh": 1.4, "ridge": hs[5],
			"tint": Color(rng.randf_range(0.9, 1.0), rng.randf_range(0.86, 0.94), rng.randf_range(0.8, 0.9)),
			"wall": ["plaster2", "stonewall", "plaster"][rng.randi() % 3], "roof": "w_roof_slate2", "roof_tint": Color(0.85, 0.85, 1.0),
			"chimney": Vector2(rng.randf_range(-1.0, 1.0), -0.5), "lights": true, "items": items})
		smoke(Vector3((hs[0] + hs[1]) * 0.5, hs[4] + 1.8, (hs[2] + hs[3]) * 0.5 - 0.5))
		wall_lantern(Vector3(hs[0] + 0.4, 1.0, hs[3] + 0.02), 0.0, 1.0)
	for lp in [LX - 30.0, LX - 20.0, LX - 10.0, LX + 1.0]: lamp_post(Vector3(lp, 0, 1.9))
	# 碼頭上的東西
	var props := ["pilot_harbor_a", "pilot_harbor_b", "pilot_harbor_c"]
	for pp in [[LX - 24.0, -2.6, 0], [LX - 15.0, -3.0, 1], [LX - 14.0, -2.8, 2], [LX - 2.0, -3.2, 0], [LX - 8.0, 0.6, 2]]:
		var pn: String = props[pp[2]]
		if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/%s.png" % pn)):
			sprite(pn, Vector3(pp[0], 0, pp[1]), {"flat_lit": 0.3, "tilt": true, "flip": rng.randf() < 0.5})
			contact_shadow(Vector3(pp[0], 0, pp[1] - 0.05), 0.75, 0.32, 0.5)
			zone_circles.append([pp[0], pp[1], 0.6])
	for b in [[LX - 22.5, -3.0], [LX - 22.0, -3.3], [LX - 5.0, -3.5], [LX + 2.5, 0.2]]: barrel(Vector3(b[0], 0, b[1]))
	crate(Vector3(LX - 12.6, 0, -3.4), 0.6, 8.0); crate(Vector3(LX - 12.0, 0, -3.6), 0.5, -12.0)
	bench(Vector3(LX - 17.0, 0, 0.9), 0.0)
	var cb := QUAY_Z - 0.34
	var bx2 := x0 + 2.0
	while bx2 < lx1 - 0.5:
		if absf(bx2 - (LX - 6.0)) > 1.6: bollard(Vector3(bx2, 0, cb))
		bx2 += 3.0
	reg_on = false
	# 停在港邊的漁船
	fishing_boat(Vector3(LX - 20.0, WATER_Y - 0.05, QUAY_Z + 1.25), 1.0)
	fishing_boat(Vector3(LX + 12.0, WATER_Y - 0.05, jz0 - 1.5), -1.0, 0.9)
	# 防波堤上釣魚的人、海鷗
	var fn := sprite("pilot_fisher_anim", Vector3(LX + 19.0, 0, jz1 - 0.15), {"tilt": true, "flat_lit": 0.2, "frame_fixed": 0.0, "scale": 0.75})
	contact_shadow(Vector3(LX + 19.0, 0, jz1 - 0.2), 0.45, 0.25, 0.5)
	zone_npcs.append({"m": fn.material_override, "n": int(meta.get("pilot_fisher_anim_frames", 1)), "dt": 0.8})
	zone_circles.append([LX + 19.0, jz1 - 0.15, 0.3])
	var gname := "pilot_gull" if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/pilot_gull.png")) else "bird"
	for i in 6:
		var g := sprite(gname, Vector3.ZERO, {"fps": 5.0 + rng.randf() * 2.0, "shadow": false, "center": true, "tilt": true, "flat_lit": 0.6, "glow_all": 0.1, "scale": 0.7})
		flyers.append({"n": g, "kind": "gull", "c": Vector3(LX + rng.randf_range(-20.0, 30.0), rng.randf_range(4.0, 7.0), rng.randf_range(-6.0, 3.0)), "r": rng.randf_range(2.0, 5.0), "v": rng.randf_range(0.25, 0.45) * (1.0 if i % 2 else -1.0), "p": rng.randf() * TAU})


# ------------------------------------------------------------------ 立體化（2026-11-18）：漁船、燈塔改成 3D 模型＋點陣貼圖；平面道具加貼地的接觸陰影
var sh_blob: Shader
func contact_shadow(p: Vector3, rx: float, rz: float, a := 0.45) -> void:
	if not sh_blob:
		sh_blob = Shader.new()
		sh_blob.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;\nuniform float a = 0.45;\nvoid fragment() { vec2 d = UV * 2.0 - 1.0; float r = dot(d, d); ALBEDO = vec3(0.04, 0.03, 0.08); ALPHA = a * clamp(1.0 - r, 0.0, 1.0) * clamp(1.0 - r, 0.0, 1.0); }"
	var q := QuadMesh.new(); q.size = Vector2(rx * 2.0, rz * 2.0); q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new(); mi.mesh = q
	var m := ShaderMaterial.new(); m.shader = sh_blob; m.set_shader_parameter("a", a); m.render_priority = -1
	mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = p + Vector3(0, 0.008, 0)
	add_child(mi); hide_in_mask.append(mi)

# 漁船：船殼上紅下白（中間一條藍線）、甲板、駕駛艙（窗戶亮燈）、桅杆＋捲起的帆、船舷掛輪胎
func fishing_boat(pos: Vector3, face: float, s := 1.0) -> void:
	var root := Node3D.new(); root.position = pos; root.rotation.y = 0.0 if face > 0.0 else PI; root.scale = Vector3.ONE * s
	add_child(root)
	var keep := parent_node; parent_node = root
	var gr := geo("planks"); var gw := geo("planks"); var gbl := geo("planks"); var gd := geo("planks")
	var n := 12; var L := 5.2
	var sec: Array = []
	for i in n + 1:
		var u := float(i) / n
		var hw := 0.95 * pow(sin(PI * (0.08 + 0.9 * u)), 0.6)
		var top := 0.95 + 0.35 * u * u * u + 0.1 * (1.0 - u) * (1.0 - u)
		sec.append([-L * 0.5 + L * u, hw, top])
	for i in n:
		var a: Array = sec[i]; var b: Array = sec[i + 1]
		for sg in [-1.0, 1.0]:
			var a0 := Vector3(a[0], -0.25, sg * a[1] * 0.45); var b0 := Vector3(b[0], -0.25, sg * b[1] * 0.45)
			var a1 := Vector3(a[0], 0.32, sg * a[1] * 0.92); var b1 := Vector3(b[0], 0.32, sg * b[1] * 0.92)
			var a2 := Vector3(a[0], 0.4, sg * a[1] * 0.95); var b2 := Vector3(b[0], 0.4, sg * b[1] * 0.95)
			var a3 := Vector3(a[0], a[2], sg * a[1]); var b3 := Vector3(b[0], b[2], sg * b[1])
			var a4 := Vector3(a[0], 0.75, sg * a[1] * 0.9); var b4 := Vector3(b[0], 0.75, sg * b[1] * 0.9)
			if sg > 0:
				gw.quad(a0, b0, b1, a1); gbl.quad(a1, b1, b2, a2); gr.quad(a2, b2, b3, a3); gd.quad(b4, a4, a3, b3)
			else:
				gw.quad(b0, a0, a1, b1); gbl.quad(b1, a1, a2, b2); gr.quad(b2, a2, a3, b3); gd.quad(a4, b4, b3, a3)
		gd.quad(Vector3(a[0], 0.75, a[1] * 0.9), Vector3(b[0], 0.75, b[1] * 0.9), Vector3(b[0], 0.75, -b[1] * 0.9), Vector3(a[0], 0.75, -a[1] * 0.9))
	var s0: Array = sec[0]
	gr.quad(Vector3(s0[0], 0.4, -s0[1]), Vector3(s0[0], 0.4, s0[1]), Vector3(s0[0], s0[2], s0[1]), Vector3(s0[0], s0[2], -s0[1]))
	gw.quad(Vector3(s0[0], -0.25, -s0[1] * 0.45), Vector3(s0[0], -0.25, s0[1] * 0.45), Vector3(s0[0], 0.4, s0[1] * 0.95), Vector3(s0[0], 0.4, -s0[1] * 0.95))
	put(gr, "planks", {"tint": Color(0.95, 0.32, 0.28)})
	put(gw, "planks", {"tint": Color(1.25, 1.2, 1.15)})
	put(gbl, "planks", {"tint": Color(0.35, 0.5, 0.95)})
	put(gd, "planks", {"tint": Color(1.1, 0.92, 0.8), "glow_all": 0.05}, false)
	# 駕駛艙
	var gc := geo("planks")
	gc.box(Vector3(-0.3, 0.75, 0), Vector3(1.3, 1.0, 1.0))
	put(gc, "planks", {"tint": Color(0.85, 0.66, 0.56)})
	var gcr := geo("w_roof_red2")
	gcr.box(Vector3(-0.3, 1.75, 0), Vector3(1.45, 0.1, 1.15))
	put(gcr, "w_roof_red2", {"tint": Color(0.8, 0.7, 0.75)})
	var gwin := geo("lantern")
	gwin.box(Vector3(-0.3, 1.15, 0.5), Vector3(0.45, 0.35, 0.03), false, 1)
	put(gwin, "lantern", {"emit": 2.0, "glow_all": 0.5, "lit": 0.0}, false)
	# 桅杆、橫桁、捲起的帆、繩索
	var gm := geo("wood")
	gm.box(Vector3(0.9, 0.75, 0), Vector3(0.1, 3.0, 0.1))
	gm.box(Vector3(0.9, 2.6, 0), Vector3(1.8, 0.07, 0.07))
	gm.prism(Vector3(0.9, 2.45, 0), 0.09, 0.12, 6)
	put(gm, "wood", {"tint": Color(0.7, 0.55, 0.45)})
	var gs := geo("cloth")
	gs.box(Vector3(0.9, 2.5, 0), Vector3(1.6, 0.14, 0.16))
	put(gs, "cloth", {"tint": Color(1.2, 1.12, 1.0)})
	# 船舷的輪胎
	var gt := geo("barreltop")
	for k in 4:
		var tx := -1.6 + k * 1.05
		gt.box(Vector3(tx, 0.3, 0.98), Vector3(0.36, 0.36, 0.08), false, 1)
	put(gt, "barreltop", {"tint": Color(0.25, 0.22, 0.26)})
	parent_node = keep
	pixel_wire(root.to_global(Vector3(0.9, 3.7, 0)), root.to_global(Vector3(2.55, 1.35, 0)), 0.05, [], 1.0, Color(0.3, 0.24, 0.2))
	pixel_wire(root.to_global(Vector3(0.9, 3.7, 0)), root.to_global(Vector3(-2.5, 1.0, 0)), 0.08, [], 1.0, Color(0.3, 0.24, 0.2))
	if FileAccess.file_exists(ProjectSettings.globalize_path("res://tex/pilot_harbor_a.png")):
		sprite("pilot_harbor_a", root.to_global(Vector3(-1.7, 0.75, 0.1)), {"flat_lit": 0.3, "tilt": true, "scale": 0.7, "shadow": false})
	omni(root.to_global(Vector3(-0.3, 1.2, 0.9)), Color(1.0, 0.65, 0.35), 0.8, 2.5, false, 0.5)

# 燈塔：石砌圓台、往上收窄的白色塔身（紅色帶）、拱窗、環形陽台、玻璃燈室、紅色圓錐屋頂、風向標
func lighthouse3d(c: Vector3) -> float:
	var keep := parent_node; parent_node = self
	var gb := geo("w_stone")
	gb.prism(c, 1.7, 0.9, 14)
	gb.disc(c + Vector3(0, 0.9, 0), 1.7, 14)
	put(gb, "w_stone", {"tint": Color(0.85, 0.8, 0.92)})
	var n := 16
	var y0 := 0.9; var y1 := 6.3; var r0 := 1.1; var r1 := 0.82
	var gt := geo("stonewall"); var gred := geo("brick")
	for i in n:
		var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
		for band in [[y0, 4.9, gt], [4.9, 5.6, gred], [5.6, y1, gt]]:
			var ya: float = band[0]; var yb: float = band[1]; var g: Geo = band[2]
			var ra := lerpf(r0, r1, (ya - y0) / (y1 - y0)); var rb := lerpf(r0, r1, (yb - y0) / (y1 - y0))
			g.uo = Vector2(float(i) * 0.2, 0)
			g.quad(c + Vector3(cos(a1) * ra, ya, sin(a1) * ra), c + Vector3(cos(a0) * ra, ya, sin(a0) * ra), c + Vector3(cos(a0) * rb, yb, sin(a0) * rb), c + Vector3(cos(a1) * rb, yb, sin(a1) * rb))
	put(gt, "stonewall", {"tint": Color(1.45, 1.42, 1.38), "grime": 0.5, "wall_top": y1})
	put(gred, "brick", {"tint": Color(1.0, 0.45, 0.42)})
	# 拱窗（亮燈）：正面三扇
	var gwin := geo("lantern")
	for wy in [2.0, 3.3, 4.5]:
		var rr := lerpf(r0, r1, (wy - y0) / (y1 - y0))
		gwin.box(c + Vector3(0, wy, rr - 0.03), Vector3(0.3, 0.5, 0.06), false, 1)
	put(gwin, "lantern", {"emit": 1.6, "glow_all": 0.5, "lit": 0.0}, false)
	# 陽台＋欄杆
	var gg := geo("w_stone")
	gg.prism(c + Vector3(0, y1, 0), 1.18, 0.12, n)
	gg.disc(c + Vector3(0, y1 + 0.12, 0), 1.18, n)
	put(gg, "w_stone", {"tint": Color(0.6, 0.58, 0.68)})
	var grl := geo("wood")
	for i in 24:
		var a := TAU * i / 24.0
		grl.box(c + Vector3(cos(a) * 1.12, y1 + 0.12, sin(a) * 1.12), Vector3(0.04, 0.42, 0.04))
	for i in 24:
		var a0 := TAU * i / 24.0; var a1 := TAU * (i + 1) / 24.0
		var pa := c + Vector3(cos(a0) * 1.12, y1 + 0.52, sin(a0) * 1.12); var pb := c + Vector3(cos(a1) * 1.12, y1 + 0.52, sin(a1) * 1.12)
		grl.quad(pa, pb, pb + Vector3(0, 0.05, 0), pa + Vector3(0, 0.05, 0))
	put(grl, "wood", {"tint": Color(0.18, 0.16, 0.2)})
	# 燈室：發光的玻璃柱＋深色窗框
	var gl := geo("lantern")
	gl.prism(c + Vector3(0, y1 + 0.12, 0), 0.62, 0.95, 10)
	put(gl, "lantern", {"emit": 3.5, "glow_all": 0.8, "lit": 0.0}, false)
	var gf := geo("wood")
	for i in 10:
		var a := TAU * i / 10.0
		gf.box(c + Vector3(cos(a) * 0.63, y1 + 0.12, sin(a) * 0.63), Vector3(0.05, 0.95, 0.05))
	gf.prism(c + Vector3(0, y1 + 1.05, 0), 0.7, 0.08, 10)
	put(gf, "wood", {"tint": Color(0.16, 0.14, 0.18)})
	# 屋頂（圓錐）與風向標
	var gr := geo("w_roof_red2")
	var ry := y1 + 1.13
	for i in 12:
		var a0 := TAU * i / 12.0; var a1 := TAU * (i + 1) / 12.0
		gr.tri(c + Vector3(cos(a1) * 0.82, ry, sin(a1) * 0.82), c + Vector3(cos(a0) * 0.82, ry, sin(a0) * 0.82), c + Vector3(0, ry + 0.75, 0))
	put(gr, "w_roof_red2", {"tint": Color(1.05, 0.8, 0.8)})
	var gv := geo("wood")
	gv.box(c + Vector3(0, ry + 0.7, 0), Vector3(0.03, 0.5, 0.03))
	gv.box(c + Vector3(0.05, ry + 1.1, 0), Vector3(0.36, 0.03, 0.03))
	put(gv, "wood", {"tint": Color(0.16, 0.14, 0.18)})
	parent_node = keep
	return y1 + 0.6


# ------------------------------------------------------------------ 涵洞過場（轉向動畫）：船駛向山壁裡的拱形涵洞，鏡頭從側面繞到船後方，穿過點著壁燈的涵洞，出口的光越來越亮，再換到下一站
const TUN_X := 1500.0
const TUN_L := 20.0
var tun_on := false
var tun_t := 0.0
var tun_dir := 1.0
var tun_next := 0
var tun_rel0 := Vector3.ZERO
var tun_glow: Array = []
var tun_glow_mat: ShaderMaterial

func build_tunnel() -> void:
	rng.seed = 6060
	parent_node = self
	var x0 := TUN_X; var x1 := TUN_X + TUN_L
	var zc := LANE_Z; var hw := 1.6; var spring := 1.2; var R := hw
	var rock := tex_or("pilot_valley_rock", "stonewall")
	# 水面（倒影較強，壁燈的光會映在水上）
	var dwm: ShaderMaterial = water_mat.duplicate()
	dwm.set_shader_parameter("strength", 0.5)
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(TUN_L + 32.0, 12.0)
	water.mesh = wm; water.material_override = dwm
	water.position = Vector3((x0 + x1) * 0.5, WATER_Y, zc); water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water); hide_in_mask.append(water)
	# 山體：涵洞兩側與上方的岩塊；涵洞外的兩端是一段開放的運河（遠岸有岩壁與苔地）
	var gh := geo(rock)
	gh.box(Vector3((x0 + x1) * 0.5, WATER_Y - 0.4, (zc - hw - 0.4 + zc - 24.0) * 0.5), Vector3(TUN_L, 5.2 - WATER_Y + 0.4, 24.0 - hw - 0.4))     # 後側山體
	gh.box(Vector3((x0 + x1) * 0.5, WATER_Y - 0.4, (zc + hw + zc + 18.0) * 0.5), Vector3(TUN_L, 4.6 - WATER_Y + 0.4, 18.0 - hw))              # 前側山體（一路延伸到鏡頭外：只能從涵洞過去）
	for ex in [[x0 - 16.0, x0], [x1, x1 + 16.0]]:
		gh.box(Vector3((ex[0] + ex[1]) * 0.5, WATER_Y - 0.4, (zc + hw + 0.3 + zc + 18.0) * 0.5), Vector3(ex[1] - ex[0], 0.35 - WATER_Y + 0.4, 18.0 - hw - 0.3))      # 涵洞外近岸（窄水道）
	gh.box(Vector3((x0 + x1) * 0.5, spring + R + 0.15, zc), Vector3(TUN_L, 4.0 - spring - R - 0.15, 2.0 * hw + 0.02))                     # 拱頂上方
	for ex in [[x0 - 16.0, x0], [x1, x1 + 16.0]]:
		gh.box(Vector3((ex[0] + ex[1]) * 0.5, WATER_Y - 0.4, zc - hw - 3.0), Vector3(ex[1] - ex[0], 1.0 - WATER_Y + 0.4 + 0.4, 5.0))     # 涵洞外遠岸的低岩壁
	put(gh, rock, {"tint": Color(0.82, 0.76, 0.88)})
	var gm := geo(tex_or("pilot_valley_moss", "grass"))
	gm.quad(Vector3(x0, 5.2, zc - hw - 0.4), Vector3(x1, 5.2, zc - hw - 0.4), Vector3(x1, 5.2, zc - 24.0), Vector3(x0, 5.2, zc - 24.0))
	gm.quad(Vector3(x0, 4.6, zc + 18.0), Vector3(x1, 4.6, zc + 18.0), Vector3(x1, 4.6, zc + hw), Vector3(x0, 4.6, zc + hw))
	gm.quad(Vector3(x0, 4.0, zc + hw), Vector3(x1, 4.0, zc + hw), Vector3(x1, 4.0, zc - hw - 0.4), Vector3(x0, 4.0, zc - hw - 0.4))
	for ex in [[x0 - 16.0, x0], [x1, x1 + 16.0]]:
		gm.quad(Vector3(ex[0], 0.355, zc + 18.0), Vector3(ex[1], 0.355, zc + 18.0), Vector3(ex[1], 0.355, zc + hw + 0.3), Vector3(ex[0], 0.355, zc + hw + 0.3))
	for ex in [[x0 - 16.0, x0], [x1, x1 + 16.0]]:
		gm.quad(Vector3(ex[0], 1.4, zc - hw - 0.5), Vector3(ex[1], 1.4, zc - hw - 0.5), Vector3(ex[1], 1.4, zc - hw - 5.5), Vector3(ex[0], 1.4, zc - hw - 5.5))
	put(gm, tex_or("pilot_valley_moss", "grass"), {"tint": Color(0.9, 0.85, 0.82)}, false)
	# 涵洞內：兩側直牆＋半圓拱頂（法線朝內）、每 3 公尺一道凸出的拱肋
	var gi := geo("w_stone")
	gi.quad(Vector3(x1, WATER_Y - 0.4, zc - hw), Vector3(x0, WATER_Y - 0.4, zc - hw), Vector3(x0, spring, zc - hw), Vector3(x1, spring, zc - hw))
	gi.quad(Vector3(x0, WATER_Y - 0.4, zc + hw), Vector3(x1, WATER_Y - 0.4, zc + hw), Vector3(x1, spring, zc + hw), Vector3(x0, spring, zc + hw))
	gi.quad(Vector3(x0, WATER_Y - 0.4, zc - hw), Vector3(x1, WATER_Y - 0.4, zc - hw), Vector3(x1, WATER_Y - 0.4, zc - hw), Vector3(x0, WATER_Y - 0.4, zc - hw))
	var seg := 10
	for k in seg:
		var a0 := PI * k / seg; var a1 := PI * (k + 1) / seg
		var p0 := Vector3(0, spring + sin(a0) * R, zc + cos(a0) * R); var p1 := Vector3(0, spring + sin(a1) * R, zc + cos(a1) * R)
		gi.quad(Vector3(x0, p0.y, p0.z), Vector3(x1, p0.y, p0.z), Vector3(x1, p1.y, p1.z), Vector3(x0, p1.y, p1.z))
	put(gi, "w_stone", {"tint": Color(0.62, 0.56, 0.66)})
	var gr := geo("w_stone")
	var rx := x0
	while rx <= x1 + 0.01:
		for k in seg:
			var a0 := PI * k / seg; var a1 := PI * (k + 1) / seg
			var r2 := R - 0.12
			var p0 := Vector3(rx, spring + sin(a0) * r2, zc + cos(a0) * r2); var p1 := Vector3(rx, spring + sin(a1) * r2, zc + cos(a1) * r2)
			for side in [-0.18, 0.18]:
				var q0 := p0 + Vector3(side, 0, 0); var q1 := p1 + Vector3(side, 0, 0)
				var o0 := Vector3(rx + side, spring + sin(a0) * R, zc + cos(a0) * R); var o1 := Vector3(rx + side, spring + sin(a1) * R, zc + cos(a1) * R)
				if side < 0: gr.quad(o0, q0, q1, o1)
				else: gr.quad(q0, o0, o1, q1)
			gr.quad(Vector3(rx - 0.18, p0.y, p0.z), Vector3(rx + 0.18, p0.y, p0.z), Vector3(rx + 0.18, p1.y, p1.z), Vector3(rx - 0.18, p1.y, p1.z))
		for side in [-1.0, 1.0]:
			gr.box(Vector3(rx, WATER_Y - 0.4, zc + side * (hw - 0.06)), Vector3(0.36, spring - WATER_Y + 0.4, 0.12))
		rx += 3.0
	put(gr, "w_stone", {"tint": Color(0.82, 0.76, 0.86)})
	# 兩端洞口的拱石框（面向外）
	var gp := geo("w_stone")
	for ex in [[x0, -1.0], [x1, 1.0]]:
		var px: float = ex[0]; var sd: float = ex[1]
		for k in 9:
			var a := PI * (k + 0.5) / 9.0
			var cc := Vector3(px + sd * 0.12, spring + sin(a) * (R + 0.2), zc + cos(a) * (R + 0.2))
			gp.box(cc - Vector3(0, 0.15, 0), Vector3(0.3, 0.3, 0.42))
		# 拱腳到地面之間的洞口側邊
		for side in [-1.0, 1.0]:
			gp.box(Vector3(px + sd * 0.12, WATER_Y - 0.4, zc + side * (hw + 0.2)), Vector3(0.3, spring - WATER_Y + 0.4, 0.42))
	put(gp, "w_stone", {"tint": Color(1.0, 0.94, 1.0)})
	# 洞口兩角（拱圈外、方形山壁內）填滿
	var gf := geo(rock)
	for ex in [[x0, -1.0], [x1, 1.0]]:
		var px: float = ex[0]; var sd: float = ex[1]
		for k in seg:
			var a0 := PI * k / seg; var a1 := PI * (k + 1) / seg
			var pa := Vector3(px, spring + sin(a0) * R, zc + cos(a0) * R); var pb := Vector3(px, spring + sin(a1) * R, zc + cos(a1) * R)
			var ta := Vector3(px, spring + R + 0.16, pa.z); var tb := Vector3(px, spring + R + 0.16, pb.z)
			if sd < 0: gf.quad(pb, pa, ta, tb)
			else: gf.quad(pa, pb, tb, ta)
	put(gf, rock, {"tint": Color(0.82, 0.76, 0.88)})
	# 壁燈（3D：發光的小燈箱＋鐵架），兩側交錯，每盞一顆會閃的點光
	var gl := geo("lantern"); var gk := geo("wood")
	var lx := x0 + 2.0; var side := 1.0
	while lx < x1 - 1.0:
		var lz := zc + side * (hw - 0.18)
		gl.box(Vector3(lx, 0.95, lz), Vector3(0.18, 0.26, 0.18))
		gk.box(Vector3(lx, 1.2, lz), Vector3(0.24, 0.05, 0.24))
		gk.box(Vector3(lx, 1.15, zc + side * (hw - 0.06)), Vector3(0.05, 0.05, 0.2))
		omni(Vector3(lx, 1.0, zc + side * (hw - 0.4)), Color(1.0, 0.58, 0.28), 1.5, 4.0, false, 0.6, 0.08, 0.3)
		lx += 3.5; side = -side
	put(gl, "lantern", {"emit": 3.0, "glow_all": 0.8, "lit": 0.0}, false)
	put(gk, "wood", {"tint": Color(0.18, 0.15, 0.2)})
	# 出口的光：洞口外一片發光的面（顏色依下一站：黃昏暖光／藍調）
	tun_glow_mat = ShaderMaterial.new(); tun_glow_mat.shader = Shader.new()
	tun_glow_mat.shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;\nuniform vec3 col = vec3(1.0, 0.75, 0.45);\nuniform float k = 1.0;\nvoid fragment() { float v = 1.0 - UV.y * 0.35; ALBEDO = col * k * v; }"
	for ex in [[x1 + 0.5, -1.0], [x0 - 0.5, 1.0]]:
		var q := QuadMesh.new(); q.size = Vector2(2.0 * hw + 0.6, spring + R - WATER_Y + 0.6)
		var g := MeshInstance3D.new(); g.mesh = q; g.material_override = tun_glow_mat
		g.position = Vector3(ex[0], (spring + R + WATER_Y) * 0.5, zc); g.rotation.y = ex[1] * PI * 0.5
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; g.visible = false
		add_child(g); tun_glow.append(g)

func tunnel_cam(p: float) -> void:
	# p：0 = 原本的側面鏡頭（相對船的位置不變）→ 1 = 船正後方、略高
	var bp := boat.position
	var behind := Vector3(-tun_dir * 5.6, 2.05, 0.0)
	var r0 := Vector2(tun_rel0.x, tun_rel0.z); var r1 := Vector2(behind.x, behind.z)
	var a := lerp_angle(r0.angle(), r1.angle(), p)
	var d := lerpf(r0.length(), r1.length(), p)
	var h := lerpf(tun_rel0.y, behind.y, p)
	var cp := bp + Vector3(cos(a) * d, h, sin(a) * d)
	var tgt0 := bp + Vector3(1.7, 0.4, -2.2); var tgt1 := bp + Vector3(tun_dir * 6.0, 0.55, 0.0)
	cam.look_at_from_position(cp, tgt0.lerp(tgt1, p), Vector3.UP)

func tunnel_start(next: int, dirn: float) -> void:
	if not cam_basis_set: cam_basis0 = cam.global_transform.basis; cam_basis_set = true
	tun_rel0 = cam.global_position - boat.position
	tun_on = true; tun_t = 0.0; tun_dir = dirn; tun_next = next
	boat.position = Vector3(TUN_X - 9.0 if dirn > 0.0 else TUN_X + TUN_L + 9.0, boat.position.y, LANE_Z)
	boat.rotation.y = 0.0 if dirn > 0.0 else PI
	boat_vel = dirn * 3.2
	for g in tun_glow: g.visible = false
	tun_glow[0 if dirn > 0.0 else 1].visible = true
	var nt: float = STAGES[next].get("night", 0.0)
	tun_glow_mat.set_shader_parameter("col", Vector3(1.0, 0.72, 0.42).lerp(Vector3(0.5, 0.58, 1.0), nt))
	for f in frame_nodes: f[0].visible = false
	if dof_node: dof_node.visible = false
	for n in sky_nodes: n.visible = false
	streak_cam_x = INF
	tunnel_cam(0.0)

func tunnel_update(dt: float) -> void:
	tun_t += dt
	boat.position.x += boat_vel * dt
	var bp := boat.position
	# 鏡頭：前 2.4 秒從側面繞到船後
	var p := smoothstep(0.0, 2.4, tun_t)
	tunnel_cam(p)
	# 主角：面向鏡頭的看板；轉到後面以後換成背影
	var hp := Vector3(bp.x, bp.y + 0.32, bp.z)
	move_sprite(hero_n, hp)
	var cp := cam.global_position
	hero_n.rotation = Vector3(-deg_to_rad(PITCH) * (1.0 - p) * 0.6, atan2(cp.x - hp.x, cp.z - hp.z), 0.0)
	hero_n.scale.x = absf(hero_n.scale.x) * (-1.0 if (tun_dir > 0.0 and p < 0.5) else 1.0)
	if p >= 0.5 and walk_dir != "back":
		walk_dir = "back"; hero_tex("pilot_hero_walk_back"); hero_m.set_shader_parameter("frame_fixed", 1.0)
	# 出口的光隨距離變亮；快到出口時白幕
	var dist_end := (TUN_X + TUN_L - bp.x) if tun_dir > 0.0 else (bp.x - TUN_X)
	tun_glow_mat.set_shader_parameter("k", lerpf(0.9, 2.2, clampf(1.0 - dist_end / TUN_L, 0.0, 1.0)))
	if dist_end < 2.5 and passage == 0.0:
		fade_rect.color = Color(1.0, 0.92, 0.8, fade_a)
		passage = 2.0 * tun_dir

func tunnel_end() -> void:
	tun_on = false
	hero_n.rotation = Vector3(-deg_to_rad(PITCH), 0.0, 0.0)
	walk_dir = "side"; hero_tex("pilot_hero_walk_side"); hero_m.set_shader_parameter("frame_fixed", 1.0)
	if dof_node: dof_node.visible = true
	boat_vel = tun_dir * 4.0
	enter_stage(tun_next, tun_dir)
	await get_tree().create_timer(1.0).timeout
	if passage == 0.0: fade_rect.color = Color(0.02, 0.01, 0.03, fade_a)
