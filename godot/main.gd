extends Node3D
# HD-2D 小鎮（第二版）：黃昏側逆光的運河小街。場景全部由這支腳本程序化組出來。
# 正常啟動：持續執行。  `-- --shots`：截 3 張全景（間隔 2 秒）＋ 2 張特寫後離開。
# 對照：`-- --shots --tag=xxx --no-fog --no-beams --no-dof --no-refl`（--no-fog 只關體積霧；光束片另由 --no-beams 控制）。

const PPM := 32.0          # 全場統一點陣密度：32 點陣 / 公尺
const PAD := 4.0           # sprite 四周的透明邊（點陣）
const WATER_Y := -0.5
const FG_Y := -0.25
const FG_Z := 4.5          # 前景河岸的邊緣
const HERO := Vector3(-5.0, 0.0, -0.4)
const LAMP_Z := -1.0        # 路燈離護岸遠一點，燈前的積水才放得下拉長的倒影光柱
const STEP_X := 3.3
const BOAT_X := -6.4
const FOV := 30.0
const PITCH := 15.0        # 俯角
const YAW := 4.0           # 鏡頭右轉，屋排斜向深處
const K_PX := 4.0          # 焦平面（主角所在深度）上 1 點陣 = 4 螢幕像素（1080p）

var meta: Dictionary
var _tex := {}
var _mat := {}
var _quad := {}
var sh_pix: Shader = load("res://shaders/pix.gdshader")
var sh_ground: Shader = load("res://shaders/ground.gdshader")
var sh_water: Shader = load("res://shaders/water.gdshader")
var sh_part: Shader = load("res://shaders/particle.gdshader")
var sh_beam: Shader = load("res://shaders/beam.gdshader")
var sh_pix_mip: Shader      # 同一支 shader，但取樣器改成 nearest＋mipmap＋各向異性（給斜看的屋頂，避免摩爾紋）
var rng := RandomNumberGenerator.new()
var args: PackedStringArray
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var sun_dir := Vector3(0.30, -0.26, 0.92).normalized()   # 光的行進方向：夕陽在畫面左上方的天空裡，仰角約 15°，從後方斜射向鏡頭（逆光）
var depth0 := 0.0          # 主角的鏡頭深度（由 K_PX 反推）
var cam_fwd: Vector3
var cam_right: Vector3
var cam_up: Vector3
var cam_pos: Vector3
var mirrors: Array = []
var flyers: Array = []
var flickers: Array = []
var leaf_emitters: Array = []
var boat: MeshInstance3D
var streak_src: Array = []
var streak_col: Array = []
var t := 0.0
var frames_n := 0

# 與 pix.gdshader 的 gust() 同一條式子：草、樹、落葉共用同一陣風
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
	m.set_shader_parameter("rim_dir", Vector2(-signf(sun_dir.x), -1.0))
	for k in o:
		if k != "mip": m.set_shader_parameter(k, o[k])
	_mat[key] = m
	return m

const MAT_KEYS := ["blink", "breathe", "gust_x", "frame_fixed", "rim", "sway_px", "vsway_px", "rustle_px", "emit", "glow_all", "backlight", "tint", "rough", "fps", "lit"]

# 直立的像素 sprite（底邊對齊 pos.y），尺寸 = 像素數 / PPM × scale
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
	if sc != 1.0: mo["sprite_scale"] = sc
	mi.material_override = mat(name, mo)
	mi.position = pos
	if o.get("flip", false): mi.scale.x = -1
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if o.get("shadow", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if o.has("layer"): mi.layers = o["layer"]
	add_child(mi)
	# 逆光的 sprite 會被自己的影子蓋住（背光面自我遮蔽），描邊與透光就亮不起來。
	# 做法：本體不投影，另放一份「只投影」的分身，沿光的方向往後退 15 公分。
	if o.get("shadow", true) and (o.has("rim") or o.has("backlight")):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := MeshInstance3D.new()
		sh.mesh = mi.mesh
		sh.material_override = mi.material_override
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.add_child(sh)
		sh.global_position = pos + sun_dir * 0.15
	return mi

# ------------------------------------------------------------------ 幾何（UV 以公尺 × PPM / 貼圖像素 計算，點陣密度固定）
class Geo:
	var st := SurfaceTool.new()
	var tp: Vector2
	func _init(tex_px: Vector2) -> void:
		tp = tex_px
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a=左下 b=右下 c=右上 d=左上（從正面看）
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uo := Vector2.ZERO, us := 1.0) -> void:
		var n := (b - a).cross(d - a).normalized()
		var ul := (b - a).length() * 28.8 / tp.x * us
		var vl := (d - a).length() * 28.8 / tp.y
		var pts := [a, d, c, a, c, b]
		var uvs := [Vector2(0, vl), Vector2(0, 0), Vector2(ul, 0), Vector2(0, vl), Vector2(ul, 0), Vector2(ul, vl)]
		for i in 6:
			st.set_normal(n); st.set_uv(uvs[i] + uo); st.add_vertex(pts[i])
	func tri(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		var ul := (b - a).length() * 28.8 / tp.x
		var hgt := (c - (a + b) * 0.5).length() * 28.8 / tp.y
		var pts := [a, c, b]
		var uvs := [Vector2(0, 0), Vector2(ul * 0.5, -hgt), Vector2(ul, 0)]
		for i in 3:
			st.set_normal(n); st.set_uv(uvs[i]); st.add_vertex(pts[i])
	# 盒子：c = 底面中心
	func box(c: Vector3, s: Vector3) -> void:
		var x0 := c.x - s.x * 0.5; var x1 := c.x + s.x * 0.5
		var y0 := c.y; var y1 := c.y + s.y
		var z0 := c.z - s.z * 0.5; var z1 := c.z + s.z * 0.5
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1))
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0))
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0))
		quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1))
		quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0))
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
	add_child(mi)
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

