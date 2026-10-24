"""
Générateur procédural de tous les sons du jeu (aucun fichier audio externe).

Usage :  python generate_sounds.py <dossier_sortie>
Nécessite numpy + scipy.

Chaque fonction `snd_*` fabrique un son ; les boucles sont rendues
"bouclables" par un fondu enchaîné entre la fin et le début.
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
rng = np.random.default_rng(1347)
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"


# ---------------------------------------------------------------- outils
def n_samples(d):
    return int(round(d * SR))


def tt(d):
    return np.arange(n_samples(d)) / SR


def white(d):
    return rng.standard_normal(n_samples(d))


def pink(d):
    n = n_samples(d)
    x = rng.standard_normal(n)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    freqs[0] = 1
    f /= np.sqrt(freqs)
    y = np.fft.irfft(f, n)
    return y / (np.std(y) + 1e-9)


def brown(d):
    x = np.cumsum(rng.standard_normal(n_samples(d)))
    x = hp(x, 20)
    return x / (np.std(x) + 1e-9)


def _sos(kind, f, order):
    nyq = SR / 2
    if isinstance(f, (list, tuple)):
        f = [min(max(v, 10), nyq * 0.98) for v in f]
    else:
        f = min(max(f, 10), nyq * 0.98)
    return butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return sosfilt(_sos("lowpass", f, order), x)


def hp(x, f, order=2):
    return sosfilt(_sos("highpass", f, order), x)


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("bandpass", [lo, hi], order), x)


def reso(x, fc, q=8.0):
    """Filtre résonant étroit (passe-bande autour de fc)."""
    bw = fc / q
    return bp(x, max(fc - bw / 2, 20), fc + bw / 2, 2)


def env_exp(d, attack=0.002, decay=0.2):
    t = tt(d)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-5))


def env_lin(d, points):
    """points = [(t, v), ...]"""
    t = tt(d)
    ts, vs = zip(*points)
    return np.interp(t, ts, vs)


def sine(freq, d, phase=0.0):
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * tt(d) + phase)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(ph + phase)


def saw(freq, d):
    if np.isscalar(freq):
        freq = np.full(n_samples(d), float(freq))
    ph = np.cumsum(freq) / SR
    return 2 * (ph - np.floor(ph + 0.5))


def square(freq, d):
    return np.sign(sine(freq, d))


def pad(x, d):
    n = n_samples(d)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def place(buf, x, at):
    i = int(at * SR)
    if i >= len(buf):
        return buf
    j = min(len(buf), i + len(x))
    buf[i:j] += x[: j - i]
    return buf


def place_wrap(buf, x, at):
    """Place un son dans un tampon bouclé (ce qui dépasse revient au début)."""
    i = int(at * SR) % len(buf)
    for k in range(0, len(x), len(buf)):
        seg = x[k : k + len(buf)]
        end = i + len(seg)
        if end <= len(buf):
            buf[i:end] += seg
        else:
            cut = len(buf) - i
            buf[i:] += seg[:cut]
            buf[: len(seg) - cut] += seg[cut:]
    return buf


def norm(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def softclip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def reverb(x, seconds=1.5, wet=0.3, damp=4000, predelay=0.01):
    n = n_samples(seconds)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / seconds))
    ir = lp(ir, damp)
    ir = np.concatenate([np.zeros(n_samples(predelay)), ir])
    ir /= np.sqrt(np.sum(ir**2)) + 1e-9
    y = fftconvolve(x, ir)[: len(x) + len(ir)]
    dry = np.concatenate([x, np.zeros(len(y) - len(x))])
    return dry * (1 - wet) + y * wet * 1.2


def loopify(x, fade=0.5):
    n = n_samples(fade)
    out = x[:-n].copy()
    w = np.linspace(0, 1, n)
    out[:n] = x[:n] * np.sqrt(w) + x[-n:] * np.sqrt(1 - w)
    return out


def fade_out(x, d=0.05):
    n = min(n_samples(d), len(x))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def fade_in(x, d=0.01):
    n = min(n_samples(d), len(x))
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    return x


def write(name, x, peak=0.89, stereo=None):
    os.makedirs(OUT, exist_ok=True)
    if stereo is not None:
        left, right = x, stereo
        m = max(np.max(np.abs(left)), np.max(np.abs(right))) + 1e-9
        data = np.stack([left / m * peak, right / m * peak], axis=1)
        ch = 2
    else:
        data = norm(x, peak)[:, None]
        ch = 1
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("  ", name, f"{len(pcm) / SR:.2f}s")


def glottal(f0, d, jitter=0.02, shimmer=0.1):
    """Train d'impulsions de type voix (pour grognements / cris)."""
    n = n_samples(d)
    if np.isscalar(f0):
        f0 = np.full(n, float(f0))
    jit = 1 + jitter * lp(rng.standard_normal(n), 30) * 3
    ph = np.cumsum(f0 * jit) / SR
    frac = ph - np.floor(ph)
    pulse = np.exp(-frac * 9) * (1 + shimmer * rng.standard_normal(n))
    return pulse - np.mean(pulse)


def formants(x, freqs, qs=None, gains=None):
    y = np.zeros_like(x)
    for i, f in enumerate(freqs):
        q = qs[i] if qs else 6
        g = gains[i] if gains else 1.0
        y += reso(x, f, q) * g
    return y


def modal(f0, ratios, decays, d, amps=None):
    t = tt(d)
    y = np.zeros_like(t)
    for i, (r, dec) in enumerate(zip(ratios, decays)):
        a = amps[i] if amps else 1 / (i + 1)
        y += a * np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6.28)) * np.exp(-t / dec)
    return y


# ---------------------------------------------------------------- pas
def step_concrete(i):
    d = 0.25
    heel = white(d) * env_exp(d, 0.0005, 0.018)
    heel = bp(heel, 250, 3500) * 1.0 + sine(rng.uniform(70, 95), d) * env_exp(d, 0.001, 0.03) * 0.8
    toe = bp(white(d), 600, 5000) * env_exp(d, 0.0005, 0.012) * 0.55
    grit = hp(white(d) * (rng.random(n_samples(d)) > 0.985) * 3, 2500) * env_exp(d, 0.004, 0.06) * 0.25
    y = heel + grit
    y = place(y, toe, rng.uniform(0.035, 0.06))
    return fade_out(y, 0.05)


def step_wood(i):
    d = 0.3
    thump = reso(white(d), rng.uniform(110, 150), 4) * env_exp(d, 0.001, 0.06) * 3
    knock = reso(white(d), rng.uniform(350, 500), 6) * env_exp(d, 0.0008, 0.03) * 1.5
    click = hp(white(d), 2000) * env_exp(d, 0.0003, 0.006) * 0.4
    y = thump + knock + click
    if i % 3 == 0:  # léger grincement du plancher
        f = np.linspace(rng.uniform(180, 240), rng.uniform(260, 320), n_samples(d))
        creak = reso(glottal(f, d, 0.08, 0.3), 900, 3) * env_lin(d, [(0, 0), (0.05, 0.3), (0.25, 0)])
        y += creak * 0.4
    return fade_out(y, 0.05)


def step_gravel(i):
    d = 0.32
    n = n_samples(d)
    grains = np.zeros(n)
    for _ in range(rng.integers(70, 120)):
        at = rng.beta(2, 4) * 0.22
        g = white(0.004) * env_exp(0.004, 0.0002, 0.0012) * rng.uniform(0.3, 1)
        place(grains, g, at)
    y = bp(grains, 900, 7000) + bp(white(d), 150, 900) * env_exp(d, 0.003, 0.05) * 0.6
    return fade_out(y, 0.05)


def step_grass(i):
    d = 0.35
    env = env_lin(d, [(0, 0), (0.03, 1), (0.12, 0.5), (0.3, 0)])
    rustle = bp(white(d), 1500, 7000) * env * (0.6 + 0.4 * lp(rng.standard_normal(n_samples(d)), 60) * 4)
    thud = lp(white(d), 300) * env_exp(d, 0.002, 0.04) * 2
    return fade_out(rustle + thud, 0.05)


def bubble(d=0.03, f0=None):
    f0 = f0 or rng.uniform(400, 1400)
    f = np.linspace(f0, f0 * rng.uniform(1.6, 2.6), n_samples(d))
    return sine(f, d) * env_exp(d, 0.001, d / 3)


def droplet(f0=None):
    """Goutte qui retombe dans l'eau : petit « plic » dont la note monte (bulle d'air piégée)."""
    f0 = f0 or rng.uniform(900, 2600)
    d = rng.uniform(0.012, 0.03)
    f = np.linspace(f0, f0 * rng.uniform(1.3, 1.9), n_samples(d))
    return sine(f, d) * env_exp(d, 0.0008, d / 4) + hp(white(d), 3000) * env_exp(d, 0.0002, 0.002) * 0.3


