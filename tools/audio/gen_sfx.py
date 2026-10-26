#!/usr/bin/env python3
"""Synthesizes the SFX that have no recorded (Kenney CC0) take: fountain splash, guard whistle,
jackpot, big win, loss sting, slips, the waiter's tray crash, megaphone, last-call bell, cash
register, hot-table shimmer, lounge chime, the spring boing, the scratch-card rasp and a cue for
every emote (`emote_<id>`, timed to its choreography). Writes 16-bit mono WAVs into
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


def scratch():
    """A coin dragged over scratch-card foil: a short dry rasp of grainy, papery noise (played per
    stroke with a varied pitch, so a long scratch is many of them)."""
    rng = np.random.default_rng(21)
    n = int(0.16 * SR)
    t = secs(n)
    rasp = band(noise(n, rng), 1800, 7500)
    grains = np.repeat(rng.uniform(0.25, 1.0, n // 220 + 1), 220)[:n]  # the foil catching the coin edge
    body = band(noise(n, rng), 500, 1800) * 0.35
    env = (1 - np.exp(-t * 300)) * np.exp(-t * 9) * adsr(n, a=0.004, r=0.03)
    return finish((rasp * grains + body) * env, peak_db=-6.0)


def stone_grind():
    """The Sword Tapper heave: a blade grinding in its stone, a low gritty scrape with stone
    crumbs ticking off it, swelling and fading (the thud of a stuck sword is the recorded thud)."""
    rng = np.random.default_rng(23)
    n = int(0.75 * SR)
    t = secs(n)
    grit = np.repeat(rng.uniform(0.2, 1.0, n // 300 + 1), 300)[:n]  # the blade catching the rock
    scrape = band(noise(n, rng), 140, 1400) * grit
    rumble = band(noise(n, rng), 50, 220) * 0.8
    wobble = 1.0 + 0.35 * np.sin(2 * np.pi * 7.5 * t)  # the heave, tug by tug
    env = np.sin(np.pi * np.clip(t / 0.75, 0, 1)) ** 0.7
    buf = (scrape + rumble) * wobble * env
    for _ in range(14):  # crumbs
        at = float(rng.uniform(0.05, 0.6))
        m = int(0.02 * SR)
        c = band(noise(m, rng), 1500, 5000) * np.exp(-secs(m) * 220)
        put(buf, c, at, float(rng.uniform(0.15, 0.4)))
    return finish(buf, peak_db=-5.0, hi=6000)


def sword_ring():
    """The sword comes free: a bright metal ring-out (inharmonic partials of a struck blade,
    beating slightly) over a short whoosh of the pull."""
    rng = np.random.default_rng(24)
    buf = buffer(2.0)
    n = len(buf)
    t = secs(n)
    f0 = 1180.0
    for ratio, amp, decay in [(1.0, 1.0, 2.2), (1.003, 0.6, 2.4), (2.76, 0.45, 3.5), (5.4, 0.25, 5.0), (8.93, 0.12, 7.0)]:
        buf += amp * np.sin(osc_phase(np.full(n, f0 * ratio), n)) * np.exp(-t * decay)
    buf *= 1 - np.exp(-t * 400)
    m = int(0.3 * SR)
    swish = band(noise(m, rng), 900, 5000) * np.sin(np.pi * secs(m) / 0.3) * 0.5
    put(buf, swish, 0.0)
    return finish(S.reverb(buf, 0.2, 1.2), peak_db=-5.0)


# --- Emotes (timed to the choreography in player/emote_poses.gd; each fits inside Emotes.LENGTHS) --

def trim(x, buf, tail):
    """`x` (the reverbed `buf`) cut `tail` seconds after `buf` ends, so a cue stops with its emote."""
    return x[..., : len(buf) + int(tail * SR)]


def kazoo(m, dur, vib=0.0):
    """A toy kazoo note: a buzzy sawtooth through a nasal band, with a little vibrato."""
    n = int(dur * SR)
    t = secs(n)
    f = midi_hz(m) * (1 + vib * np.sin(2 * np.pi * 6.0 * t) * np.clip(t / 0.15, 0, 1))
    ph = osc_phase(f, n)
    y = np.zeros(n)
    for k in range(1, 18):
        if midi_hz(m) * k > 6500:
            break
        y += np.sin(k * ph) / k
    y = band(y, 350, 4200) + 0.35 * band(y, 900, 1500)
    return y * adsr(n, a=0.015, r=0.05)


def slide(f0, f1, dur, shape=1.0):
    """A slide whistle gliding from `f0` to `f1` Hz."""
    n = int(dur * SR)
    t = secs(n)
    k = (t / dur) ** shape
    f = f0 * (f1 / f0) ** k * (1 + 0.012 * np.sin(2 * np.pi * 9 * t))
    ph = osc_phase(f, n)
    return (np.sin(ph) + 0.08 * np.sin(2 * ph)) * adsr(n, a=0.02, r=0.06)


def wah(peak, dur, base=500):
    """A muted trumpet's mute opening and closing over `dur` (for `trumpet`)."""
    return lambda t: base + peak * np.sin(np.pi * np.clip(t / dur, 0, 1))


