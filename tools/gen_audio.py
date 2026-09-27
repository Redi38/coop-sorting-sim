"""Generates the placeholder sounds and music loop in assets/audio/.

Run:  python3 tools/gen_audio.py
Everything is synthesized (sines, bells, filtered noise), so it's
license-free and reproducible. Replace any WAV with a recorded sound of the
same name and the game picks it up (see autoload/Sfx.gd).
Style: soft, warm, never harsh (DESIGN.md pillar 3 "gentle").
"""
import math
import os
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
SR = 44100
rng = np.random.default_rng(38)


def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env(t, attack=0.004, tau=0.2):
    """Soft attack, exponential decay."""
    a = np.clip(t / attack, 0, 1) if attack > 0 else 1.0
    return a * np.exp(-t / tau)


def bell(freq, dur, tau=0.4, bright=1.0, sr=SR):
    """Warm bell: a few partials, higher ones decaying faster."""
    t = t_axis(dur, sr)
    partials = [(1.0, 1.0, 1.0), (2.0, 0.45 * bright, 0.6), (3.0, 0.2 * bright, 0.4),
                (4.2, 0.08 * bright, 0.25), (5.4, 0.04 * bright, 0.18)]
    y = np.zeros_like(t)
    for ratio, amp, tau_mul in partials:
        y += amp * np.sin(2 * np.pi * freq * ratio * t) * env(t, 0.003, tau * tau_mul)
    return y


