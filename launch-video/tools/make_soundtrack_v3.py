"""Writes public/soundtrack-v3.wav for the 60 second cut (LaunchV2).

An original track and sound design, synthesised from scratch by this script: oscillators,
filtered noise, a delay and a reverb, all written here. Nothing is sampled, copied, downloaded
or generated from anyone else's recording, so it is free to use commercially.

120 BPM, A minor, a modern launch-film groove: a sparse intro under the typing, a hit on "Stop",
a riser and a drop on "Meet Thambi", a four-on-the-floor beat with a pumping bass, syncopated
chord stabs and a lead hook through the features, a stop on "And" and a second drop, a quiet
breakdown for privacy, a build, and a final hit on the logo that resolves to C major.

It also places the sound effects the picture needs (key clicks for every typed character,
Enter, mouse clicks, pops, a chime, whooshes on the cuts) from src/v2/timeline.json, so every
sound lands on its frame. Run: python3 tools/make_soundtrack_v3.py
"""
import json, math, os, random, struct, wave

RATE = 44100
BPM = 120
BEAT = 60 / BPM
BAR = BEAT * 4
FPS = 30
random.seed(2026)

here = os.path.dirname(os.path.abspath(__file__))
timeline = json.load(open(os.path.join(here, "..", "src", "v2", "timeline.json")))
starts, frame = {}, 0
for scene in timeline:
    starts[scene["id"]] = frame / FPS
    frame += scene["frames"]
LENGTH = frame / FPS + 0.3
N = int(LENGTH * RATE)

def buf():
    return [0.0] * N

dry_l, dry_r = buf(), buf()        # drums and anything that does not pump
pump_l, pump_r = buf(), buf()      # bass, stabs, pads: ducked by the kick
lead = buf()                       # mono lead, sent through the delay
rev = buf()                        # mono reverb send
sfx_l, sfx_r = buf(), buf()

def add(bl, br, start, samples, gain=1.0, pan=0.0, send=0.0):
    gl, gr = math.cos((pan + 1) * math.pi / 4) * gain, math.sin((pan + 1) * math.pi / 4) * gain
    i0 = int(start * RATE)
    for i, v in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            bl[j] += v * gl
            br[j] += v * gr
            if send:
                rev[j] += v * gain * send

def add_mono(target, start, samples, gain=1.0, send=0.0):
    i0 = int(start * RATE)
    for i, v in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            target[j] += v * gain
            if send:
                rev[j] += v * gain * send

def hz(semitones_from_a4):
    return 440.0 * 2 ** (semitones_from_a4 / 12)

def coef(cutoff):
    return 1 - math.exp(-2 * math.pi * min(cutoff, 18000) / RATE)

# ---------------------------------------------------------------- instruments

def saw_voice(f, dur, cut_from, cut_to, decay, attack=0.004, detune=(-12, 0, 12)):
    n = int(dur * RATE); out = []
    ratios = [2 ** (c / 1200) for c in detune]
    phases = [random.random() for _ in ratios]
    y1 = y2 = 0.0
    for i in range(n):
        t = i / RATE
        v = 0.0
        for k, r in enumerate(ratios):
            phases[k] = (phases[k] + f * r / RATE) % 1.0
            v += 2 * phases[k] - 1
        v /= len(ratios)
        a = coef(cut_to + (cut_from - cut_to) * math.exp(-t * 14))
        y1 += a * (v - y1); y2 += a * (y1 - y2)
        env = min(1, t / attack) * math.exp(-t * decay) * min(1, (n - i) / 300)
        out.append(y2 * env)
    return out

def pad(f, dur, cutoff, attack=0.6):
    n = int(dur * RATE); out = []
    ratios = [2 ** (c / 1200) for c in (-9, -3, 4, 10)]
    phases = [random.random() for _ in ratios]
    y1 = y2 = 0.0; a = coef(cutoff)
    release = int(0.8 * RATE)
    for i in range(n):
        v = 0.0
        for k, r in enumerate(ratios):
            phases[k] = (phases[k] + f * r / RATE) % 1.0
            v += 2 * phases[k] - 1
        y1 += a * (v / 4 - y1); y2 += a * (y1 - y2)
        out.append(y2 * min(1, i / (attack * RATE)) * min(1, (n - i) / release))
    return out

