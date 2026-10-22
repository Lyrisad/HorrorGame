"""
Textures de la maison : papier peint, portes à panneaux (couleur + normales), paillasson.
python generate_house_textures.py <dossier_sortie>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(5)


def noise(w, h, scale=8, octaves=4):
    out = np.zeros((h, w))
    amp = 1.0
    for o in range(octaves):
        s = scale * (2**o)
        small = rng.random((s + 1, s + 1))
        img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, dtype=np.float32) / 255 * amp
        amp *= 0.5
    out -= out.min()
    return out / (out.max() + 1e-9)


def height_to_normal(h, strength=4.0):
    gy, gx = np.gradient(h)
    nx, ny = -gx * strength, -gy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx**2 + ny**2 + nz**2)
    n = np.stack([nx / ln, -ny / ln, nz / ln], axis=-1)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def wallpaper(name, base, stripe, motif):
    w, h = 1024, 1024
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:] = base
    x = np.arange(w)
    stripes = ((x // 64) % 2 == 0)
    img[:, stripes] = stripe
    pil = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(pil)
    for cx in range(32, w, 128):
        for cy in range(0, h + 128, 128):
            oy = 64 if (cx // 128) % 2 else 0
            y = cy + oy
            d.ellipse([cx - 9, y - 16, cx + 9, y + 16], outline=motif, width=2)
            d.line([cx, y - 26, cx, y + 26], fill=motif, width=1)
            d.ellipse([cx - 3, y - 3, cx + 3, y + 3], fill=motif)
    arr = np.asarray(pil, dtype=np.float32)
    n = noise(w, h, 6, 5)
    stains = np.clip((noise(w, h, 3, 3) - 0.62) * 3.0, 0, 1)
    arr *= (0.9 + 0.1 * n)[..., None]
    arr *= (1 - stains * 0.25)[..., None]
    arr[..., 2] *= (1 - stains * 0.15)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name))
    print("  ", name)


def door(name, color, wood=False):
    w, h = 512, 1024
    height = np.zeros((h, w), dtype=np.float32)
    panels = [(60, 60, 230, 330), (282, 60, 452, 330), (60, 390, 230, 640), (282, 390, 452, 640), (60, 700, 230, 960), (282, 700, 452, 960)]
    for (x0, y0, x1, y1) in panels:
        height[y0:y1, x0:x1] = -1.0
        bev = 14
        height[y0 + bev:y1 - bev, x0 + bev:x1 - bev] = -0.4
    hp = Image.fromarray(((height + 1) * 120).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    hf = np.asarray(hp, dtype=np.float32) / 255
    nrm = height_to_normal(hf, 6.0)
    Image.fromarray(nrm).save(os.path.join(OUT, name + "_nrm.png"))
    n = noise(w, h, 8, 5)
    col = np.zeros((h, w, 3), dtype=np.float32)
    col[:] = color
    if wood:
        grain = np.sin(np.linspace(0, 140, w)[None, :] + noise(w, h, 4, 3) * 9.0) * 0.5 + 0.5
        col *= (0.75 + 0.25 * grain)[..., None]
    col *= (0.92 + 0.08 * n)[..., None]
    shade = 0.85 + 0.15 * hf
    col *= shade[..., None]
    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    print("  ", name)


def doormat(name):
    w, h = 768, 512
    n = noise(w, h, 64, 3)
    fib = rng.random((h, w))
    col = np.stack([120 + 60 * n + 30 * fib, 85 + 40 * n + 20 * fib, 45 + 25 * n + 10 * fib], axis=-1)
    pil = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(pil)
    f = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 96)
    bb = d.textbbox((0, 0), "BIENVENUE", font=f)
    d.text(((w - (bb[2] - bb[0])) / 2, (h - (bb[3] - bb[1])) / 2 - 20), "BIENVENUE", font=f, fill=(35, 25, 18))
    d.rectangle([20, 20, w - 20, h - 20], outline=(35, 25, 18), width=10)
    pil.filter(ImageFilter.GaussianBlur(0.8)).save(os.path.join(OUT, name))
    print("  ", name)


wallpaper("wallpaper_living.png", (150, 128, 96), (160, 138, 104), (120, 98, 70))
wallpaper("wallpaper_bedroom.png", (96, 112, 112), (104, 120, 120), (72, 86, 86))
door("door_white", (220, 216, 205))
door("door_wood", (120, 78, 48), wood=True)
doormat("doormat.png")
print("OK")
