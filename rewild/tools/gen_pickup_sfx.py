"""Synthesizes the pickup / upgrade one-shots in assets/audio/sfx (no dependencies).

    python3 rewild/tools/gen_pickup_sfx.py

garbage_pickup.wav  crumple + soft thud + little pop (a garbage pile cleared)
gear_pickup.wav     ratchet tick + bright metallic chime (a gear collected)
upgrade.wav         rising sparkly arpeggio (a water-gun upgrade bought)
tank_full.wav       water bloop + chime (the water tank is filled up)
well_start.wav      water gurgling up the shaft (a well is started)
water_rush.wav      pump clunk + rushing water swelling in (the pump turns the river on)
type_blip_1..3.wav  soft little blips, one per few letters while dialogue types out
prop_grab.wav       soft pluck (a throwable prop picked up)
throw_whoosh.wav    airy whoosh (a prop thrown)
prop_land.wav       dull thud (a thrown prop hits the ground)
prop_splash.wav     splash + bubbles (a thrown prop lands in water)
plant_pop.wav       soft cartoon pop (a petal / flower grows in)
leaf_rustle.wav     swelling rustle of leaves (a tree's leaves grow out)
jump.wav            springy little hop with a puff of air (LIRA jumps)
wind_loop.wav       seamless gusty wind (looped while the sand storm / fog blows)
bird_chirp_1..3.wav distant bird calls (the occasional ambient chirp once the air is clear)
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


def write(name, samples, peak=0.8, loop=False):
    m = max(abs(s) for s in samples) or 1.0
    fade = 0 if loop else int(0.01 * RATE)  # a loop's end must run straight into its start
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


def bubble(freq, at_gain=1.0):
    return [s * at_gain for s in tone(freq, 0.09, 0.003, 0.025, sweep=0.9)]


def well_start():
    out = silence(2.4)
    # Water rising up the shaft: a low rumble swell and bubbles climbing in pitch.
    rush = noise(2.3, 0.9, 0.7, lowpass=0.05)
    mix(out, rush, 0.05, 2.2)
    for k in range(26):
        t = 0.1 + k * 0.075 + random.uniform(-0.02, 0.02)
        mix(out, bubble(240 + k * 22 + random.uniform(-40, 40)), max(t, 0.0), random.uniform(0.15, 0.35))
    # A last bright bloop as the water reaches the top.
    mix(out, tone(520, 0.2, 0.01, 0.06, sweep=1.2), 2.0, 0.4)
    return out


def water_rush():
    out = silence(3.6)
    # Pump valve clunk.
    mix(out, tone(70, 0.35, 0.003, 0.09, sweep=-0.25), 0.0, 1.0)
    mix(out, noise(0.2, 0.002, 0.04, lowpass=0.2), 0.0, 1.2)
    # Water pushing through: a long swell of low and mid noise.
    mix(out, noise(3.3, 1.0, 0.9, lowpass=0.04), 0.2, 2.6)
    mix(out, noise(3.0, 1.3, 0.7, lowpass=0.25, highpass=0.6), 0.5, 0.6)
    for k in range(18):
        mix(out, bubble(random.uniform(200, 520)), 0.4 + k * 0.15 + random.uniform(0, 0.08), random.uniform(0.1, 0.25))
    return out


def type_blip(freq):
    out = tone(freq, 0.05, 0.002, 0.012, partials=((1, 1), (2, 0.15)), sweep=0.08)
    return out + silence(0.01)


def prop_grab():
    out = silence(0.2)
    mix(out, tone(330, 0.15, 0.003, 0.04, partials=((1, 1), (2, 0.25)), sweep=0.5), 0.0, 0.8)
    mix(out, noise(0.03, 0.001, 0.008, lowpass=0.5, highpass=0.8), 0.0, 0.4)
    return out


def throw_whoosh():
    n = int(0.45 * RATE)
    out, lp, hp_prev = [], 0.0, 0.0
    for i in range(n):
        t = i / n
        coef = 0.08 + 0.5 * math.sin(math.pi * t) ** 2  # brightens through the middle
        lp += coef * (random.uniform(-1, 1) - lp)
        s = lp - 0.85 * hp_prev
        hp_prev = lp
        out.append(s * math.sin(math.pi * t) ** 1.5)
    return out


def prop_land():
    out = silence(0.4)
    mix(out, tone(95, 0.3, 0.002, 0.06, sweep=-0.35), 0.0, 1.0)
    mix(out, noise(0.15, 0.001, 0.03, lowpass=0.25), 0.0, 0.9)
    mix(out, noise(0.05, 0.001, 0.01, lowpass=0.6, highpass=0.8), 0.12, 0.25)  # little bounce
    return out


def prop_splash():
    out = silence(0.9)
    mix(out, tone(180, 0.2, 0.002, 0.05, sweep=-0.4), 0.0, 0.6)
    mix(out, noise(0.5, 0.004, 0.12, lowpass=0.5, highpass=0.4), 0.0, 1.0)
    for k in range(7):
        mix(out, bubble(random.uniform(350, 700)), 0.15 + k * 0.07 + random.uniform(0, 0.04), random.uniform(0.15, 0.35))
    return out


def plant_pop():
    out = silence(0.18)
    mix(out, tone(380, 0.12, 0.002, 0.03, partials=((1, 1), (2, 0.2)), sweep=1.4), 0.0, 0.9)
    mix(out, noise(0.015, 0.0005, 0.004, lowpass=0.7, highpass=0.6), 0.0, 0.35)
    return out


def leaf_rustle():
    out = silence(1.6)
    # A soft airy bed under many tiny leaf clicks, swelling in and settling.
    mix(out, noise(1.5, 0.5, 0.35, lowpass=0.35, highpass=0.8), 0.0, 0.5)
    for _ in range(140):
        t = random.betavariate(2.0, 3.0) * 1.4
        mix(out, noise(0.012, 0.0005, 0.003, lowpass=random.uniform(0.4, 0.8), highpass=0.9), t,
            random.uniform(0.2, 0.6) * math.sin(math.pi * t / 1.4))
    return out


def jump():
    out = silence(0.3)
    mix(out, tone(220, 0.2, 0.004, 0.06, partials=((1, 1), (2, 0.3), (3, 0.1)), sweep=1.1), 0.0, 0.8)
    mix(out, noise(0.12, 0.004, 0.035, lowpass=0.35, highpass=0.7), 0.0, 0.5)
    return out


def wind_loop(seconds=8.0):
    """Gusty wind: noise through a lowpass whose cutoff and level drift with slow gusts.
    The tail is crossfaded over the head so it loops without a seam."""
    fade = int(1.0 * RATE)
    n = int(seconds * RATE) + fade
    gusts = [(random.uniform(0.08, 0.25), random.uniform(0, 2 * math.pi)) for _ in range(3)]
    out, lp, lp2 = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        g = sum(math.sin(2 * math.pi * f * t + ph) for f, ph in gusts) / 3.0  # -1..1
        coef = 0.012 + 0.02 * (g + 1.0)
        lp += coef * (random.uniform(-1, 1) - lp)
        lp2 += coef * (lp - lp2)
        out.append(lp2 * (0.55 + 0.45 * g))
    body = out[:n - fade]
    for i in range(fade):
        a = i / fade
        body[i] = body[i] * a + out[n - fade + i] * (1.0 - a)
    return body


def chirp(f0, f1, seconds, vibrato=0.0):
    n = int(seconds * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t + vibrato * math.sin(2 * math.pi * 40 * i / RATE)
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * math.sin(math.pi * t) ** 2)
    return out


def bird_chirp(kind):
    out = silence(1.2)
    if kind == 1:  # two falling whistles
        mix(out, chirp(4200, 3100, 0.12), 0.0)
        mix(out, chirp(4000, 2900, 0.14), 0.22, 0.8)
    elif kind == 2:  # quick trill
        for k in range(6):
            mix(out, chirp(3600, 4300, 0.045), k * 0.065, 0.6 + 0.08 * k)
    else:  # rising call then a short note
        mix(out, chirp(2600, 3800, 0.25, vibrato=120), 0.0)
        mix(out, chirp(3900, 3500, 0.08), 0.35, 0.7)
    return out


if __name__ == "__main__":
    random.seed(21)
    write("garbage_pickup.wav", garbage_pickup())
    write("gear_pickup.wav", gear_pickup())
    write("upgrade.wav", upgrade(), peak=0.7)
    write("tank_full.wav", tank_full(), peak=0.7)
    write("well_start.wav", well_start(), peak=0.75)
    write("water_rush.wav", water_rush(), peak=0.75)
    for k, f in enumerate((587.0, 659.0, 740.0)):
        write("type_blip_%d.wav" % (k + 1), type_blip(f), peak=0.5)
    write("prop_grab.wav", prop_grab(), peak=0.6)
    write("throw_whoosh.wav", throw_whoosh(), peak=0.6)
    write("prop_land.wav", prop_land(), peak=0.75)
    write("prop_splash.wav", prop_splash(), peak=0.7)
    write("plant_pop.wav", plant_pop(), peak=0.55)
    write("leaf_rustle.wav", leaf_rustle(), peak=0.6)
    write("jump.wav", jump(), peak=0.55)
    write("wind_loop.wav", wind_loop(), peak=0.6, loop=True)
    for k in (1, 2, 3):
        write("bird_chirp_%d.wav" % k, bird_chirp(k), peak=0.5)
