#!/usr/bin/env python3
"""Renders the game's background music to assets/audio/<era>_<mode>.ogg, in two styles:
  regnum_*   (the Kingdom): slow, quiet, pastoral ambience: a low drone, soft sustained chords and now
             and then a plucked, lyre-like note;
  republic_* (the Republic): livelier, with a pulse: a frame drum and shaker, a bass, an arpeggiated
             cithara and a reedy tibia (pipe) melody, still gentle;
  title_imperial: the title music: a stately march in D minor with brass chords, a fanfare melody and
             timpani, which plays through the opening scroll, the title and the loading screen.
Each in four modes (dorian, phrygian, lydian, mixolydian), looping cleanly, with a little echo. Pure
Python (no libraries) plus ffmpeg for the Ogg files. Run from the project root:
  python3 tools/make_music.py [regnum_dorian republic_lydian title_imperial ...]   (all nine by default)
About 90 to 150 seconds a piece; the results are committed, so this is only needed to change the music."""
import array, math, random, subprocess, sys

SR = 32000
LENGTH = 128  # seconds; the end flows into the start
N = SR * LENGTH  # samples in the piece being rendered (set again by each render)
rnd = random.Random(753)
buf = [0.0] * N


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def add_circular(start, samples, gain=1.0):
    for i, v in enumerate(samples):
        buf[(start + i) % N] += v * gain


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def pad(midi, start_s, dur_s, gain, attack=5.0, release=6.0):
    """A soft sustained tone: a sine with a quiet octave and a slow wobble."""
    f = hz(midi)
    n = int((dur_s + release) * SR)
    out = []
    wob = rnd.uniform(0, 6.28)
    for i in range(n):
        t = i / SR
        env = smooth(t / attack) * (1.0 - smooth((t - dur_s) / release))
        w = 1.0 + 0.0025 * math.sin(0.35 * t + wob)
        ph = 2 * math.pi * f * t * w
        out.append(env * (math.sin(ph) + 0.28 * math.sin(2 * ph) + 0.08 * math.sin(3 * ph)))
    add_circular(int(start_s * SR), out, gain)


def pluck(midi, start_s, gain, seconds=5.0, bright=0.5):
    """Karplus-Strong string: a lyre-like plucked note."""
    f = hz(midi)
    period = int(SR / f)
    line = [rnd.uniform(-1, 1) * (1 - bright * 0.4) for _ in range(period)]
    # soften the initial burst so it is warm, not buzzy
    for _ in range(3):
        line = [(line[i] + line[i - 1]) * 0.5 for i in range(period)]
    out = []
    n = int(seconds * SR)
    idx = 0
    prev = 0.0
    for i in range(n):
        cur = line[idx]
        new = (cur + prev) * 0.5 * 0.9985
        line[idx] = new
        prev = cur
        idx = (idx + 1) % period
        out.append(cur * (1.0 - smooth((i / SR - (seconds - 1.5)) / 1.5)))
    add_circular(int(start_s * SR), out, gain)



# Each piece: the drone's low note, a chord (as MIDI notes) for every 16 seconds, the scale its melody
# wanders over, and a seed. The names are the modern ones, which differ from the Greek ones; of the
# music of Rome itself almost nothing was written down, so these are in the spirit of it, not copies.
PIECES = {
    "dorian": {  # D E F G A B C: grave and calm
        "root": 38, "seed": 753, "start": 3,
        "chords": [[62, 65, 69], [60, 64, 67], [55, 58, 62], [62, 67, 71], [60, 65, 69], [57, 62, 65], [55, 60, 64], [62, 65, 69]],
        "scale": [62, 64, 65, 67, 69, 71, 72, 74]},
    "phrygian": {  # E F G A B C D: darker, with the half step above the tonic (the mode of the pipes)
        "root": 40, "seed": 509, "start": 2,
        "chords": [[52, 55, 59], [53, 57, 60], [52, 55, 59], [50, 53, 57], [55, 59, 62], [53, 57, 60], [50, 53, 57], [52, 55, 59]],
        "scale": [64, 65, 67, 69, 71, 72, 74, 76]},
    "lydian": {  # F G A B C D E: bright and open, with the raised fourth
        "root": 41, "seed": 264, "start": 3,
        "chords": [[53, 57, 60], [55, 59, 62], [60, 64, 67], [50, 53, 57], [53, 57, 60], [55, 59, 62], [57, 60, 64], [53, 57, 60]],
        "scale": [65, 67, 69, 71, 72, 74, 76, 77]},
    "mixolydian": {  # G A B C D E F: easy and rustic
        "root": 43, "seed": 146, "start": 3,
        "chords": [[55, 59, 62], [53, 57, 60], [60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60], [50, 53, 57], [55, 59, 62]],
        "scale": [67, 69, 71, 72, 74, 76, 77, 79]},
}


