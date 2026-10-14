"""Face sunetele scurte ale jocului din cod (fără înregistrări, deci fără licențe).

Rulează: python3 tools/make_sounds.py  →  sounds/*.wav
"""
import pathlib
import wave

import numpy as np

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "sounds"


def env(n, attack=0.005, release=0.08):
    """Anvelopă: pornire rapidă, apoi stingere exponențială."""
    t = np.arange(n) / RATE
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / release)


def tone(freq, dur, release=0.08, harmonics=((1, 1.0), (2, 0.25), (3, 0.08))):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    wave_ = sum(amp * np.sin(2 * np.pi * freq * k * t) for k, amp in harmonics)
    return wave_ * env(n, release=release)


def place(buf, sound, at):
    i = int(at * RATE)
    buf[i:i + len(sound)] += sound[: len(buf) - i]


def land():
    """Un „pop” scurt, în două note care urcă."""
    buf = np.zeros(int(0.22 * RATE))
    place(buf, tone(660, 0.12, 0.04), 0)
    place(buf, tone(990, 0.16, 0.05), 0.055)
    return buf


def water():
    """O picătură: un ton care alunecă în sus, ca un „bloop”."""
    dur = 0.32
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    freq = 300 + 900 * (t / dur) ** 0.6
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    bloop = np.sin(phase) * env(n, 0.004, 0.09)
    drip = tone(1500, 0.08, 0.025, ((1, 1.0),)) * 0.35
    buf = np.zeros(int(0.4 * RATE))
    place(buf, bloop, 0)
    place(buf, drip, 0.12)
    return buf


def mistake():
    """Două note joase care coboară, ușor aspre."""
    harsh = ((1, 1.0), (2, 0.5), (3, 0.35), (4, 0.2), (5, 0.12))
    buf = np.zeros(int(0.45 * RATE))
    place(buf, tone(311, 0.2, 0.09, harsh), 0)
    place(buf, tone(233, 0.28, 0.12, harsh), 0.14)
    return buf


def finish():
    """Arpegiu vesel Do–Mi–Sol–Do, cu ultima notă lungă și un acord dedesubt."""
    bell = ((1, 1.0), (2, 0.4), (3, 0.15), (4.2, 0.06))
    notes = [523.25, 659.25, 783.99, 1046.5]
    buf = np.zeros(int(1.6 * RATE))
    for i, f in enumerate(notes):
        place(buf, tone(f, 0.5, 0.18, bell), i * 0.11)
    for f in (523.25, 659.25, 783.99):
        place(buf, tone(f, 1.2, 0.45, bell) * 0.35, 0.44)
    place(buf, tone(1046.5, 1.2, 0.5, bell) * 0.8, 0.44)
    return buf


def save(name, samples, volume=0.6):
    samples = samples / np.max(np.abs(samples)) * volume
    fade = min(len(samples), int(0.01 * RATE))
    samples[-fade:] *= np.linspace(1, 0, fade)
    data = (samples * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    save("land", land(), 0.45)
    save("water", water(), 0.5)
    save("mistake", mistake(), 0.5)
    save("finish", finish(), 0.6)
