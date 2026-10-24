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
    """Trace humide laissée sur le béton par une main / un pied mouillé de la créature : une tache sombre
    aux bords irréguliers (l'eau s'étale), plus marquée là où la paume a appuyé, quatre traînées
    allongées des doigts, quelques gouttes autour. Pas de contour net : c'est de l'eau, pas de la peinture."""
    rnd = np.random.default_rng(5)
    W, H = 256, 512
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    def blob(cx, cy, rx, ry, rot=0.0):
        c, s_ = math.cos(rot), math.sin(rot)
        dx, dy = xx - cx, yy - cy
        u = (dx * c + dy * s_) / rx
        v = (-dx * s_ + dy * c) / ry
        return np.exp(-(u * u + v * v) * 2.2)

    # paume (bas) + empreintes allongées des doigts vers le haut
    m = blob(W * 0.5, H * 0.74, 52, 74) * 0.9
    for k, (ang, ln) in enumerate([(-0.38, 150), (-0.12, 190), (0.13, 180), (0.36, 140)]):
        bx = W * 0.5 + math.sin(ang) * 30
        by = H * 0.66
        cx = bx + math.sin(ang) * ln * 0.5
        cy = by - math.cos(ang) * ln * 0.5
        m = np.maximum(m, blob(cx, cy, 11, ln * 0.5, -ang) * rnd.uniform(0.55, 0.85))
    # bords irréguliers : bruit multi-échelle
    noise = np.zeros((H, W), dtype=np.float32)
    for scale, amp in ((48, 0.5), (16, 0.3), (5, 0.2)):
        n = np.array(Image.fromarray((rnd.random((H // scale + 2, W // scale + 2)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), dtype=np.float32) / 255.0
        noise += n * amp
    m = np.clip((m * (0.8 + noise * 0.5) - 0.12) * 2.4, 0, 1)
    # gouttes projetées autour
    for _ in range(18):
        x, y = rnd.uniform(15, W - 15), rnd.uniform(15, H - 15)
        r = rnd.uniform(2.0, 5.0)
        m = np.maximum(m, np.exp(-((xx - x) ** 2 + (yy - y) ** 2) / (r * r)) * 0.6)
    m = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float32) / 255.0
    alpha = (np.clip(m, 0, 1) * 235).astype(np.uint8)
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., 0] = 10
    rgba[..., 1] = 11
    rgba[..., 2] = 9
    rgba[..., 3] = alpha
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "decal_wet_print.png"))
    orm = np.zeros((H, W, 4), dtype=np.uint8)
    orm[..., 0] = 255
    orm[..., 1] = 25
    orm[..., 2] = 0
    orm[..., 3] = (np.clip(m * 1.4, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(orm, "RGBA").save(os.path.join(OUT, "decal_wet_print_orm.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    tally()
    wet_print()
    print("ok")
