"""Récupère des sons CC0 de Freesound (aperçus HQ en mp3, même licence que l'original) pour une requête.
usage: fs_fetch.py <dossier> <nombre> "requête" ["requête" ...]
Écrit <dossier>/<requête>/<id>.mp3 et un index.tsv (id, auteur, titre, url) pour les crédits.
"""
import html
import os
import re
import sys
import time
import urllib.parse
import urllib.request

H = {"User-Agent": "Mozilla/5.0 (horrorgame-dev)"}
OUT = sys.argv[1]
N = int(sys.argv[2])


def get(url, tries=3, budget=120.0):
    # Freesound répond parfois au compte-gouttes : délai d'expiration, durée maximale, quelques essais
    for k in range(tries):
        try:
            t0 = time.time()
            data = b""
            with urllib.request.urlopen(urllib.request.Request(url, headers=H), timeout=45) as r:
                while True:
                    chunk = r.read(65536)
                    if not chunk:
                        return data
                    data += chunk
                    if time.time() - t0 > budget:
                        raise TimeoutError("trop lent (%d ko en %d s)" % (len(data) // 1024, budget))
        except Exception as e:
            print("   (essai %d) %s : %s" % (k + 1, url[-40:], e), flush=True)
    return None


for q in sys.argv[3:]:
    params = {"q": q, "f": 'license:"Creative Commons 0"', "s": "Downloads (most first)", "g": "1"}
    raw = get("https://freesound.org/search/?" + urllib.parse.urlencode(params))
    if raw is None:
        print("==", q, "recherche impossible", flush=True)
        continue
    page = raw.decode("utf-8", "replace")
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
    # l'index d'abord (crédits), les téléchargements ensuite
    with open(os.path.join(d, "index.tsv"), "w", encoding="utf-8") as f:
        for sid, author, title, url in rows:
            f.write(f"{sid}\t{author}\t{title}\thttps://freesound.org/people/{author}/sounds/{sid}/\n")
    print("==", q, len(rows), flush=True)
    for sid, author, title, url in rows:
        path = os.path.join(d, sid + ".mp3")
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            data = get(url)
            if data:
                with open(path + ".part", "wb") as g:
                    g.write(data)
                os.replace(path + ".part", path)
        print("  ", sid, author, "|", title[:60], "" if os.path.exists(path) else "(échec)", flush=True)