# ------------------------------------------------------------------ 房屋
# 規格：x 中心、w 寬、h 牆高、d 深、rh 屋頂高、z 正面位置、ridge "x"（屋脊橫向）或 "z"（山牆朝前）
func house(h: Dictionary) -> void:
	var x: float = h.x; var w: float = h.w; var wh: float = h.h; var d: float = h.d; var rh: float = h.rh
	var zf: float = h.get("z", -2.5)
	var zb := zf - d
	var zc := (zf + zb) * 0.5
	var x0 := x - w * 0.5; var x1 := x + w * 0.5
	var wall_tex: String = h.get("wall", "plaster2")
	var wtint: Color = h.get("tint", Color(1, 0.9, 0.78))
	var base_h := 0.45
	var gb := geo("stonewall")
	gb.box(Vector3(x, 0, zc), Vector3(w + 0.1, base_h, d + 0.1))
	put(gb, "stonewall", {"tint": Color(0.95, 0.88, 0.85), "rough": 0.9, "grime": 0.6, "wall_top": 3.0})
	var gw := geo(wall_tex)
	gw.box(Vector3(x, base_h, zc), Vector3(w, wh - base_h, d))
	var ov := 0.28
	if h.ridge == "z":
		gw.tri(Vector3(x0, wh, zf), Vector3(x1, wh, zf), Vector3(x, wh + rh, zf))
		gw.tri(Vector3(x1, wh, zb), Vector3(x0, wh, zb), Vector3(x, wh + rh, zb))
	else:
		gw.tri(Vector3(x0, wh, zb), Vector3(x0, wh, zf), Vector3(x0, wh + rh, zc))
		gw.tri(Vector3(x1, wh, zf), Vector3(x1, wh, zb), Vector3(x1, wh + rh, zc))
	put(gw, wall_tex, {"tint": wtint, "rough": 0.9, "grime": 0.7, "wall_top": wh}).layers = 17
	if h.has("upper"):
		var uy: float = h.upper
		var gu := geo("plaster2")
		gu.box(Vector3(x, uy, zc), Vector3(w + 0.16, wh - uy, d + 0.16))
		if h.ridge == "z":
			var kk := rh / (w * 0.5)
			gu.tri(Vector3(x0 - 0.08, wh, zf + 0.08), Vector3(x1 + 0.08, wh, zf + 0.08), Vector3(x, wh + rh - 0.02, zf + 0.08))
		put(gu, "plaster2", {"tint": h.get("upper_tint", Color(1, 0.93, 0.8)), "rough": 0.9, "grime": 1.0, "wall_top": wh + rh * 0.5}).layers = 17
		var gt := geo("planks")
		var zt := zf + 0.08
		gt.box(Vector3(x, uy - 0.06, zt), Vector3(w + 0.24, 0.16, 0.1))
		gt.box(Vector3(x, wh - 0.1, zt), Vector3(w + 0.2, 0.12, 0.1))
		for bx in [x0 - 0.02, x1 + 0.02, x - w * 0.17, x + w * 0.17]:
			gt.box(Vector3(bx, uy, zt), Vector3(0.12, wh - uy, 0.1))
		put(gt, "planks", {"tint": Color(0.5, 0.38, 0.34), "rough": 0.9})
	# 屋頂（有厚度的封簷板：邊緣一律是 2–3 點陣寬的深色木條）
	var gr := geo("roof2")
	var ge := geo("planks")
	var rt: Color = h.get("roof_tint", Color(0.95, 0.5, 0.36))
	var th := 3.0 / PPM
	if h.ridge == "x":
		var k := rh / (d * 0.5)
		var ey := wh - ov * k
		var e0 := Vector3(x0 - ov, ey, zf + ov); var e1 := Vector3(x1 + ov, ey, zf + ov)
		var r0 := Vector3(x0 - ov, wh + rh, zc); var r1 := Vector3(x1 + ov, wh + rh, zc)
		var b0 := Vector3(x0 - ov, ey, zb - ov); var b1 := Vector3(x1 + ov, ey, zb - ov)
		gr.quad(e0, e1, r1, r0)
		gr.quad(b1, b0, r0, r1)
		ge.box(Vector3(x, ey - th, zf + ov), Vector3(w + ov * 2, th, 0.08))
		ge.box(Vector3(x, wh + rh - 0.02, zc), Vector3(w + ov * 2 + 0.04, 0.1, 0.16))
		# 兩側斜邊的封簷板
		for sx in [x0 - ov - 0.01, x1 + ov + 0.01]:
			var dn := Vector3(0, -th, 0)
			ge.quad(Vector3(sx, ey, zf + ov) + dn, Vector3(sx, wh + rh, zc) + dn, Vector3(sx, wh + rh, zc), Vector3(sx, ey, zf + ov))
			ge.quad(Vector3(sx, wh + rh, zc) + dn, Vector3(sx, ey, zb - ov) + dn, Vector3(sx, ey, zb - ov), Vector3(sx, wh + rh, zc))
	else:
		var k2 := rh / (w * 0.5)
		var zf2 := zf + ov; var zb2 := zb - ov
		var ey2 := wh - ov * k2
		var l0 := Vector3(x0 - ov, ey2, zf2); var l1 := Vector3(x0 - ov, ey2, zb2)
		var q0 := Vector3(x1 + ov, ey2, zf2); var q1 := Vector3(x1 + ov, ey2, zb2)
		var t0 := Vector3(x, wh + rh, zf2); var t1 := Vector3(x, wh + rh, zb2)
		# 山牆朝前的屋頂，兩片斜面的「屋脊方向」幾乎順著視線（掠射角，縮短成約 1/4）。
		# 貼圖沿屋脊方向拉長 4 倍，讓瓦片在畫面上接近正方、看得出一片片，不會變成拉絲。
		gr.quad(l1, l0, t0, t1, Vector2.ZERO, 0.25)
		gr.quad(q0, q1, t1, t0, Vector2.ZERO, 0.25)
		var dn2 := Vector3(0, -4.0 / PPM, 0)
		var fz := Vector3(0, 0, 0.01)
		ge.quad(l0 + dn2 + fz, t0 + dn2 + fz, t0 + fz, l0 + fz)
		ge.quad(t0 + dn2 + fz, q0 + dn2 + fz, q0 + fz, t0 + fz)
		# 屋簷下緣（左右兩條）
		ge.box(Vector3(x0 - ov, ey2 - th, zc), Vector3(0.08, th, d + ov * 2))
		ge.box(Vector3(x1 + ov, ey2 - th, zc), Vector3(0.08, th, d + ov * 2))
	if h.ridge == "z":
		# 山牆朝前：兩片斜面幾乎順著視線，任何沿屋脊方向變化的貼圖都會被壓成拉絲。
		# 這兩片改用程序化的「一排排瓦」：只沿坡向（畫面上看得到的方向）分排，沿屋脊方向只有 1.5 m 一段的大塊深淺。
		put(gr, "roof2", {"tint": rt, "rough": 0.8, "courses": 1.0})
	else:
		put(gr, "roof2", {"tint": rt, "rough": 0.8, "moss": 1.0, "mip": true})
	put(ge, "planks", {"tint": Color(0.36, 0.27, 0.27), "rough": 0.9})
	if h.has("chimney"):
		var cx: float = x + h.chimney
		var gc := geo("brick")
		var cy := wh + rh * 0.35
		gc.box(Vector3(cx, cy, zc - 0.3), Vector3(0.5, rh * 0.65 + 0.55, 0.5))
		put(gc, "brick", {"tint": Color(0.9, 0.8, 0.78), "grime": 0.8, "wall_top": cy + 1.0})
		var gcap := geo("stonewall")
		gcap.box(Vector3(cx, cy + rh * 0.65 + 0.55, zc - 0.3), Vector3(0.62, 0.1, 0.62))
		put(gcap, "stonewall")
	var zs := zf + 0.02 + (0.08 if h.has("upper") else 0.0)
	for it in h.get("items", []):
		var nm: String = it[0]
		var p := Vector3(x + it[1], it[2], zf + 0.02 if it[2] < h.get("upper", 99.0) - 0.5 else zs)
		sprite(nm, p, {"emit": it[3] if it.size() > 3 else 0.0, "shadow": false})
		if it.size() > 3 and it[3] > 0.0:
			var s := px_size(nm) / PPM
			omni(p + Vector3(0, s.y * 0.45, 0.6), Color(1.0, 0.66, 0.34), 0.4, 4.0 if p.x > -0.5 else 3.0, false, 0.8, 0.06)

# ------------------------------------------------------------------ 樹：樹幹 sprite ＋ 前後錯開的多團葉叢（真的有深度 → 葉隙漏光）
func tree(pos: Vector3, kind: String, n: int, spread := Vector3(1.5, 1.0, 0.8), flip := false, cy := 3.0) -> void:
	sprite("trunk", pos, {"flip": flip, "rough": 0.9})
	var cnt: int = meta[kind + "_n"]
	for i in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf())
		var p := pos + Vector3(cos(a) * r * spread.x, cy + sin(a) * r * spread.y, rng.randf_range(-spread.z, spread.z))
		sprite("%s_%d" % [kind, i % cnt], p, {"center": true, "vsway_px": 6.0, "gust_x": pos.x, "rustle_px": 1.0, "backlight": 0.22, "glow_all": 0.05, "flip": rng.randf() < 0.5, "rough": 0.9})

