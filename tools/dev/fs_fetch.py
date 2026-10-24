"""Récupère des sons CC0 de Freesound (aperçus HQ en mp3, même licence que l'original) pour une requête.
usage: fs_fetch.py <dossier> <nombre> "requête" ["requête" ...]
Écrit <dossier>/<requête>/<id>.mp3 et un index.tsv (id, auteur, titre, url) pour les crédits.
"""
import html
import os
import re
import sys
import urllib.parse
import urllib.request

H = {"User-Agent": "Mozilla/5.0 (horrorgame-dev)"}
OUT = sys.argv[1]
N = int(sys.argv[2])


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r:
        return r.read()


for q in sys.argv[3:]:
    params = {"q": q, "f": 'license:"Creative Commons 0"', "s": "Downloads (most first)", "g": "1"}
    page = get("https://freesound.org/search/?" + urllib.parse.urlencode(params)).decode("utf-8", "replace")
    d = os.path.join(OUT, q.replace(" ", "_"))
    os.makedirs(d, exist_ok=True)
    rows = []
    # chaque résultat : lien /people/<auteur>/sounds/<id>/ (avec son titre) et l'aperçu data-mp3
    for m in re.finditer(r'data-mp3="(https://cdn\.freesound\.org/previews/\d+/(\d+)_\d+-lq\.mp3)"', page):
        url, sid = m.group(1), m.group(2)
        if any(r[0] == sid for r in rows):
            continue
        t = re.search(r'href="/people/([^/"]+)/sounds/%s/"[^>]*>([^<]*)<' % sid, page)
        author, title = (t.group(1), html.unescape(t.group(2)).strip()) if t else ("?", "?")
        rows.append((sid, author, title, url.replace("-lq.mp3", "-hq.mp3")))
        if len(rows) >= N:
            break
    with open(os.path.join(d, "index.tsv"), "w", encoding="utf-8") as f:
        for sid, author, title, url in rows:
            path = os.path.join(d, sid + ".mp3")
            if not os.path.exists(path):
                with open(path, "wb") as g:
                    g.write(get(url))
            f.write(f"{sid}\t{author}\t{title}\thttps://freesound.org/people/{author}/sounds/{sid}/\n")
    print("==", q, len(rows))
    for r in rows:
        print("  ", r[0], r[1], "|", r[2][:60])
