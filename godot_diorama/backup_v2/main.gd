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

const MAT_KEYS := ["blink", "breathe", "gust_x", "frame_fixed", "rim", "sway_px", "vsway_px", "rustle_px", "emit", "glow_all", "backlight", "tint", "rough", "fps", "lit", "flat_lit"]

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
	func box(c: Vector3, s: Vector3, rand_uv := true) -> void:
		var x0 := c.x - s.x * 0.5; var x1 := c.x + s.x * 0.5
		var y0 := c.y; var y1 := c.y + s.y
		var z0 := c.z - s.z * 0.5; var z1 := c.z + s.z * 0.5
		if rand_uv: uo = Vector2(floorf(c.x * 7.0) * 0.137, floorf(c.z * 5.0) * 0.211)      # 每個盒子的貼圖起點錯開，避免同一塊花紋重複
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1))
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0))
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0))
		quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1))
		quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0))
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
	var cast: bool = h.get("cast", true)
	var wall_tex: String = h.get("wall", "plaster2")
	var wtint: Color = h.get("tint", Color(1, 0.9, 0.78))
	var base_h := 0.3
	var gb := geo("stonewall")
	gb.box(Vector3(x, 0, zc), Vector3(w + 0.1, base_h, d + 0.1))
	put(gb, "stonewall", {"tint": Color(0.95, 0.88, 0.85), "grime": 0.6, "wall_top": 3.0}, cast)
	var gw := geo(wall_tex)
	gw.box(Vector3(x, base_h, zc), Vector3(w, wh - base_h, d))
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
		gu.box(Vector3(x, uy, zc), Vector3(w + e * 2, wh - uy, d + e * 2))
		if h.ridge == "z":
			gu.tri(Vector3(x0 - e, wh, zf + e), Vector3(x1 + e, wh, zf + e), Vector3(x, wh + rh - 0.02, zf + e))
			gu.tri(Vector3(x1 + e, wh, zb - e), Vector3(x0 - e, wh, zb - e), Vector3(x, wh + rh - 0.02, zb - e))
		else:
			gu.tri(Vector3(x0 - e, wh, zb - e), Vector3(x0 - e, wh, zf + e), Vector3(x0 - e, wh + rh - 0.02, zc))
			gu.tri(Vector3(x1 + e, wh, zf + e), Vector3(x1 + e, wh, zb - e), Vector3(x1 + e, wh + rh - 0.02, zc))
		put(gu, "plaster2", {"tint": h.get("upper_tint", Color(1, 0.93, 0.8)), "grime": 0.8, "wall_top": wh + rh * 0.5}, cast).layers = 17
		var gt := geo("planks")
		var bw := 0.1
		# 正面與左側面的木骨架（鏡頭看得到的兩面）
		var zt := zf + e
		gt.box(Vector3(x, uy - 0.05, zt), Vector3(w + e * 2 + 0.08, 0.14, 0.1))
		gt.box(Vector3(x, wh - 0.1, zt), Vector3(w + e * 2 + 0.04, 0.1, 0.1))
		for bx in [x0 - e + 0.02, x1 + e - 0.02, x - w * 0.17, x + w * 0.17]:
			gt.box(Vector3(bx, uy, zt), Vector3(bw, wh - uy, 0.1))
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
	put(gr, roof_tex, {"tint": rt, "rough": 0.8, "moss": h.get("moss", 0.7)}, cast).layers = 33
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
func tree(pos: Vector3, kinds: Array, n: int, spread: Vector3, cy: float, gap := 0.9, trunk_shadow := true, flip := false) -> void:
	sprite("trunk", pos, {"flat_lit": 0.4, "shadow": trunk_shadow, "flip": flip})
	for i in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf())
		var p := pos + Vector3(cos(a) * r * spread.x, cy + rng.randf_range(-1.0, 1.0) * spread.y * sqrt(1.0 - r * r * 0.7), sin(a) * r * spread.z)
		# 樹冠留一道缺口：夕陽穿過缺口，在主角腳邊落下一塊光池（缺口寬度以垂直光線方向的距離計）
		var perp := Vector3(sun_dir.z, 0, -sun_dir.x).normalized()
		var dn := (p - HERO).dot(perp)
		if absf(dn) < gap: continue
		sprite(kinds[i % kinds.size()], p, {"center": true, "tilt": true, "vsway_px": 4.0, "gust_x": pos.x, "rustle_px": 1.0, "flat_lit": 0.16, "glow_all": 0.04, "flip": rng.randf() < 0.5, "shadow_off": 0.0})

