"""
Prépare le boîtier à fusibles « Vintage Fuse Box » (Sketchfab, filip.alecsandru, CC-BY) :
- retire un des quatre fusibles vissés (il reste 3 logements vides : ceux que Théo doit remplir) ;
- exporte ce fusible seul (objet ramassable / fusible remis en place), centré sur lui-même ;
- ajoute des repères « Socket_1..3 » au centre des logements vides.

blender -b --factory-startup -P split_fusebox.py -- source.glb boitier.glb fusible.glb
"""
import sys

import bpy
from mathutils import Vector

src, out_box, out_fuse = sys.argv[sys.argv.index("--") + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
# tout en coordonnées monde, sans hiérarchie
for o in list(bpy.data.objects):
    if o.type == "MESH":
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type == "MESH":
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)
box = next(o for o in bpy.data.objects if o.type == "MESH")
bpy.ops.object.select_all(action="DESELECT")
box.select_set(True)
bpy.context.view_layer.objects.active = box
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")


def center(o):
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return sum(bb, Vector()) / 8.0


# logements (6) : x = ±6.6, z = -0.9 / -11.9 / -22.8 ; fusibles présents : corps de 60 sommets vers y = 9.2
REMOVE = Vector((-6.6, 0, -11.9))
EMPTY = [Vector((6.6, 0, -0.9)), Vector((-6.6, 0, -22.8)), Vector((-6.6, 0, -11.9))]
parts = [o for o in bpy.data.objects if o.type == "MESH"]
fuse_parts = []
for o in parts:
    c = center(o)
    if abs(c.x - REMOVE.x) < 0.5 and abs(c.z - REMOVE.z) < 0.5 and len(o.data.vertices) in (60, 56, 28):
        fuse_parts.append(o)
print("FUSIBLE", [(o.name, len(o.data.vertices)) for o in fuse_parts])
body = next(o for o in fuse_parts if len(o.data.vertices) == 60)
body_c = center(body)

# le fusible seul, centré sur son corps
bpy.ops.object.select_all(action="DESELECT")
for o in fuse_parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = fuse_parts[0]
bpy.ops.object.join()
fuse = bpy.context.view_layer.objects.active
fuse.name = "Fuse"
for v in fuse.data.vertices:
    v.co -= body_c
bpy.ops.object.select_all(action="DESELECT")
fuse.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_fuse, export_format="GLB", use_selection=True, export_image_format="JPEG", export_yup=True)
print("EXPORT", out_fuse)
bpy.data.objects.remove(fuse)

# le boîtier (un seul objet) + repères des logements vides
rest = [o for o in bpy.data.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in rest:
    o.select_set(True)
bpy.context.view_layer.objects.active = rest[0]
bpy.ops.object.join()
fb = bpy.context.view_layer.objects.active
fb.name = "FuseBox"
for i, e in enumerate(EMPTY):
    m = bpy.data.objects.new("Socket_%d" % (i + 1), None)
    bpy.context.scene.collection.objects.link(m)
    m.location = Vector((e.x, body_c.y, e.z))
    m.select_set(True)
fb.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_box, export_format="GLB", use_selection=True, export_image_format="JPEG", export_yup=True)
print("EXPORT", out_box, "corps du fusible en", tuple(round(v, 2) for v in body_c))
