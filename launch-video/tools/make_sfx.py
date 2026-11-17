"""Writes public/sfx-v4.wav: the sound effects for LaunchV2, to play over the music.

Every sound is synthesised here from oscillators and noise (nothing sampled or downloaded):
key clicks for typed text, the Control + Option press, Enter, mouse clicks, marker strokes as
Thambi draws, the sweep while it reads the screen, pops, a chime and soft whooshes on the cuts.
Times come from src/v2/timeline.json, so each sound lands on its frame.
Run: python3 tools/make_sfx.py
"""
import json, math, os, random, struct, wave

RATE = 44100
FPS = 30
random.seed(7)
here = os.path.dirname(os.path.abspath(__file__))
timeline = json.load(open(os.path.join(here, "..", "src", "v2", "timeline.json")))
starts, frame = {}, 0
for scene in timeline:
    starts[scene["id"]] = frame / FPS
    frame += scene["frames"]
LENGTH = frame / FPS
N = int(LENGTH * RATE)
L, R = [0.0] * N, [0.0] * N

def add(start, samples, gain=1.0, pan=0.0):
    gl, gr = math.cos((pan + 1) * math.pi / 4) * gain, math.sin((pan + 1) * math.pi / 4) * gain
    i0 = int(start * RATE)
    for i, v in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            L[j] += v * gl
            R[j] += v * gr

def coef(cutoff):
    return 1 - math.exp(-2 * math.pi * cutoff / RATE)

def key_click():
    pitch = random.uniform(0.85, 1.2)
    n = int(0.03 * RATE); y = 0.0; out = []
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1); y += 0.55 * (x - y)
        out.append((x - y) * math.exp(-t * 420) * 0.9 + math.sin(2 * math.pi * 210 * pitch * t) * math.exp(-t * 160) * 0.7)
    return out

def thock(freq=120, length=0.09):
    n = int(length * RATE); y = 0.0; out = []
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1); y += 0.4 * (x - y)
        out.append((x - y) * math.exp(-t * 200) + math.sin(2 * math.pi * freq * t) * math.exp(-t * 55) * 1.2)
    return out

def mouse_click():
    out = [0.0] * int(0.09 * RATE)
    for start, g in ((0, 1.0), (int(0.065 * RATE), 0.6)):
        for i in range(int(0.012 * RATE)):
            t = i / RATE
            out[start + i] += (random.uniform(-1, 1) * 0.5 + math.sin(2 * math.pi * 3200 * t)) * math.exp(-t * 700) * g
    return out

def pop():
    n = int(0.12 * RATE); out = []; ph = 0.0
    for i in range(n):
        t = i / RATE
        ph += 2 * math.pi * (500 + 1600 * min(1, t / 0.05)) / RATE
        out.append(math.sin(ph) * math.exp(-t * 38))
    return out

def tone(f, dur, decay, partials=((1, 1.0),)):
    n = int(dur * RATE)
    return [sum(g * math.sin(2 * math.pi * f * m * i / RATE) for m, g in partials) * math.exp(-i / RATE * decay) * min(1, i / 40) for i in range(n)]

def marker(dur):
    """A felt-tip stroke: band-limited noise with a little wobble in pressure."""
    n = int(dur * RATE); out = []; lo = hi = 0.0
    a_lo, a_hi = coef(5200), coef(900)
    for i in range(n):
        x = i / n
        v = random.uniform(-1, 1)
        lo += a_lo * (v - lo); hi += a_hi * (lo - hi)
        band = lo - hi
        env = min(1, x * 12) * min(1, (1 - x) * 6) * (0.75 + 0.25 * math.sin(i / RATE * 2 * math.pi * 9))
        out.append(band * env)
    return out

def scan(dur):
    """Reading the screen: a soft rising tone with a shimmer."""
    n = int(dur * RATE); out = []; ph = ph2 = 0.0
    for i in range(n):
        x = i / n
        ph += 2 * math.pi * (420 + 900 * x) / RATE
        ph2 += 2 * math.pi * (1260 + 2700 * x) / RATE
        env = math.sin(math.pi * x) ** 1.5
        out.append((math.sin(ph) * 0.6 + math.sin(ph2) * 0.15 * (0.5 + 0.5 * math.sin(i / RATE * 60))) * env)
    return out

def whoosh(dur):
    n = int(dur * RATE); out = []; y = 0.0
    for i in range(n):
        x = i / n
        y += coef(400 + 5000 * (1 - x)) * (random.uniform(-1, 1) - y)
        out.append(y * math.sin(math.pi * min(1, x * 1.4)) ** 2 * (1 - x) ** 0.5)
    return out

for scene in timeline:
    s0 = starts[scene["id"]]
    for ev in scene.get("sfx", []):
        at = s0 + ev["at"] / FPS
        kind = ev["type"]
        if kind == "typing":
            for c in range(ev["chars"]):
                if ev["rate"] > 1.6 and c % 2:
                    continue
                add(at + c / ev["rate"] / FPS + random.uniform(-0.006, 0.006), key_click(), random.uniform(0.32, 0.45), pan=random.uniform(-0.15, 0.15))
        elif kind == "keys":
            add(at, thock(110, 0.1), 0.55, pan=-0.15)
            add(at + 0.03, thock(135, 0.1), 0.5, pan=0.15)
        elif kind == "enter":
            add(at, thock(), 0.6)
        elif kind == "click":
            add(at, mouse_click(), 0.4, pan=0.2)
        elif kind == "pop":
            add(at, pop(), 0.38)
            for j in range(6):
                add(at + 0.03 + j * 0.05 + random.uniform(0, 0.03), tone(random.uniform(2400, 4200), 0.25, 18), 0.06, pan=random.uniform(-0.7, 0.7))
        elif kind == "chime":
            for j, f in enumerate((1318.5, 1975.5)):
                add(at + j * 0.08, tone(f, 1.2, 4.5, ((1, 1.0), (2.76, 0.2))), 0.14, pan=-0.2 + 0.4 * j)
        elif kind == "draw":
            add(at, marker(ev["len"] / FPS), 0.32, pan=random.uniform(-0.3, 0.3))
        elif kind == "scan":
            add(at, scan(22 / FPS), 0.2)
        elif kind == "swish":
            add(at - 0.05, whoosh(0.35), 0.25, pan=0.2)

# A soft whoosh into every scene.
for scene in timeline[1:]:
    add(starts[scene["id"]] - 0.18, whoosh(0.36), 0.16, pan=random.uniform(-0.3, 0.3))

# Lift everything about 5 dB so it reads over the music, with a soft limiter on the loudest hits.
L = [math.tanh(v * 1.8) for v in L]
R = [math.tanh(v * 1.8) for v in R]
peak = max(max(abs(v) for v in L), max(abs(v) for v in R), 1e-9)
scale = min(1.0, 0.95 / peak)
out = os.path.join(here, "..", "public", "sfx-v4.wav")
with wave.open(out, "wb") as f:
    f.setnchannels(2); f.setsampwidth(2); f.setframerate(RATE)
    f.writeframes(b"".join(struct.pack("<hh", int(l * scale * 32767), int(r * scale * 32767)) for l, r in zip(L, R)))
print("wrote public/sfx-v4.wav", round(LENGTH, 2), "s, peak", round(peak, 2))