def step_water(i):
    """Pas dans 5 cm d'eau : le pied claque la surface, l'eau est chassée (gerbe qui chuinte),
    des gouttes retombent tout autour, puis un petit remous quand le pied repart."""
    d = 0.6
    n = n_samples(d)
    y = np.zeros(n)
    # claque du pied à plat sur l'eau
    slap = bp(white(0.09), 350, 3800) * env_exp(0.09, 0.0015, 0.018) * 1.4
    place(y, slap, 0.0)
    place(y, lp(white(0.12), 220) * env_exp(0.12, 0.003, 0.03) * 1.2, 0.002)
    # gerbe : l'eau chassée chuinte, sa couleur descend (2,5 kHz → 800 Hz)
    sw = 0.24
    src = white(sw)
    gerbe = np.zeros(n_samples(sw))
    blk = 512
    for k in range(0, len(src), blk):
        fc = 2500 * (1 - k / len(src)) + 800 * (k / len(src))
        seg = bp(src[max(0, k - blk) : k + blk], fc * 0.6, fc * 1.6)
        gerbe[k : k + blk] = seg[-len(gerbe[k : k + blk]) :]
    gerbe *= env_lin(sw, [(0, 0), (0.01, 1), (0.08, 0.55), (sw, 0)]) * (0.7 + 0.3 * np.abs(_norm_walk(len(gerbe), 60)))
    place(y, gerbe * 0.75, 0.006)
    # gouttes qui retombent, de moins en moins fortes
    for _ in range(rng.integers(8, 15)):
        at = 0.04 + rng.beta(1.5, 3.5) * 0.4
        place(y, droplet() * rng.uniform(0.12, 0.4) * (1.0 - at * 1.4), at)
    # remous quand le pied repart
    lift = bp(white(0.14), 500, 1800) * env_lin(0.14, [(0, 0), (0.05, 1), (0.14, 0)]) * 0.25
    place(y, lift, rng.uniform(0.3, 0.38))
    return fade_out(reverb(y, 0.35, 0.12), 0.08)


def glass_crunch(i):
    """Pied qui écrase des éclats de verre : crissement granuleux et éclats qui tintent."""
    d = 0.45
    n = n_samples(d)
    y = np.zeros(n)
    place(y, step_concrete(i) * 0.5, 0.0)
    # crissement : des centaines de micro-chocs serrés, le verre qui se brise sous la semelle
    crunch = np.zeros(n)
    for _ in range(rng.integers(140, 220)):
        at = rng.beta(1.6, 4.0) * 0.32
        c = white(0.003) * env_exp(0.003, 0.0001, 0.0006) * rng.uniform(0.2, 1.0)
        place(crunch, c, at)
    y += bp(crunch, 2200, 11000) * 1.3
    # éclats qui tintent en glissant
    for _ in range(rng.integers(4, 8)):
        place(y, modal(rng.uniform(3500, 9000), [1, 2.2, 3.4], [0.03, 0.02, 0.012], 0.12) * rng.uniform(0.08, 0.25), rng.uniform(0.01, 0.3))
    return fade_out(y, 0.06)


def flashlight_tap(i):
    """Deux petits coups secs du plat de la main sur le corps alu de la lampe."""
    d = 0.5
    y = np.zeros(n_samples(d))
    for k, at in enumerate((0.0, rng.uniform(0.14, 0.2))):
        hit = modal(rng.uniform(1100, 1500), [1, 2.7, 4.1], [0.02, 0.012, 0.008], 0.1) * 0.5
        hit += lp(white(0.1), 600) * env_exp(0.1, 0.001, 0.012) * 1.2
        hit += bp(white(0.1), 2000, 6000) * env_exp(0.1, 0.0003, 0.004) * 0.6
        place(y, hit * (1.0 if k == 0 else 0.8), at)
    return fade_out(y, 0.05)


def dying_breath_loop():
    """Respiration d'un homme qui se vide de son sang : courte, irrégulière, mouillée (gargouillis),
    avec une plainte à l'expiration."""
    d = 7.0
    y = np.zeros(n_samples(d))
    t = 0.1
    while t < d - 0.2:
        ins = rng.uniform(0.35, 0.6)
        seg = bp(white(ins), 600, 2800) * env_lin(ins, [(0, 0), (ins * 0.6, 1), (ins, 0)]) * 0.5
        wet = np.abs(_norm_walk(len(seg), rng.uniform(18, 30)))
        seg *= 0.5 + wet
        place_wrap(y, seg, t)
        t += ins + rng.uniform(0.05, 0.15)
        ex = rng.uniform(0.6, 1.1)
        f0 = np.linspace(rng.uniform(95, 115), rng.uniform(75, 85), n_samples(ex))
        moan = formants(glottal(f0, ex, 0.12, 0.6), [450, 900, 2300], [4, 5, 6], [1, 0.5, 0.15]) * 0.06
        air = bp(white(ex), 300, 1800) * 0.45
        gurgle = bp(white(ex), 200, 900) * (np.abs(_norm_walk(n_samples(ex), 25)) ** 2) * 0.8
        seg2 = (moan + air + gurgle) * env_lin(ex, [(0, 0), (0.06, 1), (ex * 0.5, 0.6), (ex, 0)])
        place_wrap(y, seg2, t)
        t += ex + rng.uniform(0.5, 1.4)
    return y


def dying_cough(i):
    """Toux grasse, deux ou trois quintes, du sang dans la gorge."""
    d = 1.6
    y = np.zeros(n_samples(d))
    at = 0.0
    for k in range(int(rng.integers(2, 4))):
        c = rng.uniform(0.2, 0.32)
        burst = bp(white(c), 250, 3500) * env_exp(c, 0.004, 0.07) * 1.2
        burst += formants(glottal(rng.uniform(120, 160), c, 0.25, 0.8), [550, 1100, 2400], [3, 4, 5], [1, 0.6, 0.2]) * env_exp(c, 0.004, 0.06) * 0.35
        burst += bp(white(c), 150, 700) * (np.abs(_norm_walk(n_samples(c), 30)) ** 2) * env_exp(c, 0.01, 0.12) * 1.2
        place(y, burst * (1.0 - k * 0.2), at)
        at += c + rng.uniform(0.08, 0.2)
    return fade_out(reverb(y, 0.6, 0.12), 0.1)


def death_rattle():
    """Dernier souffle : une longue expiration qui gargouille et s'éteint."""
    d = 3.0
    n = n_samples(d)
    rattle = bp(white(d), 180, 900) * (np.abs(_norm_walk(n, 14)) ** 1.5) * 1.3
    air = bp(white(d), 400, 2200) * 0.35
    moan = formants(glottal(np.linspace(90, 60, n), d, 0.2, 0.7), [400, 850], [4, 5]) * 0.05
    y = (rattle + air + moan) * env_lin(d, [(0, 0), (0.15, 1), (1.2, 0.7), (2.6, 0.08), (d, 0)])
    return fade_out(y, 0.2)


