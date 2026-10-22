"""Télécharge des avatars Microsoft Rocketbox (FBX + textures) via l'API GitHub."""
import json
import os
import sys
import urllib.request

H = {"User-Agent": "horrorgame-dev"}
OUT = sys.argv[1]


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r:
        return json.loads(r.read())


def dl(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 1000:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r, open(path, "wb") as f:
        while True:
            c = r.read(1 << 20)
            if not c:
                break
            f.write(c)


for rel in sys.argv[2:]:
    name = rel.split("/")[-1]
    base = f"https://api.github.com/repos/microsoft/Microsoft-Rocketbox/contents/Assets/Avatars/{rel}"
    for sub in ("Export", "Textures"):
        for item in get(f"{base}/{sub}"):
            if item["type"] != "file":
                continue
            if sub == "Export" and item["name"].endswith("_facial.fbx"):
                continue
            dl(item["download_url"], os.path.join(OUT, name, sub, item["name"]))
    print("OK", name, flush=True)
