"""Textures du chapitre « Surface » (le camp des ravisseurs, la forêt) :
- decal_spray13.png : « S·13 » à la bombe rouge sur la plaque d'égout de la session précédente (coulures, nuage)
- board_subjects.png : le tableau de liège de la régie, les 4 sujets de la session 14 (3 barrés, « EN COURS »)
- screen_stream.png : la page du direct sur l'écran de la régie (spectateurs, dons, vote pour la suite)
- cb_label.png : l'étiquette scotchée sur la radio de la cabane (canal 19)
python generate_surface.py [dossier_sortie]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "gen")
FONTS = "C:/Windows/Fonts/"
rng = np.random.default_rng(14)


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


def spray_13():
    """Le chiffre de la session peint à la bombe : trait épais, bords flous, nuage de gouttelettes, coulures."""
    S = 512
    stroke = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(stroke)
    f = font("impact.ttf", 300)
    bb = d.textbbox((0, 0), "13", font=f)
    d.text(((S - bb[2]) / 2 - bb[0], (S - bb[3]) / 2 - bb[1] - 10), "13", font=f, fill=255)
    # un « S » plus petit devant, et un trait souligné
    d.text((40, 70), "S", font=font("impact.ttf", 120), fill=255)
    d.line([(70, 430), (450, 415)], fill=255, width=16)
    a = np.array(stroke.filter(ImageFilter.GaussianBlur(3.5)), np.float32) / 255
    # nuage de peinture autour du trait
    halo = np.array(stroke.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255
    speck = (rng.random((S, S)) < halo * 0.35).astype(np.float32)
    # coulures sous les zones les plus chargées
    drip = np.zeros((S, S), np.float32)
    cols = np.where(a.max(axis=0) > 0.8)[0]
    for x in rng.choice(cols, size=min(14, len(cols)), replace=False):
        ys = np.where(a[:, x] > 0.8)[0]
        if len(ys) == 0:
            continue
        y0 = ys.max()
        ln = int(rng.uniform(20, 90))
        for k in range(ln):
            w = max(1, int(3 * (1 - k / ln)))
            drip[min(S - 1, y0 + k), max(0, x - w):x + w] = 1.0 - k / ln * 0.3
    alpha = np.clip(np.maximum(np.maximum(a, speck * 0.8), drip) * 0.92, 0, 1)
    rgb = np.zeros((S, S, 3), np.float32)
    rgb[...] = [150, 18, 14]
    rgb *= (0.8 + 0.3 * rng.random((S, S, 1)))
    out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "decal_spray13.png"))
    print("   decal_spray13.png")


def portrait(w, h, seed, tone):
    """Photo d'identité floue (tirage instantané) : une silhouette de tête et d'épaules, grain, flash."""
    r = np.random.default_rng(seed)
    img = Image.new("RGB", (w, h), tuple(int(c) for c in tone))
    d = ImageDraw.Draw(img)
    skin = tuple(int(c) for c in (r.uniform(150, 210), r.uniform(110, 160), r.uniform(90, 130)))
    d.ellipse([w * 0.3, h * 0.18, w * 0.7, h * 0.62], fill=skin)
    d.rounded_rectangle([w * 0.12, h * 0.6, w * 0.88, h * 1.2], radius=int(w * 0.3), fill=tuple(int(c) for c in r.uniform(30, 90, 3)))
    hair = tuple(int(c) for c in r.uniform(20, 70, 3))
    d.pieslice([w * 0.28, h * 0.12, w * 0.72, h * 0.5], 180, 360, fill=hair)
    a = np.array(img.filter(ImageFilter.GaussianBlur(2.2)), np.float32)
    a += r.normal(0, 9, a.shape)
    yy, xx = np.mgrid[0:h, 0:w]
    a *= (1.15 - 0.45 * np.hypot((xx - w / 2) / w, (yy - h / 2) / h))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def board_subjects():
    W, H = 1024, 720
    n = rng.random((H // 6 + 1, W // 6 + 1))
    cork = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
    base = np.stack([150 + 40 * cork, 105 + 30 * cork, 62 + 20 * cork], -1) * (0.85 + 0.15 * rng.random((H, W, 1)))
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    marker = font("segoepr.ttf", 46)
    d.text((40, 24), "SESSION 14 — 4 sujets", font=marker, fill=(20, 20, 26))
    d.text((40, 82), "« le public a choisi »", font=font("segoepr.ttf", 30), fill=(150, 20, 20))
    subjects = [("Sujet 1", "Maxime D. — 24 ans", True), ("Sujet 2", "Inès F. — 23 ans", True),
                ("Sujet 3", "Karim H. — 25 ans", True), ("Sujet 4", "Théo M. — 24 ans\nagent de sécurité", False)]
    for i, (title, name, done) in enumerate(subjects):
        x = 40 + i * 245
        y = 160 + (i % 2) * 18
        card = Image.new("RGB", (210, 270), (238, 236, 230))
        card.paste(portrait(186, 186, 40 + i, (90 + i * 10, 95, 100)), (12, 12))
        cd = ImageDraw.Draw(card)
        cd.text((14, 205), title, font=font("segoepr.ttf", 26), fill=(30, 30, 40))
        card = card.rotate(rng.uniform(-5, 5), expand=True, fillcolor=(0, 0, 0))
        mask = card.convert("L").point(lambda v: 255 if v > 8 else 0)
        img.paste(card, (x, y), mask)
        d.ellipse([x + 95, y - 6, x + 113, y + 12], fill=(200, 30, 30))  # punaise
        d.multiline_text((x + 6, y + 300), name, font=font("segoepr.ttf", 24), fill=(20, 20, 26), spacing=2)
        if done:
            d.line([(x + 10, y + 20), (x + 200, y + 260)], fill=(170, 10, 10), width=14)
            d.line([(x + 200, y + 20), (x + 10, y + 260)], fill=(170, 10, 10), width=14)
        else:
            d.text((x + 10, y + 380), "EN COURS", font=font("impact.ttf", 46), fill=(170, 10, 10))
    d.text((40, 640), "Pas d'intervention avant la sortie.   La bête se rappelle au sifflet.", font=font("segoepr.ttf", 28), fill=(20, 20, 26))
    img.save(os.path.join(OUT, "board_subjects.png"))
    print("   board_subjects.png")


def stream_page():
    W, H = 960, 540
    img = Image.new("RGB", (W, H), (14, 14, 18))
    d = ImageDraw.Draw(img)
    b = font("segoeuib.ttf", 26)
    r_ = font("segoeui.ttf", 20)
    s = font("segoeui.ttf", 17)
    d.rounded_rectangle([20, 18, 150, 54], radius=6, fill=(210, 20, 30))
    d.text((34, 20), "● DIRECT", font=b, fill=(255, 255, 255))
    d.text((170, 20), "SESSION 14", font=b, fill=(235, 235, 240))
    d.text((W - 300, 22), "4 312 spectateurs", font=b, fill=(235, 235, 240))
    # zone vidéo (le flux de la caméra-piéton) : le mot « HORS LIGNE » si rien
    d.rectangle([20, 70, 600, 396], fill=(4, 4, 6))
    d.text((32, 80), "BWC-7 · SN 0417 · T.MARCHAND", font=s, fill=(200, 200, 200))
    d.text((240, 220), "flux principal", font=r_, fill=(90, 90, 100))
    # vote
    d.text((20, 410), "PROCHAINE ÉTAPE — vote en cours", font=b, fill=(235, 235, 240))
    for k, (label, pct) in enumerate([("« LA RADIO »", 0.61), ("« LA ROUTE »", 0.39)]):
        y = 450 + k * 40
        d.rectangle([20, y, 600, y + 30], fill=(40, 40, 48))
        d.rectangle([20, y, 20 + int(580 * pct), y + 30], fill=(210, 20, 30) if k == 0 else (90, 90, 100))
        d.text((30, y + 2), f"{label}   {int(pct * 100)} %", font=r_, fill=(255, 255, 255))
    # dons et chat
    d.text((620, 70), "DONS", font=b, fill=(235, 235, 240))
    chat = [("vlad_88", "50 €", "fais-le passer par l'eau"), ("nightowl", "20 €", "LÂCHE LA BÊTE"),
            ("k0rr", "100 €", "coupe-lui la lumière lol"), ("anon_4471", "10 €", "il est malin celui-là"),
            ("m.b", "500 €", "vote : LA RADIO"), ("silent_v", "5 €", "elle l'a pas vu ??"),
            ("Dmitri", "250 €", "plus long que la 13"), ("lu_cie", "30 €", "les 3 autres c'était trop court"),
            ("xXx", "15 €", "il boite mdr")]
    y = 110
    for who, amount, msg in chat:
        d.text((620, y), who, font=font("segoeuib.ttf", 18), fill=(120, 170, 255))
        d.text((620 + 10 + d.textlength(who, font=font("segoeuib.ttf", 18)), y), amount, font=font("segoeuib.ttf", 18), fill=(90, 220, 120))
        d.text((620, y + 22), msg, font=s, fill=(225, 225, 230))
        y += 48
    img.save(os.path.join(OUT, "screen_stream.png"))
    print("   screen_stream.png")


def cb_label():
    W, H = 256, 96
    img = Image.new("RGB", (W, H), (232, 226, 196))
    d = ImageDraw.Draw(img)
    d.text((10, 6), "CANAL 19 — URGENCES", font=font("segoepr.ttf", 24), fill=(20, 20, 60))
    d.text((10, 48), "batterie 12 V (voir garage)", font=font("segoepr.ttf", 18), fill=(20, 20, 60))
    img.save(os.path.join(OUT, "cb_label.png"))
    print("   cb_label.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    spray_13()
    board_subjects()
    stream_page()
    cb_label()
