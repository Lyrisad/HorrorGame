"""
Icônes de téléphone (pictogrammes Material Icons de Google, licence Apache 2.0) dessinées depuis leurs
tracés vectoriels SVG : décrocher, raccrocher, micro coupé, clavier, haut-parleur.

Usage :  python generate_icons.py <dossier_sortie>
"""
import os
import re
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)

PATHS = {
    "icon_call": "M20.01 15.38c-1.23 0-2.42-.2-3.53-.56-.35-.12-.74-.03-1.01.24l-1.57 1.97c-2.83-1.35-5.48-3.9-6.89-6.83l1.95-1.66c.27-.28.35-.67.24-1.02-.37-1.11-.56-2.3-.56-3.53 0-.54-.45-.99-.99-.99H4.19C3.65 3 3 3.24 3 3.99 3 13.28 10.73 21 20.01 21c.71 0 .99-.63.99-1.18v-3.45c0-.54-.45-.99-.99-.99z",
    "icon_hangup": "M12 9c-1.6 0-3.15.25-4.6.72v3.1c0 .39-.23.74-.56.9-.98.49-1.87 1.12-2.66 1.85-.18.18-.43.28-.7.28-.28 0-.53-.11-.71-.29L.29 13.08c-.18-.17-.29-.42-.29-.7 0-.28.11-.53.29-.71C3.34 8.78 7.46 7 12 7s8.66 1.78 11.71 4.67c.18.18.29.43.29.71 0 .28-.11.53-.29.71l-2.48 2.48c-.18.18-.43.29-.71.29-.27 0-.52-.11-.7-.28-.79-.74-1.69-1.36-2.67-1.85-.33-.16-.56-.5-.56-.9v-3.1C15.15 9.25 13.6 9 12 9z",
    "icon_mute": "M19 11h-1.7c0 .74-.16 1.43-.43 2.05l1.23 1.23c.56-.98.9-2.09.9-3.28zm-4.02.17c0-.06.02-.11.02-.17V5c0-1.66-1.34-3-3-3S9 3.34 9 5v.18l5.98 5.99zM4.27 3L3 4.27l6.01 6.01V11c0 1.66 1.33 3 2.99 3 .22 0 .44-.03.65-.08l1.66 1.66c-.71.33-1.5.52-2.31.52-2.76 0-5.3-2.1-5.3-5.1H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c.91-.13 1.77-.45 2.54-.9L19.73 21 21 19.73 4.27 3z",
    "icon_keypad": "M12 19c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zM6 1c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12-8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm-6 8c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z",
    "icon_speaker": "M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z",
}


def parse(d):
    """Tracé SVG (M L H V C S Z, absolus et relatifs) → liste de polygones (courbes échantillonnées)."""
    toks = re.findall(r"[MmLlHhVvCcSsZz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    polys, cur = [], []
    x = y = 0.0
    sx = sy = 0.0
    last_c2 = None
    i = 0
    cmd = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def cubic(p0, p1, p2, p3):
        for k in range(1, 13):
            t = k / 12
            mt = 1 - t
            cur.append((mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
                        mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1]))

    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in "Zz":
                if cur:
                    polys.append(cur)
                cur = []
                x, y = sx, sy
                last_c2 = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = num(), num()
            if rel:
                nx, ny = x + nx, y + ny
            if cur:
                polys.append(cur)
            cur = [(nx, ny)]
            x, y = sx, sy = nx, ny
            cmd = "l" if rel else "L"
            last_c2 = None
        elif c == "L":
            nx, ny = num(), num()
            if rel:
                nx, ny = x + nx, y + ny
            cur.append((nx, ny))
            x, y = nx, ny
            last_c2 = None
        elif c == "H":
            nx = num()
            x = x + nx if rel else nx
            cur.append((x, y))
            last_c2 = None
        elif c == "V":
            ny = num()
            y = y + ny if rel else ny
            cur.append((x, y))
            last_c2 = None
        elif c == "C":
            v = [num() for _ in range(6)]
            if rel:
                v = [v[0] + x, v[1] + y, v[2] + x, v[3] + y, v[4] + x, v[5] + y]
            cubic((x, y), (v[0], v[1]), (v[2], v[3]), (v[4], v[5]))
            last_c2 = (v[2], v[3])
            x, y = v[4], v[5]
        elif c == "S":
            v = [num() for _ in range(4)]
            if rel:
                v = [v[0] + x, v[1] + y, v[2] + x, v[3] + y]
            c1 = (2 * x - last_c2[0], 2 * y - last_c2[1]) if last_c2 else (x, y)
            cubic((x, y), c1, (v[0], v[1]), (v[2], v[3]))
            last_c2 = (v[0], v[1])
            x, y = v[2], v[3]
    if cur:
        polys.append(cur)
    return polys


def icon(name, size=128, color=(255, 255, 255, 255), angle=0):
    k = 16
    S = size * k
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    sc = S / 24.0
    for poly in parse(PATHS[name]):
        if len(poly) >= 3:
            d.polygon([(px * sc, py * sc) for px, py in poly], fill=color)
    if angle:
        img = img.rotate(angle, resample=Image.BICUBIC)
    return img.resize((size, size), Image.LANCZOS)


def main():
    for n in PATHS:
        icon(n).save(os.path.join(OUT, n + ".png"))
        print("  ", n + ".png")


if __name__ == "__main__":
    main()
