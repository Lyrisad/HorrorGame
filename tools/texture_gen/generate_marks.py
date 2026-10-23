"""Décals des égouts (assets/gen) :
  decal_tally.png         : traits gravés au mur pour compter les jours (planque d'une ancienne victime)
  decal_wet_print.png     : empreinte mouillée de la créature (paume allongée, longs doigts griffus)
  decal_wet_print_orm.png : la même, très lisse (ça brille sous la lampe comme de l'eau)
python generate_marks.py [dossier_sortie]
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "gen")


def tally(days=11):
    rnd = random.Random(11)
    W, H = 768, 384
    S = 2
    img = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(img)
    x = 60 * S
    base = 300 * S
    top = 80 * S
    for k in range(days):
        in_group = k % 5
        if in_group == 4:
            # le cinquième trait barre les quatre autres en diagonale
            x0 = x - 4 * 34 * S - 10 * S
            d.line([(x0, base - 40 * S + rnd.randint(-8, 8) * S), (x - 20 * S, top + 50 * S + rnd.randint(-8, 8) * S)], fill=230, width=7 * S)
            x += 40 * S
            continue
        xa = x + rnd.randint(-5, 5) * S
        xb = x + rnd.randint(-9, 9) * S
        d.line([(xa, base + rnd.randint(-12, 12) * S), (xb, top + rnd.randint(-14, 14) * S)], fill=215 + rnd.randint(-25, 25), width=(6 + rnd.randint(0, 3)) * S)
        x += 34 * S
    a = img.resize((W, H), Image.LANCZOS)
    # gravé dans la crasse : bords irréguliers
    noise = Image.effect_noise((W, H), 90).filter(ImageFilter.GaussianBlur(1.0))
    arr = np.array(a, dtype=np.float32) * (0.6 + np.array(noise, dtype=np.float32) / 255.0 * 0.6)
    alpha = np.clip(arr, 0, 255).astype(np.uint8)
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., 0] = 205
    rgba[..., 1] = 200
    rgba[..., 2] = 185
    rgba[..., 3] = alpha
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "decal_tally.png"))


def wet_print():
    rnd = random.Random(5)
    W, H = 256, 512
    S = 2
    img = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(img)
    # paume allongée (en bas), doigts très longs vers le haut, terminés par des griffes
    cx, cy = W * S / 2, H * S * 0.72
    d.ellipse([cx - 52 * S, cy - 70 * S, cx + 52 * S, cy + 80 * S], fill=255)
    angles = [-0.42, -0.14, 0.12, 0.38]
    lengths = [200, 250, 240, 190]
    for a, ln in zip(angles, lengths):
        x0, y0 = cx + math.sin(a) * 40 * S, cy - 50 * S
        pts = [(x0, y0)]
        x, y = x0, y0
        steps = 8
        for i in range(steps):
            a2 = a + rnd.uniform(-0.05, 0.05) + i * a * 0.03
            x += math.sin(a2) * ln * S / steps
            y -= math.cos(a2) * ln * S / steps
            pts.append((x, y))
        for i in range(len(pts) - 1):
            w = int((15 - i * 1.4) * S)
            d.line([pts[i], pts[i + 1]], fill=255, width=max(2 * S, w))
        # griffe : trait fin qui raye le sol
        d.line([pts[-1], (pts[-1][0] + math.sin(a) * 22 * S, pts[-1][1] - 22 * S)], fill=180, width=2 * S)
    a = img.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(2.0))
    arr = np.array(a, dtype=np.float32) / 255.0
    # eau qui a coulé : bords irréguliers, gouttelettes autour
    noise = np.array(Image.effect_noise((W, H), 120).filter(ImageFilter.GaussianBlur(3.0)), dtype=np.float32) / 255.0
    arr = np.clip(arr * (0.7 + noise * 0.6), 0, 1)
    for _ in range(26):
        x, y = rnd.uniform(20, W - 20), rnd.uniform(20, H - 20)
        r = rnd.uniform(1.5, 5)
        yy, xx = np.mgrid[0:H, 0:W]
        arr = np.maximum(arr, np.clip(1.0 - np.hypot(xx - x, yy - y) / r, 0, 1) * 0.7)
    alpha = (arr * 255).astype(np.uint8)
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., 0] = 22
    rgba[..., 1] = 24
    rgba[..., 2] = 20
    rgba[..., 3] = alpha
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "decal_wet_print.png"))
    # ORM : occlusion 1, rugosité très basse (mouillé), pas de métal
    orm = np.zeros((H, W, 4), dtype=np.uint8)
    orm[..., 0] = 255
    orm[..., 1] = 18
    orm[..., 2] = 0
    orm[..., 3] = alpha
    Image.fromarray(orm, "RGBA").save(os.path.join(OUT, "decal_wet_print_orm.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    tally()
    wet_print()
    print("ok")
