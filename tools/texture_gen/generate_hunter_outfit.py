"""Tenue du deuxième homme au masque (celui du van) : la texture du treillis Rocketbox recolorée en tenue de
chasse kaki délavée, avec le gilet porte-plaques passé en orange fluo de chasseur (comme les battues : « chasse en
cours »). La peau des bras reste telle quelle. On le distingue du premier (tout en noir) même de loin, de nuit.
python generate_hunter_outfit.py [dossier du personnage]   (par défaut assets/characters/hunter)
"""
import os
import sys

import numpy as np
from PIL import Image

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "characters", "hunter")
src = np.asarray(Image.open(os.path.join(DIR, "hunter_sm004_body_color_acu.jpg")).convert("RGB"), np.float32) / 255.0
h, w = src.shape[:2]
r, g, b = src[..., 0], src[..., 1], src[..., 2]
lum = 0.3 * r + 0.59 * g + 0.11 * b
mx = src.max(axis=2)
mn = src.min(axis=2)
sat = (mx - mn) / (mx + 1e-5)
# peau : orangée, saturée (les avant-bras) ; on n'y touche pas
skin = (r > g * 1.12) & (g > b * 1.05) & (sat > 0.25)

# gilet porte-plaques (repéré sur l'atlas, en fractions de la texture) : dos, puis devant avec ses côtés
vest = np.zeros((h, w), bool)
for x0, y0, x1, y1 in [(0.395, 0.095, 0.605, 0.455), (0.40, 0.445, 0.60, 0.56), (0.33, 0.555, 0.69, 0.72)]:
    vest[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)] = True
vest &= ~skin

l = np.clip((lum - lum.mean()) * 1.1 + 0.5, 0, 1)
khaki = l[..., None] * np.array([0.58, 0.52, 0.36]) * 0.95
orange = np.clip(l * 1.35, 0, 1)[..., None] * np.array([1.0, 0.38, 0.05])
out = np.where(vest[..., None], orange, khaki)
out = np.where(skin[..., None], src, out)
Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(os.path.join(DIR, "hunter_b_body.png"))
print("hunter_b_body.png")
