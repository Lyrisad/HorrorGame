"""Voix des dialogues : tools/voices_src/<personnage>/<réplique>.(mp3|wav) → assets/audio/dialogues/<personnage>/<réplique>.wav
Silences coupés aux deux bouts (petite marge + fondu), coupe-bas 90 Hz, léger coupe-haut 9 kHz (micro de caméra),
volume égalisé (même intensité moyenne pour toutes les répliques, crêtes sous -1 dB). La distance, l'écho des égouts
et l'étouffement derrière un mur sont ajoutés par le jeu (son 3D, bus d'écho).
python process_voices.py   (depuis n'importe où)
"""
import glob
import os
import wave

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


if __name__ == "__main__":
    for d in sorted(glob.glob(os.path.join(SRC, "*"))):
        who = os.path.basename(d)
        os.makedirs(os.path.join(OUT, who), exist_ok=True)
        for f in sorted(glob.glob(os.path.join(d, "*.mp3")) + glob.glob(os.path.join(d, "*.wav"))):
            name = os.path.splitext(os.path.basename(f))[0]
            y = process(load(f))
            write(os.path.join(OUT, who, name + ".wav"), y)
            print(f"   {who}/{name}  {len(y) / SR:.2f}s")
