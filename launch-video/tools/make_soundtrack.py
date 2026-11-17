"""Writes public/soundtrack.wav: an original track made from sine waves and noise by this script.
Nothing is sampled or copied, so it is free to use anywhere. Run: python3 tools/make_soundtrack.py"""
import math, random, struct, wave, os

RATE = 44100
LENGTH = 58.8
BPM = 110
BEAT = 60 / BPM
N = int(RATE * LENGTH)
left = [0.0] * N
right = [0.0] * N
random.seed(7)

def freq(semitones_from_a4):
    return 440 * 2 ** (semitones_from_a4 / 12)

def add(buffer_l, buffer_r, start, samples, pan=0.0):
    gl, gr = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
    i0 = int(start * RATE)
    for i, v in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            buffer_l[j] += v * gl
            buffer_r[j] += v * gr

def pad(f, dur, gain):
    n = int(dur * RATE); out = []
    attack, release = int(0.5 * RATE), int(0.8 * RATE)
    for i in range(n):
        t = i / RATE
        env = min(1, i / attack) * min(1, (n - i) / release)
        v = math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.004 * t) + 0.25 * math.sin(2 * math.pi * f * 2 * t)
        out.append(v * env * gain)
    return out

def pluck(f, dur, gain):
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 7) * min(1, i / 60)
        v = math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 2 * t) * math.exp(-t * 12) + 0.15 * math.sin(2 * math.pi * f * 3 * t) * math.exp(-t * 18)
        out.append(v * env * gain)
    return out

def bass(f, dur, gain):
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        env = min(1, i / 200) * math.exp(-t * 2.2)
        out.append((math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 2 * t)) * env * gain)
    return out

def kick(gain):
    n = int(0.28 * RATE); out = []; phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 48 + 110 * math.exp(-t * 28)
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * math.exp(-t * 11) * gain)
    return out

def hat(gain, decay=60):
    n = int(0.07 * RATE); out = []; prev = 0.0
    for i in range(n):
        noise = random.uniform(-1, 1)
        high = noise - prev; prev = noise
        out.append(high * math.exp(-(i / RATE) * decay) * gain)
    return out

def clap(gain):
    n = int(0.16 * RATE); out = []; prev = 0.0
    for i in range(n):
        t = i / RATE
        noise = random.uniform(-1, 1)
        band = 0.6 * noise + 0.4 * prev; prev = noise
        out.append(band * (math.exp(-t * 26) + 0.5 * math.exp(-max(0, t - 0.012) * 40)) * gain)
    return out

# Four chords, two bars each: A minor 9, F major 7, C major (add 9), G (add 4). Semitones from A4.
chords = [
    {"root": -24, "notes": [-12, -9, -5, -2, 2]},
    {"root": -28, "notes": [-16, -9, -5, -4, 0]},
    {"root": -21, "notes": [-9, -5, -2, 3, 5]},
    {"root": -26, "notes": [-14, -10, -7, -2, 0]},
]
BAR = BEAT * 4
bars = int(LENGTH / BAR) + 1
DRUMS_FROM, BREAK_FROM, BREAK_TO, END = 6.7, 48.4, 53.0, 56.5
KICK, HAT, CLAP = kick(0.55), hat(0.10), clap(0.16)

for bar in range(bars):
    t0 = bar * BAR
    chord = chords[(bar // 2) % 4]
    if bar % 2 == 0:
        for k, note in enumerate(chord["notes"][:4]):
            add(left, right, t0, pad(freq(note), BAR * 2 + 0.6, 0.045), pan=(k - 1.5) * 0.4)
    in_break = BREAK_FROM <= t0 < BREAK_TO
    drums = t0 >= DRUMS_FROM and not in_break and t0 < END
    arp = t0 >= 3.4 and t0 < END
    if t0 >= 3.4 and t0 < END:
        for beat in ([0, 2.5] if drums else [0]):
            add(left, right, t0 + beat * BEAT, bass(freq(chord["root"]), BEAT * 1.6, 0.22))
    if arp:
        pattern = [0, 2, 4, 2, 3, 1, 4, 2]
        for step in range(8):
            note = chord["notes"][pattern[step]] + (12 if step in (2, 6) else 0)
            gain = 0.07 if in_break else 0.10
            add(left, right, t0 + step * BEAT / 2, pluck(freq(note), 0.5, gain), pan=0.5 if step % 2 else -0.5)
    if drums:
        for beat in range(4):
            add(left, right, t0 + beat * BEAT, KICK)
            add(left, right, t0 + (beat + 0.5) * BEAT, HAT, pan=0.3)
            if beat in (1, 3):
                add(left, right, t0 + beat * BEAT, CLAP, pan=-0.1)

# Fade in, fade out, gentle limiter.
for i in range(N):
    t = i / RATE
    g = min(1, t / 0.4) * min(1, max(0, (LENGTH - t) / 2.2))
    left[i] = math.tanh(left[i] * g * 1.5)
    right[i] = math.tanh(right[i] * g * 1.5)

os.makedirs("public", exist_ok=True)
with wave.open("public/soundtrack.wav", "wb") as f:
    f.setnchannels(2); f.setsampwidth(2); f.setframerate(RATE)
    f.writeframes(b"".join(struct.pack("<hh", int(l * 30000), int(r * 30000)) for l, r in zip(left, right)))
print("wrote public/soundtrack.wav", round(LENGTH, 1), "s")
