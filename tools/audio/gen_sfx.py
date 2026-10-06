#!/usr/bin/env python3
"""Synthesizes the SFX that have no recorded (Kenney CC0) take: fountain splash, guard whistle,
jackpot, big win, loss sting, slips, the waiter's tray crash, megaphone, last-call bell, cash
register, hot-table shimmer, lounge chime and the spring boing. Writes 16-bit mono WAVs into
audio/sfx/ (they replace the old sfxr-style placeholders from tools/gen_audio.py).

    python3 tools/audio/gen_sfx.py            # all
    python3 tools/audio/gen_sfx.py splash     # some

Needs numpy; ffmpeg to mix in the recorded Kenney coin clinks (CC0, audio/sfx/coin-v*.ogg).
Deterministic. Sound direction (docs/ART_DIRECTION.md): warm lounge casino, comedic, never harsh:
everything is band-limited below ~9 kHz and peaks at -3 dBFS; call sites set the final level.
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402
from synth import SR, secs, band, noise, osc_phase, adsr, midi_hz  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "audio", "sfx")


def finish(x, peak_db=-3.0, hi=9000):
    """Mono, band-limited, click-free, peak-normalised."""
    if x.ndim == 2:
        x = x.mean(axis=0)
    x = band(x, 40, hi)
    x = S.fade(x, 0.002, 0.04)
    return x * (S.db(peak_db) / (np.max(np.abs(x)) + 1e-12))


def buffer(seconds):
    return np.zeros(int(seconds * SR))


def put(buf, x, at, gain=1.0):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[: j - i] * gain


def kenney(name):
    """A recorded CC0 take as float mono (empty if ffmpeg/the file is missing)."""
    path = os.path.join(OUT, name)
    try:
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return np.zeros(1)
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0


def coins(buf, rng, start, count, spread, gain=0.5):
    """A shower of recorded coin clinks, pitch-varied by resampling."""
    takes = [kenney("coin-v%d.ogg" % i) for i in range(1, 7)]
    for _ in range(count):
        c = takes[int(rng.integers(0, len(takes)))]
        rate = float(rng.uniform(0.85, 1.25))
        idx = np.arange(0, len(c) - 1, rate)
        c = np.interp(idx, np.arange(len(c)), c)
        put(buf, c, start + float(rng.uniform(0, spread)), gain * float(rng.uniform(0.5, 1.0)))


# --- Recipes -------------------------------------------------------------------------------------

def splash():
    """Body into the fountain: a heavy slap, a rush of water, bubbles and falling droplets."""
    rng = np.random.default_rng(5)
    buf = buffer(1.6)
    n = len(buf)
    t = secs(n)
    slap = band(noise(int(0.25 * SR), rng), 200, 2500) * np.exp(-secs(int(0.25 * SR)) * 18)
    put(buf, slap, 0.0, 1.0)
    rush = band(noise(n, rng), 600, 6000) * np.exp(-t * 4.0) * (1 - np.exp(-t * 60))
    buf += 0.45 * rush
    for _ in range(70):  # bubbles: short rising sine chirps
        at = float(rng.uniform(0.02, 0.9)) ** 1.6
        tau = float(rng.uniform(0.015, 0.06))
        f0 = float(rng.uniform(350, 1400))
        m = int(tau * 6 * SR)
        tt = secs(m)
        b = np.sin(osc_phase(f0 * (1 + 2.5 * tt / (tau * 6)), m)) * np.exp(-tt / tau)
        put(buf, b, at, float(rng.uniform(0.08, 0.25)))
    for _ in range(18):  # droplets landing back
        at = float(rng.uniform(0.35, 1.3))
        m = int(0.05 * SR)
        tt = secs(m)
        f0 = float(rng.uniform(900, 2200))
        d = np.sin(osc_phase(f0 * (1 + 1.5 * tt / 0.05), m)) * np.exp(-tt * 70)
        put(buf, d, at, float(rng.uniform(0.05, 0.15)))
    return finish(S.reverb(buf, 0.18, 0.8))


def whistle():
    """Referee pea whistle: a short and a long blast (tweet, tweeeet) with the pea's warble."""
    rng = np.random.default_rng(6)
    buf = buffer(0.95)
    for at, dur in [(0.0, 0.16), (0.26, 0.55)]:
        n = int(dur * SR)
        t = secs(n)
        warble = 1.0 + 0.035 * np.sin(2 * np.pi * 38 * t) + 0.01 * rng.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1))
        f = 2650 * warble * (1 + 0.03 * (1 - np.exp(-t * 30)))
        ph = osc_phase(f, n)
        am = 0.75 + 0.25 * np.sin(2 * np.pi * 38 * t + 1.0)
        tone = (np.sin(ph) + 0.12 * np.sin(2 * ph)) * am
        breath = band(noise(n, rng), 1800, 5000) * 0.18
        env = adsr(n, a=0.012, r=0.05)
        put(buf, (tone + breath) * env, at)
    return finish(S.reverb(buf, 0.12, 0.7), peak_db=-6.0, hi=7000)


