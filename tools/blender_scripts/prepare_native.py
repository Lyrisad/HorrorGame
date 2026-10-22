"""
Prépare un personnage déjà animé par son auteur (modèle Sketchfab avec ses propres animations)
pour le jeu : même sortie que retarget.py (assets/characters/<nom>/<nom>.glb + .anims.json).

  blender -b --factory-startup -P prepare_native.py -- config.json

config :
  "src": modèle .glb d'origine, "out": .glb produit
  "remove_objects": préfixes d'objets à supprimer (ex. "Icosphere")
  "ref_action" + "height": action de référence (pose en T) et sa hauteur voulue en mètres
  "rename_bones": {ancien: nouveau} (noms standards : Hips, Spine, Neck, Head...)
  "actions": [{"src": nom d'origine, "name": nom dans le jeu, "loop": bool,
               "start"/"end": frames (30 i/s), "lift": décalage vertical (m, après mise à l'échelle),
               "speed": vitesse au sol imposée (m/s)}]
Les animations d'origine sont « sur place » : la vitesse au sol de chaque cycle est mesurée sur les
appuis (mains/pieds posés qui glissent vers l'arrière), pour que le jeu cale la lecture dessus.
"""
import json
import statistics
import sys

import bpy
from mathutils import Vector

FPS = 30
cfg = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))


def mesh_points(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in m.vertices]
        ev.to_mesh_clear()
    return pts


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS  # avant l'import : les clés tombent sur des frames entières
    bpy.ops.import_scene.gltf(filepath=cfg["src"])
    for o in list(bpy.data.objects):
        if any(o.name.startswith(p) for p in cfg.get("remove_objects", [])):
            bpy.data.objects.remove(o, do_unlink=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.animation_data_create()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    acts = {a.name: a for a in bpy.data.actions}

    # renommage des os (+ chemins d'animation et groupes de sommets)
    ren = cfg.get("rename_bones", {})
    for old, new in ren.items():
        if old in arm.data.bones:
            arm.data.bones[old].name = new
    for a in bpy.data.actions:
        for fc in a.fcurves:
            for old, new in ren.items():
                key = f'pose.bones["{old}"]'
                if key in fc.data_path:
                    fc.data_path = fc.data_path.replace(key, f'pose.bones["{new}"]')
    for o in meshes:
        for vg in o.vertex_groups:
            if vg.name in ren:
                vg.name = ren[vg.name]

    # mise à l'échelle d'après la pose de référence
    arm.animation_data.action = acts[cfg["ref_action"]]
    scene.frame_set(0)
    pts = mesh_points(meshes)
    h = max(p.z for p in pts) - min(p.z for p in pts)
    s = cfg["height"] / h
    roots = {o for o in bpy.data.objects if o.parent is None}
    for r in roots:
        r.matrix_world = r.matrix_world.copy()
        r.scale = r.scale * s
        r.location = r.location * s
    bpy.context.view_layer.update()
    print(f"échelle {s:.4f} (hauteur de référence {h:.3f})")

    root_pb = arm.pose.bones[0]  # os racine (_rootJoint) : sert au décalage vertical
    rest_inv = (arm.matrix_world.to_3x3() @ root_pb.bone.matrix_local.to_3x3()).inverted()
    limbs = [b.name for b in arm.data.bones if any(k in b.name.lower() for k in ("toe", "hand", "foot", "middle2"))]

    info = []
    keep = set()
    for spec in cfg["actions"]:
        act = acts[spec["src"]]
        f0, f1 = (int(round(v)) for v in act.frame_range)
        f0 = spec.get("start", f0)
        f1 = spec.get("end", f1)
        # certaines actions d'origine n'animent pas tous les os (le galop ne bouge pas le bassin) :
        # ils gardent alors la pose de référence. On part donc de celle-ci et on « cuit » chaque os
        # à chaque frame, pour que l'animation se joue à l'identique dans le moteur.
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.scale = (1, 1, 1)
        arm.animation_data.action = acts[cfg["ref_action"]]
        scene.frame_set(0)
        arm.animation_data.action = act
        d = rest_inv @ Vector((0, 0, spec.get("lift", 0.0)))
        baked = []
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            baked.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in arm.pose.bones})
        for f, pose in zip(range(f0, f1 + 1), baked):
            for pb in arm.pose.bones:
                loc, rot, sc = pose[pb.name]
                # décalage vertical (le galop d'origine flotte au-dessus du sol, par ex.)
                pb.location = loc + d if pb == root_pb else loc
                pb.rotation_quaternion = rot
                pb.scale = sc
                for ch in ("location", "rotation_quaternion", "scale"):
                    pb.keyframe_insert(ch, frame=f)
        # recadrage : la plage gardée commence à la frame 0
        if f0 != int(round(act.frame_range[0])) or f1 != int(round(act.frame_range[1])):
            for fc in act.fcurves:
                for kp in list(fc.keyframe_points):
                    if kp.co.x < f0 - 1e-3 or kp.co.x > f1 + 1e-3:
                        fc.keyframe_points.remove(kp, fast=True)
                for kp in fc.keyframe_points:
                    kp.co.x -= f0
                    kp.handle_left.x -= f0
                    kp.handle_right.x -= f0
                fc.update()
            act.frame_range = (0, f1 - f0)
            f1 -= f0
            f0 = 0
        # vitesse au sol : glissement vers l'arrière des appuis (l'avant du modèle est -Y Blender)
        speed = spec.get("speed")
        if speed is None and spec.get("loop"):
            track = []
            for f in range(f0, f1 + 1):
                scene.frame_set(f)
                track.append({l: arm.matrix_world @ arm.pose.bones[l].head for l in limbs})
            vs = []
            for l in limbs:
                lowz = min(t[l].z for t in track)
                for i in range(1, len(track)):
                    p, q = track[i - 1][l], track[i][l]
                    if p.z < lowz + 0.02 and q.z < lowz + 0.02:
                        vs.append((q.y - p.y) * FPS)
            speed = max(statistics.median(vs), 0.0) if len(vs) >= 4 else 0.0
        act.name = spec["name"]
        act.use_fake_user = True
        keep.add(act.name)
        # sol de l'action : point le plus bas du maillage sur le cycle
        lows = []
        for f in range(f0, f1 + 1, max(1, (f1 - f0) // 8)):
            scene.frame_set(f)
            lows.append(min(p.z for p in mesh_points(meshes)))
        frames = f1 - f0 + (0 if spec.get("loop") else 1)
        print(f"CLIP {spec['name']:10s} <- {spec['src']:24s} {frames} frames, {frames / FPS:.2f}s, vitesse ~{speed or 0:.2f} m/s, sol [{min(lows):.3f}, {max(lows):.3f}]")
        info.append({"name": spec["name"], "frames": frames, "seconds": frames / FPS, "speed": round(speed or 0.0, 3)})
    for a in list(bpy.data.actions):
        if a.name not in keep:
            bpy.data.actions.remove(a)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    bpy.ops.export_scene.gltf(
        filepath=cfg["out"], export_format="GLB", export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_image_format="JPEG", export_jpeg_quality=88, export_yup=True,
    )
    with open(cfg["out"][:-4] + ".anims.json", "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    print("EXPORT OK", cfg["out"])


main()