def bass(f, dur):
    n = int(dur * RATE); out = []
    ph = 0.0; y1 = y2 = 0.0
    for i in range(n):
        t = i / RATE
        ph = (ph + f / RATE) % 1.0
        saw = 2 * ph - 1
        a = coef(260 + 900 * math.exp(-t * 22))
        y1 += a * (saw - y1); y2 += a * (y1 - y2)
        sub = math.sin(2 * math.pi * ph)
        env = min(1, i / 120) * min(1, (n - i) / 260)
        out.append((0.8 * y2 + 0.45 * sub) * env)
    return out

def lead_note(f, dur):
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        bright = math.exp(-t * 9)
        w = 2 * math.pi * f * t
        v = math.sin(w) + (0.33 * math.sin(3 * w) + 0.18 * math.sin(5 * w)) * bright + 0.25 * math.sin(2 * w) * bright
        out.append(v * min(1, t / 0.004) * math.exp(-t * 4.2) * min(1, (n - i) / 250))
    return out

def keys(f, dur):
    n = int(dur * RATE); out = []
    for i in range(n):
        t = i / RATE
        w = 2 * math.pi * f * t
        v = math.sin(w) + 0.3 * math.sin(2 * w) * math.exp(-t * 5) + 0.1 * math.sin(3 * w) * math.exp(-t * 9)
        out.append(v * min(1, i / 80) * math.exp(-t * 2.6))
    return out

def kick(gain=1.0):
    n = int(0.42 * RATE); out = []; ph = 0.0
    for i in range(n):
        t = i / RATE
        f = 47 + 125 * math.exp(-t * 34)
        ph += 2 * math.pi * f / RATE
        body = math.sin(ph) * math.exp(-t * 6.2)
        click = random.uniform(-1, 1) * math.exp(-t * 900) * 0.5
        out.append(math.tanh((body + click) * 1.6) * gain)
    return out

def noise(dur, decay, hp=0.0, lp=1.0, attack=0.0):
    n = int(dur * RATE); out = []; low = 0.0; y = 0.0
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1)
        low += hp * (x - low) if hp else 0.0
        x = x - low if hp else x
        y += lp * (x - y)
        env = (min(1, t / attack) if attack else 1.0) * math.exp(-t * decay)
        out.append(y * env)
    return out

def clap():
    n = int(0.25 * RATE); out = []; y = 0.0; low = 0.0
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1)
        low += 0.08 * (x - low); x -= low
        y += 0.5 * (x - y)
        env = sum(math.exp(-max(0, t - d) * 60) * (t >= d) for d in (0, 0.009, 0.018)) * 0.6 + math.exp(-max(0, t - 0.018) * 14) * (t >= 0.018)
        out.append(y * env)
    return out

def snare():
    n = int(0.2 * RATE); out = []; y = 0.0
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1)
        y += 0.45 * (x - y)
        out.append(math.sin(2 * math.pi * 190 * t) * math.exp(-t * 26) * 0.6 + y * math.exp(-t * 17))
    return out

def riser(dur):
    n = int(dur * RATE); out = []; y = 0.0; ph = 0.0
    for i in range(n):
        x = i / n
        y += coef(300 + 9000 * x ** 2) * (random.uniform(-1, 1) - y)
        ph += 2 * math.pi * (180 + 900 * x ** 2) / RATE
        out.append((y * 0.8 + math.sin(ph) * 0.18) * x ** 2.4)
    return out

def boom():
    n = int(2.2 * RATE); out = []; ph = 0.0
    for i in range(n):
        t = i / RATE
        ph += 2 * math.pi * (34 + 70 * math.exp(-t * 5)) / RATE
        out.append(math.sin(ph) * math.exp(-t * 1.9))
    return out

def whoosh(dur, rising=False):
    n = int(dur * RATE); out = []; y = 0.0
    for i in range(n):
        x = i / n
        shape = x ** 2 if rising else math.sin(math.pi * min(1, x * 1.4)) ** 2 * (1 - x) ** 0.5
        y += coef(400 + 5000 * (x if rising else 1 - x)) * (random.uniform(-1, 1) - y)
        out.append(y * shape)
    return out