func particles(pos: Vector3, box: Vector3, amount: int, tex_name: String, o: Dictionary = {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = o.get("dir", Vector3(1, -0.4, 0.0))
	pm.spread = o.get("spread", 40.0)
	pm.initial_velocity_min = o.get("v0", 0.1); pm.initial_velocity_max = o.get("v1", 0.5)
	pm.gravity = o.get("gravity", Vector3(0.5, -0.42, 0.0))
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
	m.set_shader_parameter("glow_all", o.get("glow", 0.0))
	m.set_shader_parameter("tint", o.get("tint", Color.WHITE))
	m.set_shader_parameter("vary", o.get("vary", 0.0))
	if o.has("smin"):
		pm.scale_min = o["smin"]; pm.scale_max = 1.0
	q.material = m
	p.draw_pass_1 = q
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 256            # 粒子不進運河倒影
	p.visibility_aabb = AABB(Vector3(-12, -12, -8), Vector3(30, 20, 16))
	add_child(p)
	return p

# 煙囪的煙：像素煙團（依年齡換格：小 → 大 → 散），不縮放所以點陣大小一致；慢慢往右上飄
func smoke(pos: Vector3) -> void:
	var p := particles(pos, Vector3(0.03, 0.02, 0.03), 5, "smoke", {"dir": Vector3(0.3, 1, 0), "spread": 8.0, "v0": 0.28, "v1": 0.36, "gravity": Vector3(0.1, 0.02, 0), "turb": 0.15, "life": 4.5, "glow": 0.25})
	var m: ShaderMaterial = (p.draw_pass_1 as QuadMesh).material
	m.set_shader_parameter("by_age", true)
	m.set_shader_parameter("backlight", 0.3)

# 光束片：從 top 沿太陽方向往下 length 公尺；上窄下寬的梯形（下端是上端的 1.5 倍），面向鏡頭
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
	m.render_priority = 1          # 在自製景深之後畫（光束本來就是柔的）
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("seed_v", seed_v)
	m.set_shader_parameter("wx", bottom.x)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 512
	add_child(mi)

# 鏡頭座標 → 世界座標（u、v ∈ [-1,1] 是畫面位置，depth 是鏡頭深度）
func screen_point(u: float, v: float, depth: float) -> Vector3:
	var hh := depth * tan(deg_to_rad(FOV * 0.5))
	return cam_pos + cam_fwd * depth + cam_right * (u * hh * 16.0 / 9.0) + cam_up * (v * hh)

func depth_of(p: Vector3) -> float:
	return (p - cam_pos).dot(cam_fwd)

# 讓某深度的 sprite 在螢幕上剛好是 n 像素 / 點陣 所需的 scale
func scale_for(p: Vector3, n_px: float) -> float:
	return n_px * depth_of(p) / (K_PX * depth0)

# ------------------------------------------------------------------ 場景
func _ready() -> void:
	rng.seed = 11
	args = OS.get_cmdline_user_args()
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://tex/meta.json"))
	sh_pix_mip = Shader.new()
	sh_pix_mip.code = sh_pix.code.replace("source_color, filter_nearest, repeat_enable", "source_color, filter_nearest_mipmap_anisotropic, repeat_enable")
	setup_camera()
	build_env()
	build_ground()
	build_town()
	build_plants()
	build_far()
	build_sky()
	build_life()
	build_post()
	if "--no-leaves" in args:      # 驗證用：關掉落葉粒子，單獨量樹冠的擺動
		for e in leaf_emitters: e.visible = false
	if "--shots" in args:
		run_shots()

func setup_camera() -> void:
	depth0 = 1080.0 / (2.0 * tan(deg_to_rad(FOV * 0.5)) * PPM * K_PX)
	var p := deg_to_rad(PITCH); var y := deg_to_rad(YAW)
	cam_fwd = Vector3(sin(y) * cos(p), -sin(p), -cos(y) * cos(p)).normalized()
	cam_right = cam_fwd.cross(Vector3.UP).normalized()
	cam_up = cam_right.cross(cam_fwd).normalized()
	# 主角在畫面左側 1/3、略低於中線；這兩個位移都垂直於視線，所以主角深度仍是 depth0（= 4 px / 點陣）
	var aim := HERO + Vector3(0, 0.7, 0) + cam_right * 1.6 + cam_up * 1.55
	cam_pos = aim - cam_fwd * depth0
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	cam.look_at_from_position(cam_pos, cam_pos + cam_fwd, Vector3.UP)
	cam.current = true
	cam.cull_mask = 0x3FF
	if "--no-msaa" in args: get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if "--top" in args:      # 除錯：從正上方看受光範圍
		cam.fov = 50.0
		cam.look_at_from_position(Vector3(-3, 26, 0.5), Vector3(-3, 0, 0), Vector3(0, 0, -1))
	if not "--no-dof" in args:
		# 自製景深（shaders/dof.gdshader）：全螢幕四邊形掛在鏡頭前，天空背板不參與模糊
		var dq := MeshInstance3D.new()
		var qm := QuadMesh.new(); qm.size = Vector2(2, 2)
		dq.mesh = qm
		var dm := ShaderMaterial.new(); dm.shader = load("res://shaders/dof.gdshader")
		dm.set_shader_parameter("near_start", depth0 - 2.2)
		dm.set_shader_parameter("far_start", depth0 + 4.1)
		dm.render_priority = 0
		dq.material_override = dm
		dq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dq.layers = 512
		dq.extra_cull_margin = 16384.0
		cam.add_child(dq)
		dq.position = Vector3(0, 0, -1.0)

func build_env() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	# 暗部：深藍紫的環境光，很低；立面留在陰影裡，只靠窗光、燈光、SSIL 反彈
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.32, 0.62)
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.36
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.8
	env.set_glow_level(0, 0.0); env.set_glow_level(1, 0.6); env.set_glow_level(2, 0.9); env.set_glow_level(3, 0.55); env.set_glow_level(4, 0.12); env.set_glow_level(5, 0.0); env.set_glow_level(6, 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.0
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.0
	if not "--no-fog" in args:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.001
		env.volumetric_fog_albedo = Color(1.0, 0.9, 0.82)
		env.volumetric_fog_anisotropy = 0.45
		env.volumetric_fog_length = 38.0
		env.volumetric_fog_detail_spread = 1.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.0
		env.volumetric_fog_temporal_reprojection_enabled = true
		# 局部加濃的霧：只在太陽穿過的地方（庭院缺口到街上、右側屋間、水面薄霧）
		for fv in [[Vector3(-5.0, 2.3, -0.8), Vector3(10.5, 5.2, 9.5), 0.007], [Vector3(5.6, 2.2, -0.8), Vector3(4.5, 5.0, 8.0), 0.025], [Vector3(0, -0.15, 3.2), Vector3(40, 0.8, 5.0), 0.015]]:
			var v := FogVolume.new()
			v.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
			v.size = fv[1]
			var fm := FogMaterial.new()
			fm.density = fv[2]
			fm.albedo = Color(1.0, 0.9, 0.82)
			fm.edge_fade = 0.25
			v.material = fm
			v.position = fv[0]
			add_child(v)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.8
	# 分離色調：暗部偏藍紫、亮部偏暖（每個色版一條曲線）
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	gr.colors = PackedColorArray([Color(0.028, 0.03, 0.075), Color(0.2, 0.215, 0.31), Color(0.61, 0.6, 0.6), Color(1.0, 0.97, 0.9)])
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	gt.width = 256
	env.adjustment_color_correction = gt
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 3.3
	sun.light_specular = 0.3
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 0.55
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_blur = 2.0
	sun.light_angular_distance = 2.2
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, sun_dir, Vector3.UP)
	# 局部補光：只照「牆面與花圃」（layer 5），把這兩處的中間調拉回來；地面、水面、屋頂、天空都不受影響
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.86, 0.74)
	fill.light_energy = 0.0 if "--no-fill" in args else 0.55
	fill.light_specular = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.light_cull_mask = 16
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.4, -0.3, -0.87), Vector3.UP)