def dying_murmur(i):
    """Phrase soufflée, presque sans voix : des voyelles chuchotées, à peine voisées, hachées."""
    d = [2.2, 2.8, 1.8][i % 3]
    n = n_samples(d)
    src = white(d)
    vowels = [(300, 870), (600, 1000), (700, 1200), (400, 1900), (350, 2200), (500, 800)]
    y = np.zeros(n)
    voice = glottal(np.full(n, rng.uniform(95, 110)) * (1 + 0.05 * _norm_walk(n, 3)), d, 0.15, 0.6) * 0.25
    blk = 2048
    seq = [vowels[int(rng.integers(0, len(vowels)))] for _ in range(n // blk + 2)]
    for k in range(0, n, blk):
        f1, f2 = seq[k // blk]
        seg = src[max(0, k - 1024) : k + blk] + voice[max(0, k - 1024) : k + blk]
        out = reso(seg, f1, 5) + reso(seg, f2, 7) * 0.7
        y[k : k + blk] = out[-len(y[k : k + blk]) :]
    syll = np.clip(np.sin(2 * np.pi * rng.uniform(3.2, 4.5) * tt(d) + rng.uniform(0, 6)), 0, 1) ** 0.6
    hiss = hp(src, 4000) * (np.clip(np.sin(2 * np.pi * 1.1 * tt(d) + 1.0), 0, 1) ** 6) * 0.3
    y = (y * syll + hiss) * env_lin(d, [(0, 0), (0.15, 1), (d * 0.7, 0.8), (d, 0)])
    return reverb(y, 0.6, 0.15)


def creature_step(i):
    d = 0.6
    thud = sine(np.linspace(65, 38, n_samples(d)), d) * env_exp(d, 0.002, 0.09) * 1.5
    slap = bp(white(d), 700, 3500) * env_exp(d, 0.0008, 0.025) * 1.2
    y = thud + slap
    for _ in range(4):
        place(y, bubble(0.04, rng.uniform(300, 700)) * 0.3, rng.uniform(0.03, 0.2))
    nail = hp(white(d), 3000) * env_exp(d, 0.0002, 0.004) * 0.4
    place(y, nail, rng.uniform(0.05, 0.1))
    return fade_out(reverb(y, 0.4, 0.15), 0.1)


# ---------------------------------------------------------------- créature
def creature_click(i):
    d = 1.1
    y = np.zeros(n_samples(d))
    t = 0.0
    rate = rng.uniform(22, 38)
    count = rng.integers(7, 14)
    fc = rng.uniform(1100, 1900)
    for k in range(count):
        c = white(0.012) * env_exp(0.012, 0.0003, 0.002)
        c = reso(c, fc * rng.uniform(0.9, 1.1), 5) * 3 + reso(c, fc * 2.3, 6)
        place(y, c * rng.uniform(0.6, 1.0) * (1 - k / count * 0.5), t)
        t += 1 / rate * rng.uniform(0.8, 1.25)
    throat = formants(glottal(rng.uniform(60, 80), d, 0.08, 0.4), [350, 900], [3, 4]) * 0.15
    y += throat * env_lin(d, [(0, 0), (0.1, 1), (t, 0.6), (d, 0)])
    return fade_out(softclip(y * 1.5, 2), 0.1)


def _norm_walk(n, cutoff):
    """Marche aléatoire lissée, normalisée entre -1 et 1 (modulations organiques, jamais périodiques)."""
    m = lp(rng.standard_normal(n), cutoff)
    return m / (np.max(np.abs(m)) + 1e-9)


def creature_growl(i):
    """Grondement de gorge : voix « fry » irrégulière + râle humide + souffle, sans aucune périodicité
    mécanique (l'ancien grognement à trémolo régulier sonnait comme un moteur).
    0 = long grondement à l'expiration, 1 = feulement bref qui monte, 2 = inspiration rauque."""
    d = [2.4, 1.3, 1.9][i]
    n = n_samples(d)
    base = [34.0, 48.0, 30.0][i]
    contour = [env_lin(d, [(0, 1.0), (d, 0.82)]), env_lin(d, [(0, 0.9), (0.35, 1.35), (d, 1.1)]), env_lin(d, [(0, 0.8), (d, 1.15)])][i]
    f0 = base * contour * (1 + 0.28 * _norm_walk(n, 4))
    # voix « craquée » : impulsions très irrégulières (jitter fort), pas de bourdonnement régulier
    creak = glottal(np.clip(f0, 18, 120), d, 0.45, 0.9)
    flutter = 0.45 + 0.55 * np.abs(_norm_walk(n, 22))  # râle : battements aléatoires de la gorge
    voice = formants(creak * flutter, [330, 820, 2350], [2.2, 2.6, 3.2], [1.0, 0.75, 0.3])
    # poitrine : grondement sourd (bruit grave, pas une note : une note régulière sonnait « moteur »)
    chest = lp(white(d), 140) * (0.4 + 0.6 * flutter) * 2.2
    # souffle rauque à travers la gorge (formants de « hhaa »)
    breath = formants(bp(white(d), 250, 5000), [650, 1250, 2900], [2.0, 2.5, 3.5], [1.0, 0.7, 0.45]) * (0.55 + 0.45 * flutter)
    hiss = bp(white(d), 3200, 8000) * 0.12 * flutter
    mix = [(1.0, 0.8, 0.9), (1.1, 0.6, 1.0), (0.35, 0.5, 1.6)][i]  # (voix, poitrine, souffle)
    y = voice * mix[0] + chest * mix[1] + breath * mix[2] * 0.6 + hiss
    # gargouillis humides au fond de la gorge
    for _ in range([9, 5, 7][i]):
        dur = rng.uniform(0.02, 0.06)
        g = bp(white(dur), rng.uniform(350, 700), rng.uniform(900, 1800)) * env_exp(dur, 0.002, dur * 0.35)
        place(y, g * rng.uniform(0.6, 1.4), rng.uniform(0.05, d - 0.1))
    shapes = [[(0, 0), (0.45, 0.85), (1.2, 1.0), (d * 0.85, 0.7), (d, 0)],
              [(0, 0), (0.05, 1.0), (0.5, 0.9), (d * 0.8, 0.5), (d, 0)],
              [(0, 0), (0.6, 0.6), (1.4, 1.0), (d, 0)]][i]
    y = lp(y * env_lin(d, shapes), 7000)
    return reverb(softclip(y * 1.6, 1.3), 0.9, 0.16)


def creature_shriek(i):
    d = 1.9
    f0 = env_lin(d, [(0, 420), (0.18, 1250), (0.9, 1050), (1.9, 700)])
    src = glottal(f0, d, 0.06, 0.6) + saw(f0 * 1.007, d) * 0.4
    y = formants(src, [900, 2400, 3600], [3, 5, 6], [1, 0.8, 0.4])
    y += bp(white(d), 1500, 6000) * 0.35
    low = formants(glottal(f0 / 4.1, d, 0.1, 0.5), [300, 700], [3, 3]) * 0.8
    y = (y + low) * env_lin(d, [(0, 0), (0.06, 1), (1.2, 0.8), (d, 0)])
    return fade_out(reverb(softclip(y * 3, 3), 1.2, 0.25), 0.2)


def creature_attack(i):
    d = 1.8
    roar_f = env_lin(d, [(0, 140), (0.2, 260), (1.4, 120)])
    roar = formants(glottal(roar_f, d, 0.15, 0.7), [400, 1100, 2600], [2, 3, 4]) * env_lin(d, [(0, 0), (0.05, 1), (1.3, 0.6), (d, 0)])
    crunch = np.zeros(n_samples(d))
    for _ in range(14):
        place(crunch, bp(white(0.03), 500, 4000) * env_exp(0.03, 0.0005, 0.01), rng.uniform(0.1, 0.9))
    hit = sine(np.linspace(90, 40, n_samples(d)), d) * env_exp(d, 0.001, 0.12) * 2
    y = softclip(roar * 3 + crunch * 1.5 + hit, 3)
    return fade_out(reverb(y, 0.9, 0.2), 0.2)


def creature_breath_loop():
    d = 8.0
    y = np.zeros(n_samples(d))
    t = 0.0
    while t < d + 2:
        inh = rng.uniform(1.0, 1.4)
        exh = rng.uniform(1.2, 1.7)
        for dur, lo, hi, g in ((inh, 500, 2200, 0.5), (exh, 250, 1400, 0.9)):
            n = white(dur)
            rasp = 1 + 0.8 * np.sin(2 * np.pi * rng.uniform(35, 55) * tt(dur))
            seg = bp(n, lo, hi) * rasp
            seg += formants(glottal(rng.uniform(50, 65), dur, 0.15, 0.6), [300, 800], [3, 3]) * 0.12
            seg *= env_lin(dur, [(0, 0), (dur * 0.3, 1), (dur * 0.8, 0.6), (dur, 0)]) * g
            place_wrap(y, seg, t % d)
            t += dur + rng.uniform(0.1, 0.4)
    return y


# ---------------------------------------------------------------- ambiances
def rain_loop(muffled=False):
    d = 10.0
    left = pink(d + 1)
    right = pink(d + 1)
    drops_l = np.zeros(n_samples(d + 1))
    drops_r = np.zeros(n_samples(d + 1))
    for _ in range(2600):
        tgt = drops_l if rng.random() < 0.5 else drops_r
        place(tgt, white(0.01) * env_exp(0.01, 0.0002, 0.002) * rng.uniform(0.1, 1), rng.uniform(0, d + 0.9))
    if muffled:
        left = lp(left, 700, 3) * 1.0 + lp(drops_l, 1800) * 2.5
        right = lp(right, 700, 3) * 1.0 + lp(drops_r, 1800) * 2.5
    else:
        left = bp(left, 400, 9000) * 0.9 + hp(drops_l, 1500) * 1.8
        right = bp(right, 400, 9000) * 0.9 + hp(drops_r, 1500) * 1.8
    return loopify(left, 1.0), loopify(right, 1.0)


def rain_car_loop():
    d = 8.0
    base = lp(pink(d + 1), 1200) * 0.8
    taps = np.zeros(n_samples(d + 1))
    for _ in range(4000):
        place(taps, reso(white(0.02), rng.uniform(600, 1600), 3) * env_exp(0.02, 0.0002, 0.004) * rng.uniform(0.2, 1), rng.uniform(0, d + 0.95))
    y = base + taps * 1.5
    return loopify(y, 1.0)


def engine_loop():
    d = 6.0
    n = n_samples(d)
    rpm_wobble = 1 + 0.01 * np.sin(2 * np.pi * 0.7 * tt(d))
    fire = 62 * rpm_wobble
    src = glottal(fire, d, 0.01, 0.15)
    y = lp(src, 260, 3) * 1.2
    y += lp(saw(31 * rpm_wobble, d), 120) * 0.4
    road = lp(brown(d), 420, 2) * 0.9 + hp(pink(d), 1800) * 0.08
    y = y + road
    return loopify(y, 0.8)


def engine_stop():
    d = 2.5
    f = env_lin(d, [(0, 62), (0.6, 50), (1.6, 18), (d, 10)])
    src = glottal(f, d, 0.02, 0.2)
    y = lp(src, 240, 3) * env_lin(d, [(0, 1), (1.2, 0.7), (d, 0)])
    rattle = bp(white(d), 200, 1500) * env_lin(d, [(0, 0), (1.3, 0), (1.45, 0.5), (1.8, 0)])
    return y + rattle * 0.3


def wind_loop():
    d = 14.0
    gust = 0.5 + 0.5 * lp(rng.standard_normal(n_samples(d + 2)), 0.3, 1) * 60
    gust = np.clip(gust, 0.1, 1.5)
    l = bp(pink(d + 2), 150, 1200) * gust
    r = bp(pink(d + 2), 180, 1400) * np.roll(gust, 9000)
    return loopify(l, 2.0), loopify(r, 2.0)


def drone_sewer():
    d = 20.0
    t = tt(d + 2)
    y = lp(brown(d + 2), 110, 3) * 1.2
    for f, a in ((41.2, 0.5), (41.9, 0.4), (61.7, 0.25), (82.4, 0.12)):
        y += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a * (0.7 + 0.3 * np.sin(2 * np.pi * rng.uniform(0.03, 0.08) * t))
    y += bp(pink(d + 2), 600, 4000) * 0.05
    for at in (4.0, 13.0):  # gémissements métalliques lointains
        g = metal_groan(rng.uniform(2.5, 4.0)) * 0.35
        place(y, lp(g, 900), at)
    return loopify(y, 2.0)


def drone_house():
    d = 16.0
    t = tt(d + 2)
    y = np.zeros_like(t)
    for f, a in ((55, 0.5), (77.78, 0.35), (55.4, 0.4), (110.2, 0.12)):
        y += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a
    y *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * t)
    glass = np.sin(2 * np.pi * (1760 + 6 * np.sin(2 * np.pi * 5 * t)) * t) * 0.02 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t))
    y += glass + lp(brown(d + 2), 90) * 0.3
    return loopify(y, 2.0)


