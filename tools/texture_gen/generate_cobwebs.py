"""Toiles d'araignée des égouts (assets/gen/cobweb_*.png) : réseau de fils très fins reliés entre eux
(comme les toiles « en nappe » des araignées de cave), voile de soie là où c'est dense, poussière accrochée.
- cobweb_corner.png : nappe triangulaire tendue dans un coin (deux murs + plafond) ; triangle des UV
  B (0,0) — A (1,0) en haut (accroches au plafond), C (0.5,1) en bas (accroche dans l'angle des murs).
- cobweb_edge.png : nappe le long de l'arête mur / plafond (haut = plafond, bas = mur), bouts effilochés.
- cobweb_strands.png : fils qui pendent (d'un tuyau, de la voûte) avec un lambeau de nappe en haut.
Blanc = fil, alpha = couverture. Dessiné 2x plus grand puis réduit (fils anticrénelés).
python generate_cobwebs.py [dossier_sortie]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "gen")
rnd = np.random.default_rng(31)
SS = 2  # suréchantillonnage


def sagging(p0, p1, sag, n=16):
    """Fil tendu entre deux points, qui pend un peu vers le bas de l'image (son poids, la poussière)."""
    ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    c = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + sag * ln)
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in np.linspace(0, 1, n)]


class Web:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = Image.new("L", (w * SS, h * SS), 0)
        self.dust = Image.new("L", (w * SS, h * SS), 0)
        self.d = ImageDraw.Draw(self.a)
        self.dd = ImageDraw.Draw(self.dust)

    def thread(self, pts, alpha, dusty=0.35):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=int(alpha * 255), width=1)
        if rnd.random() < dusty:
            for _ in range(int(rnd.integers(1, 4))):
                x, y = pts[int(rnd.integers(0, len(pts)))]
                r = rnd.uniform(0.5, 1.8) * SS
                self.dd.ellipse([x * SS - r, y * SS - r * 0.8, x * SS + r, y * SS + r * 0.8], fill=int(rnd.uniform(80, 190)))

    def network(self, nodes, k, alpha, sag=0.04, dusty=0.35):
        """Chaque nœud est relié à ses k plus proches voisins : maillage irrégulier, pas de grands traits."""
        nodes = np.asarray(nodes, np.float32)
        done = set()
        for i, p in enumerate(nodes):
            d = np.hypot(*(nodes - p).T)
            for j in np.argsort(d)[1:k + 1]:
                key = (min(i, j), max(i, j))
                if key in done:
                    continue
                done.add(key)
                self.thread(sagging(tuple(p), tuple(nodes[j]), rnd.uniform(0.0, sag)), rnd.uniform(*alpha), dusty)

    def gauze(self, density, count, length, alpha, sag=0.05):
        """La nappe : une multitude de fils courts entrecroisés, répartis selon `density` (0..1, taille de
        l'image) — fibreux et gazeux de près, voile gris de loin, avec des trous là où la densité tombe."""
        h, w = density.shape
        flat = density.ravel() / density.sum()
        idx = rnd.choice(flat.size, size=count, p=flat)
        for i in idx:
            y, x = divmod(int(i), w)
            ang = rnd.uniform(0, math.pi)
            ln = rnd.uniform(*length)
            dx, dy = math.cos(ang) * ln / 2, math.sin(ang) * ln / 2
            self.thread(sagging((x - dx, y - dy), (x + dx, y + dy), rnd.uniform(0, sag), 8), rnd.uniform(*alpha), 0.08)

    def save(self, name, mask, film=0.5):
        a = np.array(self.a, np.float32) / 255
        # voile de soie : là où les fils sont serrés, ils forment une pellicule laiteuse
        dens = np.array(self.a.filter(ImageFilter.GaussianBlur(7 * SS)), np.float32) / 255
        a = np.clip(a + np.clip(dens * 2.2 - 0.12, 0, 1) * film * (1 - a), 0, 1)
        size = (self.w, self.h)
        a = np.array(Image.fromarray((a * 255).astype(np.uint8)).resize(size, Image.LANCZOS), np.float32) / 255
        du = np.array(self.dust.filter(ImageFilter.GaussianBlur(0.7 * SS)).resize(size, Image.LANCZOS), np.float32) / 255
        a *= mask
        du *= mask
        alpha = np.clip(a + du * 0.8, 0, 1)
        k = np.clip(du / np.maximum(alpha, 1e-3), 0, 1)[..., None]
        silk = np.array([228, 228, 224], np.float32)
        grime = np.array([146, 137, 122], np.float32)
        rgb = silk * (1 - k) + grime * k
        out = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
        Image.fromarray(out, "RGBA").save(os.path.join(OUT, name))
        print("  ", name)


