"""Textures du chapitre « Surface » (le camp des ravisseurs, la forêt) :
- decal_spray13.png : « S·13 » à la bombe rouge sur la plaque d'égout de la session précédente (coulures, nuage)
- board_subjects.png : le tableau de liège de la régie, les 4 sujets de la session 14 (3 barrés, « EN COURS »)
- screen_stream.png : la page du direct sur l'écran de la régie (spectateurs, dons, vote pour la suite)
- cb_label.png : l'étiquette scotchée sur la radio de la cabane (canal 19)
- hut_map.png : la carte IGN punaisée dans la cabane, annotée au stylo par David Roche (session 13)
- leaf_litter.png : feuilles mortes et aiguilles (décalque projeté au sol : sur les pièges, autour de la caméra)
- road_*.png : la route départementale (panneaux 80 / danger « chasse en cours » / interdit à tout véhicule, borne
  kilométrique jaune, panneau ONF en bois, balise de bord de route, peinture usée du marquage, touffe d'herbe sèche)
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


def missing_posters():
    """Avis de recherche agrafés aux arbres (les victimes des sessions d'avant) : papier délavé, photo, coulures."""
    people = [("ROMAIN LEBRUN", "31 ans", "22/08/2026", "Saint-Ouen"), ("CLARA MEYER", "19 ans", "06/10/2026", "Montreuil"),
              ("DAVID ROCHE", "41 ans", "03/11/2026", "agent de sécurité, Bobigny")]
    for i, (name, age, date, where) in enumerate(people):
        W, H = 512, 724
        n = rng.random((H // 8 + 1, W // 8 + 1))
        stain = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
        base = np.stack([228 - 40 * stain, 224 - 42 * stain, 210 - 50 * stain], -1)
        img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(img)
        d.text((W / 2, 40), "DISPARU" if i != 1 else "DISPARUE", font=font("impact.ttf", 96), fill=(170, 20, 20), anchor="mt")
        img.paste(portrait(300, 300, 90 + i, (110, 115, 120)), (106, 160))
        d.text((W / 2, 480), name, font=font("segoeuib.ttf", 40), fill=(20, 20, 20), anchor="mt")
        d.text((W / 2, 530), age + " — " + where, font=font("segoeui.ttf", 24), fill=(30, 30, 30), anchor="mt")
        d.text((W / 2, 575), "Vu(e) pour la dernière fois le " + date, font=font("segoeui.ttf", 22), fill=(30, 30, 30), anchor="mt")
        d.text((W / 2, 640), "Toute information : 06 41 27 88 0" + str(3 + i), font=font("segoeuib.ttf", 24), fill=(20, 20, 20), anchor="mt")
        a = np.array(img, np.float32)
        # pluie : coulures verticales et bords gondolés
        for _ in range(40):
            x = int(rng.uniform(0, W))
            y0 = int(rng.uniform(0, H * 0.6))
            ln = int(rng.uniform(40, 260))
            a[y0:y0 + ln, max(0, x - 1):x + 2] *= rng.uniform(0.82, 0.93)
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "poster_missing_%d.png" % i))
        print("   poster_missing_%d.png" % i)


def hut_map():
    """Carte topographique imprimée (courbes de niveau, route, sentier), annotée au stylo bille par la victime de
    la session 13. Le nord est en haut : la route en haut, la cabane à l'ouest, le camp à l'est (comme dans le jeu)."""
    W, H = 1200, 900
    # monde : x de -42 à 48, z de -58 à 8 (z vers le bas de la carte)
    def px(x, z):
        return ((x + 42) / 90 * W, (z + 58) / 66 * H)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    base = np.zeros((H, W, 3), np.float32)
    base[:] = (238, 236, 222)
    # bois (vert pâle) par grandes taches
    field = np.zeros((H, W), np.float32)
    for k in range(7):
        f = 0.004 * (1.7 ** k)
        ph = rng.uniform(0, 6.28, 4)
        field += (np.sin(xx * f + ph[0]) * np.cos(yy * f * 1.13 + ph[1]) + np.sin((xx + yy) * f * 0.7 + ph[2])) / (1.6 ** k)
    wood = np.clip((field + 0.6) * 0.9, 0, 1)[..., None]
    base = base * (1 - wood * 0.22) + np.array([196, 222, 186], np.float32) * wood * 0.22
    # courbes de niveau (brun), une maîtresse plus épaisse de temps en temps
    hgt = field * 9.0 + yy / H * 3.0
    frac = np.abs(((hgt * 2.0) % 1.0) - 0.5)
    lines = (frac > 0.47).astype(np.float32)
    master = ((np.abs(((hgt * 0.4) % 1.0) - 0.5)) > 0.485).astype(np.float32)
    lw = np.clip(lines * 0.55 + master * 0.8, 0, 1)[..., None]
    base = base * (1 - lw) + np.array([178, 128, 82], np.float32) * lw
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # quadrillage kilométrique (bleu)
    for gx in range(0, W, 150):
        d.line([(gx, 0), (gx, H)], fill=(120, 150, 205), width=1)
    for gy in range(0, H, 150):
        d.line([(0, gy), (W, gy)], fill=(120, 150, 205), width=1)
    # la route (en haut)
    ry = px(0, -52)[1]
    d.line([(0, ry), (W, ry)], fill=(60, 50, 40), width=15)
    d.line([(0, ry), (W, ry)], fill=(245, 205, 90), width=10)
    d.text((70, ry - 34), "D 117", font=font("arialbd.ttf", 22), fill=(60, 50, 40))
    d.text((W - 260, ry + 14), "Forêt domaniale", font=font("ariali.ttf", 22), fill=(40, 90, 40))
    # sentier imprimé (tirets noirs)
    trail = [(0, 2), (-1.5, -8), (1.0, -17), (-0.5, -27), (1.0, -38), (0, -49)]
    pts = [px(*p) for p in trail]
    for a, b in zip(pts, pts[1:]):
        n = int(math.dist(a, b) / 14)
        for k in range(n):
            if k % 2 == 0:
                t0, t1 = k / n, (k + 1) / n
                d.line([(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0), (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)], fill=(30, 30, 30), width=3)
    # la cabane (petit carré noir imprimé)
    hx, hy = px(-24, -19)
    d.rectangle([hx - 9, hy - 7, hx + 9, hy + 7], fill=(30, 30, 30))
    d.text((hx - 60, hy + 14), "abri", font=font("ariali.ttf", 18), fill=(30, 30, 30))
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    d = ImageDraw.Draw(img)
    # ---- au stylo bille bleu, d'une main pressée
    pen = (28, 38, 120)
    red = (170, 25, 25)
    hand = font("Inkfree.ttf", 30)
    hand_s = font("Inkfree.ttf", 24)

    def wobble_circle(cx, cy, r, color, width=4, turns=1.15):
        pts = []
        for k in range(80):
            t = k / 79 * 6.283 * turns
            rr = r * (1 + 0.08 * math.sin(t * 3.1) + rng.uniform(-0.02, 0.02))
            pts.append((cx + math.cos(t) * rr, cy + math.sin(t) * rr * 0.8))
        d.line(pts, fill=color, width=width, joint="curve")

    wobble_circle(hx, hy, 42, pen)
    d.text((hx - 110, hy - 100), "radio !! (morte)", font=hand, fill=pen)
    d.text((hx - 110, hy - 66), "batterie ?", font=hand_s, fill=pen)
    # la plaque S13 (là où il est sorti)
    sx, sy = px(-6.5, -10)
    wobble_circle(sx, sy, 22, red, 4)
    d.text((sx - 250, sy - 12), "S13 = moi. 05h51", font=hand_s, fill=red)
    # pièges : petites croix le long du sentier
    for tx, tz in [(-1.1, -12.2), (0.7, -21.5), (0.3, -33.8)]:
        cx, cy = px(tx, tz)
        d.line([(cx - 8, cy - 8), (cx + 8, cy + 8)], fill=pen, width=3)
        d.line([(cx - 8, cy + 8), (cx + 8, cy - 8)], fill=pen, width=3)
    cx, cy = px(1.0, -21.5)
    d.text((cx - 360, cy - 18), "PIÈGES (sous les feuilles)", font=hand_s, fill=pen)
    # le camp : grosse croix rouge, flèche depuis le sentier
    kx, ky = px(28, -31)
    d.line([(kx - 26, ky - 26), (kx + 26, ky + 26)], fill=red, width=6)
    d.line([(kx - 26, ky + 26), (kx + 26, ky - 26)], fill=red, width=6)
    d.text((kx - 40, ky + 36), "EUX", font=font("Inkfree.ttf", 40), fill=red)
    d.text((kx - 120, ky + 84), "écrans, groupe élec.", font=hand_s, fill=pen)
    d.text((kx - 120, ky + 112), "le VAN = un 2e type", font=hand_s, fill=pen)
    ax0, ay0 = px(4, -30)
    d.line([(ax0, ay0), (kx - 40, ky - 4)], fill=pen, width=3)
    d.line([(kx - 40, ky - 4), (kx - 58, ky - 16)], fill=pen, width=3)
    d.line([(kx - 40, ky - 4), (kx - 56, ky + 10)], fill=pen, width=3)
    # le drone, en marge
    d.text((40, 130), "drone = il me filme. des cailloux ?", font=hand_s, fill=pen)
    # la note en bas, signée
    d.text((40, H - 150), "ils voient mais n'entendent rien. la bête : l'inverse.", font=hand, fill=pen)
    d.text((40, H - 110), "ils la rappellent au sifflet.", font=hand, fill=pen)
    d.text((W - 300, H - 70), "D.R.  03/11", font=hand, fill=pen)
    # papier : pliures en croix, taches, bords jaunis, punaises
    a = np.array(img, np.float32)
    for fx in (W // 3, 2 * W // 3):
        a[:, fx - 2:fx + 2] *= 0.86
        a[:, fx + 2:fx + 10] *= 1.03
    a[H // 2 - 2:H // 2 + 2, :] *= 0.86
    edge = np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy, H - 1 - yy))
    yellow = np.clip(1 - edge / 70, 0, 1)[..., None]
    a = a * (1 - yellow * 0.25) + np.array([200, 170, 110], np.float32) * yellow * 0.25
    for _ in range(9):
        cx, cy, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(25, 90)
        m = np.clip(1 - np.hypot(xx - cx, yy - cy) / r, 0, 1)[..., None]
        a = a * (1 - m * 0.14) + np.array([150, 120, 80], np.float32) * m * 0.14
    a = np.clip(a * rng.uniform(0.97, 1.0, (H, W, 1)), 0, 255)
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    for cx, cy in [(26, 26), (W - 26, 26), (26, H - 26), (W - 26, H - 26)]:
        d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(150, 20, 20), outline=(80, 10, 10), width=2)
        d.ellipse([cx - 5, cy - 7, cx + 1, cy - 2], fill=(230, 120, 120))
    img.save(os.path.join(OUT, "hut_map.png"))
    print("   hut_map.png")