def tone(f, dur, decay, partials=((1, 1.0),)):
    n = int(dur * RATE)
    return [sum(g * math.sin(2 * math.pi * f * m * i / RATE) for m, g in partials) * math.exp(-i / RATE * decay) * min(1, i / 40) for i in range(n)]

KICK, CLAP, SNARE = kick(), clap(), snare()
HAT = noise(0.06, 70, hp=0.35)
OPEN_HAT = noise(0.32, 9, hp=0.35)
SHAKER = noise(0.05, 95, hp=0.5, lp=0.6)
CRASH = noise(2.0, 2.1, hp=0.25)

# ---------------------------------------------------------------- the song

# A minor: Am7, Fmaj7, C, G, one bar each. Semitones from A4.
CHORDS = [
    {"bass": -36, "notes": [-12, -9, -5, -2]},
    {"bass": -40, "notes": [-16, -12, -9, -5]},
    {"bass": -33, "notes": [-14, -9, -5, -2]},
    {"bass": -38, "notes": [-14, -10, -7, -2]},
]
HOOK = [
    [7, None, 3, 5, 7, None, 10, 7],
    [5, None, 3, None, 0, 3, None, None],
    [7, None, 3, 5, 7, None, 12, 10],
    [7, None, 5, None, 2, None, -2, None],
]
STABS = [0, 3, 6, 10, 12]  # sixteenth positions in a bar

AND, MORE, PRIVATE, LOGO = starts["and"], starts["more"], starts["private"], starts["logo"]
kicks = []

def play_hook(t0, bar_in_phrase, gain, octave=0, as_keys=False):
    row = HOOK[bar_in_phrase % 4]
    for step, note in enumerate(row):
        if note is None:
            continue
        length = 0.5 if as_keys else 0.42
        if as_keys:
            add(pump_l, pump_r, t0 + step * BEAT / 2, keys(hz(note + octave), 1.6), gain, pan=0.1, send=0.5)
        else:
            add_mono(lead, t0 + step * BEAT / 2, lead_note(hz(note + octave), length), gain, send=0.25)

def stabs(t0, chord, gain, positions=STABS):
    for pos in positions:
        for idx, note in enumerate(chord["notes"]):
            add(pump_l, pump_r, t0 + pos * BEAT / 4, saw_voice(hz(note), 0.2, 6500, 1500, 9), gain, pan=(idx - 1.5) * 0.65, send=0.18)

def drums(t0, crash=False, shaker=False, fill=False, kick_gain=1.0):
    for beat in range(4):
        if fill and beat == 3:
            for s in range(4):
                add(dry_l, dry_r, t0 + (3 + s / 4) * BEAT, SNARE, 0.22 + s * 0.05, pan=-0.1, send=0.2)
            add(dry_l, dry_r, t0 + 3 * BEAT, KICK, 0.9 * kick_gain); kicks.append(t0 + 3 * BEAT)
            continue
        add(dry_l, dry_r, t0 + beat * BEAT, KICK, 0.72 * kick_gain); kicks.append(t0 + beat * BEAT)
        if beat in (1, 3):
            add(dry_l, dry_r, t0 + beat * BEAT, CLAP, 0.34, pan=-0.05, send=0.25)
        add(dry_l, dry_r, t0 + (beat + 0.5) * BEAT, OPEN_HAT if beat == 3 else HAT, 0.22 if beat == 3 else 0.2, pan=0.35)
        if shaker:
            for s in (0.25, 0.75):
                add(dry_l, dry_r, t0 + (beat + s) * BEAT, SHAKER, 0.11, pan=-0.45)
    if crash:
        add(dry_l, dry_r, t0, CRASH, 0.13, pan=0.2, send=0.2)

def bassline(t0, chord, busy=False):
    for pos in (0.5, 1.5, 2.5, 3.5):
        add(pump_l, pump_r, t0 + pos * BEAT, bass(hz(chord["bass"]), BEAT * 0.45), 0.24)
    if busy:
        add(pump_l, pump_r, t0 + 3.75 * BEAT, bass(hz(chord["bass"] + 12), BEAT * 0.22), 0.26)

def arp(t0, chord, gain):
    notes = chord["notes"] + [n + 12 for n in chord["notes"]]
    for s in range(16):
        n = notes[[0, 1, 2, 3, 4, 3, 2, 1, 0, 2, 4, 6, 5, 3, 2, 1][s] % len(notes)] + 12
        add(pump_l, pump_r, t0 + s * BEAT / 4, saw_voice(hz(n), 0.12, 6000, 1500, 22, detune=(0,)), gain, pan=0.5 if s % 2 else -0.5, send=0.2)

