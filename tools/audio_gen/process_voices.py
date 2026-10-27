"""Voix des dialogues : tools/voices_src/<personnage>/<réplique>.(mp3|wav) → assets/audio/dialogues/<personnage>/<réplique>.wav
Silences coupés aux deux bouts (petite marge + fondu), coupe-bas 90 Hz, léger coupe-haut 9 kHz (micro de caméra),
volume égalisé (même intensité moyenne pour toutes les répliques, crêtes sous -1 dB). La distance, l'écho des égouts
et l'étouffement derrière un mur sont ajoutés par le jeu (son 3D, bus d'écho).
Effets par personnage (OUTPUTS) : « direct » (la voix du direct dans la radio CB de la cabane : bande étroite,
saturation, souffle, craquements, clic d'alternat) ; « masque » → deux voix tirées du même enregistrement :
masque_a (l'homme en noir, masque GP-5 : un demi-ton plus haut, membrane nasillarde) et masque_b (celui du van,
vieux masque à tuyau : 2,4 demi-tons plus bas, plus lent, plus sourd), avec l'étouffement du caoutchouc et un
léger grésillement de la membrane.
python process_voices.py [personnage ...]   (sans argument : tous ; depuis n'importe où)
"""
import glob
import os
import wave
import zlib

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "tools", "voices_src")
OUT = os.path.join(ROOT, "assets", "audio", "dialogues")
SR = 44100
TARGET_RMS = -20.0  # dBFS, sur la partie parlée


def load(path):
    x, sr = sf.read(path, always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        g = np.gcd(sr, SR)
        x = resample_poly(x, SR // g, sr // g)
    return x


def process(x):
    x = sosfilt(butter(2, 90, "highpass", fs=SR, output="sos"), x)
    x = sosfilt(butter(2, 9000, "lowpass", fs=SR, output="sos"), x)
    hop = int(0.01 * SR)
    env = np.sqrt(np.convolve(x * x, np.ones(hop) / hop, "same"))
    peak = np.max(env) + 1e-9
    on = np.where(env > peak * 10 ** (-42 / 20))[0]
    a = max(0, on[0] - int(0.06 * SR))
    b = min(len(x), on[-1] + int(0.2 * SR))
    x = x[a:b].copy()
    n_in, n_out = int(0.015 * SR), int(0.12 * SR)
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    voiced = env[a:b] > peak * 10 ** (-30 / 20)
    rms = np.sqrt(np.mean(x[voiced] ** 2)) if voiced.any() else np.sqrt(np.mean(x ** 2))
    x *= 10 ** (TARGET_RMS / 20) / (rms + 1e-9)
    pk = np.max(np.abs(x))
    if pk > 10 ** (-1 / 20):
        x *= 10 ** (-1 / 20) / pk
    return x


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def _f(kind, f, x, order=2):
    return sosfilt(butter(order, f, kind, fs=SR, output="sos"), x)


def _peak(x, f, q, gain):
    """Résonance (bande étroite ajoutée au signal) : la cavité d'un masque, la membrane d'un haut-parleur."""
    return x + _f("bandpass", [f * (1 - 0.5 / q), f * (1 + 0.5 / q)], x) * gain


def _env(x, ms=12):
    n = max(1, int(ms / 1000 * SR))
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, "same"))


def _norm(x):
    voiced = _env(x) > np.max(_env(x)) * 10 ** (-30 / 20)
    rms = np.sqrt(np.mean(x[voiced] ** 2)) if voiced.any() else np.sqrt(np.mean(x ** 2))
    x = x * 10 ** (TARGET_RMS / 20) / (rms + 1e-9)
    pk = np.max(np.abs(x))
    return x * (10 ** (-1 / 20) / pk if pk > 10 ** (-1 / 20) else 1.0)