def jackpot():
    """Jackpot: bells ringing up a major arpeggio twice, a coin shower and a held bright chord."""
    rng = np.random.default_rng(7)
    buf = buffer(3.2)
    notes = [72, 76, 79, 84, 76, 79, 84, 88]
    for i, m in enumerate(notes):
        put(buf, S.bell(midi_hz(m), 1.6, 0.8), i * 0.09, 0.9)
        put(buf, S.vibes(m - 12, 0.3, 0.7), i * 0.09, 0.5)
    for m in [72, 76, 79, 84]:
        put(buf, S.vibes(m, 1.6, 0.8), 0.78, 0.55)
        put(buf, S.bell(midi_hz(m + 12), 2.0, 0.5, bright=0.6), 0.78, 0.35)
    coins(buf, rng, 0.15, 26, 1.6, 0.35)
    return finish(S.reverb(buf, 0.22, 1.4))


def big_win():
    """Big win: a quick bright vibes run, bells, and a handful of coins."""
    rng = np.random.default_rng(8)
    buf = buffer(1.9)
    for i, m in enumerate([67, 72, 76, 79]):
        put(buf, S.vibes(m, 0.25 if i < 3 else 1.0, 0.85), i * 0.065, 0.8)
    put(buf, S.bell(midi_hz(84), 1.4, 0.7), 0.2, 0.7)
    put(buf, S.bell(midi_hz(91), 1.2, 0.5), 0.26, 0.4)
    coins(buf, rng, 0.05, 9, 0.6, 0.45)
    return finish(S.reverb(buf, 0.2, 1.2))


def trumpet(m, dur, wah, vibrato=0.0):
    """Plunger-muted trumpet by additive synthesis: harmonic k gets 1/k and a time-varying low-pass
    `wah(t)` (Hz), so the mute opening and closing shapes the tone without a filter."""
    n = int(dur * SR)
    t = secs(n)
    f = midi_hz(m) * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.3, 0, 1))
    ph = osc_phase(f, n)
    fc = wah(t)
    y = np.zeros(n)
    for k in range(1, 16):
        if midi_hz(m) * k > 7000:
            break
        y += (1.0 / k) * np.sin(k * ph) / (1 + (k * midi_hz(m) / fc) ** 4)
    return y * adsr(n, a=0.03, r=0.12)


def loss_sting():
    """Sad casino sting: muted trumpet "wah wah wah waaah", descending, the last note wobbling."""
    buf = buffer(2.1)
    for i, m in enumerate([67, 66, 65]):
        put(buf, trumpet(m - 5, 0.36, lambda t: 500 + 1400 * np.sin(np.pi * np.clip(t / 0.36, 0, 1))), i * 0.38, 0.8)
    put(buf, trumpet(59, 1.0, lambda t: 500 + 900 * (0.5 + 0.5 * np.sin(2 * np.pi * 3.0 * t)), vibrato=0.012), 1.14, 0.85)
    return finish(S.reverb(buf, 0.18, 1.0), hi=6000)


def slip():
    """Cartoon slip: a slide-whistle zip up and a squeaky skid."""
    rng = np.random.default_rng(9)
    buf = buffer(0.7)
    n = int(0.32 * SR)
    t = secs(n)
    f = 450 * 2 ** (2.2 * (t / 0.32) ** 0.8) * (1 + 0.02 * np.sin(2 * np.pi * 11 * t))
    zip_ = np.sin(osc_phase(f, n)) * adsr(n, a=0.01, r=0.06)
    put(buf, zip_, 0.0, 0.7)
    m = int(0.25 * SR)
    tt = secs(m)
    squeak = np.sin(osc_phase(1500 + 300 * np.sin(2 * np.pi * 30 * tt), m)) * np.exp(-tt * 9) * 0.25
    whoosh = band(noise(m, rng), 500, 3000) * np.sin(np.pi * tt / 0.25) * 0.3
    put(buf, squeak + whoosh, 0.05)
    return finish(buf, peak_db=-4.0)


def tray_crash():
    """The waiter goes down: a metal tray clattering on the floor, glasses shattering, a splash."""
    rng = np.random.default_rng(10)
    buf = buffer(2.0)
    # Tray: inharmonic plate modes, bouncing faster and quieter.
    at, gain = 0.05, 1.0
    for _ in range(6):
        n = int(0.9 * SR)
        t = secs(n)
        y = np.zeros(n)
        for fr, d in [(310, 5), (742, 7), (1290, 9), (1893, 11), (2660, 14), (3470, 18)]:
            y += np.sin(osc_phase(fr * float(rng.uniform(0.98, 1.02)), n)) * np.exp(-t * d) / (1 + fr / 1500)
        y += band(noise(n, rng), 800, 5000) * np.exp(-t * 60) * 0.6
        put(buf, y, at, gain * 0.6)
        at += 0.16 * gain + 0.03
        gain *= 0.6
    # Glass: many short high pings with crackle.
    for _ in range(45):
        a = 0.08 + float(rng.uniform(0, 0.5)) ** 1.5
        n = int(0.12 * SR)
        t = secs(n)
        f0 = float(rng.uniform(2500, 6500))
        g = np.sin(osc_phase(f0, n)) * np.exp(-t * float(rng.uniform(25, 60)))
        g += 0.5 * np.sin(osc_phase(f0 * 1.51, n)) * np.exp(-t * 70)
        put(buf, g, a, float(rng.uniform(0.04, 0.14)))
    crack = band(noise(int(0.3 * SR), rng), 2000, 8000) * np.exp(-secs(int(0.3 * SR)) * 14)
    put(buf, crack, 0.07, 0.35)
    # Drinks hitting the floor.
    n = int(0.6 * SR)
    t = secs(n)
    put(buf, band(noise(n, rng), 300, 3000) * np.exp(-t * 7) * (1 - np.exp(-t * 80)), 0.1, 0.35)
    return finish(S.reverb(buf, 0.2, 1.0))


