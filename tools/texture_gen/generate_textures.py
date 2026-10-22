"""
Génère les textures spécifiques au jeu (graffitis, sang, pochoirs, feuillage, faisceau de lampe...).

Usage :  python generate_textures.py <dossier_sortie>
Nécessite numpy + pillow.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(77)
FONTS = "C:/Windows/Fonts/"


def font(name, size):
    for n in (name, "arialbd.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(FONTS + n, size)
        except OSError:
            continue
    return ImageFont.load_default()


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("  ", name, img.size)


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


# ------------------------------------------------------------ graffitis
def spray_text(lines, name, color=(150, 12, 10), size=(1024, 512), font_name="impact.ttf", fsize=150, drips=True, angle=-3):
    w, h = size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    total_h = len(lines) * fsize * 1.05
    y = (h - total_h) / 2
    for line in lines:
        f = font(font_name, fsize)
        bbox = d.textbbox((0, 0), line, font=f)
        tw = bbox[2] - bbox[0]
        x = (w - tw) / 2 + rng.uniform(-20, 20)
        d.text((x, y), line, font=f, fill=255)
        y += fsize * 1.05
    mask = mask.rotate(angle, resample=Image.BICUBIC)
    m = np.asarray(mask, dtype=np.float32) / 255
    if drips:
        cols = np.where(m.max(axis=0) > 0.5)[0]
        for _ in range(28):
            if len(cols) == 0:
                break
            x = int(rng.choice(cols))
            ys = np.where(m[:, x] > 0.5)[0]
            if len(ys) == 0:
                continue
            y0 = ys.max()
            length = int(rng.uniform(20, 120))
            width = int(rng.uniform(2, 5))
            for yy in range(y0, min(h - 1, y0 + length)):
                fade = 1 - (yy - y0) / length
                m[yy, max(0, x - width // 2) : x + width // 2 + 1] = np.maximum(m[yy, max(0, x - width // 2) : x + width // 2 + 1], fade)
    soft = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), dtype=np.float32) / 255
    speck = (rng.random((h, w)) < soft * 0.25).astype(np.float32)
    alpha = np.clip(m * 0.92 + soft * 0.25 + speck * 0.5, 0, 1)
    alpha *= 0.75 + 0.25 * noise(w, h, 16, 3)
    rgb = np.zeros((h, w, 3), dtype=np.float32)
    for i in range(3):
        rgb[..., i] = color[i] * (0.8 + 0.2 * noise(w, h, 32, 2))
    img = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    save(Image.fromarray(img, "RGBA"), name)


def stencil(lines, name, color=(225, 205, 120), size=(1024, 256), fsize=110):
    w, h = size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    f = font("arialbd.ttf", fsize)
    y = (h - len(lines) * fsize * 1.1) / 2
    for line in lines:
        bbox = d.textbbox((0, 0), line, font=f)
        d.text(((w - (bbox[2] - bbox[0])) / 2, y), line, font=f, fill=255)
        y += fsize * 1.1
    m = np.asarray(mask, dtype=np.float32) / 255
    wear = noise(w, h, 24, 4)
    alpha = m * np.clip((wear - 0.25) * 2.2, 0, 1) * 0.9
    rgb = np.zeros((h, w, 3), dtype=np.float32)
    for i in range(3):
        rgb[..., i] = color[i]
    save(Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8), "RGBA"), name)


# ------------------------------------------------------------ sang / saleté
def blood_splat(name, size=512, kind="pool"):
    w = h = size
    m = np.zeros((h, w), dtype=np.float32)
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    if kind == "pool":
        for _ in range(14):
            r = rng.uniform(40, 130)
            x, y = cx + rng.normal(0, 50), cy + rng.normal(0, 50)
            d.ellipse([x - r, y - r * rng.uniform(0.6, 1), x + r, y + r * rng.uniform(0.6, 1)], fill=255)
        for _ in range(60):
            r = rng.uniform(2, 12)
            a = rng.uniform(0, 6.28)
            dist = rng.uniform(140, 240)
            x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    elif kind == "smear":
        y = cy
        for x in range(30, w - 30, 3):
            y += rng.normal(0, 1.5)
            thick = 60 * (1 - abs(x - w / 2) / (w / 2)) ** 0.5 + 10
            for k in range(-int(thick), int(thick), 3):
                if rng.random() < 0.85:
                    d.point((x, y + k), fill=int(255 * rng.uniform(0.5, 1)))
        img = img.filter(ImageFilter.GaussianBlur(2))
    elif kind == "hand":
        # empreinte de main traînée
        for dx, dy, rx, ry in ((0, 40, 70, 80), (-75, -60, 16, 55), (-30, -100, 16, 65), (15, -105, 16, 68), (58, -85, 15, 58), (95, 10, 15, 45)):
            d.ellipse([cx + dx - rx, cy + dy - ry, cx + dx + rx, cy + dy + ry], fill=255)
        for k in range(1, 6):
            for dx in (-75, -30, 15, 58):
                d.line([cx + dx, cy - 60, cx + dx + rng.normal(0, 4), cy + 120 + k * 25], fill=140, width=8)
    m = np.asarray(img.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32) / 255
    tex = noise(w, h, 8, 4)
    alpha = np.clip(m * (0.7 + 0.5 * tex), 0, 1)
    rgb = np.stack([70 + 60 * tex, 4 + 6 * tex, 4 + 6 * tex], axis=-1)
    save(Image.fromarray(np.dstack([rgb, alpha * 235]).astype(np.uint8), "RGBA"), f"{name}.png")


def grime(name, size=(512, 1024)):
    w, h = size
    n = noise(w, h, 6, 5)
    streaks = np.zeros((h, w), dtype=np.float32)
    for _ in range(40):
        x = int(rng.uniform(0, w))
        width = int(rng.uniform(4, 30))
        length = rng.uniform(0.3, 1.0)
        prof = np.clip(1 - np.linspace(0, 1, h) / length, 0, 1) ** 1.5
        streaks[:, max(0, x - width) : x + width] += prof[:, None] * rng.uniform(0.2, 0.6)
    a = np.clip(streaks * 0.7 + (n - 0.5) * 0.6, 0, 1)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), dtype=np.float32) / 255
    rgb = np.stack([20 + 15 * n, 22 + 18 * n, 12 + 8 * n], axis=-1)
    save(Image.fromarray(np.dstack([rgb, a * 220]).astype(np.uint8), "RGBA"), f"{name}.png")


def scratches(name, size=512):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    for group in range(5):
        gx = 60 + group * 85
        for k in range(4):
            x0 = gx + k * 14 + rng.normal(0, 2)
            d.line([x0, 120 + rng.normal(0, 8), x0 + rng.normal(0, 6), 380 + rng.normal(0, 10)], fill=255, width=4)
        d.line([gx - 10, 300, gx + 60, 200], fill=255, width=4)
    for _ in range(6):  # griffures
        x0 = rng.uniform(40, 470)
        d.line([x0, 30, x0 + rng.uniform(-60, 60), 480], fill=200, width=3)
    m = np.asarray(img.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255
    rgb = np.full((size, size, 3), 185, dtype=np.float32)
    save(Image.fromarray(np.dstack([rgb, m * 200]).astype(np.uint8), "RGBA"), f"{name}.png")


# ------------------------------------------------------------ nature / lumière
def needles(name, size=512):
    """Texture de branche de sapin (alpha) posée sur les cônes des arbres."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(90):
        x0 = rng.uniform(0, size)
        y0 = rng.uniform(-40, size)
        length = rng.uniform(80, 220)
        ang = math.radians(rng.uniform(70, 110))
        x1, y1 = x0 + math.cos(ang) * length, y0 + math.sin(ang) * length
        g = int(rng.uniform(28, 60))
        d.line([x0, y0, x1, y1], fill=(g // 2, g, g // 3, 255), width=3)
        for t in np.linspace(0, 1, 26):
            px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for side in (-1, 1):
                a2 = ang + side * math.radians(rng.uniform(35, 60))
                l2 = rng.uniform(10, 26) * (1 - t * 0.5)
                gg = int(rng.uniform(30, 75))
                d.line([px, py, px + math.cos(a2) * l2, py + math.sin(a2) * l2], fill=(gg // 2, gg, gg // 3, 255), width=2)
    save(img, name)


def flashlight_cookie(name, size=256):
    y, x = np.mgrid[0:size, 0:size]
    r = np.hypot(x - size / 2, y - size / 2) / (size / 2)
    hot = np.exp(-(r / 0.22) ** 2) * 1.0
    ring = np.exp(-((r - 0.42) / 0.05) ** 2) * 0.35
    spill = np.clip(1 - r, 0, 1) ** 1.4 * 0.45
    v = np.clip(hot + ring + spill, 0, 1)
    v *= 0.92 + 0.08 * noise(size, size, 12, 3)
    v[r > 0.98] = 0
    save(Image.fromarray((v * 255).astype(np.uint8), "L").convert("RGB"), name)


def paper(name, size=512):
    n = noise(size, size, 16, 5)
    base = np.stack([228 - 25 * n, 222 - 25 * n, 205 - 30 * n], axis=-1)
    save(Image.fromarray(base.astype(np.uint8), "RGB"), name)


def banner(name):
    w, h = 2048, 256
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    text = "JOYEUX ANNIVERSAIRE MAX !"
    colors = [(230, 60, 70), (250, 190, 40), (60, 170, 230), (120, 200, 90), (220, 100, 200)]
    f = font("arialbd.ttf", 120)
    d.line([0, 30, w, 30], fill=(240, 240, 240, 255), width=4)
    x = 40
    for i, ch in enumerate(text):
        if ch == " ":
            x += 50
            continue
        c = colors[i % len(colors)]
        d.polygon([(x - 8, 30), (x + 92, 30), (x + 42, 235)], fill=c + (255,))
        d.text((x + 8, 45), ch, font=f, fill=(255, 255, 255, 255))
        x += 82
    save(img, name)


def photo(name, label, seed):
    r = np.random.default_rng(seed)
    w, h = 512, 384
    n = noise(w, h, 6, 4)
    base = np.stack([40 + 50 * n, 42 + 45 * n, 38 + 40 * n], axis=-1)
    img = Image.fromarray(base.astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    cx = r.uniform(180, 330)
    d.ellipse([cx - 32, 110, cx + 32, 180], fill=(18, 18, 18))
    d.rounded_rectangle([cx - 70, 175, cx + 70, 384], 30, fill=(15, 15, 16))
    img = img.filter(ImageFilter.GaussianBlur(2.5))
    d = ImageDraw.Draw(img)
    d.text((14, 12), label, font=font("consolab.ttf", 26), fill=(240, 240, 240))
    d.text((14, h - 40), f"2026-11-{int(r.integers(1, 14)):02d}  {int(r.integers(0, 23)):02d}:{int(r.integers(0, 59)):02d}", font=font("consola.ttf", 22), fill=(255, 200, 60))
    border = Image.new("RGB", (w + 40, h + 110), (236, 234, 226))
    border.paste(img, (20, 20))
    save(border, name)


def icon(name):
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        '<rect width="128" height="128" rx="18" fill="#0b0b0d"/>'
        '<circle cx="40" cy="64" r="18" fill="#e3141e"/>'
        '<text x="66" y="76" font-family="Consolas, monospace" font-weight="bold" font-size="34" fill="#f2f2f2">REC</text>'
        "</svg>"
    )
    with open(name, "w", encoding="utf8") as f:
        f.write(svg)
    print("  ", name)


def main():
    print("Textures ->", OUT)
    spray_text(["IL ENTEND", "TOUT"], "decal_hear.png")
    spray_text(["NE COURS", "PAS"], "decal_run.png", color=(130, 10, 8), fsize=130, angle=4)
    spray_text(["AIDEZ-NOUS"], "decal_help.png", color=(120, 8, 8), size=(1024, 256), fsize=150, angle=-1)
    spray_text(["ILS", "REGARDENT"], "decal_watch.png", color=(20, 20, 20), fsize=140, angle=2)
    stencil(["LOCAL TECHNIQUE  →"], "decal_tech_right.png")
    stencil(["←  LOCAL TECHNIQUE"], "decal_tech_left.png")
    stencil(["ÉCLUSE 3  →"], "decal_lock_right.png", color=(230, 230, 230))
    stencil(["←  ÉCLUSE 3"], "decal_lock_left.png", color=(230, 230, 230))
    stencil(["SECTEUR C-7", "ACCÈS INTERDIT"], "decal_sector.png", color=(220, 220, 215), size=(1024, 384), fsize=100)
    blood_splat("decal_blood_pool", kind="pool")
    blood_splat("decal_blood_smear", kind="smear")
    blood_splat("decal_handprint", kind="hand")
    grime("decal_grime")
    scratches("decal_scratches")
    needles("needles.png")
    flashlight_cookie("flashlight_cookie.png")
    paper("paper.png")
    banner("banner.png")
    photo("photo_1.png", "SUJET 1 - M. DUBREUIL", 1)
    photo("photo_2.png", "SUJET 2 - I. FERRAND", 2)
    photo("photo_3.png", "SUJET 3 - K. HADDAD", 3)
    photo("photo_4.png", "SUJET 4 - T. MARCHAND", 4)
    icon(os.path.join(OUT, "..", "..", "icon.svg"))
    print("OK")


if __name__ == "__main__":
    main()