def water_flow_loop():
    d = 6.0
    y = lp(white(d + 1), 1600, 2) * (0.6 + 0.4 * np.abs(lp(rng.standard_normal(n_samples(d + 1)), 8)) * 6)
    for _ in range(220):
        place(y, bubble(rng.uniform(0.015, 0.05), rng.uniform(300, 1200)) * rng.uniform(0.05, 0.3), rng.uniform(0, d + 0.9))
    return loopify(y, 0.8)


def buzz_loop():
    d = 2.0
    t = tt(d)
    y = np.zeros_like(t)
    for h, a in ((1, 1), (2, 0.5), (3, 0.6), (5, 0.3), (7, 0.2), (9, 0.1)):
        y += np.sin(2 * np.pi * 100 * h * t) * a
    y = softclip(y * 0.5, 2) + hp(white(d), 3000) * 0.03
    return y


def static_loop():
    d = 3.0
    y = bp(white(d), 200, 9000)
    crack = np.zeros(n_samples(d))
    for _ in range(60):
        place(crack, white(0.003) * 2, rng.uniform(0, d - 0.01))
    return loopify(y + crack, 0.3)


def heartbeat_loop():
    d = 1.0
    y = np.zeros(n_samples(d))
    for at, f, g in ((0.0, 52, 1.0), (0.27, 44, 0.7)):
        b = lp(sine(np.linspace(f * 1.4, f, n_samples(0.18)), 0.18), 120) * env_exp(0.18, 0.006, 0.05) * g
        place(y, b, at)
    return y


def breath_heavy_loop():
    d = 3.2
    y = np.zeros(n_samples(d))
    t = 0.0
    while t < d:
        for dur, lo, hi, g in ((0.55, 900, 3500, 0.6), (0.65, 500, 2500, 1.0)):
            seg = bp(white(dur), lo, hi) * env_lin(dur, [(0, 0), (dur * 0.25, 1), (dur, 0)]) * g
            seg += formants(glottal(130, dur, 0.04, 0.3), [700, 1200], [5, 5]) * 0.05 * g
            place_wrap(y, seg, t)
            t += dur + 0.12
    return y


def radio_loop():
    d = 12.0
    t = tt(d)
    y = np.zeros_like(t)
    chords = [[220.0, 261.6, 329.6, 392.0], [174.6, 220.0, 261.6, 329.6], [196.0, 246.9, 293.7, 349.2], [164.8, 207.7, 246.9, 329.6]]
    for k, ch in enumerate(chords):
        at = k * 3.0
        for f in ch:
            dur = 3.2
            tone = (np.sin(2 * np.pi * f * tt(dur)) + 0.3 * np.sin(2 * np.pi * f * 2 * tt(dur))) * env_exp(dur, 0.01, 1.4)
            place_wrap(y, tone * 0.25, at)
    y = bp(y, 300, 3200) + bp(white(d), 1000, 6000) * 0.04
    return y