func make_mirror(plane_y: float, flag_bit: int, exclude: int) -> ViewportTexture:
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)          # 半解析度：水面／積水取樣本來就對齊 4px 的點陣格
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rc := Camera3D.new()
	rc.fov = FOV; rc.near = 0.5; rc.far = 300.0
	rc.cull_mask = (0x1FF & ~exclude) | flag_bit      # 不含光束片（layer 10）、反射面自己與 exclude 指定的層
	var renv: Environment = env.duplicate()
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
	var p := cam.global_position
	var f := -cam.global_transform.basis.z
	for m in mirrors:
		var rc: Camera3D = m.cam
		var y: float = m.y
		var mp := Vector3(p.x, 2.0 * y - p.y, p.z)
		rc.look_at_from_position(mp, mp + Vector3(f.x, -f.y, f.z), Vector3.UP)

func build_ground() -> void:
	var refl_on := not "--no-refl" in args
	# 石板街：微濕＋手擺的積水（取樣街面的平面反射）
	var street := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(44, 3.4)
	street.mesh = pm
	var m := ShaderMaterial.new(); m.shader = sh_ground
	m.set_shader_parameter("tex", tex("street")); m.set_shader_parameter("tint", Color(1.25, 1.2, 1.3))
	m.set_shader_parameter("tex_size", Vector2(meta["street"][0], meta["street"][1]))
	m.set_shader_parameter("origin", Vector2(-14.0, -3.0))
	m.set_shader_parameter("ppm", 16.0)      # 地面被俯角壓扁，點陣放大一倍才和角色的點陣大小接近
	m.set_shader_parameter("refl", make_mirror(0.0, 2048, 2 | 4 | 256))
	m.set_shader_parameter("refl_strength", 0.4 if refl_on else 0.0)
	# 積水：主角腳前、路燈下、麵包店窗下、紅磚屋門前、右側
	# 每個真實光源一條倒影光條（世界座標：光源 x、z、半寬、強度；顏色 rgb＋長度 m）。運河與積水共用同一組，
	# 光條沿「光源 → 鏡頭」的連線延伸，所以鏡頭移動也對得上。
	streak_src = [Vector4(-1.2, LAMP_Z, 0.09, 0.62), Vector4(3.2, LAMP_Z, 0.09, 0.56), Vector4(-0.2, -2.3, 0.05, 0.4), Vector4(-3.3, -2.3, 0.11, 0.55), Vector4(1.0, -2.8, 0.15, 0.5), Vector4(BOAT_X + 1.0, 1.65, 0.04, 0.8)]
	streak_col = [Vector4(1.0, 0.5, 0.13, 6.4), Vector4(1.0, 0.5, 0.13, 5.6), Vector4(1.0, 0.42, 0.1, 6.0), Vector4(1.0, 0.2, 0.05, 7.5), Vector4(1.0, 0.24, 0.06, 8.0), Vector4(1.0, 0.42, 0.1, 2.2)]
	while streak_src.size() < 8: streak_src.append(Vector4(0, 0, 0, 0)); streak_col.append(Vector4(0, 0, 0, 1))
	m.set_shader_parameter("streaks", streak_src)
	m.set_shader_parameter("streak_cols", streak_col)
	m.set_shader_parameter("cam_xz", Vector2(cam_pos.x, cam_pos.z))
	# 積水：兩盞路燈正前方各一灘（中心落在路燈倒影的連線上），其餘在窗下與街角
	var pud: Array = []
	for lx in [-1.2, 3.2]:
		var dv := (Vector2(cam_pos.x, cam_pos.z) - Vector2(lx, LAMP_Z)).normalized()
		pud.append(Vector4(lx + dv.x * 0.66, LAMP_Z + dv.y * 0.66, 0.42, 0.72))
	pud.append_array([Vector4(0.1, -1.4, 0.45, 0.6), Vector4(-2.6, -1.3, 0.45, 0.6), Vector4(-8.6, -0.8, 0.5, 0.75)])
	m.set_shader_parameter("hero_xz", Vector2(HERO.x, HERO.z))
	m.set_shader_parameter("hero_xz", Vector2(HERO.x, HERO.z))
	while pud.size() < 8: pud.append(Vector4(0, 0, 0, 0))
	m.set_shader_parameter("puddles", pud)
	street.material_override = m
	street.position = Vector3(0, 0, -1.3)
	street.layers = 4
	add_child(street)
	# 屋後與庭院的草地
	var gg := geo("grass")
	gg.quad(Vector3(-22, 0.0, -3.0), Vector3(22, 0.0, -3.0), Vector3(22, 0.0, -16), Vector3(-22, 0.0, -16))
	put(gg, "grass", {"tint": Color(0.2, 0.26, 0.24), "rough": 1.0})
	# 護岸：壓頂石＋石牆
	var gs := geo("stonewall")
	gs.box(Vector3(0.5, 0.0, 0.45), Vector3(41.0, 0.1, 0.34))
	put(gs, "stonewall", {"tint": Color(1.0, 0.95, 0.9), "rough": 0.9})
	var gq := geo("stonewall")
	var gqs := geo("quay")
	gqs.quad(Vector3(-14, -1.15, 0.63), Vector3(10, -1.15, 0.63), Vector3(10, 0.1, 0.63), Vector3(-14, 0.1, 0.63))
	put(gqs, "quay", {"tint": Color(1.25, 1.2, 1.3), "rough": 0.9})
	gq.quad(Vector3(-20, -1.0, 0.6), Vector3(21, -1.0, 0.6), Vector3(21, 0.0, 0.6), Vector3(-20, 0.0, 0.6))
	# 下到水邊的石階：兩大階往鏡頭方向降到水面（寬 1.8 m），取代原本側向的小階梯
	gq.box(Vector3(STEP_X, -1.0, 0.82), Vector3(1.8, 0.82, 0.44))
	gq.box(Vector3(STEP_X, -1.0, 1.26), Vector3(1.8, 0.62, 0.44))
	put(gq, "stonewall", {"tint": Color(0.82, 0.8, 0.84), "rough": 0.9, "grime": 0.9, "wall_top": 0.6})
	# 繫船柱
	var gp := geo("planks")
	for bx in [-8.2, -3.6, -0.3, 2.6, 5.4]:
		gp.box(Vector3(bx, 0.1, 0.45), Vector3(0.19, 0.5, 0.19))
	put(gp, "planks", {"tint": Color(0.6, 0.48, 0.42)})
	var gpc := geo("stonewall")
	for bx in [-8.2, -3.6, -0.3, 2.6, 5.4]:
		gpc.box(Vector3(bx, 0.6, 0.45), Vector3(0.25, 0.07, 0.25))
	put(gpc, "stonewall", {"tint": Color(0.7, 0.68, 0.72)})
	# 運河：平面反射（鏡像相機 → SubViewport），水面 shader 對齊點陣格取樣
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new(); wm.size = Vector2(44, 6.6)
	water.mesh = wm
	var wmat := ShaderMaterial.new(); wmat.shader = sh_water
	wmat.set_shader_parameter("refl", make_mirror(WATER_Y, 1024, 2 | 128 | 256))    # 運河倒影不含角色（128）、粒子與蝴蝶（256）
	if not refl_on: wmat.set_shader_parameter("strength", 0.0)
	wmat.set_shader_parameter("streaks", streak_src)
	wmat.set_shader_parameter("streak_cols", streak_col)
	wmat.set_shader_parameter("cam_xz", Vector2(cam_pos.x, cam_pos.z))
	water.material_override = wmat
	water.position = Vector3(0, WATER_Y, 3.6)
	water.layers = 2
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# 前景河岸
	var gf := geo("grass")
	gf.quad(Vector3(-16, FG_Y, 13), Vector3(16, FG_Y, 13), Vector3(16, FG_Y, FG_Z), Vector3(-16, FG_Y, FG_Z))
	put(gf, "grass", {"tint": Color(0.25, 0.34, 0.3)})
	var gf2 := geo("stonewall")
	gf2.quad(Vector3(16, -1.0, FG_Z), Vector3(-16, -1.0, FG_Z), Vector3(-16, FG_Y, FG_Z), Vector3(16, FG_Y, FG_Z))
	put(gf2, "stonewall")