def leaf_litter():
    """Un tapis de feuilles mortes (chêne, hêtre, quelques aiguilles) détouré, plus dense au centre : projeté par un
    Decal, il recouvre le sol ET ce qui est posé dessus (les mâchoires d'un piège à loup)."""
    S = 1024
    lrng = np.random.default_rng(5)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    browns = [(92, 62, 34), (118, 80, 40), (74, 50, 30), (135, 98, 52), (60, 44, 30), (104, 72, 44), (150, 112, 60)]

    def leaf(cx, cy, length, ang, col, kind):
        lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        dd = ImageDraw.Draw(lay)
        pts = []
        n = 28
        for k in range(n + 1):
            t = k / n
            w = math.sin(math.pi * t) ** (0.8 if kind == 0 else 1.2) * length * (0.36 if kind == 0 else 0.26)
            if kind == 0:  # chêne : bord lobé
                w *= 0.75 + 0.25 * abs(math.sin(t * math.pi * 4.5))
            pts.append((t * length - length / 2, w))
        outline = pts + [(x, -y) for (x, y) in reversed(pts)]
        ca, sa = math.cos(ang), math.sin(ang)
        poly = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for (x, y) in outline]
        a = int(lrng.uniform(225, 255))
        dd.polygon(poly, fill=col + (a,))
        # nervure centrale et queue, un peu plus sombres
        dark = tuple(int(c * 0.62) for c in col) + (a,)
        dd.line([(cx - length / 2 * ca, cy - length / 2 * sa), (cx + length / 2 * ca, cy + length / 2 * sa)], fill=dark, width=2)
        dd.line([(cx - length / 2 * ca, cy - length / 2 * sa), (cx - (length / 2 + length * 0.12) * ca, cy - (length / 2 + length * 0.12) * sa)], fill=dark, width=2)
        return lay

    def needles(cx, cy):
        lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        dd = ImageDraw.Draw(lay)
        for _ in range(int(lrng.uniform(6, 14))):
            ang = lrng.uniform(0, math.tau)
            ln = lrng.uniform(18, 34)
            x0, y0 = cx + lrng.uniform(-14, 14), cy + lrng.uniform(-14, 14)
            dd.line([(x0, y0), (x0 + math.cos(ang) * ln, y0 + math.sin(ang) * ln)], fill=(88, 66, 40, 235), width=2)
        return lay

    for i in range(520):
        # densité qui baisse vers le bord : le tapis n'a pas de contour net
        r = (lrng.random() ** 0.75) * S * 0.47
        a0 = lrng.uniform(0, math.tau)
        cx, cy = S / 2 + math.cos(a0) * r, S / 2 + math.sin(a0) * r
        if lrng.random() < 0.18:
            img = Image.alpha_composite(img, needles(cx, cy))
            continue
        col = browns[int(lrng.integers(0, len(browns)))]
        f = lrng.uniform(0.75, 1.1)
        col = tuple(int(min(255, c * f)) for c in col)
        img = Image.alpha_composite(img, leaf(cx, cy, lrng.uniform(48, 92), lrng.uniform(0, math.tau), col, int(lrng.integers(0, 2))))
    # ombre de contact entre les feuilles (elles sont empilées), grain
    a = np.array(img, np.float32)
    shade = np.array(img.split()[3].filter(ImageFilter.GaussianBlur(6)), np.float32) / 255.0
    a[..., :3] *= (0.8 + 0.2 * (1.0 - shade))[..., None]
    a[..., :3] *= lrng.uniform(0.9, 1.0, (S, S, 1))
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "leaf_litter.png"))
    print("   leaf_litter.png")


