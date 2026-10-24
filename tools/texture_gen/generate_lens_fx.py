"""Textures de l'objectif de la caméra-piéton (assets/gen) :
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


def drops():
    """Gouttes tout près de l'objectif : complètement floues (pas de contour net), de tailles variées,
    quelques traînées qui ont coulé. B = présence de la goutte (douce), RG = sens de la réfraction."""
    rnd = random.Random(3)
    off = np.zeros((H, W, 2), dtype=np.float32)
    mask = np.zeros((H, W), dtype=np.float32)
    for _ in range(34):
        r = rnd.uniform(6.0, 14.0) if rnd.random() < 0.7 else rnd.uniform(16.0, 30.0)
        cx, cy = rnd.uniform(0, W), rnd.uniform(0, H)
        stretch = 1.0 if rnd.random() < 0.8 else rnd.uniform(1.6, 3.0)  # gouttes qui ont coulé
        rr = r * 1.6
        x0, x1 = int(max(0, cx - rr)), int(min(W, cx + rr))
        y0, y1 = int(max(0, cy - rr * stretch)), int(min(H, cy + rr * stretch))
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        dx = (xx - cx) / r
        dy = (yy - cy) / (r * stretch)
        q = dx * dx + dy * dy
        g = np.exp(-q * 1.6)  # bord flou : la goutte n'est jamais au point
        o = off[y0:y1, x0:x1]
        o[..., 0] += -dx * g * 0.6
        o[..., 1] += -dy * g * 0.6
        m = mask[y0:y1, x0:x1]
        mask[y0:y1, x0:x1] = np.maximum(m, g * rnd.uniform(0.55, 1.0))
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., 0] = np.clip(off[..., 0] * 0.5 + 0.5, 0, 1) * 255
    rgba[..., 1] = np.clip(off[..., 1] * 0.5 + 0.5, 0, 1) * 255
    rgba[..., 2] = np.clip(mask, 0, 1) * 255
    rgba[..., 3] = 255
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "lens_drops.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    drops()
    print("ok")