# 點陣電線：沿懸鏈線一格一格（1 點陣 × 1 點陣）排，不是平滑斜線
func pixel_wire(p0: Vector3, p1: Vector3, sag: float, bulbs: Array) -> void:
	var gl := geo("planks")
	var n := int((p1.x - p0.x) * PPM)
	var px := 1.0 / PPM
	for i in n:
		var u := float(i) / n
		var pt := p0.lerp(p1, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
		var x := p0.x + i * px
		var y := floorf(pt.y * PPM) / PPM
		gl.quad(Vector3(x, y, pt.z), Vector3(x + px, y, pt.z), Vector3(x + px, y + px, pt.z), Vector3(x, y + px, pt.z))
		if i % 14 == 7 and bulbs.size() > 0:
			var c: Color = bulbs[(i / 14) % bulbs.size()]
			sprite("bulb", Vector3(x, y - 2.0 * px, pt.z + 0.01), {"center": true, "glow_all": 2.0, "tint": c, "lit": 0.0, "shadow": false})
			if (i / 14) % 4 == 1:
				omni(Vector3(x, y - 0.1, pt.z + 0.3), c, 0.35, 2.2, false, 0.6, 0.08)
	put(gl, "planks", {"tint": Color(0.16, 0.12, 0.16)}, false)

func build_town() -> void:
	var W := 0.62
	# A：最左的奶油黃小屋（畫面只露出右邊一點）
	house({"x": -11.4, "w": 3.8, "h": 3.0, "d": 2.5, "rh": 1.2, "ridge": "x", "tint": Color(1.0, 0.84, 0.6), "roof_tint": Color(0.9, 0.45, 0.32), "chimney": -0.9,
		"items": [["windows2_0", 0.9, 1.0, W], ["doors_0", -0.9, 0.0]]})
	# G：庭院後方退後一排的桃色小屋（在失焦區，補回「一排屋子」的節奏；位置避開射向主角的陽光）
	house({"x": -8.9, "w": 3.6, "h": 2.3, "d": 3.0, "rh": 1.1, "z": -12.0, "ridge": "x", "tint": Color(1.0, 0.8, 0.66), "roof_tint": Color(0.55, 0.52, 0.72), "chimney": 0.9,
		"items": [["windows_1", -0.8, 1.2, W], ["windows_0", 0.75, 1.2, W]]})
	# 庭院（x -8.3 ～ -4.3）：矮石牆＋門柱，夕陽從這個缺口斜射到街上
	var gwall := geo("stonewall")
	gwall.box(Vector3(-8.45, 0, -2.5), Vector3(2.1, 0.8, 0.3))
	gwall.box(Vector3(-4.5, 0, -2.5), Vector3(0.4, 0.8, 0.3))
	for gx in [-7.4, -4.75]:
		gwall.box(Vector3(gx, 0, -2.5), Vector3(0.36, 0.95, 0.36))
	put(gwall, "stonewall", {"tint": Color(0.86, 0.84, 0.9), "rough": 0.9, "grime": 1.0, "wall_top": 1.6}, false)      # 矮牆不投影：街上不再有硬邊暗楔
	var gcap := geo("stonewall")
	gcap.box(Vector3(-4.5, 0.8, -2.5), Vector3(0.5, 0.07, 0.4))
	gcap.box(Vector3(-8.45, 0.8, -2.5), Vector3(2.2, 0.07, 0.4))
	for gx in [-7.4, -4.75]:
		gcap.box(Vector3(gx, 0.95, -2.5), Vector3(0.46, 0.08, 0.46))
	put(gcap, "stonewall", {"tint": Color(1.0, 0.96, 0.95), "rough": 0.9}, false)
	# B：高的半木造屋（山牆朝前，略往前凸）
	house({"x": -2.55, "w": 3.5, "h": 3.6, "d": 3.6, "rh": 1.5, "z": -2.3, "ridge": "z", "wall": "brick", "tint": Color(0.92, 0.82, 0.8), "upper": 2.1, "upper_tint": Color(1.0, 0.9, 0.76), "roof_tint": Color(0.5, 0.52, 0.74),
		"items": [["doors_1", 0.85, 0.0, W], ["windows_3", -0.75, 0.8, W], ["windows_2", -0.85, 2.4, W], ["windows_2", 0.85, 2.4, W], ["windows_0", 0.0, 3.65, W]]})
	# C：麵包店（矮、屋脊橫向，略往後退）
	house({"x": 1.75, "w": 4.3, "h": 2.7, "d": 3.2, "rh": 1.4, "z": -2.8, "ridge": "x", "tint": Color(0.98, 0.8, 0.72), "roof_tint": Color(0.42, 0.58, 0.68), "chimney": 1.2,
		"items": [["doors_2", -0.75, 0.0, 0.4], ["windows2_1", 1.25, 0.95, W]]})
	sprite("props_4", Vector3(0.35, 1.7, -2.6), {"shadow": false})   # 招牌
	# D：右側粉藍小屋（山牆朝前）
	house({"x": 7.0, "w": 3.4, "h": 3.2, "d": 3.4, "rh": 1.5, "z": -2.4, "ridge": "z", "tint": Color(0.8, 0.87, 0.96), "roof_tint": Color(0.88, 0.47, 0.34), "chimney": 0.8,
		"items": [["doors_0", -0.7, 0.0], ["windows2_2", 0.75, 0.95, W], ["windows_1", 0.0, 2.15, W], ["windows_3", 0.0, 3.3, 0.0]]})
	house({"x": 11.4, "w": 4.0, "h": 2.9, "d": 3.4, "rh": 1.5, "ridge": "x", "tint": Color(1.0, 0.88, 0.7), "roof_tint": Color(0.55, 0.5, 0.66), "items": [["windows_0", -0.9, 1.0, W]]})
	house({"x": -20.6, "w": 4.0, "h": 3.4, "d": 3.4, "rh": 1.6, "ridge": "z", "tint": Color(0.95, 0.8, 0.74), "roof_tint": Color(0.8, 0.42, 0.32), "items": [["windows_2", 0.6, 1.0, W]]})
	# 街道小物
	sprite("props_3", Vector3(6.3, 0, -2.2), {})                                      # 長椅（麵包店前）
	sprite("props2_4", Vector3(4.1, 0, -2.7), {}); sprite("props_1", Vector3(4.65, 0, -2.75), {})
	sprite("cat_anim", Vector3(4.67, 0.92, -2.73), {"shadow": false, "fps": 0.4})               # 貓（箱子上）
	sprite("props2_5", Vector3(-1.05, 0, -2.1)); sprite("props2_5", Vector3(5.9, 0, -2.2), {"flip": true})
	sprite("props2_4", Vector3(-9.2, 0, -2.25), {})
	build_life_props()
	# 街燈（只有街燈保留高光）
	for lx in [-1.2, 3.2]:
		sprite("lamp", Vector3(lx, 0.0, LAMP_Z), {"emit": 2.6})
		omni(Vector3(lx, 2.95, LAMP_Z + 0.25), Color(1.0, 0.6, 0.25), 1.9, 6.0, false, 0.8, 0.05, 0.6)
	# 屋簷間的串燈（點陣電線＋小燈泡）
	var cols := [Color(1.0, 0.75, 0.35), Color(1.0, 0.5, 0.3), Color(1.0, 0.9, 0.55), Color(0.55, 0.9, 0.8)]
	pixel_wire(Vector3(-0.75, 3.4, -2.15), Vector3(5.3, 3.0, -2.3), 0.7, cols)
	pixel_wire(Vector3(-9.5, 2.75, -2.4), Vector3(-4.35, 3.3, -2.2), 0.8, cols)
	# 小船（繫在石階旁）
	boat = sprite("boat", Vector3(BOAT_X, WATER_Y - 0.14, 1.5), {"rough": 0.9, "layer": 17})
	omni(Vector3(BOAT_X + 1.0, 0.1, 1.65), Color(1.0, 0.6, 0.25), 0.9, 2.5, false, 1.0, 0.1)
	# 主角：2 頭身像素角色，站在庭院缺口斜射下來的夕陽裡，身後是陰影中的灰石矮牆
	sprite("hero_anim", HERO, {"rough": 0.9, "rim": 0.0 if "--no-rim" in args else 0.45, "breathe": 1.0, "blink": 1.0, "layer": 128})
	omni(HERO + Vector3(0.3, 0.7, 1.1), Color(1.0, 0.78, 0.6), 1.5, 2.4, false, 0.0)   # 地面光池的反彈光
	# 屋間夕陽的主光束：一盞有陰影的聚光燈，方向與太陽相同，穿過庭院落在主角身上（地面光池＋霧裡看得見的光錐）
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.72, 0.42)
	spot.light_energy = 30.0
	spot.spot_range = 13.0
	spot.spot_angle = 12.0
	spot.light_projector = tex("gobo")
	spot.spot_angle_attenuation = 1.0
	spot.spot_attenuation = 0.3
	spot.shadow_enabled = true
	spot.light_specular = 0.3
	spot.light_volumetric_fog_energy = 0.0 if "--no-beams" in args else 2.2
	add_child(spot)
	var sp_t := HERO + Vector3(0.1, 0.3, 0.3)
	spot.look_at_from_position(sp_t - sun_dir * 9.5, sp_t, Vector3.UP)
	# 光束片：補強體積霧裡的光束（位置都在真實的受光區內，方向 = 太陽方向）
	if not ("--no-beams" in args or "--no-fog" in args):
		beam(HERO + Vector3(0.15, 0.0, 0.4), 10.0, 1.3, 0.45, 1.0)
		beam(Vector3(-6.4, 0.0, -0.9), 9.0, 0.6, 0.25, 4.0)
		beam(Vector3(-5.9, 0.0, -3.4), 7.0, 0.9, 0.3, 7.0)

