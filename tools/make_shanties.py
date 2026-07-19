# Generates 8-bit-style instrumental sea shanty WAVs for the PalBoombox mod.
# Output: PalBoombox/music/*.wav (22050 Hz, 16-bit stereo)
#
# The tunes are traditional (public domain); these chiptune arrangements are
# transcribed by ear and approximate. Players can drop their own .wav/.mp3
# recordings into the music folder for the real deal.
#
# Usage: python tools/make_shanties.py
# Tests can redirect output with PALBOOMBOX_SHANTY_OUT_DIR.
import math
import os
import struct
import wave

SR = 22050
OUT_DIR = os.environ.get(
    "PALBOOMBOX_SHANTY_OUT_DIR",
    os.path.join(os.path.dirname(__file__), "..", "PalBoombox", "music"),
)

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_of(token):
    # "F#4" / "Bb3" / "D4" -> midi number
    name = token[0].upper()
    rest = token[1:]
    acc = 0
    if rest.startswith("#"):
        acc, rest = 1, rest[1:]
    elif rest.startswith("b"):
        acc, rest = -1, rest[1:]
    octave = int(rest)
    return 12 * (octave + 1) + NOTE_INDEX[name] + acc


def freq_of(midi):
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def parse(seq):
    """'D4:2 r:1 F4:1.5' -> list of (freq_or_None, eighths)"""
    out = []
    for token in seq.split():
        note, dur = token.split(":")
        dur = float(dur)
        if note == "r":
            out.append((None, dur))
        else:
            out.append((freq_of(midi_of(note)), dur))
    return out


def voice_melody(phase):
    # Band-limited square-ish tone: odd harmonics 1,3,5,7
    return (math.sin(phase) + math.sin(3 * phase) / 3
            + math.sin(5 * phase) / 5 + math.sin(7 * phase) / 7) * 0.72


def voice_bass(phase):
    return math.sin(phase) + 0.30 * math.sin(2 * phase)


def render_line(events, eighth_sec, voice, gain, vibrato=False):
    total = sum(d for _, d in events)
    samples = [0.0] * int(total * eighth_sec * SR + SR)
    cursor = 0.0
    for freq, dur in events:
        length = dur * eighth_sec
        n = int(length * SR)
        start = int(cursor * SR)
        if freq is not None:
            phase = 0.0
            for i in range(n):
                t = i / SR
                f = freq
                if vibrato and t > 0.12:
                    f *= 1.0 + 0.003 * math.sin(2 * math.pi * 5.2 * t)
                phase += 2 * math.pi * f / SR
                # ADSR-ish envelope
                if t < 0.008:
                    env = t / 0.008
                elif t > length - 0.04:
                    env = max(0.0, (length - t) / 0.04)
                else:
                    env = 1.0 - 0.15 * min(1.0, t / max(length, 1e-6))
                samples[start + i] += voice(phase) * env * gain
        cursor += length
    return samples, cursor


def repeat_to_length(pattern, eighths):
    """Repeat a bass pattern (parsed events) to cover `eighths` eighth-notes."""
    out = []
    acc = 0.0
    while acc < eighths - 1e-6:
        for freq, dur in pattern:
            if acc >= eighths - 1e-6:
                break
            dur = min(dur, eighths - acc)
            out.append((freq, dur))
            acc += dur
    return out


def render_song(name, bpm, melody_seq, bass_pattern_seq, repeats=2):
    eighth = 30.0 / bpm
    melody = parse(melody_seq) * repeats
    total_eighths = sum(d for _, d in melody)
    bass = repeat_to_length(parse(bass_pattern_seq), total_eighths)

    mel, dur_a = render_line(melody, eighth, voice_melody, 0.42, vibrato=True)
    bas, dur_b = render_line(bass, eighth, voice_bass, 0.30)

    n = max(len(mel), len(bas))
    mel += [0.0] * (n - len(mel))
    bas += [0.0] * (n - len(bas))

    # trim trailing silence to just past the end of the music
    end = int((max(dur_a, dur_b) + 0.4) * SR)
    frames = bytearray()
    for i in range(min(n, end)):
        v = mel[i] + bas[i]
        v = math.tanh(v * 1.1)  # soft clip
        s = int(max(-1.0, min(1.0, v)) * 32000)
        frames += struct.pack("<hh", s, s)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print(f"{name}.wav  {len(frames) / 4 / SR:6.1f}s  {os.path.getsize(path) / 1e6:.1f} MB")