def fx_radio(x, rng):
    """La voix du direct dans une radio CB : 400 Hz - 3 kHz, haut-parleur saturé, porteuse qui flotte, souffle et
    craquements, « kssh » d'alternat au début et à la fin (on appuie, on relâche)."""
    y = _f("lowpass", 3000, _f("highpass", 400, x, 4), 4)
    y = _peak(y, 1600, 2.5, 0.8)
    y = np.tanh(y / (np.max(np.abs(y)) + 1e-9) * 4.0) / np.tanh(4.0)
    t = np.arange(len(y)) / SR
    y *= 1.0 + 0.1 * np.sin(2 * np.pi * 4.7 * t + rng.uniform(0, 6)) + 0.05 * np.sin(2 * np.pi * 11.3 * t)
    hiss = _f("bandpass", [500, 3600], rng.standard_normal(len(y))) * 0.05
    crack = np.zeros(len(y))
    for _ in range(int(len(y) / SR * 7)):
        i = int(rng.integers(0, len(y) - 200))
        crack[i:i + int(rng.integers(20, 160))] += rng.uniform(-1, 1) * rng.uniform(0.15, 0.5)
    crack = _f("bandpass", [900, 5000], crack)
    body = y * 0.8 + hiss + crack

    def kssh(d):
        n = int(d * SR)
        k = _f("bandpass", [700, 4000], rng.standard_normal(n)) * np.linspace(1, 0, n) ** 1.5 * 0.45
        k[:int(0.004 * SR)] += 0.9
        return k

    return np.concatenate([kssh(0.09), body, kssh(0.22)])


def fx_mask(x, rng, voice):
    """Voix derrière un masque à gaz : coupe-haut (caoutchouc), résonances de la cavité et de la membrane phonique,
    écho minuscule de l'espace fermé, saturation légère, grésillement de la membrane qui suit la voix."""
    if voice == "a":
        x = resample_poly(x, 50, 53)  # un demi-ton plus haut (un peu plus rapide)
        lp, peaks, buzz = 2600, [(700, 3.5, 0.9), (1850, 8.0, 0.7)], 0.12
    else:
        x = resample_poly(x, 23, 20)  # 2,4 demi-tons plus bas, 15 % plus lent : le gros du van
        lp, peaks, buzz = 1750, [(480, 3.0, 1.1), (1250, 6.0, 0.5)], 0.08
    y = _f("lowpass", lp, _f("highpass", 160, x, 2), 4)
    for f, q, g in peaks:
        y = _peak(y, f, q, g)
    d = int(0.0013 * SR)
    y[d:] += 0.35 * y[:-d]
    y = y / (np.max(np.abs(y)) + 1e-9)
    y = np.tanh(y * 1.8) / np.tanh(1.8)
    hum = _f("bandpass", [2200, 6500], rng.standard_normal(len(y))) * _env(y, 15) * buzz * 4.0
    return y + hum


OUTPUTS = {
    "direct": [("direct", fx_radio)],
    "masque": [("masque_a", lambda x, r: fx_mask(x, r, "a")), ("masque_b", lambda x, r: fx_mask(x, r, "b"))],
}


if __name__ == "__main__":
    import sys

    only = sys.argv[1:]
    for d in sorted(glob.glob(os.path.join(SRC, "*"))):
        who = os.path.basename(d)
        if only and who not in only:
            continue
        for f in sorted(glob.glob(os.path.join(d, "*.mp3")) + glob.glob(os.path.join(d, "*.wav"))):
            name = os.path.splitext(os.path.basename(f))[0]
            base = process(load(f))
            for out_dir, fx in OUTPUTS.get(who, [(who, None)]):
                os.makedirs(os.path.join(OUT, out_dir), exist_ok=True)
                y = base if fx is None else _norm(fx(base, np.random.default_rng(zlib.crc32(name.encode()))))
                write(os.path.join(OUT, out_dir, name + ".wav"), y)
                print(f"   {out_dir}/{name}  {len(y) / SR:.2f}s")
