"""Small offline synthesis toolkit for Better at Gambling's lounge-jazz music and SFX (numpy only).

Everything is deterministic (seeded) so re-running the generators reproduces the same files.
Instruments are modelled, not sampled: additive upright bass, two-operator FM Rhodes, vibraphone
bars, brushed drum kit, bells, water, glass. Filters run in the frequency domain (FFT masks),
reverb is an FFT convolution with a synthetic decaying-noise impulse response. Loops are rendered
with their tail folded back onto the start, and the reverb is circular, so they repeat seamlessly.
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100


def secs(n):
    return np.arange(int(n)) / SR


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def db(x):
    return 10.0 ** (x / 20.0)


# --- Filters -------------------------------------------------------------------------------------

def _mask(n, lo, hi, width=0.25):
    """Smooth band mask over rfft bins: cosine ramps `width` octaves wide at each edge."""
    f = np.fft.rfftfreq(n, 1.0 / SR)
    m = np.ones_like(f)
    with np.errstate(divide="ignore"):
        lf = np.log2(np.maximum(f, 1e-3))
    if lo and lo > 0:
        a = np.clip((lf - (np.log2(lo) - width)) / width, 0.0, 1.0)
        m *= 0.5 - 0.5 * np.cos(np.pi * a)
    if hi and hi < SR / 2:
        a = np.clip(((np.log2(hi) + width) - lf) / width, 0.0, 1.0)
        m *= 0.5 - 0.5 * np.cos(np.pi * a)
    return m


def band(x, lo=None, hi=None, width=0.25, circular=False):
    """Band-pass (either edge optional). Zero-padded unless `circular` (loops)."""
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    pad = n if circular else int(2 ** np.ceil(np.log2(n + SR // 4)))
    spec = np.fft.rfft(x, pad) * _mask(pad, lo, hi, width)
    return np.fft.irfft(spec, pad)[:n]


def tilt(x, hz, gain_db, circular=False):
    """High shelf: everything above `hz` changed by `gain_db` (smooth half-octave transition)."""
    n = len(x)
    pad = n if circular else int(2 ** np.ceil(np.log2(n + SR // 4)))
    f = np.fft.rfftfreq(pad, 1.0 / SR)
    with np.errstate(divide="ignore"):
        a = np.clip((np.log2(np.maximum(f, 1e-3)) - np.log2(hz) + 0.5), 0.0, 1.0)
    g = db(gain_db * (0.5 - 0.5 * np.cos(np.pi * a)))
    return np.fft.irfft(np.fft.rfft(x, pad) * g, pad)[:n]


# --- Envelopes and oscillators -------------------------------------------------------------------

def adsr(n, a=0.005, d=0.0, s=1.0, r=0.05, hold=None):
    """Linear attack, exponential-ish decay to sustain, linear release over the last `r` seconds."""
    t = secs(n)
    e = np.ones(n)
    if a > 0:
        e = np.minimum(e, t / a)
    if d > 0:
        e = np.where(t > a, s + (1 - s) * np.exp(-(t - a) / d), e)
    hold = n / SR - r if hold is None else hold
    rel = np.clip(1.0 - (t - hold) / max(r, 1e-4), 0.0, 1.0)
    return e * rel


def osc_phase(freq, n):
    """Phase (radians) for a constant or per-sample frequency."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    return 2 * np.pi * np.cumsum(f) / SR


def noise(n, rng):
    return rng.uniform(-1.0, 1.0, n)


# --- Instruments ---------------------------------------------------------------------------------

def upright_bass(m, dur, vel=1.0, rng=None):
    """Plucked upright bass: warm fundamental, faster-dying overtones, a little pitch sag on the
    pluck and a soft finger thump."""
    rng = rng or np.random.default_rng(0)
    f = midi_hz(m)
    n = int((dur + 0.12) * SR)
    t = secs(n)
    pitch = f * (1.0 + 0.01 * np.exp(-t * 25))
    ph = osc_phase(pitch, n)
    amps = [0.9, 0.85, 0.6, 0.45, 0.32, 0.22, 0.15, 0.1, 0.07]
    y = np.zeros(n)
    for k, a in enumerate(amps, start=1):
        if f * k > 3000:
            break
        y += a * np.sin(k * ph + 0.3 * k) * np.exp(-t * (1.5 + 1.3 * k))
    y += 0.25 * np.sin(ph) * np.exp(-t * 0.8)  # body sustain
    thump = band(noise(int(0.03 * SR), rng), 60, 700) * np.exp(-secs(int(0.03 * SR)) * 120)
    y[: len(thump)] += 0.5 * thump
    y *= adsr(n, a=0.004, r=0.07, hold=dur)
    return band(y, 38, 2500) * vel


