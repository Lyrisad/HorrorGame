"""
Textures « lisibles » : la liste aimantée sur le frigo, les écrans des téléphones des amis,
le fond d'écran et l'icône Messages du téléphone de Théo, la note du réparateur dans les égouts.
python generate_ui_textures.py <dossier_sortie>
"""
import math
import os
import sys

import numpy as np
import generate_icons
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(21)
FONTS = "C:/Windows/Fonts/"


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


def paper_base(w, h, tint=(232, 226, 210)):
    n = rng.random((h // 16 + 1, w // 16 + 1))
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=np.float32) / 255
    fib = rng.random((h, w)) * 0.06
    base = np.stack([tint[0] - 22 * n - 40 * fib, tint[1] - 22 * n - 40 * fib, tint[2] - 26 * n - 40 * fib], axis=-1)
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")


def check(d, x, y, s, color, width=7):
    d.line([(x, y + s * 0.5), (x + s * 0.35, y + s), (x + s, y)], fill=color, width=width, joint="curve")


def fridge_note(name):
    w, h = 600, 820
    img = paper_base(w, h)
    d = ImageDraw.Draw(img)
    ink = (28, 30, 60)
    red = (165, 20, 22)
    title = font("Inkfree.ttf", 92)
    hand = font("Inkfree.ttf", 74)
    small = font("Inkfree.ttf", 46)
    d.text((70, 60), "LISTE", font=title, fill=ink)
    d.line([(66, 168), (330, 162)], fill=ink, width=6)
    rows = [("Maxime", True), ("Inès", True), ("Karim", True), ("Théo", False)]
    y = 220
    for who, done in rows:
        d.text((90, y), who, font=hand, fill=ink)
        bx = 430
        d.rectangle([bx, y + 18, bx + 60, y + 78], outline=ink, width=5)
        if done:
            check(d, bx + 4, y - 4, 74, red, 9)
        y += 108
    d.text((60, y + 30), "« Le public a choisi. »", font=small, fill=red)
    # aimant rouge en haut
    d.ellipse([w // 2 - 38, -30, w // 2 + 38, 40], fill=(180, 30, 35))
    img.filter(ImageFilter.GaussianBlur(0.6)).save(os.path.join(OUT, name))
    print("  ", name)


def worker_note(name):
    """Note froissée d'un égoutier, par terre près du réveil (comprendre la créature sans tutoriel)."""
    w, h = 640, 860
    img = paper_base(w, h, (214, 206, 182))
    d = ImageDraw.Draw(img)
    ink = (25, 25, 32)
    hand = font("Inkfree.ttf", 58)
    big = font("Inkfree.ttf", 64)
    lines = [
        ("IL NE VOIT RIEN.", big, 50),
        ("Il entend TOUT.", hand, 170),
        ("Ta lumière, il s'en fout.", hand, 260),
        ("Tes pas, non.", hand, 340),
        ("Marche pas dans l'eau.", hand, 440),
        ("Cours jamais.", hand, 520),
        ("Quand il clique :", hand, 620),
        ("à genoux, bouge plus.", hand, 700),
    ]
    for text, f, y in lines:
        d.text((48, y), text, font=f, fill=ink)
    d.line([(48, 150), (560, 140)], fill=ink, width=5)
    # taches : boue et sang
    for cx, cy, r in [(590, 120, 40), (20, 600, 30), (600, 800, 55)]:
        d.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=(120, 98, 72))
    d.ellipse([440, 760, 560, 830], fill=(110, 12, 14))
    # pliures
    arr = np.asarray(img, dtype=np.float32)
    for x0 in (w // 3, 2 * w // 3):
        arr[:, x0 - 2 : x0 + 2] *= 0.82
    arr[h // 2 - 2 : h // 2 + 2, :] *= 0.82
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)).save(os.path.join(OUT, name))
    print("  ", name)


def wallpaper(name, w=540, h=1080, hue=(0.10, 0.16, 0.32), seed=0):
    r = np.random.default_rng(seed)
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    top = np.array(hue) * 0.35
    bottom = np.array(hue)
    col = top[None, None, :] * (1 - y[..., None]) + bottom[None, None, :] * y[..., None]
    col = np.repeat(col, w, axis=1)
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(26):
        cx, cy = r.uniform(0, w), r.uniform(h * 0.35, h)
        rad = r.uniform(18, 70)
        c = (int(255 * r.uniform(0.7, 1.0)), int(255 * r.uniform(0.45, 0.8)), int(255 * r.uniform(0.2, 0.5)), int(r.uniform(30, 90)))
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(6))
    img = Image.alpha_composite(img, layer).convert("RGB")
    img.save(os.path.join(OUT, name))
    print("  ", name)


def icon_messages(name):
    s = 128
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=30, fill=(52, 199, 89, 255))
    d.ellipse([22, 28, 106, 92], fill=(255, 255, 255, 255))
    d.polygon([(34, 80), (28, 104), (56, 86)], fill=(255, 255, 255, 255))
    img.save(os.path.join(OUT, name))
    print("  ", name)