# ------------------------------------------------------------------ 3D 小道具（方塊＋像素貼圖 → 有受光面與陰影面）
func barrel(pos: Vector3) -> void:
	var g := geo("barrel")
	g.prism(pos, 0.28, 0.625, 10)
	put(g, "barrel", {"tint": Color(1.0, 0.92, 0.88)})
	var gt := geo("barreltop")
	gt.disc(pos + Vector3(0, 0.6, 0), 0.26, 10)
	put(gt, "barreltop", {}, false)

func crate(pos: Vector3, s := 0.6875, yaw := 0.0) -> void:
	var g := geo("crate")
	g.box(Vector3.ZERO, Vector3(s, s, s), false)
	var mi := put(g, "crate", {"tint": Color(1.0, 0.95, 0.9)})
	mi.position = pos; mi.rotation.y = deg_to_rad(yaw)

func bench(pos: Vector3, yaw := 0.0) -> void:
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
		dm.set_shader_parameter("far_start", depth0 + argf("df", 4.6))
		dm.set_shader_parameter("far_trans", 6.0)
		dm.set_shader_parameter("max_r", 13.0)
		dm.set_shader_parameter("far_r", 5.0)
		dm.render_priority = 0
		dq.material_override = dm
		dq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dq.layers = 512
		dq.extra_cull_margin = 16384.0
		cam.add_child(dq)
		dq.position = Vector3(0, 0, -1.0)

