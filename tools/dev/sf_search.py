"""Recherche Sketchfab (API publique, sans authentification)."""
import json
import os
import sys
import urllib.parse
import urllib.request

H = {"User-Agent": "horrorgame-dev"}
out_dir = sys.argv[1]
queries = sys.argv[2:]
os.makedirs(out_dir, exist_ok=True)


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r:
        return json.loads(r.read())


for q in queries:
    params = {
        "type": "models",
        "q": q,
        "downloadable": "true",
        "sort_by": "-likeCount",
        "count": "24",
    }
    data = get("https://api.sketchfab.com/v3/search?" + urllib.parse.urlencode(params))
    print("==", q)
    for m in data.get("results", []):
        lic = (m.get("license") or {}).get("label", "?")
        if not any(k in lic for k in ("CC0", "Attribution", "CC Attribution")):
            continue
        if "NonCommercial" in lic or "NoDerivs" in lic:
            continue
        thumbs = sorted((m.get("thumbnails") or {}).get("images", []), key=lambda t: t.get("width", 0))
        thumb = next((t["url"] for t in thumbs if t.get("width", 0) >= 256), thumbs[-1]["url"] if thumbs else None)
        print(f"  {m['uid']} | {m['name'][:50]:50s} | faces={m.get('faceCount')} anim={m.get('animationCount')} | {lic} | likes={m.get('likeCount')} | by {m['user']['username']}")
        if thumb:
            safe = "".join(c for c in m["name"] if c.isalnum())[:30]
            path = os.path.join(out_dir, f"{q.replace(' ', '_')}__{safe}__{m['uid'][:8]}.jpg")
            try:
                with urllib.request.urlopen(urllib.request.Request(thumb, headers=H)) as r, open(path, "wb") as f:
                    f.write(r.read())
            except Exception:
                pass
