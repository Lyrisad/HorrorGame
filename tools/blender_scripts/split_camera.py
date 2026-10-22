"""
Sépare la caméra de surveillance (Poly Haven « security_camera_01 », CC0) en deux : le support mural
(platine + bras, fixe) et la tête (boîtier + rotule, qui pivote). Les coordonnées d'origine sont gardées :
les deux morceaux se superposent exactement. Rotule (axe de pivot) vers (0, 0.07, -0.03) en coordonnées Godot.

blender -b --factory-startup -P split_camera.py -- source.gltf support.glb tete.glb
"""
import sys

import bpy
from mathutils import Vector

src, out_mount, out_head = sys.argv[sys.argv.index("--") + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
o = next(o for o in bpy.data.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = o
o.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
mount, head = [], []
for p in [p for p in bpy.data.objects if p.type == "MESH"]:
    bb = [p.matrix_world @ Vector(c) for c in p.bound_box]
    cz = sum(v.z for v in bb) / 8.0  # Blender : Z vers le haut
    (mount if cz < 0.07 else head).append(p)
print("SUPPORT", len(mount), "TETE", len(head))


def export(parts, name, path):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j.name = name
    bpy.ops.object.select_all(action="DESELECT")
    j.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format="JPEG", export_yup=True)
    bb = [j.matrix_world @ Vector(c) for c in j.bound_box]
    print("EXPORT", name, path, "z", round(min(v.z for v in bb), 3), round(max(v.z for v in bb), 3))


export(mount, "CameraMount", out_mount)
export(head, "CameraHead", out_head)