# 生活感：麵包店店員與麵包架、路人、晾衣繩、信箱、提燈、蔓藤（素材為 codex 生的原創像素圖）
func build_life_props() -> void:
	sprite("street2_0", Vector3(2.75, 0, -2.6), {})                         # 麵包架＋掃把
	sprite("npcs_0", Vector3(1.5, 0, -2.3), {"breathe": 2.0})
	smoke(Vector3(2.95, 4.85, -4.7))                             # 麵包店店員，站在遮雨棚下
	sprite("street2_2", Vector3(-0.2, 1.35, -2.75), {"emit": 3.0, "shadow": false})   # 招牌旁的提燈
	omni(Vector3(-0.2, 1.6, -2.3), Color(1.0, 0.66, 0.3), 0.6, 2.4, false, 0.8, 0.08)
	sprite("street2_1", Vector3(-2.5, 0.75, -2.28), {"shadow": false})      # 紅磚屋的信箱
	sprite("street2_3", Vector3(-8.6, 0, -2.25), {})                        # 蘋果籃
	sprite("props2_3", Vector3(-10.4, 0, -2.3), {})                         # 柴堆
	sprite("props2_0", Vector3(-6.7, 0, -1.85), {})                        # 澆水壺（繡球花旁）
	sprite("props2_1", Vector3(5.25, 0, -2.3), {})                          # 靠牆的長柄掃帚
	sprite("props2_2", Vector3(3.55, 0, -2.5), {})                          # 蓋格紋布的木箱
	# 牆面破損貼片：灰泥剝落露出紅磚，每棟位置與形狀不同
	for pt in [["patches_0", -10.4, 1.95, -2.48, false], ["patches_3", -12.2, 0.9, -2.48, false],  ["patches_3", 2.75, 1.85, -2.78, false], ["patches_2", 0.15, 0.75, -2.78, false], ["patches_4", 3.3, 0.6, -2.78, false], ["patches_0", 6.25, 2.5, -2.38, true], ["patches_2", 8.1, 1.2, -2.38, false]]:
		sprite(pt[0], Vector3(pt[1], pt[2], pt[3]), {"shadow": false, "flip": pt[4]})
	sprite("ivy_0", Vector3(-9.95, 0, -2.47), {"shadow": false, "rustle_px": 0.4})    # 左屋牆上的常春藤
	sprite("ivy_1", Vector3(3.6, -0.1, -2.77), {"shadow": false, "rustle_px": 0.4})   # 麵包店牆角垂下的藤
	# 晾衣繩：庭院裡一條（逆光透亮）、麵包店與右屋之間一條
	laundry(Vector3(4.0, 2.35, -3.4), Vector3(5.2, 2.35, -3.4), [4, 1])

func laundry(p0: Vector3, p1: Vector3, items: Array) -> void:
	pixel_wire(p0, p1, 0.12, [])
	for i in items.size():
		var u := (i + 0.5) / items.size()
		var nm := "laundry_%d" % items[i]
		var h := (px_size(nm).y - 2.0 * PAD) / PPM
		var pt := p0.lerp(p1, u) - Vector3(0, 0.12 * 4.0 * u * (1.0 - u) + h - 0.06, 0.0)
		sprite(nm, Vector3(snappedf(pt.x, 1.0 / PPM), snappedf(pt.y, 1.0 / PPM), pt.z), {"backlight": 0.8, "sway_px": 0.0, "vsway_px": 1.0})

