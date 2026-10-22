"""Debug : position monde de quelques os à une frame d'une action d'un .glb exporté."""
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
path, action = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
print("armature", arm.name, "loc", tuple(round(v, 3) for v in arm.matrix_world.to_translation()), "scale", tuple(round(v, 3) for v in arm.matrix_world.to_scale()))
print("parent chain:", [p.name for p in [arm.parent] if p])
act = bpy.data.actions.get(action) or next(a for a in bpy.data.actions if action in a.name)
arm.animation_data_create()
arm.animation_data.action = act
for f in (1, 10):
    bpy.context.scene.frame_set(f)
    out = []
    for b in arm.pose.bones:
        n = b.name.split(":")[-1]
        if any(k in n for k in ("Pelvis", "Hips", "Head", "Foot", "Toe0", "ToeBase")) and "End" not in n:
            w = arm.matrix_world @ b.head
            out.append(f"{n}=({w.x:.2f},{w.y:.2f},{w.z:.2f})")
    print("frame", f, " ".join(out))
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
print("mesh", mesh.name, "parent", mesh.parent.name if mesh.parent else None, "world z range", min((mesh.matrix_world @ v.co).z for v in mesh.data.vertices), max((mesh.matrix_world @ v.co).z for v in mesh.data.vertices))