def emote_six_seven():
    """6-7: a woodblock "six" (low) and "se-ven" (two higher taps) as each hand reaches the top,
    eight in all, then a muted-trumpet "meh" for the shrug."""
    buf = buffer(2.95)
    for k in range(8):
        at = 0.3 + 0.125 + 0.25 * k - 0.03  # the hand reaches the top of its swing
        if k % 2 == 0:
            put(buf, S.woodblock(76, 0.9), at)
        else:
            put(buf, S.woodblock(83, 0.8), at - 0.05)
            put(buf, S.woodblock(81, 0.75), at + 0.04)
    put(buf, trumpet(60, 0.18, lambda t: 700 + 600 * np.clip(t / 0.18, 0, 1)), 2.3, 0.7)
    put(buf, trumpet(57, 0.4, lambda t: 1300 - 700 * np.clip(t / 0.4, 0, 1), vibrato=0.01), 2.47, 0.7)
    return finish(trim(S.reverb(buf, 0.12, 0.6), buf, 0.3), hi=7000)


def emote_wave():
    """Wave: a slide whistle up as the arm swings up, then a friendly two-note "hel-lo" whistle."""
    buf = buffer(2.2)
    put(buf, slide(500, 1400, 0.28, 0.7), 0.13, 0.55)
    for at, f0, f1, d in [(0.62, 1150, 1500, 0.2), (0.86, 1450, 1050, 0.38)]:
        put(buf, slide(f0, f1, d, 0.5), at, 0.7)
    return finish(trim(S.reverb(buf, 0.2, 0.8), buf, 0.3), peak_db=-5.0, hi=6000)


def emote_laugh():
    """Laugh: a muted-trumpet cackle, "hah-hah-hah", tumbling down, then a wheezing higher "hee-hee"
    while the bean is doubled over, and a happy sigh."""
    buf = buffer(2.75)
    for i, m in enumerate([70, 69, 68, 67, 66, 65, 66, 65, 64, 63]):
        put(buf, trumpet(m - 2, 0.085, wah(1800, 0.085, 600)), 0.2 + i * 0.095, 0.75)
    for i in range(7):
        put(buf, trumpet(74 - (i % 3), 0.07, wah(2000, 0.07, 900)), 1.35 + i * 0.12, 0.55)
    put(buf, trumpet(62, 0.45, lambda t: 1200 - 800 * np.clip(t / 0.45, 0, 1), vibrato=0.01), 2.3, 0.45)
    return finish(trim(S.reverb(buf, 0.15, 0.7), buf, 0.3), hi=6000)


def emote_taunt():
    """Taunt: the playground "nyah-nyah na-nyah-nyah" on a kazoo while the hands waggle, two bum
    slaps, and a whoosh for each turn."""
    rng = np.random.default_rng(31)
    buf = buffer(2.6)
    for at, m, d in [(0.42, 67, 0.17), (0.6, 64, 0.17), (0.78, 69, 0.1), (0.88, 67, 0.1), (0.99, 64, 0.22)]:
        put(buf, kazoo(m, d, vib=0.015), at, 0.65)
    for at in (1.59, 1.83):
        m = int(0.08 * SR)
        slap = band(noise(m, rng), 500, 4500) * np.exp(-secs(m) * 60)
        slap += 0.6 * np.sin(osc_phase(np.full(m, 180.0), m)) * np.exp(-secs(m) * 50)
        put(buf, slap, at, 0.8)
    for at in (1.2, 2.0):
        m = int(0.22 * SR)
        swish = band(noise(m, rng), 700, 4000) * np.sin(np.pi * secs(m) / 0.22) ** 2
        put(buf, swish, at, 0.35)
    return finish(trim(S.reverb(buf, 0.12, 0.6), buf, 0.3), hi=7000)


def emote_cry():
    """Cry: a muted-trumpet "waaah" with the wail, a sob on every hitch of the shoulders, and a
    sniff at the end."""
    rng = np.random.default_rng(32)
    buf = buffer(2.9)
    put(buf, trumpet(64, 0.55, wah(1600, 0.55), vibrato=0.02), 0.38, 0.85)
    for i, at in enumerate([0.66, 1.0, 1.33, 1.66, 2.0]):
        put(buf, trumpet(62 - (i % 2), 0.16, wah(1100, 0.16)), at, 0.55)
        put(buf, trumpet(60 - (i % 2), 0.14, wah(700, 0.14)), at + 0.13, 0.45)
    m = int(0.28 * SR)
    sniff = band(noise(m, rng), 2500, 8000) * np.sin(np.pi * secs(m) / 0.28) ** 0.6 * np.linspace(0.6, 1.0, m)
    put(buf, sniff, 2.3, 0.4)
    return finish(trim(S.reverb(buf, 0.18, 0.9), buf, 0.3), hi=6000)


