"""Télécharge des modèles Sketchfab (format glb de préférence) + écrit les crédits.
usage: sf_download.py <dossier_assets> uid:nom [uid:nom ...]
"""
import json
import os
import sys
import urllib.request
import zipfile

TOKEN = os.environ["SKETCHFAB_TOKEN"]
ROOT = sys.argv[1]
H = {"User-Agent": "horrorgame-dev"}


def get(url, auth=False):
    h = dict(H)
    if auth:
        h["Authorization"] = "Token " + TOKEN
    with urllib.request.urlopen(urllib.request.Request(url, headers=h)) as r:
        return json.loads(r.read())


credits_path = os.path.join(ROOT, "CREDITS_SKETCHFAB.txt")
for arg in sys.argv[2:]:
    uid, name = arg.split(":", 1)
    fmt = "glb"
    if "@" in name:
        name, fmt = name.split("@")
    out_dir = os.path.join(ROOT, name)
    if os.path.isdir(out_dir) and os.listdir(out_dir):
        print("déjà là :", name)
        continue
    os.makedirs(out_dir, exist_ok=True)
    m = get(f"https://api.sketchfab.com/v3/models/{uid}")
    d = get(f"https://api.sketchfab.com/v3/models/{uid}/download", auth=True)
    if fmt not in d:
        fmt = "gltf"
    url = d[fmt]["url"]
    target = os.path.join(out_dir, name + (".glb" if fmt == "glb" else ".zip"))
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r, open(target, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    if fmt == "gltf":
        with zipfile.ZipFile(target) as z:
            z.extractall(out_dir)
        os.remove(target)
    lic = (m.get("license") or {}).get("label")
    with open(credits_path, "a", encoding="utf-8") as c:
        c.write(f"{name}: \"{m['name']}\" by {m['user']['username']} ({m['viewerUrl']}) — {lic}\n")
    print("OK", name, fmt, round(os.path.getsize(target) / 1e6, 1) if os.path.exists(target) else "", "MB")
