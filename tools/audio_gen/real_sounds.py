"""Sons enregistrés (Freesound, licence CC0) à la place des sons de synthèse : pas sur béton, dans l'eau,
sur des éclats de verre, couinements de rats.

1. Télécharger les aperçus HQ : python ../dev/fs_fetch.py <cache> 6 "footsteps concrete boots"
   "wading through water" "footsteps shallow water" "broken glass step" "glass crunch footstep" "rat squeak"
   "footsteps wooden floor" "footsteps gravel" "footsteps grass" "flies buzzing" "insect scurrying"
   "body drag concrete" "vhs rewind" "pipe bang metal" "rubble falling" "light bulb pop" "rusty gate creak"
2. python real_sounds.py <cache> <dossier assets/audio>
   → découpe chaque pas (détection des attaques), garde les plus nets, normalise, écrit <nom>_<i>.wav
"""
import glob
import os
import sys
import wave

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

SR = 44100
# nom → ([(id Freesound, auteur), ...], nombre de variantes, durée max d'un pas, peak)
SOURCES = {
    "step_concrete": ([("459964", "florianreichelt")], 4, 0.45, 0.7),
    # on marche DANS l'eau (5-10 cm, on la brasse), pas dans une flaque qui claque
    "step_water": ([("342932", "ryansitz")], 4, 0.6, 0.62),
    "step_glass": ([("164458", "martinimeniscus"), ("164457", "martinimeniscus")], 4, 0.6, 0.6),
    "rat_squeak": ([("463789", "shyguy014"), ("143125", "Zabuhailo"), ("536753", "egomassive")], 3, 0.8, 0.6),
    "step_wood": ([("164315", "Rickmk2"), ("331451", "ralph.whitehead")], 4, 0.4, 0.7),
    "step_gravel": ([("352870", "PotatokingXII"), ("353799", "monte32")], 4, 0.45, 0.6),
    "step_grass": ([("206030", "Yuval"), ("411206", "straget")], 4, 0.45, 0.55),
    # événements des égouts : coups de bélier dans les tuyaux, éboulis de la voûte
    "pipe_bang": ([("687242", "DanJFilms"), ("257300", "machine_831")], 4, 1.6, 0.85),
}