def emote_dance():
    """Dance (the disco): four-on-the-floor kick, hat offbeats and an octave bass on the four
    pointing beats, a riser into the twirl and a vibes "ta-da" as it lands."""
    rng = np.random.default_rng(33)
    buf = buffer(3.35)
    beat = 0.5
    for k in range(4):
        at = 0.15 + k * beat
        put(buf, S.kick(0.9, rng), at)
        put(buf, S.hat_chick(0.5, rng), at + beat / 2)
        put(buf, S.upright_bass(45 if k % 2 == 0 else 57, 0.2, 1.0, rng), at)
        put(buf, S.upright_bass(57 if k % 2 == 0 else 45, 0.15, 0.8, rng), at + beat / 2)
    m = int(0.65 * SR)
    riser = band(noise(m, rng), 1500, 7000) * (secs(m) / 0.65) ** 2
    put(buf, riser, 2.2, 0.35)
    put(buf, slide(400, 1200, 0.6, 1.0), 2.22, 0.3)
    for mm in (69, 73, 76, 81):
        put(buf, S.vibes(mm, 0.5, 0.8), 2.86, 0.45)
    put(buf, S.kick(0.9, rng), 2.86)
    return finish(trim(S.reverb(buf, 0.15, 0.8), buf, 0.3))


def emote_default_dance():
    """The default dance: a bouncy kick-and-snare beat with a walking bass, two bars at the
    dance's tempo (2.35 beats a second)."""
    rng = np.random.default_rng(34)
    buf = buffer(3.35)
    beat = 1.0 / 2.35
    bass = [45, 48, 50, 52, 45, 48, 52, 50]
    for k in range(8):
        at = k * beat
        put(buf, S.kick(0.85, rng), at)
        if k % 2 == 1:
            put(buf, S.brush_tap(1.0, rng), at)
        put(buf, S.hat_chick(0.45, rng), at + beat / 2)
        put(buf, S.upright_bass(bass[k], beat * 0.8, 1.0, rng), at)
    return finish(trim(S.reverb(buf, 0.12, 0.6), buf, 0.3))


def emote_gg():
    """GG: three soft pats with the handshake pumps, a warm vibes chord with the bow, and a bright
    "ding" with the thumbs up at the end."""
    rng = np.random.default_rng(35)
    buf = buffer(2.95)
    for k in range(3):
        at = 0.45 + (0.25 + k) / 3.8
        m = int(0.07 * SR)
        put(buf, band(noise(m, rng), 300, 2500) * np.exp(-secs(m) * 55), at, 0.5)
    for mm in (60, 64, 67, 71):
        put(buf, S.vibes(mm, 0.7, 0.6), 1.55, 0.35)
    put(buf, S.bell(midi_hz(84), 1.0, 0.7), 2.42, 0.8)
    coins(buf, rng, 2.42, 3, 0.15, 0.3)
    return finish(trim(S.reverb(buf, 0.18, 1.0), buf, 0.3))


def emote_thumbs_up():
    """Thumbs up: a "click" and a bright "ding!" on the punch, a second, higher one when the other
    thumb joins."""
    rng = np.random.default_rng(36)
    buf = buffer(2.0)
    for at, mm in [(0.31, 84), (0.9, 91)]:
        m = int(0.012 * SR)
        put(buf, band(noise(m, rng), 2000, 8000), at - 0.01, 0.4)
        put(buf, S.bell(midi_hz(mm), 1.0, 0.8), at, 0.8)
        put(buf, S.vibes(mm - 12, 0.3, 0.7), at, 0.4)
    return finish(trim(S.reverb(buf, 0.18, 0.9), buf, 0.3))


def emote_thumbs_down():
    """Thumbs down: a slide whistle sinking as the thumb turns over, then three muted-trumpet
    "boo"s going down."""
    buf = buffer(2.3)
    put(buf, slide(1300, 450, 0.32, 1.2), 0.27, 0.5)
    for at, m in [(0.72, 58), (1.12, 57), (1.52, 55)]:
        put(buf, trumpet(m, 0.3, wah(700, 0.3, 450)), at, 0.8)
    return finish(trim(S.reverb(buf, 0.15, 0.8), buf, 0.3), hi=6000)


RECIPES = {
    "splash": splash, "whistle": whistle, "jackpot_siren": jackpot, "big_win": big_win,
    "loss_sting": loss_sting, "slip": slip, "tray_crash": tray_crash, "megaphone": megaphone,
    "last_call_bell": last_call_bell, "cash_register": cash_register, "hot_table": hot_table,
    "chime": chime, "boing": boing, "scratch": scratch, "stone_grind": stone_grind, "sword_ring": sword_ring,
    "emote_six_seven": emote_six_seven, "emote_wave": emote_wave, "emote_laugh": emote_laugh,
    "emote_taunt": emote_taunt, "emote_cry": emote_cry, "emote_dance": emote_dance,
    "emote_default_dance": emote_default_dance, "emote_gg": emote_gg, "emote_thumbs_up": emote_thumbs_up,
    "emote_thumbs_down": emote_thumbs_down,
}

if __name__ == "__main__":
    for name in (sys.argv[1:] or list(RECIPES)):
        x = RECIPES[name]()
        S.write_wav(os.path.join(OUT, name + ".wav"), x)
        print("%-15s %s" % (name, S.stats(x)))
