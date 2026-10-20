"""Synthesizes the pickup / upgrade one-shots in assets/audio/sfx (no dependencies).

    python3 rewild/tools/gen_pickup_sfx.py

garbage_pickup.wav  crumple + soft thud + little pop (a garbage pile cleared)
gear_pickup.wav     ratchet tick + bright metallic chime (a gear collected)
upgrade.wav         rising sparkly arpeggio (a water-gun upgrade bought)
tank_full.wav       water bloop + chime (the water tank is filled up)
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(dst, src, at=0.0, gain=1.0):
    start = int(at * RATE)
    need = start + len(src) - len(dst)
    if need > 0:
        dst.extend([0.0] * need)
    for i, s in enumerate(src):
        dst[start + i] += s * gain
    return dst


def env(n, attack, decay):
    """Linear attack, exponential decay (decay = time constant in seconds)."""
    a = max(int(attack * RATE), 1)
    return [(i / a) if i < a else math.exp(-(i - a) / (decay * RATE)) for i in range(n)]


def tone(freq, seconds, attack=0.004, decay=0.15, partials=((1.0, 1.0),), sweep=0.0):
    n = int(seconds * RATE)
    e = env(n, attack, decay)
    out, phase = [], [0.0] * len(partials)
    for i in range(n):
        f = freq * (1.0 + sweep * i / n)
        s = 0.0
        for k, (ratio, amp) in enumerate(partials):
            phase[k] += 2 * math.pi * f * ratio / RATE
            s += amp * math.sin(phase[k])
        out.append(s * e[i])
    return out


def noise(seconds, attack, decay, lowpass=0.3, highpass=0.0):
    """One-pole filtered white noise (lowpass/highpass are 0..1 coefficients)."""
    n = int(seconds * RATE)
    e = env(n, attack, decay)
    out, lp, hp_prev = [], 0.0, 0.0
    for i in range(n):
        lp += lowpass * (random.uniform(-1, 1) - lp)
        s = lp - highpass * hp_prev
        hp_prev = lp
        out.append(s * e[i])
    return out


def write(name, samples, peak=0.8):
    m = max(abs(s) for s in samples) or 1.0
    fade = int(0.01 * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / m * peak * 32767)) for s in samples))
    print("wrote", os.path.normpath(path), "%.2fs" % (len(samples) / RATE))


def garbage_pickup():
    out = silence(0.45)
    # Plastic/paper crumple: a few short bright noise grains.
    for t in (0.0, 0.035, 0.06, 0.1, 0.13):
        mix(out, noise(0.06, 0.002, 0.018, lowpass=0.6, highpass=0.9), t, random.uniform(0.5, 0.9))
    # Soft body thud underneath.
    mix(out, tone(110, 0.25, 0.003, 0.06, sweep=-0.4), 0.0, 0.9)
    # Little upward "pop" as it vanishes.
    mix(out, tone(520, 0.14, 0.004, 0.05, partials=((1, 1), (2, 0.3)), sweep=0.9), 0.2, 0.45)
    return out


def gear_pickup():
    out = silence(0.9)
    # Ratchet ticks.
    for k, t in enumerate((0.0, 0.03, 0.06)):
        mix(out, noise(0.02, 0.0005, 0.004, lowpass=0.9, highpass=0.95), t, 0.5 + 0.15 * k)
    # Metallic chime: inharmonic partials like a small bell.
    bell = ((1.0, 1.0), (2.76, 0.45), (5.40, 0.22), (8.93, 0.1))
    mix(out, tone(1175, 0.8, 0.002, 0.22, partials=bell), 0.08, 0.8)
    mix(out, tone(1568, 0.7, 0.002, 0.18, partials=bell), 0.16, 0.55)
    return out


def upgrade():
    out = silence(1.2)
    notes = (523.25, 659.25, 783.99, 1046.5)  # C5 E5 G5 C6
    warm = ((1, 1.0), (2, 0.35), (3, 0.15))
    for k, f in enumerate(notes):
        mix(out, tone(f, 0.6, 0.006, 0.18 if k < 3 else 0.4, partials=warm), k * 0.075, 0.7)
    # Shimmer on top of the last note.
    for k in range(6):
        f = 2093.0 * random.choice((1.0, 1.25, 1.5, 2.0))
        mix(out, tone(f, 0.25, 0.003, 0.07), 0.3 + k * 0.05, 0.18)
    return out


def tank_full():
    out = silence(0.7)
    # Water bloop: a fast upward sine sweep with a soft attack.
    mix(out, tone(260, 0.16, 0.01, 0.06, sweep=1.6), 0.0, 0.8)
    mix(out, tone(420, 0.14, 0.01, 0.05, sweep=1.4), 0.07, 0.6)
    # Confirming chime.
    mix(out, tone(1318.5, 0.55, 0.003, 0.16, partials=((1, 1), (2, 0.2))), 0.15, 0.5)
    return out


if __name__ == "__main__":
    random.seed(21)
    write("garbage_pickup.wav", garbage_pickup())
    write("gear_pickup.wav", gear_pickup())
    write("upgrade.wav", upgrade(), peak=0.7)
    write("tank_full.wav", tank_full(), peak=0.7)