def rhodes(m, dur, vel=0.7):
    """Two-operator FM electric piano (1:1 bark that softens as it decays) plus a short 14:1 tine."""
    f = midi_hz(m)
    n = int((dur + 0.5) * SR)
    t = secs(n)
    ph = osc_phase(f, n)
    index = (1.3 * vel + 0.35) * np.exp(-t * 2.0) + 0.2
    body = np.sin(ph + index * np.sin(ph))
    tine = np.sin(14 * ph + 0.6 * np.sin(ph)) * np.exp(-t * 28) * 0.18 * vel
    env = np.exp(-t * (0.9 + f / 900.0)) * adsr(n, a=0.002, r=0.18, hold=dur)
    return (body + tine) * env * (0.35 + 0.65 * vel)


def vibes(m, dur, vel=0.8, motor=5.2):
    """Vibraphone bar: partials 1, 3.93, 9.54 (soft mallet), slow decay, motor tremolo."""
    f = midi_hz(m)
    n = int((dur + 1.2) * SR)
    t = secs(n)
    ph = osc_phase(f, n)
    y = np.sin(ph) * np.exp(-t * 1.1)
    y += 0.3 * vel * np.sin(3.93 * ph) * np.exp(-t * 3.5)
    y += 0.08 * vel * np.sin(9.54 * ph) * np.exp(-t * 12.0)
    y += 0.1 * vel * np.sin(2.0 * ph) * np.exp(-t * 2.5)  # resonator tube
    trem = 1.0 - 0.28 * (0.5 - 0.5 * np.cos(2 * np.pi * motor * t))
    env = adsr(n, a=0.003, r=0.35, hold=dur + 0.4)
    return y * trem * env * vel


def kick(vel=0.6, rng=None):
    n = int(0.35 * SR)
    t = secs(n)
    f = 52 + 70 * np.exp(-t * 35)
    y = np.sin(osc_phase(f, n)) * np.exp(-t * 9)
    y[: int(0.004 * SR)] += 0.3 * np.sin(osc_phase(900, int(0.004 * SR)))  # felt beater click
    return y * vel


def brush_tap(vel=0.6, rng=None):
    """Brush hitting the snare head: a soft crisp burst with a little drum body."""
    rng = rng or np.random.default_rng(1)
    n = int(0.22 * SR)
    t = secs(n)
    y = band(noise(n, rng), 900, 7000) * np.exp(-t * 26)
    y += 0.25 * np.sin(osc_phase(190, n)) * np.exp(-t * 30)
    return y * vel * 0.8


def brush_swish(beats, beat_s, rng, level=0.12):
    """Continuous circular brush stroke: filtered noise swelling across each two-beat sweep."""
    n = int(beats * beat_s * SR)
    t = secs(n)
    x = band(noise(n, rng), 1200, 6500)
    sweep = 0.5 - 0.5 * np.cos(2 * np.pi * t / (2 * beat_s))
    return x * (0.25 + 0.75 * sweep ** 1.5) * level


def ride(vel=0.5, rng=None, length=1.4):
    """Ride cymbal: inharmonic metallic partials over a high noise wash, gently darkened."""
    rng = rng or np.random.default_rng(2)
    n = int(length * SR)
    t = secs(n)
    y = band(noise(n, rng), 3000, 8500) * np.exp(-t * 5.5) * 0.6
    for fr, a, d in [(2953, 0.10, 3.0), (3721, 0.08, 3.6), (4417, 0.07, 4.0), (5310, 0.05, 5.0), (6870, 0.04, 6.0)]:
        y += a * np.sin(osc_phase(fr * (1 + 0.0004 * rng.standard_normal()), n)) * np.exp(-t * d)
    stick = band(noise(n, rng), 2000, 6000) * np.exp(-t * 90) * 0.5
    return (y + stick) * vel * 2.2


def hat_chick(vel=0.4, rng=None):
    rng = rng or np.random.default_rng(3)
    n = int(0.07 * SR)
    t = secs(n)
    return band(noise(n, rng), 5000, 12000) * np.exp(-t * 70) * vel * 3.5


def woodblock(m=84, vel=0.5):
    n = int(0.12 * SR)
    t = secs(n)
    f = midi_hz(m)
    y = np.sin(osc_phase(f, n)) * np.exp(-t * 45) + 0.4 * np.sin(osc_phase(f * 2.7, n)) * np.exp(-t * 70)
    return y * vel