def _bahn(size, weight="Bold"):
    f = font("bahnschrift.ttf", size)
    try:
        f.set_variation_by_name(weight)
    except Exception:  # noqa: BLE001
        pass
    return f


def _weather(img, seed, amount=0.12):
    """Un panneau qui a passé des années au bord d'une route en forêt : voile de crasse, coulures, grain."""
    r = np.random.default_rng(seed)
    a = np.array(img, np.float32)
    h, w = a.shape[:2]
    grime = np.array(Image.fromarray((r.random((h // 16 + 1, w // 16 + 1)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255.0
    streaks = np.zeros((h, w), np.float32)
    for _ in range(int(w / 18)):
        x = int(r.integers(0, w))
        y0 = int(r.integers(0, h // 2))
        ln = int(r.integers(h // 6, h // 2))
        streaks[y0:y0 + ln, max(0, x - 1):x + 2] += r.uniform(0.3, 1.0)
    streaks = np.array(Image.fromarray(np.clip(streaks * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255.0
    dark = 1.0 - amount * (0.5 + grime) - 0.18 * streaks
    a[..., :3] *= dark[..., None]
    a[..., :3] *= r.uniform(0.94, 1.0, (h, w, 1))
    a[..., :3] += np.array([6, 4, 0], np.float32) * grime[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


RED = (196, 30, 36, 255)
WHITE = (236, 236, 230, 255)
BLACK = (22, 22, 24, 255)
YELLOW = (238, 190, 30, 255)


def road_signs():
    """Panneaux de la départementale qui longe la forêt (normes françaises), détourés (alpha)."""
    S = 512
    # B14 (80 km/h) et B0 (circulation interdite à tout véhicule) : disque, liseré blanc, couronne rouge
    for name, text in [("road_sign_80", "80"), ("road_sign_b0", "")]:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.ellipse([4, 4, S - 4, S - 4], fill=WHITE)
        d.ellipse([16, 16, S - 16, S - 16], fill=RED)
        d.ellipse([78, 78, S - 78, S - 78], fill=WHITE)
        if text:
            f = _bahn(250)
            bb = d.textbbox((0, 0), text, font=f)
            d.text(((S - (bb[2] - bb[0])) / 2 - bb[0], (S - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f, fill=BLACK)
        _weather(img, len(name)).save(os.path.join(OUT, name + ".png"))
        print("   %s.png" % name)
    # A14 (autres dangers) + panonceau « CHASSE EN COURS » : la battue du week-end, panneau resté là
    W, H = 512, 640
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    th = int(W * math.sqrt(3) / 2)

    def tri(m):
        return [(W / 2, 4 + m * 2), (4 + m * 1.73, th - 4 - m), (W - 4 - m * 1.73, th - 4 - m)]

    d.polygon(tri(0), fill=WHITE)
    d.polygon(tri(10), fill=RED)
    d.polygon(tri(62), fill=WHITE)
    d.rounded_rectangle([W / 2 - 17, 150, W / 2 + 17, 330], 10, fill=BLACK)
    d.ellipse([W / 2 - 20, 352, W / 2 + 20, 392], fill=BLACK)
    py = th + 22
    d.rectangle([66, py, W - 66, H - 6], fill=WHITE)
    d.rectangle([74, py + 8, W - 74, H - 14], outline=BLACK, width=6)
    for txt, y, sz in [("CHASSE", py + 22, 70), ("EN COURS", py + 102, 56)]:
        f = _bahn(sz)
        bb = d.textbbox((0, 0), txt, font=f)
        d.text(((W - (bb[2] - bb[0])) / 2 - bb[0], y - bb[1]), txt, font=f, fill=BLACK)
    _weather(img, 31).save(os.path.join(OUT, "road_sign_chasse.png"))
    print("   road_sign_chasse.png")


def road_borne():
    """Borne kilométrique d'une départementale : capuchon jaune (numéro de la route), corps blanc (le PR)."""
    W, H = 256, 416
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.pieslice([0, 0, W - 1, 255], 180, 360, fill=YELLOW)
    d.rectangle([0, 128, W - 1, H - 1], fill=WHITE)
    f = _bahn(58)
    bb = d.textbbox((0, 0), "D 47", font=f)
    d.text(((W - (bb[2] - bb[0])) / 2 - bb[0], 62 - bb[1]), "D 47", font=f, fill=BLACK)
    f = _bahn(120)
    bb = d.textbbox((0, 0), "12", font=f)
    d.text(((W - (bb[2] - bb[0])) / 2 - bb[0], 190 - bb[1]), "12", font=f, fill=BLACK)
    a = np.array(_weather(img, 47, 0.18), np.float32)
    # terre en bas (éclaboussures de la route, herbe)
    yy = np.linspace(0, 1, H)[:, None]
    mud = np.clip((yy - 0.78) / 0.22, 0, 1) * 0.55
    a[..., 0] *= 1 - mud * 0.45
    a[..., 1] *= 1 - mud * 0.5
    a[..., 2] *= 1 - mud * 0.62
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "road_borne.png"))
    print("   road_borne.png")


def road_forest_sign():
    """Panneau en bois de l'ONF à l'entrée du chemin : planche brune, lettres creusées peintes en crème."""
    W, H = 1024, 288
    r = np.random.default_rng(9)
    base = np.zeros((H, W, 3), np.float32)
    base[:] = (88, 58, 34)
    # veines du bois (horizontales, ondulées) et joint entre les deux planches
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    grain = np.sin(yy * 0.21 + np.sin(xx * 0.008 + yy * 0.02) * 3.0 + r.uniform(0, 6)) * 0.5 + 0.5
    grain = grain ** 3
    base *= (0.82 + 0.25 * grain)[..., None]
    base[H // 2 - 3:H // 2 + 3, :] *= 0.45
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([10, 10, W - 11, H - 11], outline=(232, 214, 160, 255), width=7)
    for txt, y, sz in [("FORÊT DOMANIALE", 34, 96), ("DES ESSARTS", 156, 92)]:
        f = _bahn(sz, "SemiBold")
        bb = d.textbbox((0, 0), txt, font=f)
        x = (W - (bb[2] - bb[0])) / 2 - bb[0]
        d.text((x + 3, y - bb[1] + 3), txt, font=f, fill=(40, 26, 16, 255))
        d.text((x, y - bb[1]), txt, font=f, fill=(226, 206, 150, 255))
    _weather(img, 12, 0.2).save(os.path.join(OUT, "road_forest_sign.png"))
    print("   road_forest_sign.png")


def road_delineator():
    """Balise J6 (délinéateur) : PVC blanc, bande noire en biais en haut, crasse de la route en bas."""
    W, H = 64, 512
    img = Image.new("RGBA", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    d.polygon([(0, 70), (W, 40), (W, 150), (0, 180)], fill=BLACK)
    a = np.array(_weather(img, 6, 0.1), np.float32)
    yy = np.linspace(0, 1, H)[:, None]
    mud = np.clip((yy - 0.6) / 0.4, 0, 1) ** 1.5 * 0.6
    a[..., 0] *= 1 - mud * 0.45
    a[..., 1] *= 1 - mud * 0.5
    a[..., 2] *= 1 - mud * 0.6
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "road_delineator.png"))
    print("   road_delineator.png")


def road_paint():
    """Peinture du marquage au sol, usée par les pneus : clair = peinture, sombre = l'enrobé qui reparaît."""
    W, H = 64, 512
    r = np.random.default_rng(3)
    def smooth(h, w):
        return np.array(Image.fromarray((r.random((h, w)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255.0

    n = smooth(10, 3) * 0.65 + smooth(40, 8) * 0.3 + np.array(Image.fromarray((r.random((H, W)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255.0 * 0.05
    wear = np.clip((n - 0.2) * 3.0, 0, 1)
    v = (0.3 + 0.7 * wear) * 255
    Image.fromarray(np.clip(v, 0, 255).astype(np.uint8), "L").save(os.path.join(OUT, "road_paint.png"))
    print("   road_paint.png")


def road_grass():
    """Une touffe d'herbe de bord de route en novembre : sèche, paille, un peu de vert au pied (détourée)."""
    S = 512
    r = np.random.default_rng(21)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cols = [(176, 156, 104), (150, 128, 86), (128, 112, 74), (108, 106, 66), (84, 92, 52), (190, 172, 120), (120, 96, 64)]
    blades = []
    for i in range(170):
        x0 = S / 2 + r.normal(0, S * 0.14)
        h = S * r.uniform(0.45, 0.97)
        lean = r.normal(0, 0.28) + (x0 - S / 2) / S * 0.9
        wbase = r.uniform(5, 10)
        blades.append((h, x0, lean, wbase, cols[int(r.integers(0, len(cols)))]))
    blades.sort(key=lambda b: -b[0])
    for h, x0, lean, wbase, col in blades:
        lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        dd = ImageDraw.Draw(lay)
        left, right = [], []
        n = 14
        for k in range(n + 1):
            t = k / n
            x = x0 + lean * h * t * t
            y = S - 2 - h * t + (h * 0.12 * t ** 3 if abs(lean) > 0.35 else 0)
            w = wbase * (1 - t) ** 0.9 * 0.5
            left.append((x - w, y))
            right.append((x + w, y))
        shade = r.uniform(0.75, 1.05)
        c = tuple(int(min(255, v * shade)) for v in col)
        dd.polygon(left + right[::-1], fill=c + (255,))
        img = Image.alpha_composite(img, lay)
    a = np.array(img, np.float32)
    yy = np.linspace(0, 1, S)[:, None]
    a[..., :3] *= (0.45 + 0.55 * np.clip((1 - yy) * 1.6, 0, 1))[..., None]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "road_grass.png"))
    print("   road_grass.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    spray_13()
    board_subjects()
    stream_page()
    cb_label()
    missing_posters()
    hut_map()
    leaf_litter()
    road_signs()
    road_borne()
    road_forest_sign()
    road_delineator()
    road_paint()
    road_grass()
