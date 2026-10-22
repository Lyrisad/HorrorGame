"""
Retargeting de captures de mouvement CMU (BVH) vers un personnage riggé, puis export .glb.

blender -b --factory-startup -P retarget.py -- config.json

config.json :
{
  "target": "personnage.glb|.fbx",
  "rig": "mixamo" | "biped",
  "out": "sortie.glb",
  "height": 1.8,                       # optionnel : remise à l'échelle du personnage
  "remove_objects": ["Icosphere"],     # objets parasites à supprimer
  "texture_dir": "...",                # FBX Rocketbox : dossier des .tga
  "max_texture": 2048,
  "clips": [{"name": "walk", "bvh": "35_01.bvh", "start": 0, "end": -1,
             "loop": true, "inplace": true, "min_loop": 0.8}]
}

Méthode : pour chaque os apparié, on aligne la direction de repos de l'os cible sur
celle de l'os source (corrige T-pose / A-pose), puis on applique la rotation "monde"
de la source depuis son repos. Les clips sont réorientés pour que le personnage
regarde vers l'avant, et rendus "sur place" (le jeu gère le déplacement).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

cfg = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8-sig"))
FPS = 30

MAP_MIXAMO = {
    "Hips": "Hips", "LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Neck": "Neck", "Head": "Head",
    "LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToeBase",
}
MAP_BIPED = {
    "Hips": "Pelvis", "LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Neck": "Neck", "Head": "Head",
    "LeftShoulder": "L Clavicle", "LeftArm": "L UpperArm", "LeftForeArm": "L Forearm", "LeftHand": "L Hand",
    "RightShoulder": "R Clavicle", "RightArm": "R UpperArm", "RightForeArm": "R Forearm", "RightHand": "R Hand",
    "LeftUpLeg": "L Thigh", "LeftLeg": "L Calf", "LeftFoot": "L Foot", "LeftToeBase": "L Toe0",
    "RightUpLeg": "R Thigh", "RightLeg": "R Calf", "RightFoot": "R Foot", "RightToeBase": "R Toe0",
}
UP = Vector((0, 0, 1))
PREF_CHILD = {"Hips": "LowerBack", "LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Neck", "Neck": "Head"}


def core_name(n):
    core = n.split(":")[-1]
    if core.startswith("Bip01 "):
        core = core[6:]
    if "_" in core and core.rsplit("_", 1)[1].isdigit():
        core = core.rsplit("_", 1)[0]
    return core


def find_bone(arm, suffix):
    for b in arm.data.bones:
        if core_name(b.name) == suffix:
            return b.name
    for b in arm.data.bones:
        if core_name(b.name).lower() == suffix.lower():
            return b.name
    return None


def import_target():
    path = cfg["target"]
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True, ignore_leaf_bones=False)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    for name in cfg.get("remove_objects", []):
        for ob in list(bpy.data.objects):
            if ob.name.startswith(name):
                bpy.data.objects.remove(ob, do_unlink=True)
    # actions importées inutiles
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    return next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")


def fix_rocketbox_materials():
    tdir = cfg.get("texture_dir")
    if not tdir:
        return
    files = {f.lower(): os.path.join(tdir, f) for f in os.listdir(tdir)}
    maxs = cfg.get("max_texture", 2048)
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        stem = mat.name.lower().split(".")[0]

        def load(kind):
            cands = sorted(f for f in files if f.startswith(stem + "_") and kind in f)
            if not cands:
                return None
            img = bpy.data.images.load(files[cands[0]], check_existing=True)
            if max(img.size) > maxs:
                img.scale(maxs, maxs)
            return img

        col = load("_color")
        nor = load("_normal")
        if col is None:
            print("  pas de texture pour", mat.name)
            continue
        for n in list(nt.nodes):
            if n.type in ("TEX_IMAGE", "NORMAL_MAP"):
                nt.nodes.remove(n)
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = col
        nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
        if col.depth == 32 and ("hair" in stem or "lash" in stem or "opacity" in stem):
            nt.links.new(tn.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = "CLIP"
        if nor:
            nor.colorspace_settings.name = "Non-Color"
            tn2 = nt.nodes.new("ShaderNodeTexImage")
            tn2.image = nor
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tn2.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Roughness"].default_value = 0.6 if "head" in stem else 0.75
        bsdf.inputs["Metallic"].default_value = 0.0
        print("  matériau", mat.name, "->", col.name, nor.name if nor else "")


def rest_world(arm, bname):
    return arm.matrix_world @ arm.data.bones[bname].matrix_local


def child_dir_world(arm, bname, mapped):
    b = arm.data.bones[bname]
    for c in b.children_recursive:
        if c.name in mapped:
            d = (arm.matrix_world @ c.head_local) - (arm.matrix_world @ b.head_local)
            if d.length > 1e-4:
                return d.normalized()
    d = (arm.matrix_world @ b.tail_local) - (arm.matrix_world @ b.head_local)
    return d.normalized()


def facing(left_vec):
    """Direction "devant" à partir du vecteur vers la gauche du personnage (Z haut)."""
    f = left_vec.cross(UP)
    f.z = 0
    return f.normalized() if f.length > 1e-6 else Vector((0, -1, 0))


def yaw_of(v):
    return math.atan2(v.y, v.x)


def retarget_clip(tarm, clip, mapping):
    bvh = clip["bvh"]
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=bvh, axis_forward="-Z", axis_up="Y", rotate_mode="NATIVE",
                            update_scene_fps=False, update_scene_duration=False, global_scale=1.0)
    sarm = next(ob for ob in bpy.data.objects if ob not in before and ob.type == "ARMATURE")
    sact = sarm.animation_data.action
    f0, f1 = (int(v) for v in sact.frame_range)
    src_fps = 120.0
    with open(bvh, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if line.strip().startswith("Frame Time"):
                src_fps = 1.0 / float(line.split(":")[1])
                break

    pairs = []
    for sname, tsuffix in mapping.items():
        if sname not in sarm.data.bones:
            continue
        tname = find_bone(tarm, tsuffix)
        if tname is None:
            print("  os cible introuvable:", tsuffix)
            continue
        pairs.append((sname, tname))
    pmap = dict(pairs)
    tmapped = set(pmap.values())
    smapped = set(pmap.keys())
    t_hips = pmap["Hips"]

    # échelle (hauteur des hanches au repos, mesurée depuis les pieds)
    s_feet = [b for b in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot") if b in sarm.data.bones]
    t_feet = [pmap[b] for b in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot") if b in pmap]
    s_rest_floor = min((sarm.matrix_world @ sarm.data.bones[b].head_local).z for b in s_feet)
    t_floor = min((tarm.matrix_world @ tarm.data.bones[b].head_local).z for b in t_feet)
    s_hip_h = (sarm.matrix_world @ sarm.data.bones["Hips"].head_local).z - s_rest_floor

    def leg_len(arm, up, mid, low):
        p = [(arm.matrix_world @ arm.data.bones[n].head_local) for n in (up, mid, low)]
        return (p[1] - p[0]).length + (p[2] - p[1]).length

    # échelle par longueur de jambe (robuste si la pose de repos n'est pas droite)
    s_leg = leg_len(sarm, "LeftUpLeg", "LeftLeg", "LeftFoot")
    t_leg = leg_len(tarm, pmap["LeftUpLeg"], pmap["LeftLeg"], pmap["LeftFoot"])
    scale = t_leg / max(s_leg, 1e-6)

    def has_mapped_child(arm, bname, mapped):
        return any(c.name in mapped for c in arm.data.bones[bname].children_recursive)

    rest = {}

    def head_w(arm, bname):
        return arm.matrix_world @ arm.data.bones[bname].head_local

    def ref_child(sname):
        # même enfant de référence des deux côtés : pour le bassin la colonne (pas une jambe),
        # pour le haut du dos le cou (pas une épaule) — sinon tout le buste est tordu
        pref = PREF_CHILD.get(sname)
        if pref in pmap:
            return pref
        for c in sarm.data.bones[sname].children_recursive:
            if c.name in pmap:
                return c.name
        return None

    # alignement : os avec enfant apparié → direction vers l'enfant ;
    # os "feuilles" (tête, mains, orteils) → même correction que leur parent apparié
    for s, t in sorted(pairs, key=lambda p: len(tarm.data.bones[p[1]].parent_recursive)):
        rs0 = rest_world(sarm, s).to_quaternion()
        rt0 = rest_world(tarm, t).to_quaternion()
        sc = ref_child(s)
        sd = (head_w(sarm, sc) - head_w(sarm, s)) if sc else Vector((0, 0, 0))
        td = (head_w(tarm, pmap[sc]) - head_w(tarm, t)) if sc else Vector((0, 0, 0))
        if sd.length > 1e-4 and td.length > 1e-4:
            align = td.normalized().rotation_difference(sd.normalized())
        else:
            align = Quaternion()
            for p in tarm.data.bones[t].parent_recursive:
                if p.name in rest:
                    align = rest[p.name][3]
                    break
        rest[t] = (s, rs0, rt0, align)
        if cfg.get("debug_dirs") and clip is cfg["clips"][0]:
            print(f"  ALIGN {s:14s} -> {t:22s} {math.degrees(align.angle):6.1f} deg  src={tuple(round(v, 2) for v in sd)} tgt={tuple(round(v, 2) for v in td)}")

    # direction "devant" de la cible (au repos)
    tl = (tarm.matrix_world @ tarm.data.bones[pmap["LeftUpLeg"]].head_local) - (tarm.matrix_world @ tarm.data.bones[pmap["RightUpLeg"]].head_local)
    t_fwd = facing(tl)

    # la frame 0 des BVH CMU convertis est une T-pose de calibration : on ne la prend jamais
    # (sinon les bras « claquent » à chaque boucle et l'orientation du clip est fausse)
    start = max(clip.get("start", 0), 2)
    end = clip.get("end", -1)
    total = f1 - f0
    if end < 0 or end > total:
        end = total
    step = src_fps / FPS
    samples = []
    t = float(start)
    while t <= end:
        samples.append(t)
        t += step

    # 1) échantillonnage de la source (monde)
    src = []
    for st in samples:
        fr = f0 + st
        bpy.context.scene.frame_set(int(fr), subframe=fr - int(fr))
        src.append({s: (sarm.matrix_world @ sarm.pose.bones[s].matrix).copy() for s in smapped})

    def src_facing(i):
        m = src[i]
        lv = m["LeftUpLeg"].to_translation() - m["RightUpLeg"].to_translation()
        return facing(lv)

    # point de boucle cherché AVANT de mesurer le déplacement : vitesse, orientation et mise en place
    # sont calculées sur la boucle elle-même (sinon un acteur qui fait des allers-retours donne une
    # vitesse quasi nulle, et la boucle « recule » à chaque tour : le personnage semble planer)
    loop_cut = False
    if clip.get("loop", False) and len(src) > 40 and not clip.get("static"):
        chains = [(a, b) for a, b in (("Hips", "LeftUpLeg"), ("LeftUpLeg", "LeftLeg"), ("LeftLeg", "LeftFoot"),
                                      ("Hips", "RightUpLeg"), ("RightUpLeg", "RightLeg"), ("RightLeg", "RightFoot"),
                                      ("Hips", "LowerBack"), ("LowerBack", "Spine"))
                  if a in smapped and b in smapped]

        def lrot(m, a, b):
            return (m[a].inverted() @ m[b]).to_quaternion()

        ref0 = {c: lrot(src[0], *c) for c in chains}
        face0 = src_facing(0)
        hz0 = src[0]["Hips"].to_translation().z
        best_i, best_d = len(src) - 1, 1e9
        for i in range(int(clip.get("min_loop", 0.8) * FPS), len(src)):
            d = sum(ref0[c].rotation_difference(lrot(src[i], *c)).angle for c in chains)
            d += abs(src[i]["Hips"].to_translation().z - hz0) / s_hip_h * 4.0
            d += face0.angle(src_facing(i), 0.0)
            if d < best_d:
                best_d, best_i = d, i
        # on garde la frame qui « referme » la boucle pour mesurer le déplacement, retirée à la fin
        src = src[:best_i + 1]
        samples = samples[:best_i + 1]
        loop_cut = True
        print(f"  boucle: {best_i} frames (écart {best_d:.3f})")

    # sol réel de la capture : position la plus basse des pieds pendant le clip
    s_floor = min(m[b].to_translation().z for m in src for b in s_feet if b in m)

    hips_xy = [Vector((m["Hips"].to_translation().x, m["Hips"].to_translation().y, 0)) for m in src]
    travel = hips_xy[-1] - hips_xy[0]
    duration = max(len(src) - 1, 1) / FPS
    # orientation de référence : sens de déplacement (locomotion) ou orientation initiale
    # "ref": "facing" force l'orientation du corps (ex. marcher à reculons en tirant quelque chose),
    # "face_frame" choisit l'instant de référence, "yaw" ajoute une correction en degrés
    if clip.get("face_at") is not None:
        # orientation du corps à un instant absolu du fichier (secondes), hors segment éventuel
        fr = f0 + clip["face_at"] * src_fps
        bpy.context.scene.frame_set(int(fr))
        lv = (sarm.matrix_world @ sarm.pose.bones["LeftUpLeg"].matrix).to_translation() - (sarm.matrix_world @ sarm.pose.bones["RightUpLeg"].matrix).to_translation()
        ref = facing(lv)
    elif clip.get("inplace", True) and travel.length > 0.5 * s_hip_h and clip.get("ref") != "facing":
        ref = travel.normalized()
    elif "face_frame" in clip:
        ref = src_facing(min(int(clip["face_frame"]), len(src) - 1))  # indice à 30 i/s
    else:
        # orientation moyenne du corps pendant le clip (idle, poses...)
        acc = Vector((0, 0, 0))
        for i in range(len(src)):
            acc += src_facing(i)
        ref = acc.normalized() if acc.length > 1e-6 else src_facing(0)
    theta = yaw_of(t_fwd) - yaw_of(ref) + math.radians(clip.get("yaw", 0.0))
    rz = Matrix.Rotation(theta, 4, "Z")
    rzq = rz.to_quaternion()
    speed = travel.length * scale / duration

    # 2) hanches : en place + mise à l'échelle + réorientation
    n = len(src)
    hips_pos = []
    for i, m in enumerate(src):
        p = m["Hips"].to_translation()
        if clip.get("inplace", True):
            trend = hips_xy[0] + travel * (i / max(n - 1, 1))
            p = Vector((p.x - trend.x, p.y - trend.y, p.z))
        else:
            p = Vector((p.x - hips_xy[0].x, p.y - hips_xy[0].y, p.z))
        p = rz @ p
        hips_pos.append(Vector((p.x * scale, p.y * scale, (p.z - s_floor) * scale + t_floor)))

    # pose figée (cadavres) : la frame choisie, recentrée sous l'origine du personnage
    i_low = 0
    if clip.get("static") == "lowest":
        # allongé à plat : la tête ET les hanches au plus bas (pas assis, pas genoux relevés)
        def flatness(k):
            head_z = src[k]["Head"].to_translation().z if "Head" in src[k] else 0.0
            return hips_pos[k].z + (head_z - s_floor) * scale
        i_low = min(range(n), key=flatness)
    elif clip.get("static") in ("first", "last"):
        i_low = 0 if clip["static"] == "first" else n - 1
    if clip.get("static"):
        c0 = Vector((hips_pos[i_low].x, hips_pos[i_low].y, 0))
        hips_pos = [p - c0 for p in hips_pos]

    order = []

    def walk(b):
        order.append(b.name)
        for c in b.children:
            walk(c)

    for b in tarm.data.bones:
        if b.parent is None:
            walk(b)

    tw_inv = tarm.matrix_world.inverted()
    tw_rot_inv = tarm.matrix_world.to_quaternion().inverted()

    # silhouette voûtée : "lean" = {os source: degrés vers l'avant}, cumulés le long de la colonne
    # (le haut du corps pivote d'un bloc ; une valeur négative sur le cou redresse la tête)
    lean_cfg = clip.get("lean", {})
    lean_axis = UP.cross(t_fwd).normalized()
    lean_of = {}
    for name in order:
        par = tarm.data.bones[name].parent
        own = lean_cfg.get(rest[name][0], 0.0) if name in rest else 0.0
        lean_of[name] = (lean_of[par.name] if par is not None else 0.0) + own

    # 3) poses cibles
    frames = []
    for i, m in enumerate(src):
        arm_m = {}
        basis = {}
        for name in order:
            bone = tarm.data.bones[name]
            if bone.parent is not None:
                chain = arm_m[bone.parent.name] @ (bone.parent.matrix_local.inverted() @ bone.matrix_local)
            else:
                chain = bone.matrix_local.copy()
            if name in rest:
                s, rs0, rt0, align = rest[name]
                rs = rzq @ m[s].to_quaternion()
                rt = (rs @ rs0.inverted()) @ align @ rt0
                if lean_of[name]:
                    rt = Quaternion(lean_axis, math.radians(lean_of[name])) @ rt
                rt_arm = tw_rot_inv @ rt
                if name == t_hips:
                    mm = Matrix.LocRotScale(tw_inv @ hips_pos[i], rt_arm, Vector((1, 1, 1)))
                else:
                    mm = Matrix.LocRotScale(chain.to_translation(), rt_arm, Vector((1, 1, 1)))
                bm = chain.inverted() @ mm
                basis[name] = (bm.to_translation() if name == t_hips else Vector(), bm.to_quaternion())
                arm_m[name] = chain @ bm
            else:
                arm_m[name] = chain
        frames.append(basis)

    if clip.get("static"):
        frames = [frames[i_low], frames[i_low]]
        print(f"  pose figée à la frame {i_low}")

    # 4) boucle : la dernière frame (identique à la première) n'est pas jouée
    if loop_cut:
        frames = frames[:-1]

    # 5) action (quaternions rendus continus)
    act = bpy.data.actions.new(clip["name"])
    act.use_fake_user = True
    tarm.animation_data_create()
    tarm.animation_data.action = act
    prev = {}
    for name in rest:
        tarm.pose.bones[name].rotation_mode = "QUATERNION"
    for i, basis in enumerate(frames):
        for name, (loc, rot) in basis.items():
            if name in prev and prev[name].dot(rot) < 0:
                rot = -rot
            prev[name] = rot
            pb = tarm.pose.bones[name]
            pb.rotation_quaternion = rot
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
            if name == t_hips:
                pb.location = loc
                pb.keyframe_insert("location", frame=i + 1)
    # vérification : hauteur des hanches et des pieds à la première frame
    bpy.context.scene.frame_set(1)
    hz = (tarm.matrix_world @ tarm.pose.bones[t_hips].head).z
    fz = min((tarm.matrix_world @ tarm.pose.bones[pmap[k]].head).z for k in ("LeftFoot", "RightFoot") if k in pmap)
    print(f"  check: hanches z={hz:.3f} (voulu {hips_pos[0].z:.3f}), pieds z={fz:.3f}")
    # diagnostic : écart de direction (os → os enfant apparié) entre la source réorientée et la cible
    if cfg.get("debug_dirs"):
        fdbg = min(10, len(frames))
        bpy.context.scene.frame_set(fdbg)
        bpy.context.scene.frame_set(fdbg)
        fr = f0 + samples[fdbg - 1]
        tw = tarm.matrix_world
        errs = []
        for sname, tname in pairs:
            sch = next((c.name for c in sarm.data.bones[sname].children_recursive if c.name in smapped), None)
            tch = pmap.get(sch) if sch else None
            if not tch:
                continue
            ms = src[fdbg - 1]
            sd = (rz @ (ms[sch].to_translation() - ms[sname].to_translation())).normalized()
            td = ((tw @ tarm.pose.bones[tch].head) - (tw @ tarm.pose.bones[tname].head)).normalized()
            errs.append(f"{sname}:{math.degrees(sd.angle(td, 0.0)):.0f}" if sd.length > 0 and td.length > 0 else f"{sname}:?")
        print("  DIRS", clip["name"], " ".join(errs))
        rot_errs = []
        for name in rest:
            sname, rs0, rt0, align = rest[name]
            rs = rzq @ ms[sname].to_quaternion()
            want = (rs @ rs0.inverted()) @ align @ rt0
            got = (tw @ tarm.pose.bones[name].matrix).to_quaternion()
            rot_errs.append(f"{sname}:{math.degrees(want.rotation_difference(got).angle):.0f}")
        print("  ROTS", clip["name"], " ".join(rot_errs))
    tarm.animation_data.action = None
    bpy.data.objects.remove(sarm, do_unlink=True)
    if sact.name in bpy.data.actions:
        bpy.data.actions.remove(sact)
    print(f"CLIP {clip['name']}: {len(frames)} frames, {len(frames) / FPS:.2f}s, vitesse ~{speed:.2f} m/s, échelle {scale:.4f}")
    return {"name": clip["name"], "frames": len(frames), "seconds": len(frames) / FPS, "speed": round(speed, 3)}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    tarm = import_target()
    fix_rocketbox_materials()
    if cfg.get("height"):
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        zmin = min((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
        zmax = max((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
        s = cfg["height"] / max(zmax - zmin, 1e-6)
        roots = {o for o in bpy.data.objects if o.parent is None}
        for r in roots:
            r.scale = r.scale * s
            r.location = r.location * s
        bpy.context.view_layer.update()
        print("échelle personnage", round(s, 4))
    mapping = MAP_MIXAMO if cfg["rig"] == "mixamo" else MAP_BIPED
    info = [retarget_clip(tarm, c, mapping) for c in cfg["clips"]]
    for pb in tarm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = Quaternion()
    os.makedirs(os.path.dirname(cfg["out"]), exist_ok=True)
    if cfg.get("debug_blend"):
        bpy.ops.wm.save_as_mainfile(filepath=cfg["debug_blend"])
    bpy.ops.export_scene.gltf(
        filepath=cfg["out"], export_format="GLB", export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_image_format="JPEG", export_jpeg_quality=88, export_yup=True,
    )
    with open(os.path.splitext(cfg["out"])[0] + ".anims.json", "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    print("EXPORT OK", cfg["out"])


main()
