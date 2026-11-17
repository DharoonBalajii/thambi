"""Writes public/soundtrack-v2.wav for the second cut (LaunchV2).

An original track built here from sine waves and noise: nothing is sampled, copied or
generated from anyone else's music, so it is free to use commercially.

Shaped like a modern SaaS launch film: a quiet, warm intro under the typed problem, soft
whooshes on the blur cuts, a riser into "Meet Thambi" where the beat comes in, a steady
uplifting groove through the features, a short break on "And", a softer privacy beat and a
final hit on the logo. It reads the scene lengths from src/v2/timeline.json so every cut lands.

Run: python3 tools/make_soundtrack_v2.py
"""
import json, math, os, random, struct, wave

RATE = 44100
FPS = 30
BPM = 116
BEAT = 60 / BPM
BAR = BEAT * 4
random.seed(11)

timeline = json.load(open(os.path.join(os.path.dirname(__file__), "..", "src", "v2", "timeline.json")))
starts, t = {}, 0
for scene in timeline:
    starts[scene["id"]] = t / FPS
    t += scene["frames"]
LENGTH = t / FPS + 0.2
N = int(RATE * LENGTH)
cuts = [starts[s["id"]] for s in timeline][1:]

MEET, AND, MORE, PRIVATE, LOGO = starts["meet"], starts["and"], starts["more"], starts["private"], starts["logo"]
# The bar grid is placed so a downbeat lands exactly on "Meet Thambi".
GRID0 = MEET - math.floor(MEET / BAR) * BAR

pads_l, pads_r = [0.0] * N, [0.0] * N
mix_l, mix_r = [0.0] * N, [0.0] * N


def freq(semitones_from_a4):
    return 440 * 2 ** (semitones_from_a4 / 12)


def add(bl, br, start, samples, pan=0.0):
    gl, gr = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
    i0 = int(start * RATE)
    for i, v in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            bl[j] += v * gl
            br[j] += v * gr


def pad(f, dur, gain):
    """Warm detuned pad: three slightly detuned sines with a slow swell."""
    n = int(dur * RATE); out = []
    attack, release = int(0.9 * RATE), int(1.2 * RATE)
    for i in range(n):
        t = i / RATE
        env = min(1, i / attack) * min(1, (n - i) / release)
        v = (math.sin(2 * math.pi * f * t) + 0.6 * math.sin(2 * math.pi * f * 1.0035 * t + 1.1)
             + 0.6 * math.sin(2 * math.pi * f * 0.9965 * t + 2.3) + 0.18 * math.sin(2 * math.pi * f * 2 * t))
        out.append(v * env * gain)
    return out


def keys(f, dur, gain):
    """Soft felt-piano-like note: quick attack, gentle decay, dull overtones."""
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 3.2) * min(1, i / 90)
        v = (math.sin(2 * math.pi * f * t) + 0.28 * math.sin(2 * math.pi * f * 2 * t) * math.exp(-t * 6)
             + 0.08 * math.sin(2 * math.pi * f * 3 * t) * math.exp(-t * 10))
        out.append(v * env * gain)
    return out


def pluck(f, dur, gain):
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 8) * min(1, i / 50)
        v = math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 2 * t) * math.exp(-t * 14)
        out.append(v * env * gain)
    return out


def bass(f, dur, gain):
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        env = min(1, i / 220) * min(1, (n - i) / 400) * (0.75 + 0.25 * math.exp(-t * 4))
        out.append((math.sin(2 * math.pi * f * t) + 0.22 * math.sin(2 * math.pi * f * 2 * t)) * env * gain)
    return out


def kick(gain):
    n = int(0.3 * RATE); out = []; phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 46 + 120 * math.exp(-t * 30)
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * math.exp(-t * 9) * gain)
    return out