def megaphone():
    """Picking up the megaphone: a switch click and a short bullhorn "bee-boop" chirp."""
    rng = np.random.default_rng(11)
    buf = buffer(0.75)
    put(buf, band(noise(int(0.01 * SR), rng), 1000, 6000), 0.0, 0.6)
    for at, m, dur in [(0.06, 79, 0.14), (0.22, 84, 0.22)]:
        n = int(dur * SR)
        ph = osc_phase(midi_hz(m), n)
        y = np.tanh(3.0 * (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)))
        y = band(y, 450, 3200) * adsr(n, a=0.01, r=0.04)
        put(buf, y, at, 0.5)
    return finish(S.reverb(buf, 0.15, 0.6), peak_db=-5.0)


def last_call_bell():
    """The bartender's brass bell, rung three times: last call."""
    buf = buffer(2.6)
    for i in range(3):
        put(buf, S.bell(1180.0, 1.8, 0.9, bright=0.8), i * 0.32, 1.0 if i < 2 else 1.15)
    return finish(S.reverb(buf, 0.25, 1.4))


def cash_register():
    """Cha-ching: drawer slam then the register bell, a few coins."""
    rng = np.random.default_rng(12)
    buf = buffer(1.3)
    n = int(0.12 * SR)
    t = secs(n)
    clack = band(noise(n, rng), 300, 4000) * np.exp(-t * 45) + 0.6 * np.sin(osc_phase(140, n)) * np.exp(-t * 35)
    put(buf, clack, 0.0, 0.9)
    put(buf, S.bell(2093.0, 1.1, 0.9, bright=1.0), 0.11, 0.9)
    coins(buf, rng, 0.14, 4, 0.25, 0.35)
    return finish(S.reverb(buf, 0.15, 0.9))


def hot_table():
    """A table heats up: a swelling shimmer under a rising vibes arpeggio."""
    rng = np.random.default_rng(13)
    buf = buffer(2.0)
    n = int(1.1 * SR)
    t = secs(n)
    swell = band(noise(n, rng), 2500, 8000) * (t / 1.1) ** 2.5 * 0.4
    put(buf, swell, 0.0)
    for i, m in enumerate([65, 69, 72, 76, 79, 84]):
        put(buf, S.vibes(m, 0.3 if i < 5 else 0.9, 0.8), 0.45 + i * 0.075, 0.8)
    put(buf, S.bell(midi_hz(96), 1.0, 0.4, bright=0.5), 0.84, 0.3)
    return finish(S.reverb(buf, 0.22, 1.2))


def chime():
    """Lounge chime: a soft vibes Fmaj9 roll (doors open, quiz start, back to the tables)."""
    buf = buffer(2.2)
    for i, m in enumerate([65, 69, 72, 76, 79]):
        put(buf, S.vibes(m, 1.2, 0.7), i * 0.07, 0.7)
    return finish(S.reverb(buf, 0.25, 1.4))


def boing():
    """Cartoon spring: a wobbling pitch that settles."""
    n = int(0.6 * SR)
    t = secs(n)
    f = 180 * (1 + 0.55 * np.exp(-t * 7) * np.sin(2 * np.pi * 14 * t)) * (1 + 0.6 * np.exp(-t * 20))
    ph = osc_phase(f, n)
    y = (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * np.exp(-t * 5) * adsr(n, a=0.004, r=0.08)
    return finish(y, peak_db=-4.0)


RECIPES = {
    "splash": splash, "whistle": whistle, "jackpot_siren": jackpot, "big_win": big_win,
    "loss_sting": loss_sting, "slip": slip, "tray_crash": tray_crash, "megaphone": megaphone,
    "last_call_bell": last_call_bell, "cash_register": cash_register, "hot_table": hot_table,
    "chime": chime, "boing": boing,
}

if __name__ == "__main__":
    for name in (sys.argv[1:] or list(RECIPES)):
        x = RECIPES[name]()
        S.write_wav(os.path.join(OUT, name + ".wav"), x)
        print("%-15s %s" % (name, S.stats(x)))