func build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.13, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.4, 0.78)      # 陰影區：冷紫藍
	env.ambient_light_energy = argf("amb", 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = argf("exp", 1.04)
	env.tonemap_white = 6.0
	env.glow_enabled = true
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
	env.ssil_intensity = 0.8
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
	gr.colors = PackedColorArray([Color(0.022, 0.03, 0.075), Color(0.22, 0.24, 0.315), Color(0.59, 0.61, 0.58), Color(1.0, 0.99, 0.88)])
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
	sun.light_energy = argf("sun", 10.0)
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
	fill.light_color = Color(1.0, 0.8, 0.72)
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
		env.fog_light_color = Color(0.62, 0.42, 0.5)
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.0
		env.fog_density = argf("haze", 0.42)
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
	ground_mat.set_shader_parameter("tex", tex("plaza"))
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
	gl.quad(Vector3(-40, LOW_Y, BACK_Z), Vector3(40, LOW_Y, BACK_Z), Vector3(40, LOW_Y, -60), Vector3(-40, LOW_Y, -60))
	put(gl, "cobble", {"tint": Color(0.5, 0.45, 0.6)}, false)
	var gr2 := geo("stonewall")
	gr2.quad(Vector3(16, LOW_Y, BACK_Z), Vector3(-16, LOW_Y, BACK_Z), Vector3(-16, 0, BACK_Z), Vector3(16, 0, BACK_Z))
	put(gr2, "stonewall", {"tint": Color(0.8, 0.75, 0.9)}, false)
	# 堤岸牆（砌石、苔、水線污痕）
	var gq := geo("quay")
	gq.uo = Vector2(0.13, 0)
	gq.quad(Vector3(-12, WATER_Y - 0.3, QUAY_Z), Vector3(12, WATER_Y - 0.3, QUAY_Z), Vector3(12, 0, QUAY_Z), Vector3(-12, 0, QUAY_Z))
	put(gq, "quay", {"tint": Color(1.35, 1.2, 1.3), "ground_mask": 1.0}).layers = 17
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
	var wm := PlaneMesh.new(); wm.size = Vector2(44, 12)
	water.mesh = wm
	var wmat := ShaderMaterial.new(); wmat.shader = load("res://shaders/water.gdshader")
	wmat.set_shader_parameter("refl", make_mirror(WATER_Y, 1024, 2 | 256))
	if has("--no-refl"): wmat.set_shader_parameter("strength", 0.0)
	var ss: Array = [Vector4(-1.55, QUAY_Z + 1.05, 0.05, 0.8), Vector4(7.1, 1.9, 0.09, 0.75), Vector4(-5.3, -0.9, 0.12, 0.5), Vector4(1.4, -4.6, 0.3, 0.45), Vector4(6.35, -4.3, 0.4, 0.5), Vector4(10.7, 1.0, 0.1, 0.7), Vector4(-0.95, -4.3, 0.08, 0.5)]
	var sc: Array = [Vector4(1.0, 0.45, 0.1, 2.4), Vector4(1.0, 0.5, 0.13, 7.0), Vector4(1.0, 0.5, 0.15, 9.0), Vector4(1.0, 0.45, 0.12, 12.5), Vector4(1.0, 0.5, 0.14, 12.5), Vector4(1.0, 0.5, 0.13, 7.0), Vector4(1.0, 0.5, 0.13, 12.5)]
	while ss.size() < 8: ss.append(Vector4(0, 0, 0, 0)); sc.append(Vector4(0, 0, 0, 1))
	wmat.set_shader_parameter("streaks", ss)
	wmat.set_shader_parameter("streak_cols", sc)
	wmat.set_shader_parameter("cam_xz", Vector2(cam_pos.x, cam_pos.z))
	wmat.set_shader_parameter("quay_z", QUAY_Z)
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
	house({"x0": -0.7, "x1": 3.5, "zb": -8.4, "zf": -4.6, "h": 3.0, "rh": 1.6, "ridge": "z", "wall": "brick", "tint": Color(0.95, 0.82, 0.8), "upper": 1.55, "upper_tint": Color(0.9, 0.8, 0.7), "roof_tint": Color(0.6, 0.66, 0.86), "chimney": Vector2(0.9, -0.8),
		"items": [["doors_1", "f", 0.95, 0.3, W], ["windows_3", "f", -0.85, 0.42, W], ["windows_2", "f", -0.95, 1.72, W], ["windows_2", "f", 0.95, 1.72, W], ["windows_0", "f", 0.0, 3.0, W], ["windows_1", "l", 0.9, 1.75, W], ["windows_0", "l", -0.9, 1.75, 0.0]]})
	# C：麵包店（矮、屋脊橫向、大片屋頂朝鏡頭）
	house({"x0": 4.5, "x1": 10.2, "zb": -8.2, "zf": -4.3, "h": 2.0, "rh": 1.5, "ridge": "x", "tint": Color(1.0, 0.88, 0.76), "roof": "w_roof_red2", "roof_tint": Color(1.05, 0.86, 0.78), "chimney": Vector2(1.2, 0.5),
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
	# 遠景第三排（更低更遠，交給大氣霧與景深）：屋頂與亮窗的剪影、一座鐘樓
	var fx := -17.0
	var k := 0
	while fx < 17.0:
		var fw := 3.2 + float((k * 7) % 5) * 0.5
		var fh := 4.6 + float((k * 5) % 4) * 0.7
		var its: Array = [["w_win_b" if k % 2 == 0 else "w_win_a", "f", -0.6 if k % 2 == 0 else 0.5, fh - 1.5, W]]
		if k % 3 == 0: its.append(["w_win_d", "f", 0.9, fh - 2.4, W])
		house_at({"x0": fx, "x1": fx + fw, "zb": -21.0 - float(k % 3), "zf": -17.5 - float(k % 2) * 0.8, "h": fh, "rh": 1.3, "ridge": "x" if k % 2 == 0 else "z", "tint": Color(0.8, 0.72, 0.78), "roof": "w_roof_slate2" if k % 3 else "w_roof_red2", "roof_tint": Color(0.8, 0.8, 0.95), "cast": false, "lights": false, "chimney": Vector2(0.7, 0.0), "items": its}, -9.0)
		fx += fw + 0.5
		k += 1
	house_at({"x0": -11.2, "x1": -9.4, "zb": -27.0, "zf": -25.2, "h": 10.5, "rh": 3.0, "ridge": "z", "tint": Color(0.7, 0.64, 0.74), "roof": "w_roof_slate2", "roof_tint": Color(0.7, 0.75, 0.95), "cast": false, "lights": false, "items": [["w_win_e", "f", 0.0, 8.6, W]]}, -9.0)
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
	sprite("w_fisher", Vector3(4.6, 0, QUAY_Z + 0.75), {"flat_lit": 0.3, "tilt": true, "glow_all": 0.07})
	well(Vector3(8.3, 0, 0.1))
	# 小船（繫在堤岸邊）
	build_boat(Vector3(-2.6, WATER_Y - 0.1, QUAY_Z + 1.05))
	pixel_wire(Vector3(-1.0, WATER_Y + 0.4, QUAY_Z + 0.9), Vector3(-0.4, 0.3, QUAY_Z - 0.34), -0.25, [], 2.0, Color(1.6, 1.2, 0.7))

func build_plants() -> void:
	var kinds := ["maple_0", "maple_1", "maple_2", "maple_3", "maple_4", "maple_5", "canopy_autumn_0", "canopy_autumn_2"]
	tree(Vector3(argf("tx", -6.3), 0, argf("tz", -5.4)), kinds, 42, Vector3(2.4, 1.0, 2.0), 3.25, 1.6)
	# 花圃後角的第二棵小楓樹（樹幹在後、枝葉伸到巷口上方）
	rng.seed = 23
	tree(Vector3(-4.5, 0, -8.1), kinds, 14, Vector3(1.3, 0.5, 1.2), 3.3, 2.5, false, true)      # 樹幹不投影：它的影子正好會蓋住主角的光池
	# 往右伸出去的幾團枝葉：影子落在光池右邊，把受光區切成一道道光帶與長影（位置由「影子要落在哪」反推）
	var sd := Vector3(sun_dir.x, 0, sun_dir.z).normalized()
	var perp := Vector3(sun_dir.z, 0, -sun_dir.x).normalized()
	var reach := 1.0 / tan(deg_to_rad(argf("el", SUN_EL)))
	var k := 0
	for b in [[2.5, -1.9, 2.9], [2.7, 0.3, 3.3], [2.45, 2.3, 2.8], [-1.9, 1.6, 2.6], [0.9, -1.8, 2.4], [0.3, -3.8, 2.8], [1.1, -4.4, 3.0]]:      # 後三團遮住主角身後（畫面上方）那段，光池落在她腳邊與前方
		var land: Vector3 = HERO + perp * b[0] + sd * b[1]
		var cp: Vector3 = land - sd * (b[2] * reach) + Vector3(0, b[2], 0)
		sprite(kinds[k % kinds.size()], cp, {"center": true, "tilt": true, "vsway_px": 4.0, "gust_x": -6.3, "rustle_px": 1.0, "flat_lit": 0.16, "glow_all": 0.05, "flip": k % 2 == 0, "shadow_off": 0.0})
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
# 註：BAKER／CHILD 在廣場上的攤位旁（往畫面中間拉近）
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
	hero_n = sprite("hero_anim", HERO, {"tilt": true, "breathe": 1.0, "blink": 1.0, "layer": 128, "flat_lit": 0.16, "rim": 0.5})
	# 事件一：麵包店店員把麵包遞給小孩（兩人面對面，三格手部動作）
	var b := sprite("baker_anim", BAKER, {"tilt": true, "flat_lit": 0.6, "frame_fixed": 0.0})
	baker_m = b.material_override
	var c := sprite("child4_anim", CHILD, {"tilt": true, "flat_lit": 0.6, "frame_fixed": 0.0})
	child_m = c.material_override
	# 事件二：貓在廣場上追蝴蝶
	cat_n = sprite("catrun_anim", CAT_C, {"tilt": true, "flat_lit": 0.15, "frame_fixed": 0.0})
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
	m.set_shader_parameter("tex", tex("w_sky7"))
	m.set_shader_parameter("row0", argf("skyrow", 150.0))
	m.set_shader_parameter("gain", argf("skygain", 1.0))
	mi.material_override = m
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
	# 暗角
	var layer := CanvasLayer.new()
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/vignette.gdshader")
	m.set_shader_parameter("strength", 0.46)
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
	if has("--fps") and int(t) != int(t - dt): print("fps=", Engine.get_frames_per_second(), " window=", DisplayServer.window_get_size(), " mode=", DisplayServer.window_get_mode())
	sync_mirrors()
	var px := 1.0 / PPM
	for f in flyers:
		var n: MeshInstance3D = f.n
		match f.kind:
			"float":
				n.position.x += f.v * dt
				if n.position.x > 11.5: n.position.x = -11.5
			"bird":
				var u := fmod(f.x0 + t * f.v + 4.0, 30.0)
				n.position = Vector3(13.0 - u, f.y + sin(t * 1.1 + f.p) * f.bob, f.z)
				n.scale.x = -1.0
			"bfly":
				var c: Vector3 = f.c
				var p: float = f.p
				var x := sin(t * 0.7 + p) * 0.5 + sin(t * 1.9 + p * 2.0) * 0.2
				var y := sin(t * 1.3 + p * 1.7) * 0.2 + sin(t * 3.1 + p) * 0.07
				var z := cos(t * 0.5 + p) * 0.3
				var np := c + Vector3(x, y, z)
				n.scale.x = 1.0 if np.x >= n.position.x else -1.0
				n.position = Vector3(snappedf(np.x, px), snappedf(np.y, px), np.z)
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
		var bl: Array = [Vector4(HERO.x, HERO.z, 0.36, 0.2), Vector4(BAKER.x, BAKER.z, 0.34, 0.2), Vector4(CHILD.x, CHILD.z, 0.32, 0.18)]
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
	var tag := ""
	for a in args:
		if a.begins_with("--tag="): tag = a.substr(6)
	var dir := ProjectSettings.globalize_path("res://").path_join("../shots/godot_diorama").simplify_path()
	for a in args:
		if a.begins_with("--out="): dir = dir.path_join(a.substr(6))
	if has("--work"): dir = ProjectSettings.globalize_path("res://tools/work")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(argf("wait", 3.0)).timeout
	var f0 := frames_n
	await get_tree().create_timer(1.0).timeout
	print("fps(1s)=", frames_n - f0)
	if tag != "":
		var im: Image = await grab()
		im.save_png(dir.path_join("compare_%s.png" % tag))
		print("saved compare_", tag, " ", im.get_size())
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
	get_tree().quit()