def noise_hit(dur, gain, decay, smooth=0.0, high=True):
    n = int(dur * RATE); out = []; prev = 0.0; lp = 0.0
    for i in range(n):
        x = random.uniform(-1, 1)
        lp = lp * smooth + x * (1 - smooth)
        v = (lp - prev) if high else lp
        prev = lp
        out.append(v * math.exp(-(i / RATE) * decay) * gain)
    return out


def clap(gain):
    n = int(0.18 * RATE); out = []; prev = 0.0
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1)
        v = 0.6 * x + 0.4 * prev; prev = x
        out.append(v * (math.exp(-t * 24) + 0.5 * math.exp(-max(0, t - 0.011) * 38) + 0.35 * math.exp(-max(0, t - 0.022) * 40)) * gain)
    return out


def whoosh(dur, gain, rising=True):
    """Filtered noise that swells (or falls) — the sound of a blur cut."""
    n = int(dur * RATE); out = []; lp = 0.0
    for i in range(n):
        x = i / n
        shape = math.sin(math.pi * x) ** 2 if not rising else x ** 2.2
        cutoff = 0.04 + 0.5 * (x if rising else 1 - x)
        lp += cutoff * (random.uniform(-1, 1) - lp)
        out.append(lp * shape * gain)
    return out


def boom(gain):
    n = int(1.6 * RATE); out = []; phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 38 + 60 * math.exp(-t * 6)
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * math.exp(-t * 2.4) * gain)
    return out


# D major, uplifting: Dmaj9, Bm9, Gmaj9 (#11 colour), A6sus. Semitones from A4.
chords = [
    {"root": -31, "notes": [-19, -15, -12, -8, -5]},   # D3 F#3 A3 C#4 E4
    {"root": -34, "notes": [-22, -19, -15, -12, -8]},  # B2 D3 F#3 A3 C#4
    {"root": -38, "notes": [-26, -22, -19, -15, -10]}, # G2 B2 D3 F#3 B3
    {"root": -36, "notes": [-24, -19, -17, -12, -10]}, # A2 D3 E3 A3 B3
]

KICK, CLAP = kick(0.62), clap(0.15)
SHAKER = noise_hit(0.05, 0.05, 90)
OPEN_HAT = noise_hit(0.22, 0.05, 18)

def section(t):
    """How much of the band plays at time t."""
    if t < MEET: return "intro"
    if AND <= t < MORE: return "break"
    if PRIVATE <= t < starts["contrast"]: return "soft"
    if t >= LOGO + BAR: return "outro"
    return "full"