func build_plants() -> void:
	# 庭院：大楓樹（靠紅磚屋側牆，樹影落在牆上）、後方暗色樹籬、左邊小綠樹
	tree(Vector3(-7.7, 0, -6.0), "canopy_autumn", 15, Vector3(1.3, 0.9, 0.8), false, 3.2)
	for i in 10:
		sprite("canopy_green_%d" % (i % 4), Vector3(-11.6 + i * 0.75, 0.4 + (i % 3) * 0.2, -7.6 - (i % 2) * 0.3), {"center": true, "vsway_px": 1.0, "rustle_px": 0.6, "tint": Color(0.3, 0.42, 0.44), "glow_all": 0.12, "backlight": 0.06, "flip": i % 2 == 0})
	for bp in [["bushes_2", -8.8, -3.6], ["bushes_0", -4.7, -3.6], ["bushes_3", -4.6, -4.8], ["bushes_3", -9.2, -4.8]]:
		sprite(bp[0], Vector3(bp[1], 0, bp[2]), {"rustle_px": 0.6, "vsway_px": 1.0, "backlight": 0.4})
	leaf_emitters.append(particles(Vector3(-7.2, 4.3, -4.0), Vector3(2.0, 0.6, 1.6), 30, "leaf_o", {"vary": 1.0, "smin": 0.55}))
	# 屋後遠一點的樹牆（擋住平坦的草地，並給屋頂線一個暗背景）
	for fr in [[-21.0, -9.6, 0.0], [-13.6, -9.2, 0.0], [-6.2, -9.8, 0.0], [1.2, -9.4, 0.0], [8.6, -9.7, 0.0], [16.0, -9.5, 0.0]]:
		var fp := Vector3(fr[0], fr[2], fr[1])
		sprite("forest", fp, {"lit": 0.0, "glow_all": 0.5 if fr[2] == 0.0 else 0.75, "tint": Color(0.5, 0.46, 0.58) if fr[2] == 0.0 else Color(0.42, 0.36, 0.55), "shadow": false, "scale": scale_for(fp, 4.0), "flip": int(absf(fr[0])) % 2 == 0})
	# 樹後的深色樹林層次：幾棵樹幹與樹冠的剪影（冷色、自帶一點亮度），靠光束那一側的樹冠邊緣帶暖色
	for tr in [[-10.2, -8.6, false], [-8.9, -9.1, true], [-5.6, -8.8, false], [-4.7, -9.3, true]]:
		var tp := Vector3(tr[0], 0, tr[1])
		sprite("trunk", tp, {"lit": 0.0, "glow_all": 0.3, "tint": Color(0.36, 0.3, 0.46), "shadow": false, "flip": tr[2]})
		for k in 4:
			var warm: bool = k == 0 and tr[0] < -5.0 and tr[0] > -9.5
			sprite("canopy_green_%d" % ((k + int(absf(tr[0]))) % 4), tp + Vector3(-0.9 + k * 0.6, 3.0 + (k % 2) * 0.55, -0.1 * k), {"center": true, "vsway_px": 2.0, "gust_x": tr[0], "lit": 0.0, "glow_all": 0.42 if warm else 0.24, "tint": Color(0.95, 0.62, 0.36) if warm else Color(0.34, 0.44, 0.5), "shadow": false, "flip": k % 2 == 0})
	# 左下街面的反彈光：很低的一盞暖色小燈（不進霧、沒有高光），讓石板紋理讀得出來
	omni(Vector3(-9.0, 1.3, -0.6), Color(1.0, 0.72, 0.52), 0.9, 5.5, false, 0.0, 0.0, 0.0)
	# 右側屋間的小綠樹＋暗樹籬
	tree(Vector3(4.6, 0, -5.6), "canopy_green", 9, Vector3(1.1, 0.9, 0.7), true)
	for i in 4:
		sprite("canopy_green_%d" % (i % 4), Vector3(3.9 + i * 0.6, 0.8 + (i % 2) * 0.4, -6.9), {"center": true, "vsway_px": 1.0, "rustle_px": 0.6, "tint": Color(0.3, 0.42, 0.44), "glow_all": 0.12, "backlight": 0.06})
	# 補幾團葉子擋住射到 D 屋側牆的零碎陽光（原本在屋間留下幾塊失焦的白斑）
	for i in 6:
		sprite("canopy_green_%d" % (i % 4), Vector3(3.9 + (i % 3) * 0.45, 1.5 + (i / 3) * 1.1 + (i % 2) * 0.3, -4.9 - (i % 2) * 0.5), {"center": true, "vsway_px": 2.0, "rustle_px": 0.8, "backlight": 0.5, "flip": i % 2 == 1})
	leaf_emitters.append(particles(Vector3(3.6, 4.4, -2.0), Vector3(2.6, 0.5, 1.5), 14, "leaf_r", {"vary": 1.0, "smin": 0.55}))
	leaf_emitters.append(particles(Vector3(-1.0, 4.6, -1.5), Vector3(7.0, 0.5, 1.0), 13, "leaf_r", {"vary": 1.0, "smin": 0.55}))
	# 牆腳的草與花（主角身後那段矮牆留白，讓她跳出來）
	for i in 60:
		var x := rng.randf_range(-10.0, 9.0)
		var z := -2.28
		if x > -9.5 and x < -4.25:
			if x > -7.5 and x < -4.4: continue
			z = -2.3
		elif x > -4.3 and x < -0.8: z = -2.1
		elif x > -0.5 and x < 3.9: z = -2.6
		elif x > 3.9 and x < 5.3: z = rng.randf_range(-4.6, -2.9)
		elif x > 5.3: z = -2.2
		if i % 3 == 0:
			sprite("grasses_%d" % (i % 5), Vector3(x, 0, z + rng.randf_range(-0.03, 0.06)), {"sway_px": 3.0, "backlight": 0.5, "glow_all": 0.1, "tint": Color(0.62, 0.85, 0.62), "flip": i % 2 == 0, "shadow": false, "layer": 17})
		else:
			sprite("plants2_%d" % (rng.randi() % 8), Vector3(x, 0, z + rng.randf_range(-0.03, 0.06)), {"sway_px": 2.0, "backlight": 0.4, "flip": i % 2 == 0, "shadow": false, "layer": 17})
	for fp in [[-7.9, -2.25, 2], [-7.2, -2.2, 3], [-8.7, -2.25, 3], [-3.6, -2.05, 0], [0.9, -2.55, 4], [1.9, -2.55, 1], [4.3, -3.1, 5], [4.9, -3.4, 2], [5.6, -2.2, 0], [6.4, -2.15, 4], [-9.6, -2.3, 1]]:
		sprite("flowers_%d" % fp[2], Vector3(fp[0], 0, fp[1]), {"sway_px": 2.0, "backlight": 0.25, "shadow": false, "layer": 17})
	sprite("bushes_2", Vector3(-8.2, 0, -2.2), {"rustle_px": 0.6, "vsway_px": 1.0, "backlight": 0.4})     # 藍繡球（冷色）
	sprite("bushes_1", Vector3(4.4, 0, -3.3), {"rustle_px": 0.6, "vsway_px": 1.0, "backlight": 0.4})
	sprite("bushes_3", Vector3(5.0, 0, -3.8), {"rustle_px": 0.6, "vsway_px": 1.0, "backlight": 0.4})
	# 庭院裡的野花
	for i in 9:
		sprite("flowers_%d" % (i % 6), Vector3(rng.randf_range(-8.0, -4.6), 0, rng.randf_range(-5.0, -3.0)), {"sway_px": 2.0, "backlight": 0.25, "shadow": false, "layer": 17})
	# 地上的落葉（平躺）
	for i in 90:
		var near_tree := i < 55
		var lp := Vector3(rng.randf_range(-8.5, -1.0) if near_tree else rng.randf_range(-10.0, 9.0), 0.012, rng.randf_range(-2.2, 0.2))
		var lf := sprite("leaf_o" if i % 3 else "leaf_r", lp, {"center": true, "frame_fixed": float(i % 4), "shadow": false})
		lf.rotation = Vector3(-PI / 2, 0, 0)
		lf.scale.x = -1.0 if i % 2 else 1.0
	# 前景河岸：離鏡頭近，改用半尺寸（螢幕上仍約 4 px / 點陣），再由景深模糊
	var fs := 0.5
	for i in 150:
		var x := rng.randf_range(-9.0, 5.5)
		var z := rng.randf_range(FG_Z + 0.1, FG_Z + 2.0)
		sprite("plants2_%d" % (i % 8), Vector3(x, FG_Y, z), {"sway_px": 2.0, "backlight": 0.4, "flip": i % 2 == 0, "shadow": false, "scale": fs})
	for i in 30:
		sprite("flowers_%d" % (i % 6), Vector3(rng.randf_range(-8.5, 5.0), FG_Y, rng.randf_range(FG_Z + 0.1, FG_Z + 1.4)), {"sway_px": 2.0, "backlight": 0.5, "shadow": false, "scale": fs})
	for bp in [["bushes_1", -6.4, 0.6], ["bushes_3", -1.2, 0.9], ["bushes_2", 2.6, 0.5], ["bushes_0", -3.6, 1.3]]:
		sprite(bp[0], Vector3(bp[1], FG_Y, FG_Z + bp[2]), {"rustle_px": 0.6, "vsway_px": 1.0, "backlight": 0.4, "scale": fs})
	# 前景左上角：只在畫面邊緣垂下三小枝（半尺寸），自帶一點暖色所以不是一團黑
	for d in [[-1.02, 0.93, 6.6], [-0.86, 1.02, 7.0], [-1.08, 0.7, 7.3]]:
		var cp := screen_point(d[0], d[1], d[2])
		sprite("canopy_autumn_%d" % (int(d[2] * 10.0) % 4), cp, {"center": true, "vsway_px": 3.0, "rustle_px": 1.0, "backlight": 0.15, "glow_all": 0.04, "tint": Color(0.36, 0.2, 0.24), "scale": fs})
	# 漂在運河上的落葉（平躺在水面，慢慢往右漂）
	for i in 16:
		var wl := sprite("leaf_o" if i % 2 else "leaf_r", Vector3(rng.randf_range(-11.0, 6.0), WATER_Y + 0.012, rng.randf_range(0.9, 4.2)), {"center": true, "frame_fixed": float(i % 4), "shadow": false, "glow_all": 0.25})
		wl.rotation = Vector3(-PI / 2, 0, 0)
		flyers.append({"n": wl, "kind": "float", "v": rng.randf_range(0.05, 0.12)})
	# 睡蓮葉（平躺在水面，補綠色；避開燈光倒影的位置）
	for lp in [[-9.6, 1.2], [-9.1, 1.5], [-8.7, 1.1], [-6.9, 2.3], [-6.4, 2.6], [-4.6, 1.0], [-4.1, 1.3], [1.6, 2.6], [2.1, 2.3], [5.9, 1.9], [6.4, 2.2], [6.1, 2.6], [0.4, 3.6], [-2.4, 3.3], [-7.8, 3.6], [-8.3, 3.3]]:
		var ll := sprite("lily", Vector3(lp[0], WATER_Y + 0.01, lp[1]), {"center": true, "frame_fixed": float(int(absf(lp[0]) * 10.0) % 3), "shadow": false, "glow_all": 0.5})
		ll.rotation = Vector3(-PI / 2, 0, 0)
	# 光塵
	particles(HERO + Vector3(0.5, 1.6, 0.0), Vector3(2.4, 1.4, 1.2), 26, "mote", {"dir": Vector3(1, 0.3, 0), "spread": 180.0, "v0": 0.03, "v1": 0.12, "gravity": Vector3(0.03, 0.01, 0), "turb": 0.4, "life": 8.0, "glow": 0.0, "size_px": 1.0})

