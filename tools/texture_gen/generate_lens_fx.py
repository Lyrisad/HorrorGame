"""Textures de l'objectif de la caméra-piéton (assets/gen) :
  lens_crack.png : vitre de l'objectif fêlée par le coup reçu à la maison (R = fissures, G = zone éclatée)
  lens_drops.png : gouttes d'eau sur l'objectif (RG = décalage de réfraction, B = goutte)
python generate_lens_fx.py [dossier_sortie]
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "gen")
W, H = 1024, 576


def crack():
    rnd = random.Random(7)
    S = 2  # dessin en double résolution puis réduction (traits lissés)
    img = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(img)
    # point d'impact en bas à gauche, là où le coup a porté
    p0 = (0.095 * W * S, 0.83 * H * S)

    def jagged(p, ang, length, width, depth):
        pts = [p]
        x, y = p
        steps = max(3, int(length / (26 * S)))
        for _ in range(steps):
            ang += rnd.uniform(-0.07, 0.07)
            seg = length / steps * rnd.uniform(0.7, 1.3)
            x += math.cos(ang) * seg
            y += math.sin(ang) * seg
            pts.append((x, y))
            # petites branches
            if depth > 0 and rnd.random() < 0.1:
                jagged((x, y), ang + rnd.choice([-1, 1]) * rnd.uniform(0.35, 0.8), length * rnd.uniform(0.1, 0.22), max(1, width - 1), depth - 1)
        d.line(pts, fill=255, width=int(width), joint="curve")
        return pts

    def at_dist(pts, dist):
        acc = 0.0
        for a, b in zip(pts, pts[1:]):
            seg = math.hypot(b[0] - a[0], b[1] - a[1])
            if acc + seg >= dist:
                t = (dist - acc) / max(seg, 1e-6)
                return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            acc += seg
        return None

    radials = []
    n = 11
    for k in range(n):
        ang = -math.pi * 0.62 + k * (math.pi * 0.95 / (n - 1)) + rnd.uniform(-0.12, 0.12)
        length = rnd.uniform(0.12, 0.42) * W * S
        if k in (4, 7):
            length = rnd.uniform(0.55, 0.75) * W * S  # deux longues fissures qui traversent l'image
        radials.append(jagged(p0, ang, length, rnd.choice([2, 3, 3, 4]) * S // 2 + 1, 1))
    # cercles concentriques de la toile d'araignée, entre deux rayons voisins
    for rr in (0.035, 0.075, 0.12):
        for k in range(n - 1):
            if rnd.random() < 0.3:
                continue
            pa = at_dist(radials[k], rr * W * S * rnd.uniform(0.85, 1.15))
            pb = at_dist(radials[k + 1], rr * W * S * rnd.uniform(0.85, 1.15))
            if pa is None or pb is None:
                continue
            mid = ((pa[0] + pb[0]) / 2 + rnd.uniform(-3, 3) * S, (pa[1] + pb[1]) / 2 + rnd.uniform(-3, 3) * S)
            d.line([pa, mid, pb], fill=210, width=S + 1)
    lines = img.resize((W, H), Image.LANCZOS)
    # zone éclatée autour de l'impact (verre pilé, laiteux)
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.hypot(xx - p0[0] / S, (yy - p0[1] / S))
    haze = np.clip(1.0 - r / (0.045 * W), 0, 1) ** 1.5
    noise = np.array(Image.effect_noise((W, H), 60).filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255.0
    haze = np.clip(haze * (0.6 + noise * 0.8), 0, 1)
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., 0] = np.array(lines)
    rgba[..., 1] = (haze * 255).astype(np.uint8)
    rgba[..., 3] = 255
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "lens_crack.png"))


def drops():
    rnd = random.Random(3)
    off = np.zeros((H, W, 2), dtype=np.float32)
    mask = np.zeros((H, W), dtype=np.float32)
    for _ in range(90):
        r = rnd.uniform(3.0, 9.0) if rnd.random() < 0.7 else rnd.uniform(10.0, 22.0)
        cx, cy = rnd.uniform(0, W), rnd.uniform(0, H)
        stretch = 1.0 if rnd.random() < 0.75 else rnd.uniform(1.4, 2.6)  # gouttes qui coulent
        x0, x1 = int(max(0, cx - r - 2)), int(min(W, cx + r + 2))
        y0, y1 = int(max(0, cy - r * stretch - 2)), int(min(H, cy + r * stretch + 2))
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        dx = (xx - cx) / r
        dy = (yy - cy) / (r * stretch)
        q = dx * dx + dy * dy
        inside = q < 1.0
        h = np.sqrt(np.clip(1.0 - q, 0, 1))
        # une goutte agit comme une petite lentille : l'image y est retournée et grossie
        o = off[y0:y1, x0:x1]
        o[..., 0] = np.where(inside, -dx * (1.0 - h * 0.5), o[..., 0])
        o[..., 1] = np.where(inside, -dy * (1.0 - h * 0.5), o[..., 1])
        m = mask[y0:y1, x0:x1]
        mask[y0:y1, x0:x1] = np.where(inside, np.maximum(m, np.clip((1.0 - q) * 4.0, 0, 1)), m)
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., 0] = np.clip(off[..., 0] * 0.5 + 0.5, 0, 1) * 255
    rgba[..., 1] = np.clip(off[..., 1] * 0.5 + 0.5, 0, 1) * 255
    rgba[..., 2] = mask * 255
    rgba[..., 3] = 255
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "lens_drops.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    crack()
    drops()
    print("ok")