def party_music_loop():
    bpm = 122
    beat = 60 / bpm
    bars = 8
    d = beat * 4 * bars
    n = n_samples(d)
    mix = np.zeros(n)
    kick_env = np.zeros(n)
    roots = [55.0, 43.65, 65.41, 49.0]  # Am F C G
    chords = [[220, 261.6, 329.6], [174.6, 220, 261.6], [196, 261.6, 329.6], [196, 246.9, 293.7]]
    for b in range(bars * 4):
        at = b * beat
        k = sine(np.geomspace(160, 48, n_samples(0.35)), 0.35) * env_exp(0.35, 0.001, 0.14)
        k += hp(white(0.35), 3000) * env_exp(0.35, 0.0002, 0.003) * 0.3
        place(mix, k * 1.0, at)
        place(kick_env, env_exp(0.3, 0.001, 0.12), at)
        if b % 4 in (1, 3):
            clap = np.zeros(n_samples(0.3))
            for o in (0, 0.011, 0.022):
                place(clap, bp(white(0.25), 900, 3500) * env_exp(0.25, 0.0005, 0.03 if o < 0.02 else 0.09), o)
            place(mix, clap * 0.5, at)
        hat = hp(white(0.12), 7000) * env_exp(0.12, 0.0005, 0.035)
        place(mix, hat * 0.25, at + beat / 2)
        place(mix, hp(white(0.05), 8000) * env_exp(0.05, 0.0003, 0.01) * 0.1, at + beat / 4)
        bar = b // 4
        root = roots[(bar // 2) % 4]
        bn = saw(root * 2, beat * 0.45) * env_lin(beat * 0.45, [(0, 0), (0.01, 1), (beat * 0.4, 0.7), (beat * 0.45, 0)])
        place(mix, lp(bn, 380) * 0.55, at + beat / 2)
    sc = 1 - 0.7 * np.clip(kick_env, 0, 1)
    padbuf = np.zeros(n)
    for bar in range(bars):
        ch = chords[(bar // 2) % 4]
        for f in ch:
            dur = beat * 4
            tone = saw(f * (1 + rng.uniform(-0.003, 0.003)), dur) + saw(f * 1.004, dur) * 0.6
            place(padbuf, tone * env_lin(dur, [(0, 0), (0.05, 1), (dur - 0.05, 0.8), (dur, 0)]) * 0.12, bar * beat * 4)
    mix += lp(padbuf, 1800) * sc
    arp = np.zeros(n)
    for s in range(bars * 16):
        bar = s // 16
        ch = chords[(bar // 2) % 4]
        f = ch[s % 3] * (2 if (s // 3) % 2 else 1)
        note = (saw(f, 0.12) * 0.5 + np.sin(2 * np.pi * f * tt(0.12))) * env_exp(0.12, 0.001, 0.05)
        place(arp, note * 0.12, s * beat / 4)
    mix += lp(arp, 3000) * sc
    return softclip(mix * 0.9, 1.4)


def tape_stop(music):
    seg = music[: n_samples(2.2)]
    d = 1.7
    t = tt(d)
    rate = np.clip(1 - t / d, 0, 1) ** 1.3
    pos = np.cumsum(rate)
    out = np.interp(pos, np.arange(len(seg)), seg)
    return lp(out, 2500) * env_lin(d, [(0, 1), (d * 0.8, 0.7), (d, 0)])


# ---------------------------------------------------------------- événements
def stinger_violin():
    d = 4.0
    t = tt(d)
    y = np.zeros_like(t)
    for f in (1480, 1568, 1661, 1760, 2093, 2217):
        vib = 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(5, 7) * t + rng.uniform(0, 6))
        y += saw(f * vib, d) * rng.uniform(0.5, 1)
    y = bp(y, 900, 6000) * env_lin(d, [(0, 0), (0.03, 1), (0.6, 0.7), (2.5, 0.2), (d, 0)])
    boom = sine(np.geomspace(70, 28, n_samples(d)), d) * env_exp(d, 0.002, 0.6) * 3
    boom += lp(white(d), 300) * env_exp(d, 0.002, 0.2) * 1.5
    return reverb(y + boom, 2.2, 0.35)


def jumpscare():
    """Le choc du kidnappeur : coup sourd + cluster de cordes stridentes + souffle saturé, très court."""
    d = 2.2
    t = tt(d)
    # cordes : grappe dissonante dans l'aigu, attaque instantanée, archets qui grincent
    y = np.zeros_like(t)
    for f in (1245, 1319, 1397, 1661, 1865, 2489, 2637):
        vib = 1 + 0.02 * np.sin(2 * np.pi * rng.uniform(7, 11) * t + rng.uniform(0, 6))
        y += saw(f * vib, d) * rng.uniform(0.5, 1)
    y = bp(y, 1100, 7000) * env_lin(d, [(0, 0), (0.008, 1), (0.25, 0.85), (0.9, 0.3), (d, 0)])
    scrape = bp(white(d), 2500, 9000) * env_lin(d, [(0, 0), (0.01, 0.9), (0.5, 0.2), (d, 0)]) * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * t))
    # impact : grave qui tombe + claquement
    boom = sine(np.geomspace(110, 30, n_samples(d)), d) * env_exp(d, 0.001, 0.5) * 3.2
    boom += lp(white(d), 700) * env_exp(d, 0.0005, 0.08) * 2.5
    # souffle à travers le masque, saturé
    breath = bp(white(d), 300, 2500) * env_lin(d, [(0, 0), (0.02, 1), (0.4, 0.6), (1.2, 0)]) * 0.9
    out = softclip(y * 0.9 + scrape * 0.7 + boom + breath, 2.2)
    return reverb(out, 1.6, 0.25)


def tap_running_loop():
    """Robinet ouvert : filet d'eau fin qui tombe dans un évier (pas une cascade)."""
    d = 6.0
    n = n_samples(d)
    y = np.zeros(n)
    # le filet : bruit aigu, étroit, qui frémit
    stream = bp(white(d), 2200, 7500) * (0.55 + 0.25 * lp(rng.standard_normal(n), 6) * 8)
    y += stream * 0.35
    # bulles et éclaboussures au fond de l'évier : petits « plic » brefs et aigus
    for _ in range(int(d * 55)):
        f0 = rng.uniform(900, 3200)
        dur = rng.uniform(0.01, 0.035)
        b = sine(np.linspace(f0, f0 * rng.uniform(1.3, 1.9), n_samples(dur)), dur) * env_exp(dur, 0.0005, dur * 0.4)
        place_wrap(y, b * rng.uniform(0.15, 0.6), rng.uniform(0, d))
    # résonance de la cuve en inox
    y += bp(white(d), 450, 900) * 0.08
    return loopify(hp(y, 300), 0.4)


def flies_loop():
    """Quelques mouches qui tournent : bourdonnements dont la hauteur et le volume vont et viennent."""
    d = 8.0
    n = n_samples(d)
    y = np.zeros(n)
    for k in range(5):
        f0 = rng.uniform(170, 260)
        wob = 1 + 0.08 * _norm_walk(n, 1.5) + 0.02 * np.sin(2 * np.pi * rng.uniform(5, 9) * tt(d))
        near = np.clip(0.35 + 0.65 * _norm_walk(n, 0.8), 0.0, 1.0) ** 2  # elle s'approche, s'éloigne
        buzz = saw(f0 * wob, d) * 0.6 + np.sign(np.sin(2 * np.pi * np.cumsum(f0 * wob) / SR)) * 0.4
        y += bp(buzz, 180, 3500) * near * rng.uniform(0.5, 1.0)
    return loopify(y, 0.6)


def steam_hiss_loop():
    """Fuite de vapeur sous pression : sifflement continu, souffle grave, petites saccades."""
    d = 6.0
    n = n_samples(d)
    jitter = 1.0 + 0.12 * _norm_walk(n, 6)
    hiss = hp(white(d), 2200) * 0.7 + bp(white(d), 800, 2600) * 0.35
    roar = lp(white(d), 260) * 0.5
    whistle = sine(3150 * (1 + 0.004 * _norm_walk(n, 2)), d) * 0.035
    return loopify((hiss + roar + whistle) * jitter, 0.5)


def wind_gust():
    """Coup de vent de la forêt qui s'engouffre par la grille d'un puits : souffle qui monte et retombe,
    sifflement dans les barreaux, feuillage qui bruisse."""
    d = 4.5
    n = n_samples(d)
    t = tt(d)
    swell = env_lin(d, [(0, 0), (1.2, 0.8), (1.9, 1.0), (2.8, 0.7), (d, 0)]) * (0.75 + 0.25 * _norm_walk(n, 3))
    body = lp(pink(d), 900) * 1.2 + bp(white(d), 300, 1400) * 0.4
    whistle = sum(sine(f * (1 + 0.03 * _norm_walk(n, 1.5)), d) * a for f, a in ((620, 0.05), (930, 0.03), (1240, 0.015)))
    rustle = bp(white(d), 2500, 7000) * np.clip(_norm_walk(n, 18), 0, 1) * 0.5
    y = (body + whistle * (0.4 + swell)) * swell + rustle * swell
    return reverb(y, 1.6, 0.3)


def owl_hoot():
    """Chouette hulotte au loin : « hou... hou-hou-hou » étouffé, entendu depuis le fond d'un puits."""
    d = 3.2
    y = np.zeros(n_samples(d))
    for at, dur, f in ((0.0, 0.55, 410), (1.15, 0.18, 395), (1.42, 0.18, 400), (1.7, 0.6, 385)):
        tone = sine(np.linspace(f, f * 0.94, n_samples(dur)), dur) + sine(np.linspace(f * 2, f * 1.88, n_samples(dur)), dur) * 0.12
        tone *= env_lin(dur, [(0, 0), (dur * 0.2, 1), (dur * 0.7, 0.8), (dur, 0)])
        place(y, tone, at)
    return reverb(lp(y, 1600) * 0.8, 2.2, 0.45)


def stinger_soft():
    d = 5.0
    t = tt(d)
    y = np.zeros_like(t)
    for f in (55, 58.3, 82.4, 87.3, 116.5):
        y += saw(f, d) * 0.4
    y = lp(y, 500) * env_lin(d, [(0, 0), (3.8, 1), (4.3, 0.2), (d, 0)])
    y += bp(white(d), 2000, 8000) * env_lin(d, [(0, 0), (3.8, 0.4), (4.0, 0), (d, 0)])
    return reverb(y, 1.8, 0.3)


def boom_hit():
    d = 3.5
    y = sine(np.geomspace(90, 25, n_samples(d)), d) * env_exp(d, 0.001, 0.8) * 2
    y += lp(white(d), 900) * env_exp(d, 0.001, 0.15)
    y += bp(white(d), 2000, 8000) * env_exp(d, 0.001, 0.05) * 0.3
    return reverb(softclip(y, 1.5), 2.5, 0.3)


def metal_groan(d=3.0):
    n = n_samples(d)
    f = 35 + 30 * np.abs(lp(rng.standard_normal(n), 2)) * 25
    src = glottal(f, d, 0.2, 0.6)
    y = formants(src, [310, 720, 1450, 2900], [10, 12, 14, 16], [1, 0.8, 0.5, 0.25])
    return y * env_lin(d, [(0, 0), (d * 0.2, 1), (d * 0.8, 0.8), (d, 0)])


def door_creak(slow=False):
    d = 4.5 if slow else 2.0
    n = n_samples(d)
    base = (90 if slow else 140) + 120 * np.abs(lp(rng.standard_normal(n), 3 if slow else 6)) * 20
    src = glottal(base, d, 0.15, 0.6)
    y = formants(src, [480, 1150, 2400], [8, 9, 10], [1, 0.7, 0.4])
    y *= env_lin(d, [(0, 0), (0.1, 1), (d * 0.85, 0.7), (d, 0)])
    return reverb(y, 0.6, 0.15)


def door_slam():
    d = 1.6
    thump = sine(np.geomspace(110, 45, n_samples(d)), d) * env_exp(d, 0.001, 0.09) * 2.5
    crack = bp(white(d), 200, 5000) * env_exp(d, 0.0005, 0.02) * 1.5
    rattle = np.zeros(n_samples(d))
    for _ in range(10):
        place(rattle, reso(white(0.03), rng.uniform(1500, 3500), 10) * env_exp(0.03, 0.0005, 0.01), rng.uniform(0.02, 0.25))
    return reverb(softclip(thump + crack + rattle * 0.5, 1.4), 1.1, 0.25)


def door_locked():
    d = 1.0
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.18, 0.33, 0.52):
        c = reso(white(0.08), rng.uniform(2200, 3200), 8) * env_exp(0.08, 0.0005, 0.012) * 2
        c += reso(white(0.08), rng.uniform(500, 800), 5) * env_exp(0.08, 0.001, 0.02)
        place(y, c, at)
    return reverb(y, 0.5, 0.15)


def knock_sequence():
    d = 2.2
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.42, 0.84):
        k = reso(white(0.25), 170, 3) * env_exp(0.25, 0.001, 0.05) * 3 + reso(white(0.25), 420, 5) * env_exp(0.25, 0.001, 0.02)
        place(y, k, at)
    return reverb(y, 0.9, 0.3)


def thud_wall():
    d = 1.4
    y = sine(np.geomspace(80, 40, n_samples(d)), d) * env_exp(d, 0.002, 0.12) * 2 + lp(white(d), 500) * env_exp(d, 0.001, 0.05)
    return reverb(y, 1.0, 0.3)


def power_down():
    d = 2.6
    clunk = sine(np.geomspace(150, 50, n_samples(d)), d) * env_exp(d, 0.001, 0.07) * 2 + bp(white(d), 800, 5000) * env_exp(d, 0.0005, 0.01)
    f = env_lin(d, [(0, 100), (2.2, 22), (d, 15)])
    hum = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(4 * np.pi * np.cumsum(f) / SR)) * env_lin(d, [(0, 0.6), (2.0, 0.3), (d, 0)])
    return reverb(clunk + hum * 0.4, 1.2, 0.2)


def flicker():
    d = 1.2
    y = np.zeros(n_samples(d))
    b = buzz_loop()
    for _ in range(7):
        dur = rng.uniform(0.03, 0.12)
        at = rng.uniform(0, d - dur)
        seg = b[: n_samples(dur)] * rng.uniform(0.3, 1)
        place(y, seg, at)
        place(y, white(0.004) * 1.5, at)
    return y


def servo():
    d = 0.55
    f = env_lin(d, [(0, 520), (0.1, 700), (0.45, 680), (d, 480)])
    y = bp(saw(f, d), 600, 4000) * env_lin(d, [(0, 0), (0.04, 1), (0.45, 0.8), (d, 0)])
    ticks = np.zeros(n_samples(d))
    for k in range(9):
        place(ticks, hp(white(0.003), 4000) * 0.5, 0.03 + k * 0.055)
    return y + ticks


def phone_buzz():
    d = 1.1
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.55):
        dur = 0.38
        z = square(172, dur) * 0.6 + sine(172, dur)
        z = lp(z, 1200) * env_lin(dur, [(0, 0), (0.02, 1), (dur - 0.03, 1), (dur, 0)])
        rattle = bp(white(dur), 2000, 6000) * (square(86, dur) > 0) * 0.15
        place(y, z + rattle, at)
    return y


def phone_ping():
    d = 0.9
    y = np.zeros(n_samples(d))
    for at, f in ((0.0, 1318.5), (0.12, 1760.0)):
        tone = (np.sin(2 * np.pi * f * tt(0.6)) + 0.25 * np.sin(2 * np.pi * f * 2.76 * tt(0.6))) * env_exp(0.6, 0.002, 0.15)
        place(y, tone, at)
    return y


def phone_ring():
    d = 3.0
    y = np.zeros(n_samples(d))
    notes = [1046.5, 1318.5, 1568.0, 1318.5, 1046.5, 1318.5, 1568.0, 2093.0]
    for k, f in enumerate(notes):
        tone = (np.sin(2 * np.pi * f * tt(0.3)) + 0.4 * np.sin(2 * np.pi * f * 4.0 * tt(0.3))) * env_exp(0.3, 0.002, 0.08)
        place(y, tone, k * 0.14)
    return y


def metal_clang():
    d = 2.5
    y = np.zeros(n_samples(d))
    for at, f0, g in ((0.0, 310, 1.0), (0.21, 345, 0.6), (0.4, 330, 0.35)):
        c = modal(f0, [1, 2.32, 4.25, 6.63, 9.38], [1.0, 0.6, 0.35, 0.2, 0.12], 2.0) * g
        c += bp(white(2.0), 1000, 8000) * env_exp(2.0, 0.0003, 0.01) * g
        place(y, c, at)
    roll = bp(white(1.2), 2000, 6000) * (rng.random(n_samples(1.2)) > 0.995) * 4
    place(y, roll * env_lin(1.2, [(0, 1), (1.2, 0)]), 0.6)
    return reverb(y, 1.5, 0.25)


def glass_break():
    """Bouteille qui éclate sur le béton : choc sourd du verre, éclats aigus, débris qui tintent."""
    d = 1.4
    y = np.zeros(n_samples(d))
    # choc du culot (le verre épais résonne avant de céder)
    place(y, modal(1050, [1, 2.35, 3.8], [0.06, 0.04, 0.02], 0.3) * 0.8, 0.0)
    # rupture : craquement large bande très court
    place(y, hp(white(0.08), 1800) * env_exp(0.08, 0.0002, 0.012) * 2.2, 0.004)
    # gros éclats
    for _ in range(7):
        f0 = rng.uniform(2600, 6800)
        place(y, modal(f0, [1, 1.83, 2.71, 3.93], [0.22, 0.13, 0.07, 0.04], 0.5) * rng.uniform(0.35, 0.8), rng.uniform(0.004, 0.05))
    # petits débris qui rebondissent et tintent
    for k in range(22):
        at = rng.uniform(0.05, 0.95) ** 1.6
        f0 = rng.uniform(3200, 9000)
        g = rng.uniform(0.08, 0.35) * (1.0 - at)
        place(y, modal(f0, [1, 2.1, 3.3], [0.06, 0.035, 0.02], 0.2) * g, at)
    y += bp(white(d), 3000, 9000) * env_lin(d, [(0, 0), (0.01, 0.25), (0.15, 0.06), (0.8, 0.0), (d, 0)])
    return reverb(y, 0.8, 0.15)


def chain_snap():
    d = 1.6
    snap = modal(2400, [1, 1.5, 2.7, 3.9], [0.15, 0.1, 0.06, 0.04], d) * 1.5 + hp(white(d), 2000) * env_exp(d, 0.0002, 0.006) * 2
    links = np.zeros(n_samples(d))
    for _ in range(9):
        place(links, modal(rng.uniform(1800, 3200), [1, 2.1, 3.4], [0.08, 0.05, 0.03], 0.2), rng.uniform(0.15, 0.9))
    return reverb(snap + links * 0.7, 1.4, 0.3)


def cutter_strain():
    d = 2.6
    n = n_samples(d)
    f = 700 + 250 * lp(rng.standard_normal(n), 4) * 15
    y = formants(glottal(np.abs(f), d, 0.1, 0.5), [1200, 2500], [8, 9]) * env_lin(d, [(0, 0), (0.3, 0.5), (d, 1)])
    return y + bp(white(d), 3000, 8000) * 0.05


def gate_open():
    d = 4.0
    y = metal_groan(d) * 1.0
    clank = modal(180, [1, 2.4, 4.4, 6.1], [0.9, 0.5, 0.3, 0.2], 1.5) * 1.2
    place(y, clank, d - 1.4)
    return reverb(y, 1.8, 0.3)


def ladder_step():
    d = 0.6
    y = modal(rng.uniform(520, 640), [1, 2.7, 5.1], [0.25, 0.12, 0.06], d) + bp(white(d), 1000, 5000) * env_exp(d, 0.0003, 0.01)
    return reverb(y, 0.8, 0.25)


def pickup():
    d = 0.5
    rustle = bp(white(d), 1500, 6000) * env_lin(d, [(0, 0), (0.05, 1), (0.3, 0.3), (d, 0)]) * 0.5
    tap = reso(white(d), 900, 4) * env_exp(d, 0.001, 0.02)
    return rustle + place(np.zeros(n_samples(d)), tap, 0.18)


def paper():
    d = 0.8
    y = np.zeros(n_samples(d))
    for _ in range(140):
        place(y, white(0.004) * rng.uniform(0.2, 1), rng.beta(2, 3) * 0.7)
    return bp(y, 2000, 9000) + bp(white(d), 3000, 8000) * env_lin(d, [(0, 0), (0.1, 0.2), (d, 0)])


def flashlight_click():
    d = 0.15
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.035):
        place(y, reso(white(0.02), 3200, 6) * env_exp(0.02, 0.0002, 0.002) * 2, at)
    return y


