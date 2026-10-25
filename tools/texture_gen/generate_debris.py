"""Débris qui flottent dans les cunettes (assets/gen/water_debris.png, 4 cases de 128 px) :
feuille morte détrempée · mousse sale · brindille · voile d'écume.
python generate_debris.py [dossier_sortie]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "gen")
C = 128
rnd = np.random.default_rng(9)


def noise(size, scale):
    n = rnd.random((size // scale + 2, size // scale + 2))
    return np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC), dtype=np.float32) / 255.0


def leaf():
    """Feuille morte détrempée, brun sombre, pointue, nervure centrale et nervures latérales, bord rongé."""
    S = 4
    img = Image.new("L", (C * S, C * S), 0)
    d = ImageDraw.Draw(img)
    pts_l, pts_r = [], []
    for k in range(41):
        y = k / 40
        w = math.sin(math.pi * y) ** 0.75 * (1.0 - 0.25 * y) * 0.27
        yy = (0.1 + y * 0.78) * C * S
        pts_l.append((C * S / 2 - w * C * S, yy))
        pts_r.append((C * S / 2 + w * C * S, yy))
    d.polygon(pts_l + pts_r[::-1], fill=255)
    mask = np.array(img.resize((C, C), Image.LANCZOS), dtype=np.float32) / 255.0
    # bord rongé, petits trous de décomposition
    mask *= np.clip((noise(C, 7) - 0.03) * 5.0, 0, 1)
    yy, xx = np.mgrid[0:C, 0:C]
    col = np.zeros((C, C, 3), dtype=np.float32)
    base = np.array([62, 44, 24], dtype=np.float32)
    mott = 0.75 + noise(C, 10)[..., None] * 0.45 + noise(C, 3)[..., None] * 0.15
    col[:] = base * mott
    # nervures plus sombres
    vein = np.exp(-((xx - C / 2) ** 2) / 2.0)
    for k in range(6):
        y0 = C * (0.25 + k * 0.1)
        for sgn in (-1, 1):
            # de la nervure centrale vers le bord, en remontant vers la pointe (un seul côté à la fois)
            side = (xx - C / 2) * sgn
            dist = np.abs((yy - y0) + side * 0.7) / 1.2
            vein = np.maximum(vein, np.exp(-dist ** 2) * (side > 0) * (side < C * 0.22))
    col *= (1.0 - vein[..., None] * 0.35)
    rgba = np.zeros((C, C, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(col, 0, 255)
    rgba[..., 3] = (np.clip(mask, 0, 1) * 255).astype(np.uint8)
    # petite tige
    im = Image.fromarray(rgba)
    ImageDraw.Draw(im).line([(C / 2, C * 0.88), (C / 2 + 3, C * 0.97)], fill=(50, 36, 20, 255), width=2)
    return im


def foam():
    n = noise(C, 10) * 0.6 + noise(C, 4) * 0.4
    yy, xx = np.mgrid[0:C, 0:C]
    r = np.hypot(xx - C / 2, yy - C / 2) / (C * 0.45)
    m = np.clip((n - 0.35 - r * 0.45) * 3.0, 0, 1)
    bub = (noise(C, 2) > 0.72).astype(np.float32) * (m > 0.2)
    col = np.zeros((C, C, 4), dtype=np.float32)
    col[..., 0] = 170 - 40 * n
    col[..., 1] = 165 - 40 * n
    col[..., 2] = 140 - 40 * n
    col[..., 3] = np.clip(m * 200 + bub * 30, 0, 255)
    return Image.fromarray(col.astype(np.uint8))


def twig():
    """Brindille : un petit bout de bois tordu, écorce sombre."""
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = []
    for k in range(12):
        t = k / 11
        pts.append((C * (0.12 + 0.76 * t), C * (0.5 + 0.06 * math.sin(t * 5.0) + (t - 0.5) * 0.25)))
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=(58, 42, 28, 255), width=max(2, int(5 - i * 0.25)))
    d.line([pts[5], (pts[5][0] + 14, pts[5][1] - 16)], fill=(55, 40, 26, 255), width=2)
    a = np.array(img, dtype=np.float32)
    a[..., :3] *= (0.7 + noise(C, 3)[..., None] * 0.5)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def scum():
    """Voile d'écume grise-verdâtre qui flotte, à peine opaque."""
    n = noise(C, 14) * 0.6 + noise(C, 5) * 0.4
    yy, xx = np.mgrid[0:C, 0:C]
    r = np.hypot(xx - C / 2, yy - C / 2) / (C * 0.48)
    m = np.clip((n - 0.3 - r * 0.5) * 2.5, 0, 1)
    col = np.zeros((C, C, 4), dtype=np.float32)
    col[..., 0] = 92 + 30 * n
    col[..., 1] = 98 + 30 * n
    col[..., 2] = 78 + 20 * n
    col[..., 3] = m * 120
    return Image.fromarray(col.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    atlas = Image.new("RGBA", (C * 4, C), (0, 0, 0, 0))
    for i, f in enumerate([leaf, foam, twig, scum]):
        atlas.paste(f(), (i * C, 0))
    atlas.save(os.path.join(OUT, "water_debris.png"))
    print("ok")
