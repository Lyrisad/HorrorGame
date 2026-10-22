"""toursheet.py dossier sortie_prefixe : planches 4x4 numérotées des captures du tour."""
import os, sys, glob
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
files = []
for f in glob.glob(os.path.join(src, "v*_*.png")):
    b = os.path.basename(f)[1:-4]
    start, k = b.split("_")
    files.append((int(start) + int(k), f))
files.sort()
font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 22)
w, h = 640, 360
for s in range(0, len(files), 16):
    sheet = Image.new("RGB", (w * 4, h * 4))
    d = ImageDraw.Draw(sheet)
    for j, (idx, f) in enumerate(files[s:s + 16]):
        im = Image.open(f).convert("RGB").resize((w, h))
        x, y = (j % 4) * w, (j // 4) * h
        sheet.paste(im, (x, y))
        d.rectangle([x, y, x + 60, y + 28], fill=(0, 0, 0))
        d.text((x + 4, y + 2), str(idx), font=font, fill=(255, 255, 0))
    sheet.save(f"{out}_{s // 16:02d}.png")
print(len(files))