def hit_impact():
    d = 1.4
    y = sine(np.geomspace(120, 40, n_samples(d)), d) * env_exp(d, 0.001, 0.1) * 3
    y += bp(white(d), 300, 4000) * env_exp(d, 0.0005, 0.03) * 2
    return softclip(reverb(y, 0.6, 0.15), 3)


def body_fall():
    d = 1.6
    y = sine(np.geomspace(90, 35, n_samples(d)), d) * env_exp(d, 0.002, 0.12) * 2.5
    y += bp(white(d), 1500, 6000) * env_lin(d, [(0, 0), (0.05, 0.6), (0.5, 0)])
    clatter = np.zeros(n_samples(d))
    for _ in range(5):
        place(clatter, reso(white(0.03), rng.uniform(1800, 3000), 6) * env_exp(0.03, 0.0005, 0.008), rng.uniform(0.1, 0.5))
    return reverb(y + clatter, 0.8, 0.2)


def drag_loop():
    d = 3.0
    pulls = 0.4 + 0.6 * np.clip(np.sin(2 * np.pi * 0.9 * tt(d)), 0, 1)
    y = lp(white(d), 900) * pulls + bp(white(d), 1500, 4000) * pulls * 0.15
    return loopify(y, 0.4)


def glitch(i):
    d = rng.uniform(0.3, 0.7)
    y = np.zeros(n_samples(d))
    t = 0.0
    while t < d:
        dur = rng.uniform(0.01, 0.05)
        kind = rng.integers(0, 3)
        if kind == 0:
            seg = square(rng.uniform(200, 3000), dur)
        elif kind == 1:
            seg = np.round(white(dur) * 2) / 2
        else:
            seg = np.zeros(n_samples(dur))
        place(y, seg * rng.uniform(0.2, 0.7), t)
        t += dur
    return y


