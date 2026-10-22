import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

src = sys.argv[1]
out = sys.argv[2]
names = sys.argv[3].split(",")
cell = 256
cols = 4
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell * 2, rows * (cell + 24)), (20, 20, 20))
d = ImageDraw.Draw(sheet)
f = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
for i, n in enumerate(names):
    x = (i % cols) * cell * 2
    y = (i // cols) * (cell + 24)
    for j, v in enumerate(("front", "side")):
        p = os.path.join(src, f"{n}_{v}.png")
        if os.path.exists(p):
            sheet.paste(Image.open(p).resize((cell, cell)), (x + j * cell, y + 24))
    d.text((x + 4, y + 2), n, font=f, fill=(255, 255, 0))
sheet.save(out)
print(out)