def one_pole_lowpass(x, cutoff, sr=SR):
    """cutoff may be a scalar or a per-sample array (time-varying)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = np.exp(-2 * np.pi * cutoff / sr)
    y = np.zeros_like(x)
    prev = 0.0
    for i in range(len(x)):
        prev = (1 - a[i]) * x[i] + a[i] * prev
        y[i] = prev
    return y


def place(buf, clip, at, sr=SR):
    i = int(at * sr)
    n = min(len(clip), len(buf) - i)
    buf[i:i + n] += clip[:n]


def finish(y, peak_db=-3.0, fade=0.006, sr=SR):
    y = y - np.mean(y)
    n = int(fade * sr)
    if n > 0 and len(y) > 2 * n:
        ramp = np.linspace(0, 1, n)
        y[:n] *= ramp
        y[-n:] *= ramp[::-1]
    peak = np.max(np.abs(y)) or 1.0
    return y / peak * (10 ** (peak_db / 20))


def write(name, y, sr=SR, peak_db=-3.0):
    y = finish(np.asarray(y, dtype=float), peak_db, sr=sr)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((y * 32767).astype("<i2").tobytes())
    rms = 20 * math.log10(np.sqrt(np.mean(y ** 2)) + 1e-9)
    print(f"wrote {name}.wav  {len(y) / sr:.2f}s  rms {rms:.1f} dBFS")


os.makedirs(OUT, exist_ok=True)

# --- pickup: soft rising "bloop" + a whisper of cloth
t = t_axis(0.2)
f = 520 * (1.5 ** np.clip(t / 0.06, 0, 1))
y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.003, 0.05)
noise = one_pole_lowpass(rng.normal(size=len(t)), 2500) * env(t, 0.001, 0.015) * 0.6
write("pickup", y + noise, peak_db=-6)

# --- release (drop / put down): small wooden "tock"
t = t_axis(0.25)
y = (np.sin(2 * np.pi * 210 * t) + 0.3 * np.sin(2 * np.pi * 430 * t)) * env(t, 0.001, 0.045)
click = one_pole_lowpass(rng.normal(size=len(t)), 1800) * env(t, 0.0005, 0.008) * 1.5
write("release", y + click, peak_db=-7)

# --- place correct: warm two-note chime (E5 -> B5)
buf = np.zeros(int(1.0 * SR))
place(buf, bell(659.25, 0.95, tau=0.35), 0.0)
place(buf, bell(987.77, 0.9, tau=0.4) * 0.8, 0.09)
write("place_correct", buf, peak_db=-5)

# --- place wrong: gentle muted "uh-oh" (A3 -> F3), marimba-ish
def marimba(freq, dur):
    t = t_axis(dur)
    return (np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 4 * t) * env(t, 0.001, 0.03)) * env(t, 0.002, 0.13)
buf = np.zeros(int(0.55 * SR))
place(buf, marimba(220.0, 0.4), 0.0)
place(buf, marimba(174.61, 0.45), 0.12)
write("place_wrong", buf, peak_db=-8)

# --- toss: airy whoosh (noise through a sweeping low-pass, hump envelope)
t = t_axis(0.38)
hump = np.sin(np.pi * np.clip(t / 0.38, 0, 1)) ** 2
cut = 500 + 2200 * np.sin(np.pi * np.clip(t / 0.38, 0, 1))
n = rng.normal(size=len(t))
y = one_pole_lowpass(n, cut) - 0.6 * one_pole_lowpass(n, 250)
write("toss", y * hump, peak_db=-9)

# --- ping: one bright soft bell with an octave shimmer
buf = np.zeros(int(0.9 * SR))
place(buf, bell(880.0, 0.85, tau=0.3, bright=0.7), 0.0)
place(buf, bell(1760.0, 0.6, tau=0.18, bright=0.3) * 0.25, 0.015)
write("ping", buf, peak_db=-7)

# --- ui click: tiny soft tick
t = t_axis(0.06)
y = np.sin(2 * np.pi * 1400 * t) * env(t, 0.0005, 0.008)
write("click", y, peak_db=-12)

# --- category complete: C5 E5 G5 C6 arpeggio
buf = np.zeros(int(1.4 * SR))
for i, f0 in enumerate([523.25, 659.25, 783.99, 1046.5]):
    place(buf, bell(f0, 1.0, tau=0.45) * (0.8 + 0.07 * i), i * 0.09)
write("category_complete", buf, peak_db=-5)

# --- round complete: two-octave arpeggio + a soft chord swell
buf = np.zeros(int(3.4 * SR))
notes = [261.63, 329.63, 392.0, 523.25, 659.25, 783.99, 1046.5]
for i, f0 in enumerate(notes):
    place(buf, bell(f0, 1.6, tau=0.6) * 0.7, i * 0.1)
t = t_axis(3.4)
swell = np.clip((t - 0.5) / 0.8, 0, 1) * np.exp(-np.clip(t - 1.3, 0, None) / 0.9)
chord = sum(np.sin(2 * np.pi * f0 * t) * a for f0, a in [(261.63, 1), (329.63, 0.8), (392.0, 0.7), (523.25, 0.4)])
buf += one_pole_lowpass(chord, 1800) * swell * 0.35
write("round_complete", buf, peak_db=-4)

# --- ambient music loop: slow pad chords + sparse music-box notes (seamless)
MSR = 22050
LOOP = 48.0
N = int(LOOP * MSR)
t = np.arange(N) / MSR
chords = [  # Cmaj7, Am7, Fmaj7, G6 — 12 s each
    [130.81, 196.0, 246.94, 329.63],
    [110.0, 164.81, 196.0, 261.63],
    [87.31, 174.61, 220.0, 329.63],
    [98.0, 146.83, 196.0, 329.63],
]
seg = LOOP / len(chords)
pad = np.zeros(N)
for ci, chord in enumerate(chords):
    center = (ci + 0.5) * seg
    # periodic distance to the chord's centre, so the last chord crossfades
    # into the first across the loop point
    d = np.abs(((t - center + LOOP / 2) % LOOP) - LOOP / 2)
    w = np.clip(1 - (d - seg * 0.35) / (seg * 0.3), 0, 1)
    w = 0.5 - 0.5 * np.cos(np.pi * w)
    for k, f0 in enumerate(chord):
        # frequencies rounded to whole cycles per loop keep the loop seamless
        f_loop = round(f0 * LOOP) / LOOP
        f_det = round(f0 * 1.003 * LOOP) / LOOP
        trem = 1 + 0.15 * np.sin(2 * np.pi * (k + 1) / LOOP * 3 * t)
        pad += w * trem * (np.sin(2 * np.pi * f_loop * t) + 0.5 * np.sin(2 * np.pi * f_det * t)) / (k + 1.5)
# Filter two copies back to back and keep the second: the filter then
# starts in its steady state, so the loop point has no click.
pad = one_pole_lowpass(np.concatenate([pad, pad]), 900, sr=MSR)[N:]
melody = np.zeros(N + MSR * 3)
penta = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
tm = 1.0
while tm < LOOP - 0.5:
    f0 = penta[rng.integers(0, len(penta))]
    note = bell(f0, 2.5, tau=0.55, bright=0.5, sr=MSR) * rng.uniform(0.35, 0.7)
    i = int(tm * MSR)
    melody[i:i + len(note)] += note
    tm += rng.uniform(1.3, 3.2)
melody[:MSR * 3] += melody[N:N + MSR * 3]   # wrap tails over the loop point
melody = melody[:N]
music = 0.55 * pad / (np.max(np.abs(pad)) or 1) + 0.45 * melody / (np.max(np.abs(melody)) or 1)
# no fade here: the loop must be seamless
y = music - np.mean(music)
y = y / np.max(np.abs(y)) * 10 ** (-6 / 20)
with wave.open(os.path.join(OUT, "music_loop.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(MSR)
    w.writeframes((y * 32767).astype("<i2").tobytes())
typical = np.percentile(np.abs(np.diff(y)), 99)
print(f"wrote music_loop.wav  {LOOP:.0f}s (seamless loop)  loop-point step {abs(y[0] - y[-1]):.4f} vs 99th-pct step {typical:.4f}")