def signal_lost():
    d = 2.0
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.25, 0.5):
        place(y, np.sin(2 * np.pi * 1000 * tt(0.12)) * env_lin(0.12, [(0, 0), (0.005, 1), (0.11, 1), (0.12, 0)]) * 0.6, at)
    place(y, bp(white(1.0), 300, 8000) * env_lin(1.0, [(0, 1), (0.95, 1), (1.0, 0)]) * 0.5, 0.8)
    return y


def ui_beep():
    d = 0.5
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.16):
        place(y, np.sin(2 * np.pi * 2093 * tt(0.09)) * env_lin(0.09, [(0, 0), (0.004, 1), (0.08, 1), (0.09, 0)]), at)
    return y


def tinnitus():
    d = 7.0
    y = np.sin(2 * np.pi * 6400 * tt(d)) * env_lin(d, [(0, 0), (0.1, 1), (d, 0)]) + bp(white(d), 5000, 8000) * 0.02
    return y


def whisper(i):
    d = 2.6
    n = n_samples(d)
    src = white(d)
    f1 = 400 + 400 * np.abs(lp(rng.standard_normal(n), 5)) * 12
    syll = np.clip(np.sin(2 * np.pi * rng.uniform(4, 6) * tt(d) + rng.uniform(0, 6)), 0, 1) ** 0.7
    y = np.zeros(n)
    block = 1024
    for s in range(0, n, block):  # formant variant par blocs (voyelles chuchotées)
        f = float(f1[s])
        seg = src[max(0, s - 512) : s + block]
        out = reso(seg, f, 4) + reso(seg, f * 2.6, 6) * 0.6
        y[s : s + block] = out[-len(y[s : s + block]) :]
    hiss = hp(src, 4500) * (rng.random(n) > 0.0) * np.clip(np.sin(2 * np.pi * 1.3 * tt(d)), 0, 1) ** 4
    y = y * syll + hiss * 0.5
    return reverb(y * env_lin(d, [(0, 0), (0.2, 1), (d - 0.3, 1), (d, 0)]), 1.2, 0.3)


def drip(i):
    d = 0.5
    y = bubble(rng.uniform(0.02, 0.04), rng.uniform(900, 1800)) * 0.8
    y = pad(y, d) + pad(hp(white(0.004), 3000) * 0.3, d)
    return y


def rat_squeak():
    d = 1.0
    y = np.zeros(n_samples(d))
    for at in (0.0, 0.18, 0.31):
        dur = rng.uniform(0.07, 0.12)
        f = np.linspace(rng.uniform(3500, 4200), rng.uniform(4800, 5600), n_samples(dur)) * (1 + 0.04 * np.sin(2 * np.pi * 60 * tt(dur)))
        place(y, sine(f, dur) * env_lin(dur, [(0, 0), (0.01, 1), (dur, 0)]), at)
    return y


def splash_big():
    d = 1.2
    y = hp(white(d), 300) * env_exp(d, 0.005, 0.18)
    for _ in range(25):
        place(y, bubble(rng.uniform(0.02, 0.07), rng.uniform(250, 1000)) * rng.uniform(0.2, 0.7), rng.uniform(0.02, 0.6))
    return reverb(y, 1.0, 0.25)


def car_door():
    d = 1.4
    y = sine(np.geomspace(100, 50, n_samples(d)), d) * env_exp(d, 0.001, 0.08) * 2
    latch = reso(white(0.05), 2600, 7) * env_exp(0.05, 0.0003, 0.008) * 2
    y += bp(white(d), 300, 3000) * env_exp(d, 0.0005, 0.02)
    place(y, latch, 0.02)
    return y


def wiper():
    """Un aller (ou retour) d'essuie-glace : caoutchouc mouillé qui frotte le verre,
    eau chassée, ronron du moteur et petite butée en bout de course."""
    r = np.random.default_rng(77)
    d = 0.62
    n = n_samples(d)
    t = tt(d)
    sweep = np.clip(t / 0.55, 0, 1)
    noise = r.standard_normal(n)
    swish = bp(noise, 600, 2400) * (1.0 - 0.55 * sweep) + bp(noise, 2200, 7500) * (0.25 + 0.55 * np.sin(np.pi * sweep))
    judder = 1.0 + 0.22 * np.sin(2 * np.pi * 29 * t + 1.5 * np.sin(2 * np.pi * 2.5 * t))
    swish *= judder * env_lin(d, [(0, 0), (0.06, 1), (0.4, 0.8), (0.54, 0.25), (d, 0)])
    drops = np.zeros(n)
    for _ in range(18):
        at = r.uniform(0.25, 0.56)
        dur = 0.025
        drop = bp(r.standard_normal(n_samples(dur)), 1800, 5200) * env_exp(dur, 0.001, 0.006) * r.uniform(0.3, 1.0)
        place(drops, drop, at)
    motor = (sine(98, d) * 0.6 + sine(196, d) * 0.3 + bp(noise, 80, 300) * 0.4) * env_lin(d, [(0, 0.5), (0.3, 0.7), (d, 0.3)])
    thunk = lp(r.standard_normal(n_samples(0.12)), 240) * env_exp(0.12, 0.003, 0.03)
    out = swish * 0.85 + drops * 0.35 + motor * 0.1
    place(out, thunk * 1.3, 0.53)
    return lp(out, 6500)


WIPE_STROKE = 0.6
WIPE_CYCLE = 3.2


def wiper_cycle():
    """Un cycle d'essuie-glace intermittent, entendu de l'habitacle (boucle de 3,2 s) :
    aller (0,6 s), petit « tock » au retournement, retour, butée de parking, puis repos.
    Le frottement du caoutchouc mouillé suit la vitesse de la balaie (nul aux extrémités,
    maximal au milieu), étouffé par le verre ; léger ronron du moteur pendant le mouvement."""
    r = np.random.default_rng(1977)
    d = WIPE_CYCLE
    n = n_samples(d)
    y = np.zeros(n)
    x = r.standard_normal(n_samples(WIPE_STROKE))
    for k, start in enumerate((0.0, WIPE_STROKE)):
        D = WIPE_STROKE
        t = tt(D)
        v = np.sin(np.pi * t / D)  # vitesse de la balaie
        pink = np.cumsum(r.standard_normal(n_samples(D))) * 0.02
        pink = hp(pink, 60)
        rub = bp(r.standard_normal(n_samples(D)), 220, 1400) * 0.9 + lp(pink, 900) * 0.6
        rub *= 0.85 + 0.15 * np.sin(2 * np.pi * (9.0 + k) * t)  # léger frémissement du balai
        wet = bp(r.standard_normal(n_samples(D)), 1400, 3200) * 0.22
        boom = reso(r.standard_normal(n_samples(D)), 165, 6) * 0.5
        motor = (sine(96, D) + 0.4 * sine(192, D) + 0.15 * sine(288, D)) * 0.05
        stroke = rub * v ** 1.3 + wet * v ** 2.2 + boom * v + motor * np.clip(v * 2.0, 0, 1)
        place(y, stroke, start)
    # « tock » du retournement (en haut) puis butée de parking (en bas, un peu plus franche)
    for at, g in ((WIPE_STROKE, 0.5), (2 * WIPE_STROKE, 0.8)):
        dur = 0.09
        tock = lp(r.standard_normal(n_samples(dur)), 900) * env_exp(dur, 0.001, 0.012) + sine(118, dur) * env_exp(dur, 0.002, 0.03) * 0.8
        place(y, tock * g, at - 0.01)
    y = lp(y, 3000)
    return fade_out(fade_in(y, 0.005), 0.02)


def gasmask_breath_loop():
    """Respiration lente à travers un masque à gaz (cartouche filtrante + clapet)."""
    r = np.random.default_rng(91)
    d = 4.4
    y = np.zeros(n_samples(d))
    # inspiration : air aspiré à travers le filtre, clapet qui vibre
    di = 1.35
    ni = r.standard_normal(n_samples(di))
    inh = bp(ni, 260, 1700) + reso(ni, 520, 5) * 0.8 + reso(ni, 1300, 7) * 0.4
    inh *= 1 + 0.35 * np.sin(2 * np.pi * 17 * tt(di))
    inh *= env_lin(di, [(0, 0), (0.35, 0.8), (0.9, 1.0), (di, 0)])
    place(y, inh * 0.9, 0.15)
    # expiration : plus grave, plus longue, petit claquement de la soupape au début
    de = 1.6
    ne = r.standard_normal(n_samples(de))
    exh = bp(ne, 140, 1100) + reso(ne, 380, 4) * 1.0 + reso(ne, 900, 6) * 0.4
    exh *= env_lin(de, [(0, 0), (0.15, 1.0), (0.9, 0.7), (de, 0)])
    place(y, exh * 0.75, 2.05)
    click = bp(r.standard_normal(n_samples(0.03)), 900, 4000) * env_exp(0.03, 0.0005, 0.006)
    place(y, click * 1.2, 2.02)
    place(y, click * 0.6, 1.5)
    wet = reverb(lp(y, 3000), 0.6, 0.12, damp=2500)
    out = wet[: len(y)].copy()
    return place_wrap(out, wet[len(y):], 0.0)


