#!/usr/bin/env python3
"""Renders the game's background music to assets/audio/<name>.ogg: slow, quiet, endlessly looping
pieces, each in its own mode, with a low drone, soft sustained chords and now and then a plucked,
lyre-like note, all with a little echo. Pure Python (no libraries) plus ffmpeg for the Ogg files.
Run from the project root: python3 tools/make_music.py [dorian phrygian lydian mixolydian]
(about 90 seconds a piece; the results are committed, so this is only needed to change the music)."""
import array, math, random, subprocess, sys

SR = 32000
LENGTH = 128  # seconds; the end flows into the start
N = SR * LENGTH
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


def render(name):
    global rnd, buf
    cfg = PIECES[name]
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
    # a little room: a few echoes, wrapped round the loop
    for delay_s, gain in [(0.37, 0.35), (0.71, 0.25), (1.13, 0.2), (1.9, 0.12)]:
        d = int(delay_s * SR)
        src = buf[:]
        for i in range(N):
            buf[i] += src[i - d] * gain
    # normalise to a low, even level
    peak = max(abs(v) for v in buf)
    k = 0.30 / peak
    pcm = array.array("h", (int(max(-1.0, min(1.0, v * k)) * 32767) for v in buf))
    proc = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
         "-ac", "2", "-c:a", "vorbis", "-strict", "-2", "-b:a", "80k", "assets/audio/%s.ogg" % name],
        input=pcm.tobytes())
    if proc.returncode != 0:
        sys.exit(proc.returncode)


for piece in (sys.argv[1:] or PIECES):
    render(piece)