func build_far() -> void:
	pass      # 遠景的山與針葉林剪影改畫在天空背板裡（sky2d.gdshader），和天空一樣保持銳利

func build_life() -> void:
	# 飛鳥：一小群橫越屋頂上方，每隻有自己的速度、高度與拍翅節奏
	for i in 7:
		var s := sprite("bird", Vector3.ZERO, {"lit": 0.0, "glow_all": 1.0, "tint": Color(0.1, 0.07, 0.13), "fps": 6.0 + rng.randf() * 3.0, "shadow": false, "center": true})
		flyers.append({"n": s, "kind": "bird", "x0": rng.randf_range(0.0, 9.0), "y": rng.randf_range(4.75, 5.55), "z": rng.randf_range(-2.0, 0.5), "v": rng.randf_range(0.8, 1.5), "p": rng.randf() * 6.0, "bob": rng.randf_range(0.08, 0.22)})
	# 蝴蝶（大隻、飽和色）：一隻在主角身邊的夕陽裡
	var spots := [[HERO + Vector3(1.55, 0.5, 0.3), "bflyL_y"], [Vector3(-7.4, 0.95, -2.0), "bflyL_b"], [Vector3(-3.4, 1.0, -1.9), "bflyL_o"], [Vector3(1.6, 1.1, -2.3), "bflyL_b"], [Vector3(4.6, 0.9, -2.8), "bflyL_y"], [Vector3(-2.0, 0.4, FG_Z + 0.4), "bflyL_o"]]
	for sp in spots:
		var p: Vector3 = sp[0]
		var sc := 0.5 if p.z > 3.0 else 1.0
		var s := sprite(sp[1], p, {"fps": 9.0, "shadow": false, "center": true, "backlight": 0.5, "glow_all": 0.35, "scale": sc, "layer": 256})
		flyers.append({"n": s, "kind": "bfly", "c": p, "p": rng.randf() * 20.0})

func build_sky() -> void:
	# 天空背板：掛在鏡頭前 220 m、蓋滿視野的四邊形（內容見 sky2d.gdshader）
	var d := 220.0
	var hh := d * tan(deg_to_rad(FOV * 0.5)) * 1.1
	var q := QuadMesh.new()
	q.size = Vector2(hh * 2.0 * 16.0 / 9.0, hh * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/sky2d.gdshader")
	var cl := ["clouds3_0", "clouds3_1", "clouds3_0"]
	for i in 3:
		m.set_shader_parameter("c%d" % i, tex(cl[i]))
		m.set_shader_parameter("s%d" % i, Vector2(meta[cl[i]][0], meta[cl[i]][1]))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 512
	cam.add_child(mi)
	mi.position = Vector3(0, 0, -d)

func build_post() -> void:
	var layer := CanvasLayer.new()
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/vignette.gdshader")
	r.material = m
	layer.add_child(r)
	add_child(layer)

func _process(dt: float) -> void:
	t += dt
	frames_n += 1
	sync_mirrors()
	var px := 1.0 / PPM
	for f in flyers:
		var n: MeshInstance3D = f.n
		match f.kind:
			"float":
				n.position.x += f.v * dt
				if n.position.x > 7.0: n.position.x = -12.0
			"bird":
				var u := fmod(f.x0 + t * f.v + 4.0, 26.0)
				n.position = Vector3(8.0 - u, f.y + sin(t * 1.1 + f.p) * f.bob, f.z)
				n.scale.x = -1.0
			"bfly":
				var c: Vector3 = f.c
				var p: float = f.p
				var x := sin(t * 0.7 + p) * 0.6 + sin(t * 1.9 + p * 2.0) * 0.2
				var y := sin(t * 1.3 + p * 1.7) * 0.25 + sin(t * 3.1 + p) * 0.07
				var z := cos(t * 0.5 + p) * 0.15
				var np := c + Vector3(x, y, z)
				n.scale.x = 1.0 if np.x >= n.position.x else -1.0
				n.position = Vector3(snappedf(np.x, px), snappedf(np.y, px), np.z)
	# 店員的待機動作：每隔幾秒低頭看一下籃子（整個人下移 1 點陣）
	if boat: boat.position.y = WATER_Y - 0.14 + snappedf(sin(t * 1.57) * 1.5 / PPM, 1.0 / PPM)      # 小船隨水上下 1 點陣
	for fl in flickers:
		var l: OmniLight3D = fl.l
		l.light_energy = fl.e * (1.0 + fl.a * (sin(t * 9.0 + fl.p) * 0.6 + sin(t * 23.0 + fl.p * 3.0) * 0.4))
	# 落葉跟著同一陣風：陣風來時往右吹得更遠
	for e in leaf_emitters:
		var pm: ParticleProcessMaterial = e.process_material
		pm.gravity = Vector3(0.15 + 1.1 * gust(t, e.position.x), -0.42, 0.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_tree().quit()

# ------------------------------------------------------------------ 截圖模式
func grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func run_shots() -> void:
	var tag := ""
	var only_one := false
	var out := "r11"
	for a in args:
		if a.begins_with("--tag="): tag = a.substr(6); only_one = true
		if a.begins_with("--out="): out = a.substr(6)
	var dir := ProjectSettings.globalize_path("res://").path_join("../shots/godot/" + out).simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(2.5).timeout
	var f0 := frames_n
	await get_tree().create_timer(1.0).timeout
	print("fps(1s)=", frames_n - f0)
	if only_one:
		var im: Image = await grab()
		im.save_png(dir.path_join("compare_%s.png" % tag))
		print("saved compare_", tag, " ", im.get_size())
		get_tree().quit()
		return
	var hp := cam.unproject_position(HERO + Vector3(0, 0.7, 0))
	for i in 3:
		var img: Image = await grab()
		img.save_png(dir.path_join("full_%d.png" % (i + 1)))
		print("saved full_", i + 1, " ", img.get_size(), " t=", snappedf(t, 0.01))
		if i == 2:
			var r1 := Rect2i(clampi(int(hp.x) - 330, 0, 960), clampi(int(hp.y) - 170, 0, 540), 960, 540)
			img.get_region(r1).save_png(dir.path_join("closeup_hero_reflection.png"))
			img.get_region(Rect2i(clampi(int(hp.x) - 420, 0, 960), 0, 960, 540)).save_png(dir.path_join("closeup_tree_lightshaft.png"))
		else:
			await get_tree().create_timer(2.0).timeout
	get_tree().quit()