def ringtone(i):
    """Trois sonneries distinctes (une par téléphone des amis)."""
    melodies = [
        ([659.3, 784.0, 987.8, 784.0], 0.16),  # marimba montante
        ([1174.7, 880.0, 1174.7, 880.0, 1174.7, 880.0], 0.11),  # trille
        ([523.3, 523.3, 659.3, 523.3, 784.0, 740.0], 0.19),  # mélodie "classique"
    ]
    notes, step = melodies[i]
    d = 2.4
    y = np.zeros(n_samples(d))
    for rep in range(2):
        for k, f in enumerate(notes):
            nd = step * 1.6
            body = np.sin(2 * np.pi * f * tt(nd)) + 0.35 * np.sin(2 * np.pi * f * (3.0 if i != 1 else 2.0) * tt(nd))
            place(y, body * env_exp(nd, 0.003, step * (0.6 if i == 0 else 0.4)), rep * 1.15 + k * step)
    return lp(y, 7000)


def phone_tap():
    """Frappe sur un écran tactile (clavier du téléphone)."""
    r = np.random.default_rng(12)
    dur = 0.05
    return bp(r.standard_normal(n_samples(dur)), 1500, 6000) * env_exp(dur, 0.0005, 0.008) + sine(220, dur) * env_exp(dur, 0.001, 0.01) * 0.3


def ringback():
    """Tonalité de retour d'appel française (425 Hz) : une sonnerie de 1,5 s."""
    d = 1.6
    y = sine(425, d) * env_lin(d, [(0, 0), (0.02, 1), (1.5, 1), (1.52, 0), (d, 0)])
    return bp(y, 300, 3400)


def message_sent():
    """« Swoosh » d'envoi d'un message."""
    d = 0.45
    f = env_lin(d, [(0, 500), (0.25, 2600), (d, 3200)])
    sweep = sine(f, d) * env_lin(d, [(0, 0), (0.05, 0.6), (0.25, 0.4), (d, 0)])
    air = bp(np.random.default_rng(3).standard_normal(n_samples(d)), 1200, 6000) * env_lin(d, [(0, 0), (0.12, 0.5), (d, 0)])
    return sweep * 0.5 + air * 0.4


def distant_wail():
    d = 3.5
    f0 = env_lin(d, [(0, 320), (0.4, 470), (1.8, 430), (2.6, 360), (d, 300)])
    f0 = f0 * (1 + 0.02 * lp(rng.standard_normal(n_samples(d)), 7) * 10)
    y = formants(glottal(f0, d, 0.03, 0.2), [820, 1180, 2900], [6, 7, 9], [1, 0.6, 0.25])
    y *= env_lin(d, [(0, 0), (0.3, 1), (2.4, 0.8), (d, 0)])
    return reverb(lp(y, 1400), 3.5, 0.6, damp=2000, predelay=0.05)


def thunder(i):
    d = 7.0
    n = n_samples(d)
    env = np.zeros(n)
    t = rng.uniform(0.0, 0.3)
    while t < d * 0.7:
        place(env, env_exp(1.5, 0.05, rng.uniform(0.3, 1.2)) * rng.uniform(0.3, 1.0), t)
        t += rng.uniform(0.15, 0.8)
    y = lp(brown(d), 160, 2) * np.clip(env, 0, 1.5) * 2 + lp(white(d), 600) * np.clip(env, 0, 1.5) * 0.3
    return reverb(y * env_lin(d, [(0, 1), (d * 0.8, 0.6), (d, 0)]), 3.0, 0.4, damp=1500)


def wake_gasp():
    d = 1.4
    y = bp(white(d), 700, 3500) * env_lin(d, [(0, 0), (0.12, 1), (0.6, 0.5), (1.1, 0)])
    y += formants(glottal(160, d, 0.05, 0.3), [750, 1300], [5, 6]) * 0.08 * env_lin(d, [(0, 0), (0.15, 1), (0.8, 0)])
    return y


# ---------------------------------------------------------------- export
def main():
    print("Génération des sons dans", OUT)
    # pas (béton, bois, gravier, herbe, eau, verre) et rats : vrais enregistrements CC0, voir real_sounds.py
    for i in range(3):
        write(f"creature_step_{i}", creature_step(i), 0.85)
        write(f"creature_click_{i}", creature_click(i), 0.85)
        write(f"creature_growl_{i}", creature_growl(i), 0.85)
        write(f"glitch_{i}", glitch(i), 0.6)
        write(f"drip_{i}", drip(i), 0.5)
    for i in range(2):
        write(f"flashlight_tap_{i}", flashlight_tap(i), 0.5)
        write(f"dying_cough_{i}", dying_cough(i), 0.75)
    for i in range(3):
        write(f"dying_murmur_{i}", dying_murmur(i), 0.55)
    write("dying_breath_loop", dying_breath_loop(), 0.6)
    write("death_rattle", death_rattle(), 0.6)
    write("creature_shriek", creature_shriek(0), 0.95)
    write("creature_attack", creature_attack(0), 0.95)
    write("creature_breath_loop", creature_breath_loop(), 0.8)
    for i in range(2):
        write(f"whisper_{i}", whisper(i), 0.6)
        write(f"thunder_{i}", thunder(i), 0.9)

    rl, rr = rain_loop(False)
    write("rain_loop", rl, 0.6, stereo=rr)
    rl, rr = rain_loop(True)
    write("rain_inside_loop", rl, 0.6, stereo=rr)
    write("rain_car_loop", rain_car_loop(), 0.55)
    write("engine_loop", engine_loop(), 0.7)
    write("engine_stop", engine_stop(), 0.7)
    wl, wr = wind_loop()
    write("wind_loop", wl, 0.5, stereo=wr)
    write("drone_sewer", drone_sewer(), 0.75)
    write("drone_house", drone_house(), 0.6)
    write("water_flow_loop", water_flow_loop(), 0.6)
    write("buzz_loop", buzz_loop(), 0.5)
    write("static_loop", static_loop(), 0.5)
    write("heartbeat_loop", heartbeat_loop(), 0.9)
    write("breath_heavy_loop", breath_heavy_loop(), 0.6)
    write("radio_loop", radio_loop(), 0.55)
    music = party_music_loop()
    write("party_music_loop", music, 0.8)
    write("tape_stop", tape_stop(music), 0.8)

    write("stinger_violin", stinger_violin(), 0.95)
    write("stinger_soft", stinger_soft(), 0.85)
    write("boom_hit", boom_hit(), 0.95)
    write("door_creak", door_creak(False), 0.7)
    write("door_creak_slow", door_creak(True), 0.7)
    write("door_slam", door_slam(), 0.95)
    write("door_locked", door_locked(), 0.7)
    write("knock_sequence", knock_sequence(), 0.85)
    write("thud_wall", thud_wall(), 0.85)
    write("power_down", power_down(), 0.85)
    write("flicker", flicker(), 0.6)
    write("servo", servo(), 0.45)
    write("phone_buzz", phone_buzz(), 0.6)
    write("phone_ping", phone_ping(), 0.6)
    write("phone_ring", phone_ring(), 0.6)
    write("metal_clang", metal_clang(), 0.95)
    write("chain_snap", chain_snap(), 0.9)
    write("cutter_strain", cutter_strain(), 0.6)
    write("gate_open", gate_open(), 0.9)
    write("ladder_step", ladder_step(), 0.7)
    write("pickup", pickup(), 0.6)
    write("paper", paper(), 0.5)
    write("flashlight_click", flashlight_click(), 0.5)
    write("hit_impact", hit_impact(), 0.95)
    write("body_fall", body_fall(), 0.9)
    write("drag_loop", drag_loop(), 0.6)
    write("signal_lost", signal_lost(), 0.7)
    write("ui_beep", ui_beep(), 0.5)
    write("tinnitus", tinnitus(), 0.25)
    # rat_squeak_0..2 : vrais enregistrements CC0, voir real_sounds.py
    write("splash_big", splash_big(), 0.8)
    write("car_door", car_door(), 0.85)
    write("wiper", wiper(), 0.5)
    write("distant_wail", distant_wail(), 0.7)
    write("wake_gasp", wake_gasp(), 0.6)
    print("OK")


if __name__ == "__main__":
    main()
