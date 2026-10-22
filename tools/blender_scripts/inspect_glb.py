"""Inspecte des fichiers .glb/.fbx : objets, dimensions, squelettes, animations.
blender -b -P inspect_glb.py -- fichier1.glb fichier2.glb ...
"""
import sys

import bpy
from mathutils import Vector

files = sys.argv[sys.argv.index("--") + 1:]
for path in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    print("=" * 80)
    print("FILE", path)
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    meshes = 0
    tris = 0
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            meshes += 1
            tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
            for c in ob.bound_box:
                w = ob.matrix_world @ Vector(c)
                mn = Vector(map(min, mn, w))
                mx = Vector(map(max, mx, w))
    print(f"meshes={meshes} tris={tris} bbox min={tuple(round(v, 2) for v in mn)} max={tuple(round(v, 2) for v in mx)} size={tuple(round(v, 2) for v in (mx - mn))}")
    names = [ob.name for ob in bpy.data.objects if ob.type == "MESH"]
    print("mesh objects:", names[:40], "..." if len(names) > 40 else "")
    for ob in bpy.data.objects:
        if ob.type == "ARMATURE":
            bones = [b.name for b in ob.data.bones]
            print(f"ARMATURE {ob.name}: {len(bones)} bones: {bones[:60]}")
    print("materials:", [m.name for m in bpy.data.materials][:30])
    print("actions:", [(a.name, round(a.frame_range[1] - a.frame_range[0])) for a in bpy.data.actions])