def load(path):
    x, sr = sf.read(path, always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        g = np.gcd(sr, SR)
        x = resample_poly(x, SR // g, sr // g)
    return sosfilt(butter(2, 60, "highpass", fs=SR, output="sos"), x)


def envelope(x, hop):
    y = sosfilt(butter(2, 150, "highpass", fs=SR, output="sos"), x)
    return np.sqrt(np.convolve(y * y, np.ones(hop * 2) / (hop * 2), "same"))[::hop]


def segments(x, max_len):
    hop = int(0.005 * SR)
    env = envelope(x, hop)
    d = np.maximum(np.diff(env, prepend=env[0]), 0)
    thr = 0.15 * np.max(d)
    on = []
    for i in range(1, len(d) - 1):
        if d[i] > thr and d[i] >= d[i - 1] and d[i] >= d[i + 1] and (not on or (i - on[-1]) * hop / SR > 0.22):
            on.append(i)
    floor = np.percentile(env, 10) + 1e-9
    out = []
    for k, i in enumerate(on):
        a = max(0, i * hop - int(0.012 * SR))
        end = on[k + 1] * hop - int(0.03 * SR) if k + 1 < len(on) else len(x)
        b = min(a + int(max_len * SR), end, len(x))
        if b - a < int(0.15 * SR):
            continue
        seg = x[a:b].copy()
        e = envelope(seg, hop)
        # le segment commence juste avant l'impact principal (pas sur un frottement qui le précède)
        ip = int(np.argmax(e[: max(1, int(0.4 * SR / hop))]))
        if ip * hop > int(0.05 * SR):
            a2 = a + ip * hop - int(0.025 * SR)
            seg = x[a2:min(a2 + int(max_len * SR), end, len(x))].copy()
            if len(seg) < int(0.15 * SR):
                continue
            e = envelope(seg, hop)
        peak = np.max(e)
        # un deuxième impact fort dans le même segment : moins bon (on entend deux pas)
        late = e[int(0.12 * SR / hop):]
        second = float(np.max(late) / peak) if len(late) else 0.0
        # coupe la queue sous -40 dB du pic
        above = np.where(e > peak * 0.01)[0]
        if len(above):
            seg = seg[: min(len(seg), (above[-1] + 6) * hop)]
        # netteté : pic par rapport au bruit de fond de l'enregistrement, et pas de 2e attaque forte
        score = 20 * np.log10(peak / floor) - 25.0 * max(0.0, second - 0.3)
        out.append((score, seg))
    return out


def finish(seg, peak):
    n_in = int(0.004 * SR)
    n_out = min(int(0.06 * SR), len(seg) // 3)
    seg[:n_in] *= np.linspace(0, 1, n_in)
    seg[-n_out:] *= np.linspace(1, 0, n_out)
    return seg / (np.max(np.abs(seg)) + 1e-9) * peak


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(cache, out):
    for name, (srcs, count, max_len, peak) in SOURCES.items():
        picks = []
        for sid, _author in srcs:
            files = glob.glob(os.path.join(cache, "**", sid + ".mp3"), recursive=True)
            if not files:
                print("   manquant :", sid)
                continue
            segs = sorted(segments(load(files[0]), max_len), key=lambda s: -s[0])
            picks.append(segs)
        # on alterne les enregistrements pour varier, en prenant les plus nets de chacun
        chosen = []
        k = 0
        while len(chosen) < count and any(picks):
            src = picks[k % len(picks)]
            if src:
                chosen.append(src.pop(0)[1])
            k += 1
        for i, seg in enumerate(chosen):
            write(os.path.join(out, f"{name}_{i}.wav"), finish(seg, peak))
            print(f"   {name}_{i}  {len(seg) / SR:.2f}s")


# boucles : (id, auteur) → la fenêtre de 8 s la plus régulière, bouclée en fondu enchaîné
LOOPS = {
    "flies_loop": [("46938", "galeku"), ("395593", "BeeProductive")],
    "body_drag_loop": [("578493", "PostProdDog")],
}


def make_loop(cache, out, name, srcs, length=8.0, fade=0.6):
    mix = None
    for sid, _author in srcs:
        files = glob.glob(os.path.join(cache, "**", sid + ".mp3"), recursive=True)
        if not files:
            continue
        x = load(files[0])
        hop = int(0.05 * SR)
        e = envelope(x, hop)
        win = int(length / 0.05)
        best, best_i = -1e9, 0
        for i in range(0, max(1, len(e) - win), 4):
            w = e[i:i + win]
            score = np.mean(w) - 1.5 * np.std(w)  # assez fort ET régulier
            if score > best:
                best, best_i = score, i
        seg = x[best_i * hop: best_i * hop + int((length + fade) * SR)]
        seg = seg / (np.max(np.abs(seg)) + 1e-9)
        mix = seg if mix is None else mix[:min(len(mix), len(seg))] + 0.7 * seg[:min(len(mix), len(seg))]
    if mix is None:
        return
    n = int(fade * SR)
    body = mix[:-n].copy()
    w = np.linspace(0, 1, n)
    body[:n] = mix[:n] * np.sqrt(w) + mix[-n:] * np.sqrt(1 - w)
    write(os.path.join(out, name + ".wav"), body / (np.max(np.abs(body)) + 1e-9) * 0.6)
    print(f"   {name}  {len(body) / SR:.2f}s")


# extraits continus (pas d'attaques nettes) : les fenêtres les plus fournies, sans chevauchement
CLIPS = {
    "roach_skitter": (("767054", "ThabzMalik"), 3, 0.7),
    "tape_rewind": (("402451", "plasterbrain"), 1, 3.0),
    "lamp_break": (("558969", "sandb1ns"), 1, 2.8),
    "grate_creak": (("207993", "unfa"), 3, 2.2),
    "rubble": (("381645", "AlanCat"), 3, 2.0),
}


def make_clips(cache, out, name, src, count, length):
    files = glob.glob(os.path.join(cache, "**", src[0] + ".mp3"), recursive=True)
    if not files:
        return
    x = load(files[0])
    hop = int(0.02 * SR)
    e = envelope(x, hop)
    win = int(length / 0.02)
    used = np.zeros(len(e), dtype=bool)
    for i in range(count):
        best, best_i = -1.0, -1
        for k in range(0, len(e) - win, 3):
            if used[k:k + win].any():
                continue
            sc = float(np.mean(e[k:k + win]))
            if sc > best:
                best, best_i = sc, k
        if best_i < 0:
            break
        used[max(0, best_i - win // 2):best_i + win + win // 2] = True
        seg = x[best_i * hop: best_i * hop + int(length * SR)].copy()
        write(os.path.join(out, f"{name}_{i}.wav"), finish(seg, 0.5))
        print(f"   {name}_{i}  {len(seg) / SR:.2f}s")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
    for nm, src in LOOPS.items():
        make_loop(sys.argv[1], sys.argv[2], nm, src)
    for nm, (src, count, length) in CLIPS.items():
        make_clips(sys.argv[1], sys.argv[2], nm, src, count, length)
