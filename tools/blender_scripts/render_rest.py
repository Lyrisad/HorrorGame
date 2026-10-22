"""Debug : rendu (Workbench) d'un personnage dans sa pose de repos, de face et de dos.
blender -b --factory-startup -P render_rest.py -- modele.fbx|.glb sortie_prefixe [action frame]
"""
import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
path, out = args[0], args[1]
action = args[2] if len(args) > 2 else ""
frame = int(args[3]) if len(args) > 3 else 1
if path.lower().endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=path)
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o)
elif path.lower().endswith(".fbx"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True, ignore_leaf_bones=False)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if arm is not None:
    arm.animation_data_create()
    act = bpy.data.actions.get(action) if action else None
    arm.animation_data.action = act
    if act is None:
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
bpy.context.scene.frame_set(frame)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in meshes:
    ev = o.evaluated_get(dg)
    m = ev.to_mesh()
    pts += [ev.matrix_world @ v.co for v in m.vertices]
    ev.to_mesh_clear()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (lo + hi) * 0.5
size = max(hi.x - lo.x, hi.z - lo.z)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = size * 1.05
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
for name, direction in (("front", Vector((0, -1, 0))), ("back", Vector((0, 1, 0)))):
    cam.location = c + direction * 10.0
    cam.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
print("RENDU", out, "taille", tuple(round(v, 2) for v in (hi - lo)))