total_bars = int(math.ceil(LENGTH / BAR))
for b in range(total_bars):
    t0 = b * BAR
    chord = CHORDS[b % 4]
    if b < 3:                                   # intro under the typing
        for note in chord["notes"]:
            add(pump_l, pump_r, t0, pad(hz(note), BAR + 0.8, 800 + b * 300), 0.09, pan=random.uniform(-0.6, 0.6), send=0.3)
        if b >= 1:
            play_hook(t0, b, 0.05, as_keys=True)
        if b >= 2:
            for e in range(8):
                add(dry_l, dry_r, t0 + e * BEAT / 2, HAT, 0.05 + 0.03 * (e % 2), pan=0.3)
            add(dry_l, dry_r, t0, KICK, 0.45); add(dry_l, dry_r, t0 + 2 * BEAT, KICK, 0.45)
    elif b == 3:                                # "Stop": a hit, then the build
        stabs(t0, chord, 0.09, positions=[0])
        add(dry_l, dry_r, t0, boom(), 0.35)
        add(dry_l, dry_r, t0, KICK, 0.9)
        for note in chord["notes"]:
            add(pump_l, pump_r, t0, pad(hz(note), BAR - 0.15, 1200, attack=0.9), 0.09, send=0.3)
        add(dry_l, dry_r, t0 + 0.1, riser(BAR - 0.2), 0.16)
        for s in range(8):
            add(dry_l, dry_r, t0 + BAR / 2 + s * BEAT / 4, SNARE, 0.06 + s * 0.022, send=0.15)
    elif 4 <= b < 22 or 23 <= b < 25:           # the groove
        section_b = 12 <= b < 20
        last_before_break = b in (11, 19)
        drums(t0, crash=b in (4, 12, 20, 23), shaker=section_b or b >= 23, fill=last_before_break)
        bassline(t0, chord, busy=section_b)
        stabs(t0, chord, 0.09 if not section_b else 0.075)
        if section_b and b < 16:
            arp(t0, chord, 0.045)
        else:
            play_hook(t0, b, 0.26, octave=12 if b >= 23 else 0)
    elif b == 22:                               # build, then the stop on "And"
        drums(t0, fill=False, shaker=True)
        bassline(t0, chord)
        play_hook(t0, b, 0.18)
        add(dry_l, dry_r, AND - 1.0, riser(1.0), 0.18)
        for s in range(8):
            add(dry_l, dry_r, AND - 1.0 + s * BEAT / 4, SNARE, 0.07 + s * 0.025, send=0.15)
        add(sfx_l, sfx_r, AND + 0.1, whoosh(0.9, rising=True), 0.2)
        add(sfx_l, sfx_r, AND, boom(), 0.32)
    elif b == 25:                               # breakdown for privacy
        for note in chord["notes"] + [chord["bass"] + 24]:
            add(pump_l, pump_r, t0, pad(hz(note), BAR + 1.0, 1400), 0.085, send=0.4)
        play_hook(t0, 0, 0.09, octave=12, as_keys=True)
    elif b in (26, 27):                         # build into the logo
        for note in chord["notes"]:
            add(pump_l, pump_r, t0, pad(hz(note), BAR + 0.2, 1500 + (b - 26) * 2500), 0.08, send=0.3)
        for beat in range(4):
            add(dry_l, dry_r, t0 + beat * BEAT, KICK, 0.55 + (b - 26) * 0.3); kicks.append(t0 + beat * BEAT)
        play_hook(t0, b - 24, 0.12)
        if b == 27:
            add(dry_l, dry_r, t0, riser(BAR - 0.1), 0.2)
            for s in range(24):
                pos = s / 6 if s < 12 else 2 + (s - 12) / 6
                add(dry_l, dry_r, t0 + pos * BEAT, SNARE, 0.05 + s * 0.008, send=0.15)