def fbm(w, h, scale, octaves=4):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        sc = max(2, int(scale / 2 ** o))
        n = rnd.random((h // sc + 2, w // sc + 2))
        out += amp * np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
        tot += amp
        amp *= 0.5
    return out / tot


def holes(w, h, scale, cut):
    """Taches de nappe et trous déchirés : 0 dans les trous, 1 dans la soie."""
    return np.clip((fbm(w, h, scale) - cut) * 5.0, 0, 1)


def corner():
    S = 512
    w = Web(S, S)
    A, B, C = np.array([S - 4.0, 4.0]), np.array([4.0, 4.0]), np.array([S / 2, S - 4.0])

    def inside(p):
        return p[1] >= 4 and abs(p[0] - S / 2) <= (S / 2 - 4) * (1 - p[1] / S)

    yy, xx = np.mgrid[0:S, 0:S]
    tri = (np.abs(xx - S / 2) <= (S / 2 - 6) * (1 - yy / S)).astype(np.float32)
    dens = tri * (1.0 - yy / S) ** 1.6 * (0.15 + holes(S, S, 90, 0.42)) + tri * 0.01
    w.gauze(dens, 2600, (14, 70), (0.07, 0.24), 0.06)
    # nœuds : quelques fils plus longs qui relient la nappe, serrés près du plafond
    nodes = []
    while len(nodes) < 110:
        p = np.array([rnd.uniform(0, S), S * rnd.random() ** 1.9])
        if inside(p):
            nodes.append(p)
    w.network(nodes, 2, (0.14, 0.35), 0.05)
    # amarrages : les nœuds proches d'un bord y sont attachés
    for p in nodes:
        for e0, e1 in ((A, B), (B, C), (C, A)):
            v = e1 - e0
            t = np.clip(np.dot(p - e0, v) / np.dot(v, v), 0, 1)
            q = e0 + v * t
            if np.hypot(*(q - p)) < 26 and rnd.random() < 0.7:
                w.thread(sagging(tuple(p), tuple(q), 0.02), rnd.uniform(0.25, 0.55))
    # quelques longs fils porteurs, du plafond vers l'angle des murs (pas tous au même point)
    for _ in range(4):
        p = B + (A - B) * rnd.uniform(0.15, 0.85)
        q = C + (np.array([S / 2, 4.0]) - C) * rnd.uniform(0.0, 0.35) + rnd.normal(0, 6, 2)
        w.thread(sagging(tuple(p), tuple(q), 0.015), rnd.uniform(0.3, 0.5), 0.6)
    m = np.clip(((S / 2) * (1 - yy / S) + 1 - np.abs(xx - S / 2)) / 3.0, 0, 1).astype(np.float32)
    w.save("cobweb_corner.png", m, 0.55)


def edge():
    W, H = 1024, 256
    w = Web(W, H)
    yy, xx = np.mgrid[0:H, 0:W]
    dens = np.sin(np.pi * xx / W) ** 0.8 * (1.0 - 0.6 * yy / H) * (0.12 + holes(W, H, 80, 0.45))
    w.gauze(dens.astype(np.float32), 4200, (14, 70), (0.07, 0.22), 0.07)
    nodes = []
    while len(nodes) < 160:
        x = rnd.uniform(0, W)
        # le long de l'arête, la nappe est plus fournie au milieu, effilochée aux bouts
        if rnd.random() < math.sin(math.pi * x / W) ** 0.7:
            nodes.append(np.array([x, H * rnd.random() ** 1.3]))
    w.network(nodes, 2, (0.12, 0.32), 0.06)
    for p in nodes:
        if p[1] < 22 and rnd.random() < 0.8:
            w.thread(sagging(tuple(p), (p[0] + rnd.normal(0, 10), 1.5), 0.0), rnd.uniform(0.25, 0.5))
        elif p[1] > H - 30 and rnd.random() < 0.8:
            w.thread(sagging(tuple(p), (p[0] + rnd.normal(0, 10), H - 1.5), 0.0), rnd.uniform(0.25, 0.5))
    m = np.clip(np.minimum(xx, W - xx) / (W * 0.12), 0, 1).astype(np.float32)
    w.save("cobweb_edge.png", m, 0.5)


def strands():
    W, H = 256, 512
    w = Web(W, H)
    # lambeau de nappe accroché en haut
    yy, xx = np.mgrid[0:H, 0:W]
    top = np.clip(1.0 - yy / 130.0, 0, 1) ** 1.5 * np.clip(np.minimum(xx, W - xx) / 40.0, 0, 1)
    w.gauze((top * (0.1 + holes(W, H, 50, 0.45)) + 1e-6).astype(np.float32), 700, (10, 50), (0.07, 0.22), 0.1)
    # fils qui pendent, souples ; certains collés à plusieurs en une cordelette poussiéreuse
    for _ in range(8):
        x0 = rnd.uniform(36, W - 36)
        ln = rnd.uniform(0.35, 0.95) * H
        amp, fr, ph = rnd.uniform(3, 9), rnd.uniform(0.6, 1.6), rnd.uniform(0, 6.3)
        n_ply = 1 if rnd.random() < 0.6 else int(rnd.integers(2, 4))
        for ply in range(n_ply):
            off = ply * rnd.uniform(0.8, 1.6)
            pts = [(x0 + off + math.sin(t * fr * 3.0 + ph) * amp * t, t * ln) for t in np.linspace(0, 1, 40)]
            w.thread(pts, rnd.uniform(0.45, 0.85), 0.8 if n_ply > 1 else 0.4)
        if rnd.random() < 0.55:
            xe, ye = x0 + math.sin(fr * 3.0 + ph) * amp, ln
            r = rnd.uniform(1.6, 3.6) * SS
            w.dd.ellipse([xe * SS - r, ye * SS - r, xe * SS + r, ye * SS + r * 1.5], fill=int(rnd.uniform(140, 210)))
    yy, xx = np.mgrid[0:H, 0:W]
    m = np.clip(np.minimum(xx, W - xx) / 12.0, 0, 1).astype(np.float32)
    w.save("cobweb_strands.png", m, 0.45)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    corner()
    edge()
    strands()
