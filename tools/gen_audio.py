#!/usr/bin/env python3
"""Generates placeholder sound effects as 16-bit mono WAV files in audio/sfx/ (pure Python,
sfxr-style synthesis). Deterministic; re-run after changing a recipe. Never block on these."""
import math, os, random, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")


def env(t, dur, attack=0.005, release=0.1):
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0


def render(name, dur, fn, gain=0.6, seed=1):
    rnd = random.Random(seed)
    n = int(RATE * dur)
    frames = bytearray()
    for i in range(n):
        t = i / RATE
        v = fn(t, rnd) * env(t, dur) * gain
        v = max(-1.0, min(1.0, v))
        frames += struct.pack("<h", int(v * 32767))
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


def sine(f, t):
    return math.sin(2 * math.pi * f * t)


def square(f, t):
    return 1.0 if (f * t) % 1.0 < 0.5 else -1.0


def noise(rnd):
    return rnd.uniform(-1, 1)


def chip_clack(t, r):   # sharp satisfying clack
    return (noise(r) * math.exp(-t * 90) + sine(1800, t) * math.exp(-t * 60)) * 1.2


def coin(t, r):
    return sine(2200, t) * math.exp(-t * 12) + sine(3300, t) * math.exp(-t * 18) * 0.5


def big_win(t, r):      # bells + coins
    notes = [660, 880, 1100, 1320]
    i = min(int(t / 0.12), len(notes) - 1)
    bell = sine(notes[i], t) * math.exp(-(t % 0.12) * 10)
    sparkle = sine(2600 + 400 * math.sin(t * 30), t) * 0.25 * math.exp(-t * 2)
    return bell * 0.7 + sparkle


def loss_sting(t, r):   # short sad casino sting
    f = 330 * (1 - 0.35 * min(t / 0.5, 1))
    return (sine(f, t) + 0.3 * sine(f * 0.5, t)) * math.exp(-t * 3)


def bonk(t, r):         # comedic ragdoll impact
    f = 160 * (1 - 0.5 * min(t / 0.15, 1))
    return sine(f, t) * math.exp(-t * 18) + noise(r) * math.exp(-t * 70) * 0.5


def buzzer(t, r):       # VIP access denied
    return square(110, t) * 0.5 + square(113, t) * 0.4


def whistle(t, r):      # guard whistle
    f = 2600 + 150 * math.sin(t * 60)
    return sine(f, t) * 0.8


def whoosh(t, r):
    return noise(r) * math.exp(-((t - 0.1) ** 2) * 200) * 0.9


def oof(t, r):
    f = 220 * (1 - 0.3 * min(t / 0.2, 1))
    return (sine(f, t) + 0.5 * sine(f * 2, t)) * math.exp(-t * 10)


def boing(t, r):        # spring glove
    f = 400 + 600 * math.exp(-t * 6) * math.sin(t * 40)
    return sine(f, t) * math.exp(-t * 4)


def splash(t, r):
    return noise(r) * math.exp(-t * 6) * (0.4 + 0.6 * math.sin(t * 25))


def card_flip(t, r):
    return noise(r) * math.exp(-t * 120) * 0.7


def reel_stop(t, r):
    return (sine(900, t) * math.exp(-t * 40) + noise(r) * math.exp(-t * 150) * 0.4)


def plink(t, r):
    return sine(1500, t) * math.exp(-t * 50)


def ui_click(t, r):
    return sine(1200, t) * math.exp(-t * 80)


def ui_hover(t, r):
    return sine(900, t) * math.exp(-t * 120) * 0.5


def countdown_beep(t, r):
    return sine(880, t) * 0.8


def jackpot_siren(t, r):
    f = 600 + 400 * math.sin(t * 8)
    return sine(f, t) * 0.7


def slip(t, r):
    f = 800 + 1200 * t
    return sine(f, t) * math.exp(-t * 6) * 0.7


def ball_roll(t, r):
    return noise(r) * 0.3 * (0.5 + 0.5 * math.sin(t * 90))


def pickup(t, r):
    return sine(1400 + 800 * t, t) * math.exp(-t * 20)


def footstep(t, r):
    return noise(r) * math.exp(-t * 60) * 0.5 + sine(120, t) * math.exp(-t * 40) * 0.5


def thud(t, r):
    return sine(90, t) * math.exp(-t * 20) + noise(r) * math.exp(-t * 80) * 0.4


def jump(t, r):
    return sine(300 + 500 * t, t) * math.exp(-t * 15) * 0.6


RECIPES = [
    ("chip_clack", 0.12, chip_clack), ("coin", 0.4, coin), ("big_win", 1.2, big_win), ("loss_sting", 0.7, loss_sting),
    ("bonk", 0.3, bonk), ("buzzer", 0.5, buzzer), ("whistle", 0.5, whistle), ("whoosh", 0.3, whoosh), ("oof", 0.3, oof),
    ("boing", 0.5, boing), ("splash", 0.7, splash), ("card_flip", 0.08, card_flip), ("reel_stop", 0.15, reel_stop),
    ("plink", 0.1, plink), ("ui_click", 0.06, ui_click), ("ui_hover", 0.05, ui_hover), ("countdown_beep", 0.12, countdown_beep),
    ("jackpot_siren", 2.0, jackpot_siren), ("slip", 0.4, slip), ("ball_roll", 1.5, ball_roll), ("pickup", 0.2, pickup),
    ("footstep", 0.1, footstep), ("thud", 0.25, thud), ("jump", 0.2, jump),
]

if __name__ == "__main__":
    for name, dur, fn in RECIPES:
        render(name, dur, fn)
    print("generated %d sfx in %s" % (len(RECIPES), os.path.abspath(OUT)))
