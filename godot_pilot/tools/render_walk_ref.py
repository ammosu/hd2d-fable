# 走路姿勢參考：Quaternius「Beach Character」（CC0）的 Walk 動作，從遊戲同樣的 33° 俯角、正面／背面／側面各取 4 格。
#   blender -b -P tools/render_walk_ref.py -- <glb> <輸出資料夾>
import bpy, sys, math, os
from mathutils import Vector
glb, out = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
act = next(a for a in bpy.data.actions if a.name.endswith("Walk"))
arm.animation_data.action = act
f0, f1 = act.frame_range
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "OBJECT"
sc.render.film_transparent = True
sc.render.resolution_x, sc.render.resolution_y = 256, 320
for o in sc.objects:
    if o.type == "MESH": o.color = (0.15, 0.15, 0.2, 1)
# 依包圍盒找中心與高度
sc.frame_set(int(f0))
pts = [o.matrix_world @ Vector(c) for o in sc.objects if o.type == "MESH" for c in o.bound_box]
zmax = max(p.z for p in pts); cz = zmax * 0.5
cam_d = bpy.data.cameras.new("c"); cam_d.type = "ORTHO"; cam_d.ortho_scale = zmax * 1.45
cam = bpy.data.objects.new("c", cam_d); sc.collection.objects.link(cam); sc.camera = cam
pitch = math.radians(33.0)
views = {"front": 0.0, "side": 90.0, "back": 180.0}   # 角色朝 -Y（glTF 前方）；鏡頭繞 Z 轉
for name, yaw in views.items():
    a = math.radians(yaw)
    d = Vector((math.sin(a) * math.cos(pitch), -math.cos(a) * math.cos(pitch), math.sin(pitch)))
    cam.location = Vector((0, 0, cz)) + d * 20.0
    cam.rotation_euler = (d * -1).to_track_quat("-Z", "Y").to_euler()
    for i in range(4):
        fr = f0 + (f1 - f0) * i / 4.0
        sc.frame_set(int(round(fr)))
        sc.render.filepath = os.path.join(out, f"{name}_{i}.png")
        bpy.ops.render.render(write_still=True)
print("RANGE", f0, f1)