def finish(name):
    """Echo, level and write the Ogg file."""
    global buf
    for delay_s, gain in ECHOES:
        d = int(delay_s * SR)
        src = buf[:]
        for i in range(N):
            buf[i] += src[i - d] * gain
    rms = math.sqrt(sum(v * v for v in buf) / N)
    k = TARGET_RMS / rms
    pcm = array.array("h", (int(max(-1.0, min(1.0, v * k)) * 32767) for v in buf))
    proc = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
         "-ac", "2", "-c:a", "vorbis", "-strict", "-2", "-b:a", "80k", "assets/audio/%s.ogg" % name],
        input=pcm.tobytes())
    if proc.returncode != 0:
        sys.exit(proc.returncode)


ECHOES = [(0.37, 0.35), (0.71, 0.25), (1.13, 0.2), (1.9, 0.12)]
TARGET_RMS = 0.05  # about -26 dB: quiet


def render_regnum(mode):
    global rnd, buf, N
    cfg = PIECES[mode]
    N = SR * LENGTH
    rnd = random.Random(cfg["seed"])
    buf = [0.0] * N
    root = cfg["root"]
    # the drone: the tonic and its fifth, always there
    for m, g in [(root, 0.5), (root + 7, 0.3), (root + 12, 0.15)]:
        pad(m, 0.0, LENGTH - 6.0, g, attack=0.01, release=0.01)
    for t0 in range(0, LENGTH, 32):  # a gentle breathing high above it
        pad(root + 19, t0 + 4.0, 20.0, 0.07)
    # slow chords, one every 16 seconds, each lasting a little longer than its turn
    for i, ch in enumerate(cfg["chords"]):
        for m in ch:
            pad(m - 12 if m > 64 else m, i * 16.0, 15.0, 0.16)
    # a sparse melody on the lyre, with long silences
    scale = cfg["scale"]
    pos = cfg["start"]
    t = 5.0
    while t < LENGTH - 8.0:
        for _ in range(rnd.choice([1, 2, 2, 3])):
            pos = max(0, min(len(scale) - 1, pos + rnd.choice([-2, -1, -1, 1, 1, 2])))
            pluck(scale[pos], t, rnd.uniform(0.2, 0.32), bright=rnd.uniform(0.3, 0.7))
            t += rnd.choice([1.4, 1.8, 2.4])
        t += rnd.uniform(5.0, 11.0)
    finish("regnum_" + mode)


# --- the Republic: a pulse --------------------------------------------------------------------

BPM = {"dorian": 96, "phrygian": 108, "lydian": 112, "mixolydian": 104}
RHYTHMS = [  # a two-bar melody rhythm, in beats (each adds up to 8)
    [1, 1, 2, 1, 1, 2], [1.5, 0.5, 1, 1, 1.5, 0.5, 2], [2, 1, 1, 2, 2], [1, 0.5, 0.5, 1, 1, 1, 1, 1, 1],
    [0.5, 0.5, 1, 1, 1, 0.5, 0.5, 1, 2], [3, 1, 1, 1, 2],
]


def bass(midi, start_s, dur_s, gain):
    f = hz(midi)
    n = int(dur_s * SR)
    out = [math.exp(-3.2 * i / SR) * smooth(i / (0.01 * SR)) * (math.sin(2 * math.pi * f * i / SR) + 0.35 * math.sin(4 * math.pi * f * i / SR)) for i in range(n)]
    add_circular(int(start_s * SR), out, gain)


