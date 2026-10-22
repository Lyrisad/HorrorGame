"""Prépare le zip à envoyer : build/DernierEnregistrement.zip = dossier « Dernier Enregistrement » avec
le .exe exporté, LISEZ-MOI.txt (guide du joueur, docs/) et CREDITS.md.
usage (depuis la racine, après l'export) : python tools/dev/package.py
"""
import os
import shutil
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "build")
FILES = {
    "DernierEnregistrement.exe": os.path.join(BUILD, "DernierEnregistrement.exe"),
    "LISEZ-MOI.txt": os.path.join(ROOT, "docs", "LISEZ-MOI.txt"),
    "CREDITS.md": os.path.join(ROOT, "CREDITS.md"),
}

for name, src in FILES.items():
    if not os.path.isfile(src):
        raise SystemExit("manquant : " + src)
    if name != "DernierEnregistrement.exe":
        shutil.copyfile(src, os.path.join(BUILD, name))

out = os.path.join(BUILD, "DernierEnregistrement.zip")
tmp = out + ".tmp"
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for name, src in FILES.items():
        z.write(src, "Dernier Enregistrement/" + name)
os.replace(tmp, out)
print("ok :", out, round(os.path.getsize(out) / 1e6), "Mo")