# The final hit on the logo: impact, crash and a held C major add9 chord, then the hook's last notes.
add(dry_l, dry_r, LOGO, boom(), 0.5)
add(dry_l, dry_r, LOGO, KICK, 1.0)
add(dry_l, dry_r, LOGO, CRASH, 0.2, send=0.4)
add(dry_l, dry_r, LOGO, CLAP, 0.3, send=0.4)
for idx, note in enumerate([-21, -14, -9, -5, -2, 5]):
    add(pump_l, pump_r, LOGO, pad(hz(note), LENGTH - LOGO, 2200, attack=0.05), 0.07, pan=(idx - 2.5) * 0.3, send=0.45)
    add(pump_l, pump_r, LOGO, saw_voice(hz(note), 1.2, 6000, 1200, 2.5), 0.05, pan=(idx - 2.5) * 0.3, send=0.3)
for step, note in enumerate([7, 10, 15, 19]):
    add_mono(lead, LOGO + BAR / 2 + step * BEAT / 2 + 1.0 * (step == 3), lead_note(hz(note), 0.9), 0.15, send=0.4)

# ---------------------------------------------------------------- sound effects from the picture

def key_click():
    pitch = random.uniform(0.85, 1.2)
    n = int(0.03 * RATE); y = 0.0; out = []
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1)
        y += 0.55 * (x - y)
        thock = math.sin(2 * math.pi * 210 * pitch * t) * math.exp(-t * 160)
        out.append((x - y) * math.exp(-t * 420) * 0.9 + thock * 0.7)
    return out

def enter_key():
    n = int(0.09 * RATE); y = 0.0; out = []
    for i in range(n):
        t = i / RATE
        x = random.uniform(-1, 1); y += 0.4 * (x - y)
        out.append((x - y) * math.exp(-t * 200) + math.sin(2 * math.pi * 120 * t) * math.exp(-t * 55) * 1.2)
    return out

def mouse_click():
    out = [0.0] * int(0.09 * RATE)
    for start in (0, int(0.065 * RATE)):
        for i in range(int(0.012 * RATE)):
            t = i / RATE
            out[start + i] += (random.uniform(-1, 1) * 0.5 + math.sin(2 * math.pi * 3200 * t)) * math.exp(-t * 700) * (1 if start == 0 else 0.6)
    return out

def pop():
    n = int(0.12 * RATE); out = []; ph = 0.0
    for i in range(n):
        t = i / RATE
        ph += 2 * math.pi * (500 + 1600 * min(1, t / 0.05)) / RATE
        out.append(math.sin(ph) * math.exp(-t * 38))
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
                add(sfx_l, sfx_r, at + c / ev["rate"] / FPS + random.uniform(-0.006, 0.006), key_click(), random.uniform(0.18, 0.28), pan=random.uniform(-0.15, 0.15))
        elif kind == "enter":
            add(sfx_l, sfx_r, at, enter_key(), 0.42, send=0.1)
        elif kind == "click":
            add(sfx_l, sfx_r, at, mouse_click(), 0.22, pan=0.2)
        elif kind == "pop":
            add(sfx_l, sfx_r, at, pop(), 0.2, send=0.2)
            for k in range(7):
                add(sfx_l, sfx_r, at + 0.03 + k * 0.05 + random.uniform(0, 0.03), tone(random.uniform(2400, 4200), 0.25, 18), 0.035, pan=random.uniform(-0.7, 0.7), send=0.3)
        elif kind == "chime":
            for k, f in enumerate((1318.5, 1975.5)):
                add(sfx_l, sfx_r, at + k * 0.08, tone(f, 1.2, 4.5, ((1, 1.0), (2.76, 0.2))), 0.07, pan=-0.2 + 0.4 * k, send=0.4)
        elif kind == "swish":
            add(sfx_l, sfx_r, at - 0.05, whoosh(0.3), 0.12, pan=0.3)

big_moments = {starts["meet"], MORE, LOGO, starts["stop"], AND}
for scene in timeline[1:]:
    cut = starts[scene["id"]]
    if cut not in big_moments:
        add(sfx_l, sfx_r, cut - 0.18, whoosh(0.36), 0.085, pan=random.uniform(-0.3, 0.3))
for moment in (starts["meet"], MORE):
    add(dry_l, dry_r, moment, boom(), 0.42)
    add(sfx_l, sfx_r, moment - 0.6, whoosh(0.6, rising=True), 0.14)

# ---------------------------------------------------------------- mix

