"""
Construit tous les personnages animés du jeu (assets/characters/*.glb) à partir de :
  - Microsoft Rocketbox (tools/rocketbox_src, licence MIT)
  - créature Sketchfab « The Rake » (assets/sketchfab/rake, CC-BY) et ses propres animations
  - captures de mouvement CMU (tools/mocap/cmu)

python build_characters.py [nom ...]     (sans argument : tout reconstruire)
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER = os.path.join(ROOT, "tools", "blender", "blender-4.5.9-windows-x64", "blender.exe")
MOCAP = os.path.join(ROOT, "tools", "mocap", "cmu")
RB = os.path.join(ROOT, "tools", "rocketbox_src")


def m(clip):
    return os.path.join(MOCAP, clip + ".bvh")


def rocketbox(name):
    return {
        "target": os.path.join(RB, name, "Export", name + ".fbx"),
        "texture_dir": os.path.join(RB, name, "Textures"),
        "rig": "biped",
        "max_texture": 2048,
    }


HUMAN_CLIPS = [
    {"name": "idle", "bvh": m("77_02"), "loop": True, "inplace": True, "min_loop": 6.0},
    {"name": "walk", "bvh": m("35_01"), "loop": True, "inplace": True, "min_loop": 0.9},
    {"name": "run", "bvh": m("35_17"), "loop": True, "inplace": True, "min_loop": 0.5},
    {"name": "crouch_walk", "bvh": m("77_29"), "start": 1320, "end": 1944, "loop": True, "inplace": True, "min_loop": 1.0},
]

# coup de poing en se fendant vers l'avant (02_05 « punch/strike », 9,3 → 10,8 s ; impact vers 0,85 s)
STRIKE = {"name": "strike", "bvh": m("02_05"), "start": 1114, "end": 1300, "loop": False, "inplace": False, "face_at": 0.0}

CHARACTERS = {
    # « Le Rôdeur » : The Rake (Sketchfab, CC-BY) avec SES animations d'origine (faites pour son
    # anatomie de bête à quatre pattes) : rien n'est converti depuis des captures humaines
    "creature": {
        "native": {
            "src": os.path.join(ROOT, "assets", "sketchfab", "rake", "rake.glb"),
            "remove_objects": ["Icosphere"],
            "ref_action": "metarig|ref",
            "height": 2.45,
            "rename_bones": {"spine_01": "Hips", "spine.001_02": "Spine", "spine.002_03": "Spine1", "spine.003_04": "Spine2",
                             "spine.004_05": "Neck", "spine.005_06": "Neck1", "head_07": "Head", "jaw_08": "Jaw"},
            "actions": [
                {"src": "metarig|walk", "name": "stalk", "loop": True},
                {"src": "metarig|run", "name": "run", "loop": True, "lift": -0.16},
                {"src": "metarig|standing run", "name": "charge", "loop": True},
                {"src": "metarig|idle", "name": "crouch", "loop": True},
                {"src": "metarig|idle standing", "name": "listen", "loop": True},
                {"src": "metarig|search", "name": "search", "loop": True},
                {"src": "metarig|screech", "name": "screech", "loop": False},
            ],
        },
    },
    # Théo : + allongé sur le dos (139_18, 1re frame) pour la mort vue par la caméra tombée au sol
    "theo": dict(rocketbox("Security_Male_01"), clips=HUMAN_CLIPS + [{"name": "dead", "bvh": m("139_18"), "static": "first", "inplace": False}]),
    "kidnapper": dict(rocketbox("Military_Male_03"), clips=HUMAN_CLIPS + [STRIKE,
        # se penche et attrape (81_08, 0,6 → 3,6 s), puis tire en marchant à reculons (4 → 10,5 s)
        {"name": "pickup", "bvh": m("81_08"), "start": 72, "end": 432, "loop": False, "inplace": True, "face_at": 2.0},
        {"name": "drag", "bvh": m("81_08"), "start": 480, "end": 1260, "loop": True, "inplace": True, "face_at": 8.0, "min_loop": 1.5},
    ]),
    # cadavres : à plat ventre après une chute (Karim), sur le côté (Inès), sur le dos (Max)
    "karim": dict(rocketbox("Male_Adult_12"), clips=[{"name": "dead", "bvh": m("90_16"), "static": "last", "inplace": False}]),
    "max": dict(rocketbox("Male_Adult_08"), clips=[{"name": "dead", "bvh": m("139_18"), "static": "first", "inplace": False}]),
    "ines": dict(rocketbox("Female_Adult_05"), clips=[{"name": "dead", "bvh": m("140_03"), "static": "first", "inplace": False}]),
    # l'égoutier mourant, juste après la cage : assis par terre, adossé, jambes tendues
    # (140_04 « se relever du sol », 4,2 s : buste penché en arrière d'environ 30°)
    "egoutier": dict(rocketbox("Construction_Male_03"), clips=[{"name": "sit", "bvh": m("140_04"), "start": 500, "end": 530, "static": "first", "inplace": False}]),
}


def build(name):
    cfg = dict(CHARACTERS[name])
    out = os.path.join(ROOT, "assets", "characters", name, name + ".glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if "native" in cfg:
        cfg = dict(cfg["native"], out=out)
        script = "prepare_native.py"
    else:
        cfg["out"] = out
        script = "retarget.py"
    path = os.path.join(ROOT, "tools", "blender_scripts", f"cfg_{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=1)
    print("==>", name, flush=True)
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(ROOT, "tools", "blender_scripts", script), "--", path],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in r.stdout.splitlines() + r.stderr.splitlines():
        if any(k in line for k in ("CLIP", "boucle", "EXPORT", "Error", "Traceback", "introuvable", "matériau", "pas de texture", "figée", "échelle", "line ")):
            print("   ", line)


if __name__ == "__main__":
    for n in (sys.argv[1:] or CHARACTERS.keys()):
        build(n)