# Intro: pads on the first chord pair and a few soft piano notes, before the grid starts.
intro_bars = int(math.ceil(MEET / BAR)) + 1
bars = int(LENGTH / BAR) + 2
for bar in range(-intro_bars, bars):
    t0 = GRID0 + bar * BAR
    if t0 > LENGTH: break
    chord = chords[bar % 4]
    sec = section(max(0.0, t0))
    if t0 + BAR * 1.5 < 0:
        continue
    # Pads, one chord per bar, slightly wider in the full sections.
    pad_gain = {"intro": 0.032, "break": 0.04, "soft": 0.036, "full": 0.034, "outro": 0.04}[sec]
    for k_, note in enumerate(chord["notes"][:4]):
        add(pads_l, pads_r, max(0.0, t0), pad(freq(note), BAR + 1.3, pad_gain), pan=(k_ - 1.5) * 0.45)
    if sec == "outro":
        continue
    # Piano: sparse in the intro, a two-note motif otherwise.
    if sec in ("intro", "soft", "break"):
        for step, idx in ((0, 4), (1.5, 2), (2.5, 3)):
            tt = t0 + step * BEAT
            if tt >= 0.6:
                add(mix_l, mix_r, tt, keys(freq(chord["notes"][idx] + 12), 1.8, 0.07), pan=-0.2 + 0.2 * step)
    # Arpeggio of plucks in the groove.
    if sec in ("full", "soft"):
        pattern = [0, 2, 4, 2, 3, 4, 2, 1]
        for step in range(8):
            note = chord["notes"][pattern[step]] + 12 + (12 if step in (2, 5) else 0)
            add(mix_l, mix_r, t0 + step * BEAT / 2, pluck(freq(note), 0.45, 0.075 if sec == "full" else 0.06), pan=0.45 if step % 2 else -0.45)
    # Bass: root on the one, syncopated push before beat three.
    if sec == "full":
        for beat, length in ((0, 1.4), (1.5, 0.45), (2, 1.4), (3.5, 0.45)):
            add(mix_l, mix_r, t0 + beat * BEAT, bass(freq(chord["root"]), BEAT * length, 0.24))
    elif sec in ("soft", "break"):
        add(mix_l, mix_r, t0, bass(freq(chord["root"]), BAR * 0.95, 0.15))
    # Drums.
    if sec == "full":
        for beat in range(4):
            add(mix_l, mix_r, t0 + beat * BEAT, KICK)
            if beat in (1, 3):
                add(mix_l, mix_r, t0 + beat * BEAT, CLAP, pan=-0.08)
            add(mix_l, mix_r, t0 + (beat + 0.5) * BEAT, OPEN_HAT if beat == 3 else SHAKER, pan=0.3)
            for sixteenth in (0.25, 0.75):
                add(mix_l, mix_r, t0 + (beat + sixteenth) * BEAT, SHAKER, pan=0.4)
    elif sec == "soft":
        for beat in (0, 2):
            add(mix_l, mix_r, t0 + beat * BEAT, kick(0.32))

# Sound design on the cuts: a soft whoosh into every scene, bigger moments get a riser and a hit.
for cut in cuts:
    if cut in (MEET, MORE, LOGO):
        continue
    add(mix_l, mix_r, cut - 0.32, whoosh(0.55, 0.11, rising=False), pan=random.uniform(-0.4, 0.4))
for moment, riser in ((MEET, 1.9), (MORE, 1.5), (LOGO, 1.9)):
    add(mix_l, mix_r, moment - riser, whoosh(riser, 0.22, rising=True), pan=0)
    add(mix_l, mix_r, moment, boom(0.5))
    add(mix_l, mix_r, moment, noise_hit(1.4, 0.10, 3.2, smooth=0.55), pan=0.15)
# The final hit's tail: a held D major chord under the logo and the call to action.
for k_, note in enumerate([-19, -15, -12, -7, -3]):
    add(pads_l, pads_r, LOGO, pad(freq(note), LENGTH - LOGO, 0.03), pan=(k_ - 2) * 0.35)
    add(mix_l, mix_r, LOGO, keys(freq(note + 12), 3.5, 0.06), pan=(k_ - 2) * 0.3)

# Sidechain: the pads breathe out of the way of every kick in the groove.
def duck(t):
    if section(t) != "full":
        return 1.0
    since = (t - GRID0) % BEAT
    return 0.45 + 0.55 * min(1, since / (BEAT * 0.55))

for i in range(N):
    tt = i / RATE
    d = duck(tt)
    g = min(1, tt / 0.8) * min(1, max(0, (LENGTH - tt) / 3.0))
    left = (mix_l[i] + pads_l[i] * d) * g
    right = (mix_r[i] + pads_r[i] * d) * g
    mix_l[i] = math.tanh(left * 2.3)
    mix_r[i] = math.tanh(right * 2.3)

out = os.path.join(os.path.dirname(__file__), "..", "public", "soundtrack-v2.wav")
with wave.open(out, "wb") as f:
    f.setnchannels(2); f.setsampwidth(2); f.setframerate(RATE)
    f.writeframes(b"".join(struct.pack("<hh", int(l * 30000), int(r * 30000)) for l, r in zip(mix_l, mix_r)))
print("wrote public/soundtrack-v2.wav", round(LENGTH, 1), "s; beat enters at", round(MEET, 2), "s")
