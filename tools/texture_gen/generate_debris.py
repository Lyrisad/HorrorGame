"""Débris qui flottent dans les cunettes (assets/gen/water_debris.png, 4 cases de 128 px) :
feuille morte · mousse sale · bout de sac plastique · emballage froissé.
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
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = []
    for k in range(40):
        t = k / 39 * math.pi
        r = math.sin(t) * (0.32 + 0.04 * math.sin(t * 6))
        pts.append((C / 2 + r * C * math.cos(0) * (1 if k < 20 else 1), 0))
    # silhouette de feuille : ellipse pointue, bord un peu dentelé
    poly = []
    for k in range(64):
        a = k / 64 * 2 * math.pi
        rx, ry = 0.24 * C, 0.42 * C
        r = 1.0 + 0.06 * math.sin(a * 9)
        x = C / 2 + math.cos(a) * rx * r * (0.55 + 0.45 * abs(math.sin(a)))
        y = C / 2 + math.sin(a) * ry * r
        poly.append((x, y))
    d.polygon(poly, fill=(92, 58, 26, 255))
    d.line([(C / 2, C * 0.1), (C / 2, C * 0.92)], fill=(60, 36, 16, 255), width=2)
    for k in range(5):
        y = C * (0.25 + k * 0.12)
        d.line([(C / 2, y), (C / 2 - 18, y - 12)], fill=(66, 40, 18, 255), width=1)
        d.line([(C / 2, y), (C / 2 + 18, y - 12)], fill=(66, 40, 18, 255), width=1)
    a = np.array(img, dtype=np.float32)
    shade = 0.75 + noise(C, 16)[..., None] * 0.45
    a[..., :3] *= shade
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def foam():
    n = noise(C, 10) * 0.6 + noise(C, 4) * 0.4
    yy, xx = np.mgrid[0:C, 0:C]
    r = np.hypot(xx - C / 2, yy - C / 2) / (C * 0.45)
    m = np.clip((n - 0.35 - r * 0.45) * 3.0, 0, 1)
    # petites bulles
    bub = (noise(C, 2) > 0.72).astype(np.float32) * (m > 0.2)
    col = np.zeros((C, C, 4), dtype=np.float32)
    col[..., 0] = 196 - 40 * n
    col[..., 1] = 188 - 40 * n
    col[..., 2] = 160 - 40 * n
    col[..., 3] = np.clip(m * 220 + bub * 30, 0, 255)
    return Image.fromarray(col.astype(np.uint8))


def plastic():
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    poly = [(C * 0.18, C * 0.3), (C * 0.55, C * 0.12), (C * 0.86, C * 0.35), (C * 0.78, C * 0.8), (C * 0.4, C * 0.9), (C * 0.12, C * 0.62)]
    d.polygon(poly, fill=(214, 214, 205, 150))
    for _ in range(9):
        x0, y0 = rnd.uniform(C * 0.2, C * 0.8), rnd.uniform(C * 0.2, C * 0.8)
        d.line([(x0, y0), (x0 + rnd.uniform(-30, 30), y0 + rnd.uniform(-30, 30))], fill=(240, 240, 235, 190), width=1)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def wrapper():
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    poly = [(C * 0.25, C * 0.32), (C * 0.75, C * 0.28), (C * 0.8, C * 0.68), (C * 0.22, C * 0.72)]
    d.polygon(poly, fill=(150, 30, 26, 255))
    d.rectangle([C * 0.3, C * 0.45, C * 0.7, C * 0.55], fill=(210, 200, 170, 255))
    a = np.array(img, dtype=np.float32)
    a[..., :3] *= (0.6 + noise(C, 8)[..., None] * 0.6)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    atlas = Image.new("RGBA", (C * 4, C), (0, 0, 0, 0))
    for i, f in enumerate([leaf, foam, plastic, wrapper]):
        atlas.paste(f(), (i * C, 0))
    atlas.save(os.path.join(OUT, "water_debris.png"))
    print("ok")