def status_bar(d, w, t, color=(255, 255, 255)):
    f = font("segoeuib.ttf", 30)
    d.text((34, 18), t, font=f, fill=color)
    for i in range(4):
        hh = 8 + i * 6
        d.rectangle([w - 150 + i * 12, 46 - hh, w - 142 + i * 12, 46], fill=color)
    d.rounded_rectangle([w - 92, 22, w - 40, 46], radius=6, outline=color, width=3)
    d.rectangle([w - 88, 26, w - 66, 42], fill=color)


def friend_lock(name, owner, seed, hue, notes):
    """Écran verrouillé d'un des téléphones posés sur la table basse."""
    w, h = 360, 720
    wallpaper("_tmp_wall.png", w, h, hue, seed)
    img = Image.open(os.path.join(OUT, "_tmp_wall.png"))
    d = ImageDraw.Draw(img)
    status_bar(d, w, "23:52")
    big = font("segoeuil.ttf", 120)
    bb = d.textbbox((0, 0), "23:52", font=big)
    d.text(((w - bb[2]) / 2, 90), "23:52", font=big, fill=(255, 255, 255))
    f = font("segoeui.ttf", 26)
    bb = d.textbbox((0, 0), "samedi 14 novembre", font=f)
    d.text(((w - bb[2]) / 2, 240), "samedi 14 novembre", font=f, fill=(230, 230, 235))
    # deux notifications manquées
    card = font("segoeuib.ttf", 24)
    txt = font("segoeui.ttf", 22)
    y = 330
    for who, msg in notes:
        d.rounded_rectangle([18, y, w - 18, y + 92], radius=22, fill=(40, 40, 46))
        d.text((36, y + 12), who, font=card, fill=(255, 255, 255))
        d.text((36, y + 48), msg, font=txt, fill=(200, 200, 205))
        y += 106
    f2 = font("segoeui.ttf", 22)
    bb = d.textbbox((0, 0), owner, font=f2)
    d.text(((w - bb[2]) / 2, h - 60), owner, font=f2, fill=(200, 200, 210))
    img.save(os.path.join(OUT, name))
    os.remove(os.path.join(OUT, "_tmp_wall.png"))
    print("  ", name)


