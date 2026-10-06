#!/usr/bin/env python3
"""Generates the lounge-jazz music loops in audio/music/ (one per mood, see Audio.set_mood).

    python3 tools/audio/gen_music.py            # all moods
    python3 tools/audio/gen_music.py casino     # one mood

Needs numpy and ffmpeg (libvorbis). Deterministic: the same seed writes the same loop.
docs/ART_DIRECTION.md: lounge jazz, upright bass, brushed drums, vibraphone, slightly cheesy casino
elevator music. Menu relaxed but slightly suspicious, quiz like a game show, Last Call = the casino
theme faster and more intense, results warm and celebratory.

Each song is a chord chart; the generator plays it with a walking (or two-feel) bass, rootless
Rhodes voicings with smooth voice leading, a vibraphone melody built from a repeated motif that
follows the chords, and a brushed kit with a swung ride. The loop's tail is folded back onto its
start and the reverb is circular, so the file repeats without a seam.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "audio", "music")

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# quality → (chord tones, rootless Rhodes voicing, chord scale), all in semitones over the root
QUALITY = {
    "maj7": ([0, 4, 7, 11], [4, 7, 11, 14], [0, 2, 4, 5, 7, 9, 11]),
    "6": ([0, 4, 7, 9], [4, 7, 9, 14], [0, 2, 4, 5, 7, 9, 11]),
    "m7": ([0, 3, 7, 10], [3, 7, 10, 14], [0, 2, 3, 5, 7, 9, 10]),
    "m9": ([0, 3, 7, 10], [3, 7, 10, 14], [0, 2, 3, 5, 7, 9, 10]),
    "m6": ([0, 3, 7, 9], [3, 7, 9, 14], [0, 2, 3, 5, 7, 9, 11]),
    "7": ([0, 4, 7, 10], [4, 9, 10, 14], [0, 2, 4, 5, 7, 9, 10]),
    "7b9": ([0, 4, 7, 10], [4, 7, 10, 13], [0, 1, 4, 5, 7, 8, 10]),
    "m7b5": ([0, 3, 6, 10], [3, 6, 10, 12], [0, 1, 3, 5, 6, 8, 10]),
    "dim7": ([0, 3, 6, 9], [0, 3, 6, 9], [0, 2, 3, 5, 6, 8, 9, 11]),
}


def chord(sym):
    root = NOTE[sym[0]]
    q = sym[1:]
    if q.startswith("b"):
        root -= 1
        q = q[1:]
    elif q.startswith("#"):
        root += 1
        q = q[1:]
    tones, voicing, scale = QUALITY[q]
    return {"sym": sym, "root": root % 12, "tones": tones, "voicing": voicing, "scale": scale}


SONGS = {
    # Relaxed but slightly suspicious: D minor, two-feel bass, sparse vibes.
    "menu": {
        "bpm": 86, "swing": 0.64, "seed": 11, "bass": "two", "comp": "sustain", "melody": "sparse",
        "drums": "brushes_soft", "ride_level": 0.10, "reverb": 0.28,
        "chart": [["Dm9"], ["Dm9"], ["Gm9"], ["Gm9"], ["Em7b5"], ["A7b9"], ["Dm9"], ["Bbmaj7", "A7b9"],
                  ["Dm9"], ["Dm9"], ["Gm9"], ["C7"], ["Fmaj7"], ["Em7b5", "A7b9"], ["Dm6"], ["Em7b5", "A7b9"]],
    },
    # The casino theme: F major swing, walking bass, Charleston comping.
    "casino": {
        "bpm": 116, "swing": 0.64, "seed": 23, "bass": "walk", "comp": "charleston", "melody": "medium",
        "drums": "brushes", "ride_level": 0.16, "reverb": 0.22,
        "chart": [["Fmaj7"], ["D7b9"], ["Gm7"], ["C7"], ["Am7"], ["D7"], ["Gm7"], ["C7"],
                  ["Fmaj7"], ["F7"], ["Bbmaj7"], ["Bbm6"], ["Am7"], ["D7b9"], ["Gm7", "C7"], ["F6"],
                  ["Cm7"], ["F7"], ["Bbmaj7"], ["Bb6"], ["Am7"], ["D7"], ["G7"], ["Gm7", "C7"]],
    },
    # Game show: rhythm changes in Bb, stabbed comping and a tick-tock woodblock clock.
    "quiz": {
        "bpm": 136, "swing": 0.62, "seed": 37, "bass": "walk", "comp": "stabs", "melody": "busy",
        "drums": "brushes", "ride_level": 0.15, "reverb": 0.18, "clock": True,
        "chart": [["Bbmaj7", "G7"], ["Cm7", "F7"], ["Dm7", "G7"], ["Cm7", "F7"], ["Bb6", "Bb7"], ["Ebmaj7", "Ebm6"], ["Dm7", "G7"], ["Cm7", "F7"],
                  ["Bbmaj7", "G7"], ["Cm7", "F7"], ["Dm7", "G7"], ["Cm7", "F7"], ["Bb6", "Bb7"], ["Ebmaj7", "Ebm6"], ["Cm7", "F7"], ["Bb6"],
                  ["D7"], ["D7"], ["G7"], ["G7"], ["C7"], ["C7"], ["F7"], ["Cm7", "F7"]],
    },
    # Last Call: the casino theme (same chart and melody seed), faster, driving ride and kick.
    "last_call": {
        "bpm": 150, "swing": 0.6, "seed": 23, "bass": "walk", "comp": "drive", "melody": "medium",
        "drums": "drive", "ride_level": 0.2, "reverb": 0.16, "melody_from": "casino",
    },
    # Results podium: warm Eb ballad-swing, lyrical vibes.
    "results": {
        "bpm": 100, "swing": 0.65, "seed": 51, "bass": "walk", "comp": "sustain", "melody": "lyrical",
        "drums": "brushes_soft", "ride_level": 0.12, "reverb": 0.26,
        "chart": [["Ebmaj7"], ["Cm7"], ["Fm7"], ["Bb7"], ["Gm7"], ["C7"], ["Fm7"], ["Bb7"],
                  ["Ebmaj7"], ["Eb7"], ["Abmaj7"], ["Abm6"], ["Gm7"], ["C7b9"], ["Fm7", "Bb7"], ["Eb6"]],
    },
}
SONGS["last_call"]["chart"] = SONGS["casino"]["chart"]


def beats_of(chart):
    """Chord per beat (4/4; a bar with two chords splits 2 + 2)."""
    out = []
    for bar in chart:
        cs = [chord(c) for c in bar]
        if len(cs) == 1:
            out += [cs[0]] * 4
        else:
            out += [cs[0]] * 2 + [cs[1]] * 2
    return out


def nearest(pc, prev, lo, hi):
    """MIDI note with pitch class `pc` closest to `prev`, inside [lo, hi]."""
    best = None
    for m in range(lo, hi + 1):
        if m % 12 == pc and (best is None or abs(m - prev) < abs(best - prev)):
            best = m
    return best


# --- Bass ----------------------------------------------------------------------------------------

def bass_line(beats, style, rng):
    """[(beat index, midi, length in beats)]. Walking: the root on every bar line and chord change,
    chord/scale tones in between heading for the next root, a chromatic or fifth approach on the
    beat before it. Two-feel: half notes (root, then fifth or approach)."""
    lo, hi = 28, 50
    notes = []
    prev = 38
    n = len(beats)
    step = 2 if style == "two" else 1
    for i in range(0, n, step):
        c = beats[i]
        j = (i + step) % n
        nxt = beats[j]
        lands = i % 4 == 0 or beats[i - 1]["sym"] != c["sym"]
        next_lands = j % 4 == 0 or nxt["sym"] != c["sym"]
        if lands:
            m = nearest(c["root"], prev, lo, hi)
        elif next_lands:
            target = nearest(nxt["root"], prev, lo + 1, hi - 1)
            fifth = nearest((nxt["root"] + 7) % 12, prev, lo, hi)
            options = [target - 1, target + 1, fifth]
            m = options[int(rng.integers(0, 3))]
            if m == prev:
                m = options[0]
        else:
            target = nearest(nxt["root"], prev, lo, hi)
            pool = [(c["root"] + t) % 12 for t in c["tones"][1:]] + [(c["root"] + s) % 12 for s in c["scale"]]
            cands = [nearest(pc, prev, lo, hi) for pc in pool]
            cands = [x for x in cands if x is not None and x != prev and abs(x - prev) <= 5]
            toward = [x for x in cands if (x - prev) * (target - prev) > 0] or cands
            m = toward[int(rng.integers(0, len(toward)))] if toward else prev
        notes.append((i, m, step * 0.92))
        prev = m
    return notes


# --- Rhodes --------------------------------------------------------------------------------------

def voicing(c, prev):
    """Rootless voicing in roughly F3..D5, the inversion closest to the previous voicing."""
    pcs = [(c["root"] + v) % 12 for v in c["voicing"]]
    best = None
    for r in range(len(pcs)):
        rot = pcs[r:] + pcs[:r]
        for base in (52, 53, 54, 55, 56, 57):
            v = []
            m = base
            for pc in rot:
                while m % 12 != pc:
                    m += 1
                v.append(m)
                m += 1
            if v[-1] > 76:
                continue
            cost = sum(abs(a - b) for a, b in zip(sorted(v), sorted(prev)))
            if best is None or cost < best[0]:
                best = (cost, v)
    return best[1]


COMP = {
    # (beat offset within the chord, length in beats, velocity); offsets x.5 are swung
    "sustain": [(0, 3.6, 0.55)],
    "charleston": [(0, 1.1, 0.6), (1.5, 0.9, 0.5)],
    "stabs": [(1, 0.35, 0.6), (3, 0.35, 0.65)],
    "drive": [(0, 0.6, 0.62), (1.5, 0.45, 0.5), (2.5, 0.45, 0.52)],
}


# --- Melody --------------------------------------------------------------------------------------

RHYTHMS = {
    # two-bar motifs on the eighth grid (0..15): (onset, length in eighths)
    "sparse": [[(0, 3), (3, 1), (4, 6), (12, 3)], [(1, 2), (4, 2), (6, 8)]],
    "medium": [[(0, 2), (2, 1), (3, 2), (6, 1), (7, 5)], [(1, 1), (2, 2), (4, 1), (5, 3), (10, 1), (11, 4)]],
    "busy": [[(0, 1), (1, 1), (2, 1), (3, 2), (6, 1), (7, 1), (8, 3), (12, 1), (13, 2)], [(0, 2), (3, 1), (4, 1), (5, 1), (6, 2), (9, 1), (10, 4)]],
    "lyrical": [[(0, 4), (4, 2), (6, 6), (14, 2)], [(0, 2), (2, 2), (4, 8)]],
}
CONTOURS = [[0, 2, 1, -1, -2, 1, 2, -1, 0], [0, -1, 2, 1, -2, -1, 3, -2, 0], [0, 1, 1, 2, -3, -1, 1, 0, -1]]


def melody(chart, beats, style, rng):
    """[(time in beats, midi, length in beats, velocity)]: a motif per 8-bar section, answered,
    repeated and closed on a long chord tone. Strong beats land on chord tones."""
    lo, hi = 65, 84
    out = []
    p = 72
    bars = len(chart)
    rh = RHYTHMS[style]
    for sec in range(0, bars, 8):
        motif = rh[int(rng.integers(0, len(rh)))]
        answer = rh[int(rng.integers(0, len(rh)))]
        contour = CONTOURS[int(rng.integers(0, len(CONTOURS)))]
        for ph in range(4):
            bar0 = sec + ph * 2
            if bar0 >= bars:
                break
            if style == "sparse" and ph == 1:
                continue  # the menu breathes: every other phrase is a rest
            rhythm = motif if ph in (0, 2) else answer
            last_phrase = ph == 3
            for k, (on, ln) in enumerate(rhythm):
                if last_phrase and on >= 8:
                    break
                beat = bar0 * 4 + on / 2.0
                bi = min(int(beat), len(beats) - 1)
                c = beats[bi]
                strong = on % 4 == 0 or (on % 2 == 0 and ln >= 2)
                step = contour[k % len(contour)]
                scale = sorted({(c["root"] + s) % 12 for s in c["scale"]})
                cands = [m for m in range(lo - 2, hi + 3) if m % 12 in scale]
                idx = min(range(len(cands)), key=lambda j: abs(cands[j] - p))
                idx = max(0, min(len(cands) - 1, idx + step))
                m = cands[idx]
                if strong:
                    tones = [(c["root"] + t) % 12 for t in c["tones"][1:]] + [(c["root"] + 2) % 12 if c["sym"][-1] != "9" else c["root"]]
                    m = min((x for x in range(m - 3, m + 4) if x % 12 in tones), key=lambda x: abs(x - m), default=m)
                if m == p and k > 0 and not strong:
                    m = cands[max(0, min(len(cands) - 1, idx + (1 if step >= 0 else -1)))]
                if m > hi:
                    m -= 12
                if m < lo:
                    m += 12
                vel = 0.75 if strong else 0.6
                out.append((beat, m, ln / 2.0 * 0.95, vel + 0.08 * float(rng.random())))
                p = m
            if last_phrase:
                # Cadence: a long chord tone on the section's last bar.
                beat = (bar0 + 1) * 4
                c = beats[min(int(beat), len(beats) - 1)]
                tones = [(c["root"] + t) % 12 for t in (c["tones"][1], c["tones"][2], 0)]
                m = min((x for x in range(lo, hi + 1) if x % 12 in tones), key=lambda x: abs(x - p))
                out.append((beat, m, 3.0, 0.7))
                p = m
    return out


# --- Render --------------------------------------------------------------------------------------

def swing_time(beat, beat_s, ratio):
    """Seconds for a position in beats: off-beat eighths land at `ratio` of the beat."""
    whole = int(np.floor(beat))
    frac = beat - whole
    if abs(frac - 0.5) < 1e-6:
        frac = ratio
    return (whole + frac) * beat_s


def render(name):
    song = SONGS[name]
    rng = np.random.default_rng(song["seed"])
    bpm = song["bpm"]
    beat_s = 60.0 / bpm
    chart = song["chart"]
    beats = beats_of(chart)
    nb = len(beats)
    loop_s = nb * beat_s
    n = int(round(loop_s * S.SR))
    tail = int(4.0 * S.SR)
    buf = np.zeros((2, n + tail))
    sw = song["swing"]

    def hum():
        return float(rng.normal(0.0, 0.004))

    # Bass
    for i, m, ln in bass_line(beats, song["bass"], np.random.default_rng(song["seed"] + 1)):
        vel = 0.95 if i % 2 == 0 else 0.82
        S.place(buf, S.upright_bass(m, ln * beat_s, vel, rng), i * beat_s + hum(), 0.26, 0.0)

    # Rhodes comping, chord by chord
    prev = [57, 60, 64, 67]
    i = 0
    pattern = COMP[song["comp"]]
    while i < nb:
        c = beats[i]
        j = i
        while j < nb and beats[j]["sym"] == c["sym"] and j - i < 4:
            j += 1
        span = j - i
        v = voicing(c, prev)
        prev = v
        for off, ln, vel in pattern:
            if off >= span:
                continue
            if song["comp"] == "charleston" and span == 2 and off > 0:
                off, ln = 1.5, 0.45
            ln = min(ln, span - off)
            t = swing_time(i + off, beat_s, sw)
            for k, m in enumerate(v):
                S.place(buf, S.rhodes(m, ln * beat_s, vel * (0.9 + 0.2 * float(rng.random()))), t + hum() + k * 0.004, 0.17, -0.3 + 0.12 * k)
        i = j

    # Vibes melody
    mel_rng = np.random.default_rng(SONGS[song.get("melody_from", name)]["seed"] + 2)
    for beat, m, ln, vel in melody(chart, beats, song["melody"], mel_rng):
        t = swing_time(beat, beat_s, sw)
        S.place(buf, S.vibes(m, ln * beat_s, vel, motor=5.0 if name != "last_call" else 6.5), t + hum(), 0.36, 0.3)

    # Drums
    drng = np.random.default_rng(song["seed"] + 3)
    style = song["drums"]
    ride_lvl = song["ride_level"]
    swish = S.brush_swish(nb, beat_s, drng, level=0.11 if style != "drive" else 0.08)
    S.place(buf, swish, 0.0, 1.0, -0.15)
    for b in range(nb):
        t = b * beat_s
        backbeat = b % 2 == 1
        S.place(buf, S.ride(0.85 if backbeat else 0.7, drng), t + hum(), ride_lvl, 0.35)
        if backbeat or style == "drive":
            S.place(buf, S.ride(0.5, drng, length=0.8), swing_time(b + 0.5, beat_s, sw) + hum(), ride_lvl * (0.8 if backbeat else 0.6), 0.35)
        if backbeat:
            S.place(buf, S.hat_chick(0.6, drng), t + hum(), 0.16, 0.2)
            S.place(buf, S.brush_tap(0.7 if style != "brushes_soft" else 0.45, drng), t + hum(), 0.32, -0.1)
        S.place(buf, S.kick(0.5 if style == "drive" else 0.35), t, 0.22, 0.0)
        if style == "drive" and drng.random() < 0.3:
            S.place(buf, S.brush_tap(0.5, drng), swing_time(b + 0.5, beat_s, sw), 0.14, -0.1)
        if song.get("clock"):
            S.place(buf, S.woodblock(84 if b % 2 == 0 else 79, 0.5), t, 0.06, -0.45)

    # Fold the tail onto the start: the loop point is seamless.
    buf[:, :tail] += buf[:, n:n + tail]
    buf = buf[:, :n]
    for ch in range(2):
        # Presence lift between 1 and 3.5 kHz (the sine-ish instruments are dark), cymbal hiss tamed above.
        x = S.band(buf[ch], 30, 12000, circular=True)
        x = S.tilt(x, 1100, 6.0, circular=True)
        buf[ch] = S.tilt(S.tilt(x, 3500, -6.0, circular=True), 7000, -3.0, circular=True)
    buf = S.circular_reverb(buf, wet=song["reverb"], seconds=1.7, darkness=4200)
    buf = S.master(buf, rms_db=-19.0, peak_db=-1.0)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".ogg")
    S.write_ogg(path, buf, quality=4)
    print("%-10s %3d bpm %2d bars  %s" % (name, bpm, len(chart), S.stats(buf)))


if __name__ == "__main__":
    for nm in (sys.argv[1:] or list(SONGS)):
        render(nm)