def tibia(midi, start_s, dur_s, gain):
    """A reedy pipe: odd harmonics, a little breath, a vibrato that arrives after a moment."""
    f = hz(midi)
    n = int((dur_s + 0.1) * SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        env = smooth(t / 0.04) * (0.8 + 0.2 * math.exp(-t * 6)) * (1.0 - smooth((t - dur_s) / 0.1))
        vib = 1.0 + 0.006 * smooth((t - 0.25) / 0.3) * math.sin(2 * math.pi * 5.2 * t)
        ph += 2 * math.pi * f * vib / SR
        out.append(env * (math.sin(ph) + 0.22 * math.sin(2 * ph) + 0.4 * math.sin(3 * ph) + 0.1 * math.sin(5 * ph) + 0.03 * rnd.uniform(-1, 1)))
    add_circular(int(start_s * SR), out, gain)


def drum(start_s, gain):
    """A frame drum: a quick low thump that drops in pitch."""
    n = int(0.4 * SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * (62 + 60 * math.exp(-t * 28)) / SR
        out.append(math.exp(-t * 9) * math.sin(ph) + 0.12 * math.exp(-t * 60) * rnd.uniform(-1, 1))
    add_circular(int(start_s * SR), out, gain)


def shaker(start_s, gain):
    n = int(0.07 * SR)
    prev = 0.0
    out = []
    for i in range(n):
        x = rnd.uniform(-1, 1)
        out.append((x - prev) * math.exp(-i / SR * 55))  # a crude high-pass: all hiss, no body
        prev = x
    add_circular(int(start_s * SR), out, gain)


def render_republic(mode):
    global rnd, buf, N
    cfg = PIECES[mode]
    rnd = random.Random(cfg["seed"] + 1000)
    beat = 60.0 / BPM[mode]
    bars = 48
    N = int(bars * 4 * beat * SR)
    buf = [0.0] * N
    chords = cfg["chords"]
    scale = cfg["scale"]
    for bar in range(bars):
        t0 = bar * 4 * beat
        ch = chords[(bar // 2) % len(chords)]
        low = min(ch) - 12
        # bass on the beat, the fifth on the "and" of three
        bass(low, t0, beat * 1.6, 0.55)
        bass(low if bar % 2 else low + 7, t0 + 2 * beat, beat * 1.2, 0.4)
        if bar % 4 == 3:
            bass(low + 7, t0 + 3.5 * beat, beat * 0.5, 0.3)
        # the cithara: an eighth-note arpeggio of the chord
        for k in range(8):
            note = ch[[0, 1, 2, 1, 2, 1, 2, 1][k]] + 12
            pluck(note, t0 + k * beat / 2, 0.16 if k % 2 == 0 else 0.11, seconds=1.0, bright=0.6)
        # percussion: drum on one and three, a tap before four, a shaker on every eighth
        drum(t0, 0.5)
        drum(t0 + 2 * beat, 0.3)
        if bar % 2:
            drum(t0 + 3.5 * beat, 0.18)
        for k in range(8):
            shaker(t0 + k * beat / 2, 0.06 if k % 2 == 0 else 0.1)
    # the melody on the tibia: two-bar phrases that wander the scale and settle on a chord note
    pos = cfg["start"]
    for seg in range(bars // 2):
        t0 = seg * 8 * beat
        ch = chords[seg % len(chords)]
        if seg % 4 == 3:
            continue  # a phrase's breath
        tones = [i for i, m in enumerate(scale) if (m % 12) in [c % 12 for c in ch]]
        rhythm = RHYTHMS[(seg * 5 + rnd.randrange(3)) % len(RHYTHMS)] if seg % 8 else RHYTHMS[0]
        t = 0.0
        for j, d in enumerate(rhythm):
            if j == len(rhythm) - 1 and tones:
                pos = min(tones, key=lambda x: abs(x - pos))
            else:
                pos = max(0, min(len(scale) - 1, pos + rnd.choice([-1, -1, 0, 1, 1, 2, -2])))
            tibia(scale[pos], t0 + t * beat, d * beat * 0.92, 0.3)
            t += d
    finish("republic_" + mode)


# --- the title music: imperial ------------------------------------------------------------------

def brass(midi, start_s, dur_s, gain, attack=0.3, release=0.5, harmonics=6):
    """A brass-like tone: many harmonics, a swell in and a soft release."""
    f = hz(midi)
    n = int((dur_s + release) * SR)
    out = []
    w = 2 * math.pi * f / SR
    for i in range(n):
        t = i / SR
        env = smooth(t / attack) * (1.0 - smooth((t - dur_s) / release))
        # the tone brightens as the note swells
        bright = 0.5 + 0.5 * smooth(t / (attack * 2.5))
        v = 0.0
        for k in range(1, harmonics + 1):
            v += math.sin(k * w * i) / (k ** 1.15) * (1.0 if k <= 2 else bright)
        out.append(env * v)
    add_circular(int(start_s * SR), out, gain)


def timpani(midi, start_s, gain):
    f = hz(midi)
    n = int(1.1 * SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * f * (1.0 + 0.5 * math.exp(-t * 18)) / SR
        out.append(math.exp(-t * 4.5) * math.sin(ph) + 0.15 * math.exp(-t * 40) * rnd.uniform(-1, 1))
    add_circular(int(start_s * SR), out, gain)


# one chord per bar: the bass note and the brass chord. D minor, with the dominant major (A, with C sharp)
CHORDS = {
    "Dm": (38, [50, 57, 62, 65]), "Bb": (34, [46, 53, 58, 62]), "C": (36, [48, 55, 60, 64]),
    "Gm": (43, [43, 50, 55, 58]), "A": (45, [45, 52, 57, 61]),
}
PHRASE_A = ["Dm", "Dm", "Bb", "C"]
PHRASE_B = ["Dm", "Gm", "A", "Dm"]
# the fanfare: (beat in the bar, MIDI note, length in beats), a bar at a time
MELODY_A = [
    [(0, 69, 1.5), (1.5, 74, 0.5), (2, 77, 2)],
    [(0, 76, 1), (1, 74, 1), (2, 72, 1), (3, 74, 1)],
    [(0, 70, 1.5), (1.5, 74, 0.5), (2, 77, 2)],
    [(0, 72, 1.5), (1.5, 76, 0.5), (2, 79, 2)],
]
MELODY_B = [
    [(0, 74, 1), (1, 77, 1), (2, 81, 2)],
    [(0, 79, 1.5), (1.5, 77, 0.5), (2, 74, 2)],
    [(0, 73, 1), (1, 76, 1), (2, 81, 1), (3, 76, 1)],
    [(0, 74, 4)],
]


def render_title():
    global rnd, buf, N
    rnd = random.Random(27)
    beat = 60.0 / 72
    bars = 32
    N = int(bars * 4 * beat * SR)
    buf = [0.0] * N
    plan = (PHRASE_A + PHRASE_B) * 4
    melody = (MELODY_A + MELODY_B) * 4
    for bar in range(bars):
        t0 = bar * 4 * beat
        bass, tones = CHORDS[plan[bar]]
        second = bar >= 16  # the repeat is bigger: an octave higher fanfare, more brass
        for m in tones:  # the brass chord, held the whole bar and swelling
            brass(m, t0, 4 * beat - 0.05, 0.16 if not second else 0.2)
        brass(bass, t0, 4 * beat - 0.05, 0.4, attack=0.1, harmonics=4)
        for m in (tones[2] + 12, tones[3] + 12):  # strings above, soft
            pad(m, t0, 4 * beat - 0.1, 0.05, attack=0.6, release=0.8)
        # the fanfare on top
        for b, note, length in melody[bar]:
            brass(note + (12 if second and bar % 8 < 7 else 0), t0 + b * beat, length * beat * 0.95, 0.24, attack=0.06, release=0.25, harmonics=7)
        # timpani: a heavy one and a light three; a roll at the end of each phrase
        timpani(bass if bass < 40 else bass - 12, t0, 0.8)
        timpani(33, t0 + 2 * beat, 0.45)
        if bar % 4 == 3:
            for k in range(8):
                timpani(33 + (k % 2) * 5, t0 + 2 * beat + k * beat / 4, 0.25 + 0.06 * k)
    # a grander room: long echoes
    global ECHOES
    saved = ECHOES
    ECHOES = [(0.5, 0.4), (1.0, 0.3), (1.7, 0.2), (2.6, 0.12)]
    finish("title_imperial")
    ECHOES = saved


names = sys.argv[1:] or ["%s_%s" % (era, m) for era in ("regnum", "republic") for m in PIECES] + ["title_imperial"]
for name in names:
    if name == "title_imperial":
        render_title()
        continue
    era, mode = name.split("_", 1)
    (render_regnum if era == "regnum" else render_republic)(mode)
