#!/usr/bin/env python3
"""Compune muzica de fundal a jocului, în întregime din cod (fără mostre, deci fără licențe străine).

Stilul: pian ritmat peste tobe electronice (cam ca în jocurile de tip Dancing Line), 118–124 BPM.
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


def freq(note: str) -> float:
    """„A4” → 440 Hz."""
    name, octave = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((NOTES[name] + 12 * (octave + 1) - 69) / 12)


def times(n: int) -> np.ndarray:
    return np.arange(n) / RATE


def envelope(n: int, attack: float, release: float) -> np.ndarray:
    env = np.ones(n)
    a, r = min(n, int(attack * RATE)), min(n, int(release * RATE))
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * cutoff / RATE)
    return lfilter([1 - a], [1, -a], x)


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass(x, cutoff)


# --- Instrumente -----------------------------------------------------------------------------

def piano(f: float, length: float) -> np.ndarray:
    """Pian simplu: armonice care se sting cu atât mai repede cu cât sunt mai sus."""
    n = int(length * RATE)
    t = times(n)
    out = np.zeros(n)
    for h in range(1, 11):
        fh = f * h * (1 + 0.0004 * h * h)
        if fh > RATE / 2.2:
            break
        out += np.sin(2 * np.pi * fh * t) / h ** 1.3 * np.exp(-t * (1.0 + 0.6 * h))
    return out * envelope(n, 0.003, 0.04)


def pad(notes: list, length: float, rng) -> np.ndarray:
    n = int(length * RATE)
    t = times(n)
    out = np.zeros(n)
    for note in notes:
        for detune in (-0.1, 0.1):
            f0 = freq(note) * 2 ** (detune / 12)
            phase = rng.uniform(0, 2 * np.pi)
            for h in range(1, 6):
                out += np.sin(2 * np.pi * f0 * h * t + phase * h) / h ** 1.5
    return lowpass(out, 1400) * envelope(n, 0.05, 0.3) / 8


def bass(f: float, length: float) -> np.ndarray:
    n = int(length * RATE)
    t = times(n)
    saw = sum(np.sin(2 * np.pi * f * h * t) / h for h in range(1, 8))
    return lowpass(saw, 600) * np.exp(-t * 4) * envelope(n, 0.004, 0.03)


def kick() -> np.ndarray:
    n = int(0.35 * RATE)
    t = times(n)
    f = 45 + 110 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 9)


def hat(rng, open_=False) -> np.ndarray:
    n = int((0.18 if open_ else 0.05) * RATE)
    t = times(n)
    return highpass(rng.uniform(-1, 1, n), 7000) * np.exp(-t * (18 if open_ else 70))


def clap(rng) -> np.ndarray:
    n = int(0.25 * RATE)
    t = times(n)
    noise = highpass(lowpass(rng.uniform(-1, 1, n), 2500), 900)
    bursts = sum(np.exp(-np.maximum(0, t - d) * 60) * (t >= d) for d in (0.0, 0.01, 0.02))
    return noise * bursts * np.exp(-t * 12)


def reverb(x: np.ndarray, mix=0.3) -> np.ndarray:
    """Ecou Schroeder: patru filtre pieptene în paralel, apoi două all-pass."""
    wet = np.zeros_like(x)
    for delay_ms, gain in ((29.7, 0.82), (37.1, 0.8), (41.1, 0.78), (43.7, 0.76)):
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


# --- Compoziție ------------------------------------------------------------------------------

class Bus:
    """O pistă stereo pe care se adună sunete."""

    def __init__(self, seconds: float):
        self.data = np.zeros((2, int(seconds * RATE)))

    def add(self, sound: np.ndarray, start: float, gain: float, pan=0.0) -> None:
        i = int(start * RATE)
        sound = sound[: max(0, self.data.shape[1] - i)]
        self.data[0, i:i + len(sound)] += sound * gain * np.sqrt(0.5 * (1 - pan))
        self.data[1, i:i + len(sound)] += sound * gain * np.sqrt(0.5 * (1 + pan))


def compose(spec: dict, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    beat = 60.0 / spec["bpm"]
    bar = beat * 4
    sixteenth = beat / 4
    chords = spec["chords"]
    blocks = spec["sections"]
    bars = len(blocks) * 8
    length = bars * bar
    tail = 3.0
    dry = Bus(length + tail)    # tobe
    pumped = Bus(length + tail)  # bas și pad, care „respiră” pe ritmul tobei mari
    wet = Bus(length + tail)    # pian și melodie, cu ecou
    kick_sound, kick_gain = kick(), 0.9
    for index in range(bars):
        layers = blocks[index // 8]
        start = index * bar
        root, tones = chords[index % len(chords)]
        if "arp" in layers or "arp_soft" in layers:
            gain = 0.16 if "arp" in layers else 0.10
            for step, tone in enumerate(spec["arp"]):
                accent = 1.0 if step % 4 == 0 else 0.75
                wet.add(piano(freq(tones[tone]), 0.6), start + step * sixteenth, gain * accent,
                        pan=-0.25 if step % 2 else 0.25)
        if "lead" in layers:
            line = spec["melody"][index % len(spec["melody"])]
            for step, note in enumerate(line):
                if note != ".":
                    wet.add(piano(freq(note), 1.2), start + step * beat / 2, 0.30, pan=0.05)
                    wet.add(piano(freq(note) / 2, 1.2), start + step * beat / 2, 0.10)
        if "pad" in layers:
            pumped.add(pad(tones[:3], bar + 0.2, rng), start, 0.5)
        if "bass" in layers:
            for b in range(4):
                pumped.add(bass(freq(root + "2"), beat / 2), start + b * beat + beat / 2, 0.42)
        if "kick" in layers:
            for b in range(4):
                dry.add(kick_sound, start + b * beat, kick_gain)
        if "hats" in layers:
            for b in range(4):
                dry.add(hat(rng, open_=True), start + b * beat + beat / 2, 0.10, pan=0.3)
                dry.add(hat(rng), start + b * beat + beat / 4 * 3, 0.06, pan=-0.3)
        if "clap" in layers:
            for b in (1, 3):
                dry.add(clap(rng), start + b * beat, 0.32)
        if "fill" in layers and index % 8 == 7:
            for s in range(8):
                dry.add(clap(rng), start + 2 * beat + s * sixteenth, 0.08 + s * 0.02)

    # Pompare: bas și pad scad scurt la fiecare bătaie, ca în muzica electronică.
    t = times(pumped.data.shape[1])
    pump = 1 - 0.65 * np.exp(-((t % beat) / beat) * 7)
    mix = dry.data + pumped.data * pump
    mix += np.stack([reverb(wet.data[0]), reverb(wet.data[1])])
    loop_len = int(length * RATE)
    mix[:, : mix.shape[1] - loop_len] += mix[:, loop_len:]
    mix = mix[:, :loop_len]
    mix = np.tanh(mix * 1.2 / np.max(np.abs(mix))) / np.tanh(1.2)  # puțină saturație, ca să sune plin
    return mix * 0.8


INTRO, BUILD, DROP, BREAK, OUTRO = (
    ["arp"],
    ["arp", "hats", "bass", "fill"],
    ["arp", "kick", "hats", "clap", "bass", "pad", "lead"],
    ["arp_soft", "pad", "lead"],
    ["arp", "kick", "hats"],
)

TRACKS = {
    "ritm": {
        "bpm": 124,
        "chords": [
            ("A", ["A4", "C5", "E5", "A5"]),
            ("F", ["F4", "A4", "C5", "F5"]),
            ("C", ["C4", "E4", "G4", "C5"]),
            ("G", ["G4", "B4", "D5", "G5"]),
        ],
        "arp": [0, 2, 3, 2, 1, 2, 3, 2, 0, 2, 3, 2, 1, 2, 3, 2],
        "melody": [
            "E5 . E5 D5 C5 . D5 E5".split(),
            ". A4 C5 . F5 E5 C5 .".split(),
            "G5 . E5 . D5 C5 D5 E5".split(),
            "D5 . B4 . G4 . D5 .".split(),
            "E5 . E5 G5 A5 . G5 E5".split(),
            "F5 . E5 . C5 . A4 C5".split(),
            "E5 . D5 C5 G5 . E5 .".split(),
            "D5 . . B4 D5 . G5 .".split(),
        ],
        "sections": [INTRO, BUILD, DROP, DROP, BREAK, BUILD, DROP, OUTRO],
    },
    "zbor": {
        "bpm": 118,
        "chords": [
            ("E", ["E4", "G4", "B4", "E5"]),
            ("C", ["C4", "E4", "G4", "C5"]),
            ("G", ["G4", "B4", "D5", "G5"]),
            ("D", ["D4", "F#4", "A4", "D5"]),
        ],
        "arp": [0, 1, 2, 1, 3, 1, 2, 1, 0, 1, 2, 1, 3, 2, 1, 2],
        "melody": [
            "B4 . E5 . G5 . F#5 E5".split(),
            ". G5 . E5 C5 . E5 .".split(),
            "D5 . G5 . B5 . A5 G5".split(),
            "F#5 . A5 . D5 . F#5 .".split(),
            "G5 . F#5 E5 B4 . E5 G5".split(),
            "A5 . G5 . E5 . C5 E5".split(),
            "D5 . B4 . D5 G5 . B5".split(),
            "A5 . F#5 . D5 . . .".split(),
        ],
        "sections": [INTRO, BUILD, DROP, BREAK, DROP, DROP, BUILD, OUTRO],
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