# The stop on "And": the band drops out for that beat and comes back on the second drop.
g0, g1 = int(AND * RATE), int(MORE * RATE)
edge = int(0.01 * RATE)
for i in range(g0, min(g1, N)):
    g = max(0.0, 1 - (i - g0) / edge) if i < g0 + edge else (max(0.0, (i - (g1 - edge)) / edge) if i > g1 - edge else 0.0)
    dry_l[i] *= g; dry_r[i] *= g; pump_l[i] *= g; pump_r[i] *= g; lead[i] *= g; rev[i] *= g

# Sidechain: everything on the pump bus ducks under each kick and breathes back up.
duck = [1.0] * N
for kt in kicks:
    i0 = int(kt * RATE)
    for i in range(int(0.3 * RATE)):
        j = i0 + i
        if 0 <= j < N:
            x = i / (0.3 * RATE)
            duck[j] = min(duck[j], 0.22 + 0.78 * x ** 1.6)

# Dotted-eighth ping-pong delay on the lead.
d = int(BEAT * 0.75 * RATE)
echo_l, echo_r = buf(), buf()
for i in range(d, N):
    echo_l[i] = 0.42 * lead[i - d] + 0.38 * echo_r[i - d]
    echo_r[i] = 0.42 * echo_l[i - d]

# Reverb: four damped combs and two allpasses per side, on the send.
def reverb(src, offsets):
    combs = [[0.0] * (n + offsets) for n in (1557, 1617, 1491, 1422)]
    idx = [0, 0, 0, 0]; damp = [0.0] * 4
    aps = [[0.0] * n for n in (556 + offsets // 2, 225)]
    ai = [0, 0]
    out = [0.0] * N
    for i in range(N):
        x = src[i] * 0.3
        acc = 0.0
        for k in range(4):
            c = combs[k]; y = c[idx[k]]
            damp[k] = y * 0.7 + damp[k] * 0.3
            c[idx[k]] = x + damp[k] * 0.82
            idx[k] = (idx[k] + 1) % len(c)
            acc += y
        for k in range(2):
            a = aps[k]; bv = a[ai[k]]
            yv = -acc + bv
            a[ai[k]] = acc + bv * 0.5
            ai[k] = (ai[k] + 1) % len(a)
            acc = yv
        out[i] = acc
    return out

rev_l, rev_r = reverb(rev, 0), reverb(rev, 137)

mix_l, mix_r = [0.0] * N, [0.0] * N
peak = 1e-9
# A gentle tilt: lift everything above about 1.8 kHz so the track sits as bright as the references.
tilt_a = coef(1800)
low_l = low_r = 0.0
for i in range(N):
    t = i / RATE
    fade = min(1, t / 0.05) * min(1, max(0, (LENGTH - t) / 1.6))
    music_l = dry_l[i] + pump_l[i] * duck[i] + lead[i] * 0.85 + echo_l[i] * 0.6 + rev_l[i] * 0.6 - rev_r[i] * 0.15
    music_r = dry_r[i] + pump_r[i] * duck[i] + lead[i] * 0.85 + echo_r[i] * 0.6 + rev_r[i] * 0.6 - rev_l[i] * 0.15
    low_l += tilt_a * (music_l - low_l); low_r += tilt_a * (music_r - low_r)
    music_l = music_l + (music_l - low_l) * 1.1
    music_r = music_r + (music_r - low_r) * 1.1
    l = math.tanh((music_l * 1.2 + sfx_l[i]) * fade * 1.3)
    r = math.tanh((music_r * 1.2 + sfx_r[i]) * fade * 1.3)
    mix_l[i], mix_r[i] = l, r
    peak = max(peak, abs(l), abs(r))

scale = 0.95 / peak
out_path = os.path.join(here, "..", "public", "soundtrack-v3.wav")
with wave.open(out_path, "wb") as f:
    f.setnchannels(2); f.setsampwidth(2); f.setframerate(RATE)
    f.writeframes(b"".join(struct.pack("<hh", int(l * scale * 32767), int(r * scale * 32767)) for l, r in zip(mix_l, mix_r)))
print("wrote public/soundtrack-v3.wav", round(LENGTH, 2), "s; drop at", starts["meet"], "s; second drop at", MORE, "s; logo hit at", LOGO, "s")
