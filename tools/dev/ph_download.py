"""Télécharge des assets CC0 Poly Haven (textures 1k + modèles glTF 1k) dans le projet."""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

H = {"User-Agent": "horrorgame-dev"}
ROOT = sys.argv[1]

TEXTURES = [
    "dark_brick_wall", "damaged_concrete_floor", "rusty_metal_02", "asphalt_02", "forrest_ground_01",
    "gravel_road", "weathered_plank_siding", "grey_roof_tiles", "painted_plaster_wall", "wood_floor",
    "square_tiles", "white_plaster_02", "dirty_carpet", "fabric_pattern_07", "concrete_wall_008",
    "brown_mud_leaves_01", "dirty_concrete", "bark_willow",
]
MODELS = [
    "Sofa_01", "ArmChair_01", "modern_coffee_table_01", "dining_table", "dining_chair_02",
    "wooden_bookshelf_worn", "strawberry_chocolate_cake", "wine_bottles_01", "throw_pillows_01",
    "modern_ceiling_lamp_01", "drawer_cabinet", "old_bed_frame", "ClassicNightstand_01", "security_camera_01",
    "boombox", "metal_office_desk", "old_gas_mask", "hanging_picture_frame_01", "wall_clock", "side_table_01",
    "potted_plant_01", "electric_stove", "vintage_microwave", "cardboard_box_01", "water_manhole_cover",
    "dead_tree_trunk", "modular_industrial_pipes_01", "caged_hanging_light", "industrial_wall_lamp", "Barrel_01",
    "wooden_crate_01", "trashbag", "old_tyre", "street_rat", "power_box_01", "large_iron_gate", "bolt_cutters_01",
    "WetFloorSign_01", "metal_tool_chest", "steel_frame_shelves_01", "rubber_boots", "can_rusted",
    "mounted_fluorescent_lights",
]
TEX_MAPS = {"Diffuse": "diff", "nor_gl": "nor", "Rough": "rough", "AO": "ao"}


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r:
        return json.loads(r.read())


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r, open(dest + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(dest + ".part", dest)


jobs = []
for slug in TEXTURES:
    try:
        files = get_json(f"https://api.polyhaven.com/files/{slug}")
    except Exception as e:  # noqa: BLE001
        print("MISSING texture", slug, e)
        continue
    for key, short in TEX_MAPS.items():
        entry = files.get(key, {}).get("1k", {}).get("jpg")
        if entry:
            jobs.append((entry["url"], os.path.join(ROOT, "textures", slug, f"{slug}_{short}.jpg")))
        elif key != "AO":
            print("no", key, "for", slug)

for slug in MODELS:
    try:
        files = get_json(f"https://api.polyhaven.com/files/{slug}")
    except Exception as e:  # noqa: BLE001
        print("MISSING model", slug, e)
        continue
    g = files["gltf"]["1k"]["gltf"]
    base = os.path.join(ROOT, "models", slug)
    jobs.append((g["url"], os.path.join(base, os.path.basename(g["url"]))))
    for rel, inc in g.get("include", {}).items():
        jobs.append((inc["url"], os.path.join(base, rel.replace("/", os.sep))))

print("files:", len(jobs), flush=True)
with ThreadPoolExecutor(8) as ex:
    for i, _ in enumerate(ex.map(lambda j: download(*j), jobs)):
        if i % 25 == 0:
            print("progress", i, flush=True)
print("done")