def bell(f, dur, vel=0.7, bright=1.0):
    """Struck bell: classic inharmonic partial set (hum, prime, tierce, quint, nominal...)."""
    n = int(dur * SR)
    t = secs(n)
    y = np.zeros(n)
    for ratio, a, d in [(0.5, 0.35, 0.9), (1.0, 1.0, 1.4), (1.19, 0.45, 2.0), (1.5, 0.3, 2.4), (2.0, 0.5, 2.6), (2.52, 0.25 * bright, 4.0), (3.0, 0.15 * bright, 5.0), (4.07, 0.08 * bright, 7.0)]:
        if f * ratio < SR / 2.2:
            y += a * np.sin(osc_phase(f * ratio, n) + ratio) * np.exp(-t * d)
    y *= adsr(n, a=0.001, r=0.05)
    return y * vel * 0.4


# --- Mixing --------------------------------------------------------------------------------------

def place(buf, x, at_s, gain=1.0, pan=0.0):
    """Adds mono `x` into stereo `buf` (2, N) at `at_s` seconds with constant-power `pan` (-1..1)."""
    i = int(round(at_s * SR))
    if i >= buf.shape[1] or i + len(x) <= 0:
        return
    if i < 0:
        x = x[-i:]
        i = 0
    j = min(buf.shape[1], i + len(x))
    seg = x[: j - i] * gain
    a = (pan + 1.0) * np.pi / 4.0
    buf[0, i:j] += seg * np.cos(a)
    buf[1, i:j] += seg * np.sin(a)


def reverb_ir(seconds=1.6, seed=7, predelay=0.018, darkness=4500):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = secs(n)
    irs = []
    for ch in range(2):
        x = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
        x = band(x, 180, darkness)
        x = np.concatenate([np.zeros(int(predelay * SR)), x])
        x /= np.sqrt(np.sum(x ** 2))
        irs.append(x)
    return irs


def circular_reverb(buf, wet=0.2, seconds=1.6, darkness=4500):
    """Reverb on a loop buffer (2, N): circular convolution, so the tail wraps into the start."""
    n = buf.shape[1]
    out = np.empty_like(buf)
    for ch, ir in enumerate(reverb_ir(seconds, darkness=darkness)):
        h = np.zeros(n)
        h[: min(n, len(ir))] = ir[: min(n, len(ir))]
        w = np.fft.irfft(np.fft.rfft(buf[ch]) * np.fft.rfft(h), n)
        out[ch] = buf[ch] + wet * w
    return out


def reverb(x, wet=0.2, seconds=1.2, darkness=5000):
    """Mono → stereo reverb for one-shot SFX (zero-padded, tail kept)."""
    irs = reverb_ir(seconds, darkness=darkness)
    n = len(x) + len(irs[0])
    out = np.zeros((2, n))
    for ch, ir in enumerate(irs):
        out[ch, : len(x)] += x
        out[ch] += wet * np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    return out


def master(buf, rms_db=-20.0, peak_db=-1.0, drive=1.2):
    """Gentle tape-ish saturation, then level to `rms_db` with peaks kept under `peak_db`."""
    buf = buf - np.mean(buf, axis=-1, keepdims=True)
    rms = np.sqrt(np.mean(buf ** 2)) + 1e-12
    buf = buf * (db(rms_db + 4) / rms)
    buf = np.tanh(buf * drive) / drive
    rms = np.sqrt(np.mean(buf ** 2)) + 1e-12
    buf = buf * (db(rms_db) / rms)
    peak = np.max(np.abs(buf))
    if peak > db(peak_db):
        buf = buf * (db(peak_db) / peak)
    return buf


def fade(x, fin=0.003, fout=0.03):
    """Click-free edges for one-shots."""
    x = np.array(x, dtype=np.float64)
    n = x.shape[-1]
    a = min(n, int(fin * SR))
    b = min(n, int(fout * SR))
    if a:
        x[..., :a] *= np.linspace(0, 1, a)
    if b:
        x[..., n - b:] *= np.linspace(1, 0, b)
    return x


# --- Files ---------------------------------------------------------------------------------------

def write_wav(path, x, rate=SR):
    """16-bit WAV, mono for a 1-D array, stereo for (2, N)."""
    x = np.asarray(x)
    stereo = x.ndim == 2
    data = np.clip(x.T if stereo else x, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def write_ogg(path, x, quality=4):
    """Stereo Ogg Vorbis through ffmpeg (keeps the repo small)."""
    tmp = path + ".tmp.wav"
    write_wav(tmp, x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.remove(tmp)


def stats(x):
    """Peak/RMS (dBFS) and spectral centroid (Hz): a quick check that nothing is clipped or harsh."""
    m = x.mean(axis=0) if x.ndim == 2 else x
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    spec = np.abs(np.fft.rfft(m[: min(len(m), SR * 20)]))
    f = np.fft.rfftfreq(min(len(m), SR * 20), 1.0 / SR)
    centroid = float(np.sum(f * spec) / (np.sum(spec) + 1e-12))
    return "peak %.1f dB  rms %.1f dB  centroid %.0f Hz  %.1f s" % (peak, rms, centroid, x.shape[-1] / SR)