# ---------------------------------------------------------------------------
# Arrangements (durations are in eighth-notes; 'r' = rest)
# ---------------------------------------------------------------------------

WELLERMAN = " ".join([
    # Verse: "There once was a ship that put to sea..."
    "A3:1 D4:2 D4:1 D4:2 F4:1 E4:2 C4:1 E4:1 r:2",
    "A3:1 D4:2 D4:1 D4:2 F4:1 A4:4 r:1",
    "A4:1 A4:2 A4:1 A4:2 G4:1 F4:2 D4:2 r:1",
    "C4:1 D4:2 F4:1 E4:2 C4:1 D4:4 r:2",
    # Chorus: "Soon may the Wellerman come..."
    "F4:2 F4:1 A4:2 A4:1 G4:2 G4:1 A4:2 A4:1",
    "Bb4:2 Bb4:1 A4:1 G4:1 F4:1 A4:4 r:1",
    "A4:1 A4:2 A4:1 A4:2 G4:1 F4:2 D4:2 r:1",
    "C4:1 D4:2 F4:1 E4:2 C4:1 D4:4 r:2",
])

LEAVE_HER_JOHNNY = " ".join([
    # Verse: "I thought I heard the old man say..."
    "C4:1 F4:2 F4:1 F4:1 G4:1 A4:2 A4:2 r:2",
    "C5:2 A4:1 F4:2 G4:1 A4:4 r:2",
    "A4:1 Bb4:2 A4:1 G4:2 F4:1 G4:2 E4:2 r:2",
    "C4:1 F4:2 G4:1 A4:1 G4:1 F4:4 r:2",
    # Chorus: "Leave her, Johnny, leave her..."
    "C5:2 C5:1 A4:2 F4:1 G4:2 A4:3 r:2",
    "A4:2 Bb4:1 A4:1 G4:1 F4:1 G4:4 r:2",
    "F4:1 A4:2 A4:1 C5:2 A4:1 G4:2 F4:1 G4:1 r:2",
    "C4:1 F4:2 G4:1 A4:1 G4:1 F4:5 r:3",
])

BULLY_IN_THE_ALLEY = " ".join([
    # "So help me, Bob, I'm bully in the alley..."
    "D4:1 G4:1 G4:1 G4:1 B4:1 G4:1 A4:2",
    "B4:1 B4:1 A4:1 G4:1 E4:2 r:2",
    "D4:1 G4:1 G4:1 G4:1 B4:1 D5:1 B4:2",
    "A4:1 G4:1 A4:1 B4:1 G4:2 r:2",
    # "Sally is the girl that I love dearly..."
    "B4:1 B4:1 B4:1 D5:1 B4:1 A4:1 G4:2",
    "A4:1 A4:1 A4:1 B4:1 E4:2 r:2",
    "D4:1 G4:1 G4:1 G4:1 B4:1 D5:1 B4:2",
    "A4:1 G4:1 A4:1 B4:1 G4:2 r:2",
])

DRUNKEN_SAILOR = " ".join([
    # "What shall we do with a drunken sailor..."
    "D4:1 D4:1 D4:1 D4:1 D4:1 D4:1 D4:1 D4:1",
    "C4:1 C4:1 C4:1 C4:1 C4:1 C4:1 C4:1 C4:1",
    "D4:1 D4:1 D4:1 D4:1 D4:1 E4:1 F4:1 G4:1",
    "A3:1 D4:1 D4:1 D4:1 E4:1 C4:1 D4:2",
    # "Way hay and up she rises..."
    "D4:1 F4:1 A4:2 A4:1 A4:1 A4:2",
    "C4:1 E4:1 G4:2 G4:1 G4:1 G4:2",
    "D4:1 F4:1 A4:1 A4:1 A4:1 B4:1 C5:1 A4:1",
    "A3:1 D4:1 D4:1 D4:1 E4:1 C4:1 D4:2",
])

SONGS = [
    ("wellerman",          105, WELLERMAN,          "D2:2 D3:2"),
    ("leave_her_johnny",    84, LEAVE_HER_JOHNNY,   "F2:2 F3:2"),
    ("bully_in_the_alley", 116, BULLY_IN_THE_ALLEY, "G2:2 G3:2"),
    ("drunken_sailor",     132, DRUNKEN_SAILOR,     "D2:2 D3:2"),
]

if __name__ == "__main__":
    for name, bpm, melody, bass in SONGS:
        render_song(name, bpm, melody, bass)
