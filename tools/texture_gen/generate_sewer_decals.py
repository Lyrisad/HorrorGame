"""
Décalcomanies des égouts : marquages de service au pochoir, bandes de danger,
échelle de niveau d'eau, coulures de mousse, fissures.
python generate_sewer_decals.py <dossier_sortie>
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import generate_textures as g


def hazard(name, w=1024, h=128):
    """Bande jaune et noire usée (bas des murs des galeries techniques)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    step = 90
    for x in range(-h, w + h, step):
        d.polygon([(x, h), (x + step / 2, h), (x + step / 2 + h, 0), (x + h, 0)], fill=(20, 20, 18, 255))
        d.polygon([(x + step / 2, h), (x + step, h), (x + step + h, 0), (x + step / 2 + h, 0)], fill=(205, 165, 25, 255))
    a = np.asarray(img, dtype=np.float32)
    wear = g.noise(w, h, 20, 4)
    a[..., 3] *= np.clip((wear - 0.2) * 2.0, 0, 1)
    g.save(Image.fromarray(a.astype(np.uint8), "RGBA"), name)


def water_gauge(name, w=192, h=1024):
    """Échelle limnimétrique peinte (repères de niveau d'eau)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([60, 0, 100, h], fill=(215, 210, 195, 235))
    f = g.font("arialbd.ttf", 40)
    for i in range(0, 11):
        y = h - i * (h / 10.5) - 10
        d.rectangle([60, y - 4, 150, y + 4], fill=(170, 20, 18, 255))
        if i % 2 == 0:
            d.text((108, y - 46), f"{i / 10:.1f}", font=f, fill=(20, 20, 20, 255))
    a = np.asarray(img, dtype=np.float32)
    wear = g.noise(w, h, 10, 4)
    a[..., 3] *= np.clip((wear - 0.15) * 1.8, 0, 1)
    # trace de crue : la moitié basse est salie
    a[h // 2 :, :, :3] *= 0.55
    g.save(Image.fromarray(a.astype(np.uint8), "RGBA"), name)


def moss(name, w=1024, h=512):
    """Mousse et coulures vertes au pied des murs humides (alpha doux)."""
    n = g.noise(w, h, 8, 5)
    y = np.linspace(0, 1, h)[:, None]
    grad = np.clip((y - 0.25) * 1.6, 0, 1)
    a = np.clip((n - 0.35) * 2.0, 0, 1) * grad
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), dtype=np.float32) / 255
    rgb = np.stack([30 + 25 * n, 48 + 40 * n, 18 + 12 * n], axis=-1)
    g.save(Image.fromarray(np.dstack([rgb, a * 235]).astype(np.uint8), "RGBA"), name)


def cracks(name, size=512):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(9)
    for _ in range(5):
        x, y = rng.uniform(0.3, 0.7) * size, rng.uniform(0.3, 0.7) * size
        ang = rng.uniform(0, 2 * np.pi)
        for _k in range(40):
            nx = x + np.cos(ang) * rng.uniform(6, 16)
            ny = y + np.sin(ang) * rng.uniform(6, 16)
            d.line([(x, y), (nx, ny)], fill=255, width=int(rng.uniform(2, 4)))
            x, y = nx, ny
            ang += rng.uniform(-0.6, 0.6)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32)
    rgb = np.zeros((size, size, 3), dtype=np.float32) + 18
    g.save(Image.fromarray(np.dstack([rgb, a * 0.9]).astype(np.uint8), "RGBA"), name)


def puddle(name, size=512):
    """Flaque : tache sombre aux bords organiques."""
    n = g.noise(size, size, 4, 4)
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    r = np.sqrt(xx**2 + yy**2) * 2
    a = np.clip((1.0 - r) * 2.5 + (n - 0.5) * 1.8, 0, 1)
    a = np.clip((a - 0.35) * 3, 0, 1)
    rgb = np.zeros((size, size, 3), dtype=np.float32) + np.array([14, 16, 14])
    g.save(Image.fromarray(np.dstack([rgb, a * 200]).astype(np.uint8), "RGBA"), name)


g.stencil(["C7 - 04"], "decal_mark_c704.png", color=(220, 220, 215), size=(768, 256), fsize=150)
g.stencil(["C7 - 11"], "decal_mark_c711.png", color=(220, 220, 215), size=(768, 256), fsize=150)
g.stencil(["COLLECTEUR", "NORD"], "decal_collecteur.png", color=(225, 205, 120), size=(1024, 384), fsize=120)
g.stencil(["RÉSERVOIR", "D'ORAGE B"], "decal_reservoir.png", color=(225, 225, 220), size=(1024, 384), fsize=120)
g.stencil(["GALERIE", "TECHNIQUE"], "decal_galerie.png", color=(235, 185, 30), size=(1024, 384), fsize=120)
g.stencil(["DANGER", "HAUTE TENSION"], "decal_danger.png", color=(230, 40, 30), size=(1024, 384), fsize=120)
g.stencil(["↑ SORTIE DE SECOURS"], "decal_exit_up.png", color=(60, 200, 90), size=(1024, 256), fsize=100)
hazard("decal_hazard.png")
water_gauge("decal_gauge.png")
moss("decal_moss.png")
cracks("decal_cracks.png")
puddle("decal_puddle.png")
print("OK")
