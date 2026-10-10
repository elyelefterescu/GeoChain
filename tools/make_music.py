#!/usr/bin/env python3
"""Compune muzica de fundal a jocului, în întregime din cod (fără mostre, deci fără licențe străine).

Utilizare:
    python3 tools/make_music.py
Scrie music/<nume>.ogg (are nevoie de numpy, scipy și ffmpeg cu libvorbis).
Fiecare piesă e o buclă: coada ecoului de la final e adăugată la început, ca trecerea să nu se audă.
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

ROOT = Path(__file__).resolve().parent.parent
RATE = 44100
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name: str, octave: int) -> float:
    return 440.0 * 2 ** ((NOTES[name] + 12 * (octave + 1) - 69) / 12)


def envelope(n: int, attack: float, release: float) -> np.ndarray:
    env = np.ones(n)
    a, r = min(n, int(attack * RATE)), min(n, int(release * RATE))
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def pad_tone(f: float, n: int, rng) -> np.ndarray:
    """Un ton cald, din câteva armonice ușor dezacordate."""
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for detune in (-0.12, 0.0, 0.12):
        f0 = f * 2 ** (detune / 12)
        phase = rng.uniform(0, 2 * np.pi)
        for h in range(1, 7):
            out += np.sin(2 * np.pi * f0 * h * t + phase * h) / (h ** 1.6)
    return out / 6


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * cutoff / RATE)
    return lfilter([1 - a], [1, -a], x)


def pluck(f: float, n: int, rng, damping=0.996) -> np.ndarray:
    """Coardă ciupită (Karplus-Strong)."""
    period = max(2, int(RATE / f))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = damping * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return lowpass(out, 3500)


def bell(f: float, n: int, decay=1.6) -> np.ndarray:
    t = np.arange(n) / RATE
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 1.8 * np.exp(-t * 3)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * decay) * envelope(n, 0.004, 0.05)


def epiano(f: float, n: int) -> np.ndarray:
    t = np.arange(n) / RATE
    mod = np.sin(2 * np.pi * f * t) * 1.2 * np.exp(-t * 2.5)
    tone = np.sin(2 * np.pi * f * t + mod) + 0.25 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 4)
    return tone * np.exp(-t * 1.1) * envelope(n, 0.006, 0.08)


def bass(f: float, n: int) -> np.ndarray:
    t = np.arange(n) / RATE
    return (np.sin(2 * np.pi * f * t) + 0.2 * np.sin(4 * np.pi * f * t)) * envelope(n, 0.02, 0.25)


def reverb(x: np.ndarray, mix=0.32) -> np.ndarray:
    """Ecou Schroeder: patru filtre pieptene în paralel, apoi două all-pass."""
    wet = np.zeros_like(x)
    for delay_ms, gain in ((29.7, 0.83), (37.1, 0.81), (41.1, 0.79), (43.7, 0.77)):
        d = int(delay_ms * RATE / 1000)
        a = np.zeros(d + 1)
        a[0], a[d] = 1, -gain
        wet += lfilter([1], a, lowpass(x, 5000))
    for delay_ms, gain in ((5.0, 0.7), (1.7, 0.7)):
        d = int(delay_ms * RATE / 1000)
        b = np.zeros(d + 1)
        b[0], b[d] = -gain, 1
        a = np.zeros(d + 1)
        a[0], a[d] = 1, -gain
        wet = lfilter(b, a, wet)
    return x * (1 - mix) + wet * mix / 4


def add(track: np.ndarray, sound: np.ndarray, start: float, gain: float, pan=0.0) -> None:
    i = int(start * RATE)
    sound = sound[: max(0, track.shape[1] - i)]
    left, right = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
    track[0, i:i + len(sound)] += sound * gain * left
    track[1, i:i + len(sound)] += sound * gain * right


def compose(spec: dict, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    beat = 60.0 / spec["bpm"]
    bar = beat * 4
    bars = len(spec["sections"]) * len(spec["chords"]) * spec["bars_per_chord"]
    length = bars * bar
    tail = 4.0
    track = np.zeros((2, int((length + tail) * RATE)))
    scale = spec["scale"]
    melody_note = len(scale) // 2
    pos = 0
    for layers in spec["sections"]:
        for chord in spec["chords"]:
            for _ in range(spec["bars_per_chord"]):
                start = pos * bar
                root, notes = chord
                if "pad" in layers:
                    n = int((bar + 1.2) * RATE)
                    tone = sum(pad_tone(freq(name, octave), n, rng) for name, octave in notes)
                    tone = lowpass(tone, 900) * envelope(n, 0.6, 1.2)
                    add(track, tone, start, 0.16)
                if "bass" in layers:
                    for b in (0, 2):
                        add(track, bass(freq(root, 2), int(beat * 2 * RATE)), start + b * beat, 0.30)
                if "arp" in layers:
                    order = [0, 1, 2, 1, 0, 2, 1, 2]
                    for step in range(8):
                        name, octave = notes[order[step] % len(notes)]
                        f = freq(name, octave + 1)
                        sound = spec["arp_voice"](f, int(beat * 1.5 * RATE), rng)
                        add(track, sound, start + step * beat / 2, 0.11, pan=-0.35 if step % 2 else 0.35)
                if "melody" in layers:
                    for step in range(4):
                        if rng.random() < 0.3:
                            continue
                        melody_note = int(np.clip(melody_note + rng.choice([-2, -1, -1, 1, 1, 2]), 0, len(scale) - 1))
                        name, octave = scale[melody_note]
                        add(track, bell(freq(name, octave), int(beat * 3 * RATE)), start + step * beat, 0.09,
                            pan=rng.uniform(-0.3, 0.3))
                pos += 1
    track = np.stack([reverb(track[0]), reverb(track[1])])
    loop_len = int(length * RATE)
    track[:, : track.shape[1] - loop_len] += track[:, loop_len:]
    track = track[:, :loop_len]
    track *= 0.7 / np.max(np.abs(track))  # cam -3 dB
    return track


TRACKS = {
    "harta": {
        "bpm": 80,
        "bars_per_chord": 2,
        "chords": [
            ("D", [("D", 3), ("F#", 3), ("A", 3)]),
            ("B", [("B", 2), ("D", 3), ("F#", 3)]),
            ("G", [("G", 2), ("B", 2), ("D", 3)]),
            ("A", [("A", 2), ("C#", 3), ("E", 3)]),
        ],
        "scale": [("D", 5), ("E", 5), ("F#", 5), ("A", 5), ("B", 5), ("D", 6), ("E", 6)],
        "arp_voice": lambda f, n, rng: pluck(f, n, rng),
        "sections": [["pad"], ["pad", "bass"], ["pad", "bass", "arp"], ["pad", "bass", "arp", "melody"]],
    },
    "drum": {
        "bpm": 72,
        "bars_per_chord": 2,
        "chords": [
            ("A", [("A", 2), ("C", 3), ("E", 3)]),
            ("F", [("F", 2), ("A", 2), ("C", 3)]),
            ("C", [("C", 3), ("E", 3), ("G", 3)]),
            ("G", [("G", 2), ("B", 2), ("D", 3)]),
        ],
        "scale": [("A", 4), ("C", 5), ("D", 5), ("E", 5), ("G", 5), ("A", 5), ("C", 6)],
        "arp_voice": lambda f, n, rng: epiano(f / 2, n),
        "sections": [["pad", "arp"], ["pad", "bass", "arp"], ["pad", "bass", "arp", "melody"], ["pad", "melody"]],
    },
}


def write_ogg(track: np.ndarray, path: Path) -> None:
    pcm = (np.clip(track.T, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "4",
                        str(path)], check=True)


def main():
    out_dir = ROOT / "music"
    out_dir.mkdir(exist_ok=True)
    for i, (name, spec) in enumerate(TRACKS.items()):
        path = out_dir / f"{name}.ogg"
        write_ogg(compose(spec, seed=10 + i), path)
        print(path, f"{path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
