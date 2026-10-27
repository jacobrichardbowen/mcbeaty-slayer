"""Prepares the uploaded sound effects for the game.

One-shots: mono (so 3D panning works), leading silence trimmed to 2 ms, tail
faded. The Maxim loop is rebuilt from its middle seven shots with a crossfaded
seam; the end-of-burst file is trimmed to its final shot. The wind becomes a
seamless, gently compressed Ogg Vorbis loop.

usage: prepare_sounds.py <source dir> <output dir>

If the Maxim loop changes, set MG_FIRE_INTERVAL in game_config.gd from the
shot spacing this prints.
"""
import subprocess, sys, wave
from pathlib import Path
import numpy as np

SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)


def load(path, channels=1):
    rate = int(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=sample_rate",
                               "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout.strip())
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).copy()
    return (x.reshape(-1, channels) if channels > 1 else x), rate


def save(path, x, rate):
    peak = np.abs(x).max()
    if peak > 0.999:
        x = x * (0.999 / peak)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def trim(x, rate, lead_db=-40.0, tail_db=-55.0, pre=0.002, fade=0.015):
    peak = np.abs(x).max()
    loud = np.nonzero(np.abs(x) > peak * 10 ** (lead_db / 20))[0]
    quiet = np.nonzero(np.abs(x) > peak * 10 ** (tail_db / 20))[0]
    start = max(0, loud[0] - int(pre * rate))
    end = min(len(x), quiet[-1] + int(fade * rate))
    y = x[start:end].copy()
    n = min(int(fade * rate), len(y))
    y[-n:] *= np.linspace(1, 0, n)
    return y


def boom_attacks(x, rate, min_gap=0.07):
    """Shot times from the low boom of each report (one-pole low-pass ~250 Hz)."""
    a = 1 - np.exp(-2 * np.pi * 250 / rate)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    win = int(rate * 0.002)
    m = len(y) // win
    env = np.sqrt((y[: m * win].reshape(m, win) ** 2).mean(axis=1))
    rise = np.diff(env, prepend=0)
    picked = []
    for i in np.argsort(-rise):
        if rise[i] <= rise.max() * 0.2:
            break
        if all(abs(i - p) * win >= min_gap * rate for p in picked):
            picked.append(i)
    return sorted(int(p * win) for p in picked)


def one_shots():
    groups = ["Generic", "Grunt-Pain", "Insert Shell", "Pistol Heavy Shot", "Shotgun Reload", "Whiz"]
    for path in sorted(SRC.iterdir()):
        name = path.stem
        if name.startswith("Shotgun ") and not name.startswith("Shotgun Reload") or any(name.startswith(g + " ") for g in groups):
            x, rate = load(path)
            save(OUT / f"{name}.wav", trim(x, rate), rate)


def maxim():
    x, rate = load(SRC / "Machinegun 4 Loop.WAV")
    # Skip the opening shot (nothing rings under it) and cut just before
    # shots, so both sides of the seam sit at the same point in the rhythm.
    shots = [t for t in boom_attacks(x, rate) if t > 0.05 * rate]
    pre = int(0.006 * rate)
    begin, end = shots[0] - pre, shots[-1] - pre
    fade = int(0.010 * rate)
    loop = x[begin:end].copy()
    w = np.linspace(0, 1, fade)
    # Crossfade the end into what led up to the start, so the wrap is continuous.
    loop[-fade:] = loop[-fade:] * (1 - w) + x[begin - fade:begin] * w
    save(OUT / "Machinegun 4 Loop.wav", loop, rate)
    shots_in_loop = len(shots) - 1
    print(f"maxim loop: {len(loop) / rate * 1000:.1f} ms, {shots_in_loop} shots, "
          f"{len(loop) / rate / shots_in_loop * 1000:.1f} ms a shot")
    e, erate = load(SRC / "Machinegun 4 Loop End.WAV")
    final = boom_attacks(e, erate)[1] - int(0.006 * erate)  # the last of its two shots
    save(OUT / "Machinegun 4 Loop End.wav", trim(e[final:], erate, lead_db=-60), erate)


def wind():
    x, rate = load(SRC / "dragon-studio-howling-wind-and-snow-515984.mp3", channels=2)
    length, fade = int(110 * rate), int(4 * rate)
    # Gentle compression so gusts never drown the game: above -24 dBFS, 2:1.
    mono = x.mean(axis=1)
    win = int(0.05 * rate)
    m = len(mono) // win
    rms = np.sqrt((mono[: m * win].reshape(m, win) ** 2).mean(axis=1) + 1e-12)
    level = 20 * np.log10(rms)
    gain_db = np.where(level > -24, -(level + 24) * 0.5, 0.0)
    gain_db = np.convolve(gain_db, np.ones(20) / 20, mode="same")  # ~1 s smoothing
    gain = np.repeat(10 ** (gain_db / 20), win)
    gain = np.concatenate([gain, np.full(len(mono) - len(gain), gain[-1])])
    x = x * gain[:, None]
    loop = x[:length].copy()
    w = np.sqrt(np.linspace(0, 1, fade))[:, None]  # equal power
    loop[:fade] = x[length:length + fade] * np.sqrt(1 - w ** 2) + x[:fade] * w
    raw = (np.clip(loop, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(rate), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "3", str(OUT / "Howling Wind and Snow.ogg")], input=raw, check=True)


one_shots()
maxim()
wind()