def friend_call(name, clock="23:52", cracked=False):
    w, h = 360, 720
    img = Image.new("RGB", (w, h), (18, 20, 26))
    d = ImageDraw.Draw(img)
    for yy in range(h):
        k = yy / h
        d.line([(0, yy), (w, yy)], fill=(int(30 + 20 * k), int(22 + 10 * k), int(30 + 30 * k)))
    status_bar(d, w, clock)
    f = font("segoeui.ttf", 30)
    big = font("segoeuisl.ttf", 40)
    d.ellipse([w / 2 - 70, 120, w / 2 + 70, 260], fill=(90, 92, 100))
    q = font("segoeuib.ttf", 90)
    bb = d.textbbox((0, 0), "?", font=q)
    d.text(((w - bb[2]) / 2, 128), "?", font=q, fill=(230, 230, 235))
    for text, ff, yy, c in [("Numéro masqué", big, 290, (255, 255, 255)), ("Appel entrant…", f, 370, (200, 200, 205))]:
        bb = d.textbbox((0, 0), text, font=ff)
        d.text(((w - bb[2]) / 2, yy), text, font=ff, fill=c)
    for cx, c, ic_name in [(w * 0.27, (235, 64, 52), "icon_hangup"), (w * 0.73, (52, 199, 89), "icon_call")]:
        d.ellipse([cx - 50, h - 190, cx + 50, h - 90], fill=c)
        ic = generate_icons.icon(ic_name, 58)
        img.paste(ic, (int(cx - 29), h - 169), ic)
    d.text((w * 0.27 - 50, h - 80), "Refuser", font=font("segoeui.ttf", 22), fill=(220, 220, 220))
    d.text((w * 0.73 - 50, h - 80), "Accepter", font=font("segoeui.ttf", 22), fill=(220, 220, 220))
    if cracked:
        # écran fêlé (le téléphone est tombé) : une étoile d'impact dans un coin et ses fissures
        cx, cy = w * 0.78, h * 0.18
        for k in range(11):
            ang = k / 11 * math.tau + rng.uniform(-0.2, 0.2)
            x, y = cx, cy
            pts = [(x, y)]
            for _ in range(int(rng.integers(4, 9))):
                ang += rng.uniform(-0.35, 0.35)
                step = rng.uniform(25, 70)
                x, y = x + math.cos(ang) * step, y + math.sin(ang) * step
                pts.append((x, y))
            d.line(pts, fill=(235, 238, 245), width=1)
        d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=(200, 205, 215))
    img.save(os.path.join(OUT, name))
    print("  ", name)


def friend_watch(name):
    """Ce qu'affichent les trois téléphones quand ils se taisent tous en même temps."""
    w, h = 360, 720
    img = Image.new("RGB", (w, h), (4, 4, 6))
    d = ImageDraw.Draw(img)
    rec = font("consolab.ttf", 34)
    d.ellipse([40, 60, 66, 86], fill=(230, 30, 30))
    d.text((78, 54), "EN DIRECT", font=rec, fill=(230, 230, 230))
    big = font("segoeuib.ttf", 64)
    for i, line in enumerate(["SOURIS,", "THÉO."]):
        bb = d.textbbox((0, 0), line, font=big)
        d.text(((w - bb[2]) / 2, 270 + i * 84), line, font=big, fill=(240, 240, 240))
    small = font("consola.ttf", 24)
    bb = d.textbbox((0, 0), "1 892 spectateurs", font=small)
    d.text(((w - bb[2]) / 2, 520), "1 892 spectateurs", font=small, fill=(170, 170, 175))
    img.save(os.path.join(OUT, name))
    print("  ", name)


fridge_note("note_list.png")
worker_note("note_worker.png")
wallpaper("phone_wallpaper.png")
icon_messages("icon_messages.png")
MISSED = ("Appel manqué", "Numéro masqué (3)")
friend_lock("phone_lock_0.png", "Max", 1, (0.30, 0.12, 0.10), [("Théo", "j'arrive, j'arrive… 10 min"), MISSED])
friend_lock("phone_lock_1.png", "Inès", 2, (0.28, 0.10, 0.30), [("Maman", "tu rentres à quelle heure ?"), MISSED])
friend_lock("phone_lock_2.png", "Karim", 3, (0.08, 0.22, 0.20), [("Théo", "?? réponds"), MISSED])
friend_call("phone_call.png")
friend_call("phone_call_ines.png", "03:14", True)
friend_watch("phone_watch.png")
print("OK")
