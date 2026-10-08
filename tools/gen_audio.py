#!/usr/bin/env python3
"""NEXUS ARCADE v0.8.0 AUDIOKIT asset generator.

Synthesizes every SFX and music loop with numpy/scipy -- no licensed assets,
zero legal risk. Outputs 16-bit mono WAV at 22050 Hz into assets/audio/.

  assets/audio/sfx/    30 procedural sound effects (0.2 - 1.5 s)
                      + looping ambient SFX (engine_roar, 4 s seamless)
  assets/audio/music/  11 original genre loops (12 bars, seamless)

Music loops are 12 bars (not 32) so the raw total stays under ~15 MB.
Run:  python3 tools/gen_audio.py
"""
import os
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter

SR = 22050
ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
MUS_DIR = ROOT / "assets" / "audio" / "music"
PEAK = 0.89  # normalize target; hard requirement: peak < 0.99

_rng = np.random.default_rng(20261008)


# ---------------------------------------------------------------- helpers
def n_samp(dur: float) -> int:
    return max(1, int(round(dur * SR)))


def t_arr(n: int):
    return np.arange(n, dtype=np.float64) / SR


def env_ar(n: int, attack: float = 0.005, release: float = 0.05):
    """Linear attack, sustain at 1, linear release. Click-free envelope."""
    e = np.ones(n)
    na = max(1, int(attack * SR))
    nr = max(1, int(release * SR))
    if na < n:
        e[:na] = np.linspace(0.0, 1.0, na)
    if nr < n:
        e[-nr:] = np.linspace(1.0, 0.0, nr)
    return e


def env_decay(n: int, decay_s: float):
    return np.exp(-t_arr(n) / max(decay_s, 1e-4))


def osc(wave: str, freq: float, n: int, phase: float = 0.0):
    t = t_arr(n)
    cyc = freq * t + phase / (2 * np.pi)
    if wave == "sine":
        return np.sin(2 * np.pi * cyc)
    if wave == "square":
        return np.where(np.sin(2 * np.pi * cyc) >= 0.0, 1.0, -1.0)
    if wave == "tri":
        return 4.0 * np.abs((cyc % 1.0) - 0.5) - 1.0
    if wave == "saw":
        return 2.0 * (cyc % 1.0) - 1.0
    raise ValueError("wave: " + wave)


def sweep_wave(wave: str, f0: float, f1: float, n: int, vib=None):
    """Pitch sweep from f0 to f1; vib = (rate_hz, depth)."""
    t = t_arr(n)
    dur = n / SR
    inst = f0 + (f1 - f0) * t / dur
    if vib is not None:
        vr, vd = vib
        inst = inst * (1.0 + vd * np.sin(2 * np.pi * vr * t))
    ph = 2 * np.pi * np.cumsum(inst) / SR
    cyc = (ph / (2 * np.pi)) % 1.0
    if wave == "sine":
        return np.sin(ph)
    if wave == "square":
        return np.where(np.sin(ph) >= 0.0, 1.0, -1.0)
    if wave == "tri":
        return 4.0 * np.abs(cyc - 0.5) - 1.0
    if wave == "saw":
        return 2.0 * cyc - 1.0
    raise ValueError("wave: " + wave)


def noise(n: int):
    return _rng.standard_normal(n)


def lowpass(x, cutoff: float, order: int = 2):
    b, a = butter(order, min(cutoff, SR / 2 * 0.99) / (SR / 2))
    return lfilter(b, a, x)


def highpass(x, cutoff: float, order: int = 2):
    b, a = butter(order, min(cutoff, SR / 2 * 0.99) / (SR / 2), btype="high")
    return lfilter(b, a, x)


def echo(x, delay_s: float = 0.27, fb: float = 0.35, wet: float = 0.22):
    """Cheap feedback-comb space (IIR via lfilter, C speed)."""
    d = max(1, int(delay_s * SR))
    a = np.zeros(d + 1)
    a[0] = 1.0
    a[d] = -fb
    y = lfilter([1.0], a, x)
    mx = np.max(np.abs(x)) + 1e-9
    y = y * (mx / (np.max(np.abs(y)) + 1e-9))
    return (1.0 - wet) * x + wet * y


def _clickfix(x, a: float = 0.003, r: float = 0.008):
    """Tiny fade in/out so noise/decay-based layers never start or stop with
    a sample step (the classic sample-0 click)."""
    return x * env_ar(len(x), a, r)


def finalize(x, peak: float = PEAK):
    x = np.tanh(x * 1.05)  # gentle soft-clip, keeps things clean
    m = np.max(np.abs(x))
    if m > 1e-9:
        x = x / m * peak
    return x


def write_wav(path: Path, x):
    x = finalize(x)
    peak = float(np.max(np.abs(x)))
    assert peak < 0.99, f"clipping in {path}: {peak}"
    pcm = (x * 32767).astype(np.int16)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return len(pcm) / SR, peak


# ---------------------------------------------------------------- SFX
def _tone(f0, dur, wave="sine", gain=0.5, f1=None, attack=0.005,
          decay=None, vib=None, cut=None):
    n = n_samp(dur)
    x = sweep_wave(wave, f0, f1 if f1 else f0, n, vib=vib)
    e = env_ar(n, attack, min(0.08, dur * 0.4))
    if decay:
        e = e * env_decay(n, decay)
    x = x * e * gain
    return lowpass(x, cut) if cut else x


def _nz(dur, gain=0.4, attack=0.003, decay=None, lp=None, hp=None):
    n = n_samp(dur)
    x = noise(n) * env_ar(n, attack, min(0.08, dur * 0.4))
    if decay:
        x = x * env_decay(n, decay)
    x = x * gain
    if lp:
        x = lowpass(x, lp)
    if hp:
        x = highpass(x, hp)
    return x


def _mix(*xs):
    """Sum arrays of differing lengths (zero-pad to the longest)."""
    n = max(len(np.asarray(x)) for x in xs)
    out = np.zeros(n)
    for x in xs:
        x = np.asarray(x)
        out[:len(x)] += x
    return out


def sfx_ui_click():
    return _mix(_tone(1250, 0.09, "sine", 0.45, decay=0.02),
                _nz(0.02, 0.25, hp=4000))


def sfx_ui_hover():
    return _tone(1568, 0.10, "sine", 0.28, decay=0.05)


def sfx_ui_back():
    return _tone(520, 0.22, "square", 0.32, f1=260, decay=0.12, cut=2200)


def sfx_success():
    out = np.zeros(n_samp(0.6))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        s = int(i * 0.09 * SR)
        seg = _tone(f, 0.22, "square", 0.30, decay=0.12, cut=3200)
        out[s:s + len(seg)] += seg
    return out


def sfx_fail():
    a = _tone(233, 0.28, "saw", 0.32, f1=196, decay=0.2, cut=1200)
    b = _tone(196, 0.34, "saw", 0.32, f1=155, decay=0.25, cut=1200)
    out = np.zeros(n_samp(0.62))
    out[:len(a)] += a
    out[int(0.26 * SR):int(0.26 * SR) + len(b)] += b
    return out


def sfx_pop():
    return _mix(_tone(350, 0.14, "sine", 0.6, f1=950, decay=0.05),
                _nz(0.03, 0.3, hp=2500))


def sfx_coin():
    out = np.zeros(n_samp(0.34))
    a = _tone(988, 0.10, "sine", 0.45, decay=0.06)
    b = _tone(1319, 0.26, "sine", 0.45, decay=0.16)
    out[:len(a)] += a
    out[int(0.08 * SR):int(0.08 * SR) + len(b)] += b
    return out


def sfx_whoosh():
    # rising whoosh from layered band noises (no time-varying filter artifacts)
    n = n_samp(0.5)
    t = t_arr(n)
    l1 = lowpass(noise(n), 700) * np.clip(t / 0.5, 0, 1) ** 2
    l2 = lowpass(noise(n), 2200) * np.sin(np.pi * np.clip(t / 0.5, 0, 1)) ** 2
    l3 = highpass(noise(n), 3200) * (1 - np.clip(t / 0.5, 0, 1)) ** 2 * 0.4
    return (l1 + l2 + l3) * env_ar(n, 0.05, 0.12) * 0.55


def sfx_explosion():
    n = n_samp(1.0)
    body = _clickfix(lowpass(noise(n), 900) * env_decay(n, 0.28) * 0.8,
                     a=0.004, r=0.05)
    sub = sweep_wave("sine", 95, 34, n_samp(0.65)) * env_decay(n_samp(0.65), 0.22) * 0.7
    crack = _clickfix(highpass(noise(n_samp(0.08)), 1800)
                      * env_decay(n_samp(0.08), 0.02) * 0.5, r=0.02)
    out = np.zeros(n)
    out += body
    out[:len(sub)] += sub
    out[:len(crack)] += crack
    return out


def sfx_splash():
    n = n_samp(0.7)
    t = t_arr(n)
    wob = 0.6 + 0.4 * np.sin(2 * np.pi * 9 * t + np.sin(2 * np.pi * 3.7 * t))
    x = noise(n) * wob * env_decay(n, 0.25) * 0.5
    x = _clickfix(x, a=0.008, r=0.05)
    return lowpass(highpass(x, 350), 3800)


def sfx_laser():
    return _mix(_tone(2200, 0.30, "square", 0.34, f1=180, decay=0.16, cut=4200),
                _nz(0.05, 0.15, hp=3000))


def sfx_thud():
    return _mix(_tone(110, 0.26, "sine", 0.7, f1=44, decay=0.10),
                _nz(0.10, 0.35, decay=0.04, lp=350))


def sfx_sparkle():
    out = np.zeros(n_samp(0.7))
    penta = [2093, 2349, 2637, 3136, 3520, 4186]
    for i in range(8):
        f = penta[int(_rng.integers(0, len(penta)))]
        s = int((i * 0.07 + _rng.random() * 0.02) * SR)
        seg = _tone(f, 0.18, "sine", 0.30, decay=0.09)
        seg += 0.4 * _tone(f * 2, 0.18, "sine", 0.12, decay=0.09)
        out[s:s + len(seg)] += seg
    return out


def sfx_countdown():
    return _tone(880, 0.16, "square", 0.36, decay=0.09, cut=2600)


def sfx_whistle():
    a = _tone(2100, 0.30, "sine", 0.4, f1=2500, vib=(9, 0.02), decay=0.2)
    b = _tone(2500, 0.34, "sine", 0.4, f1=2900, vib=(9, 0.02), decay=0.24)
    out = np.zeros(n_samp(0.72))
    out[:len(a)] += a
    out[int(0.34 * SR):int(0.34 * SR) + len(b)] += b
    return out


def sfx_buzzer():
    n = n_samp(0.45)
    x = (osc("square", 140, n) + osc("square", 141.5, n)) * 0.5
    return lowpass(x * env_ar(n, 0.008, 0.06) * 0.42, 900)


def sfx_powerup():
    out = np.zeros(n_samp(0.8))
    scale = [523, 587, 659, 784, 880, 1047, 1175, 1319]
    for i, f in enumerate(scale):
        s = int(i * 0.085 * SR)
        seg = _tone(f, 0.20, "square", 0.26, decay=0.11, cut=3400)
        out[s:s + len(seg)] += seg
    return out


def sfx_jump():
    return _tone(280, 0.26, "sine", 0.5, f1=720, decay=0.14)


def sfx_land():
    return _mix(_tone(170, 0.20, "sine", 0.5, f1=62, decay=0.09),
                _nz(0.08, 0.22, decay=0.035, lp=500))


def sfx_shoot():
    return _tone(950, 0.20, "square", 0.36, f1=140, decay=0.10, cut=3600)


def sfx_hit():
    return _nz(0.16, 0.5, decay=0.05, lp=1600) + \
        _tone(220, 0.16, "sine", 0.5, f1=90, decay=0.07)


def sfx_heal():
    out = np.zeros(n_samp(0.65))
    for i, f in enumerate([660, 880, 1100]):
        s = int(i * 0.14 * SR)
        seg = _tone(f, 0.30, "sine", 0.36, attack=0.03, decay=0.18)
        out[s:s + len(seg)] += seg
    return out


def sfx_unlock():
    out = _nz(0.05, 0.4, hp=2000)
    out = np.pad(out, (0, n_samp(0.5) - len(out)))
    ding = _tone(1319, 0.42, "sine", 0.42, decay=0.25)
    s = int(0.07 * SR)
    out[s:s + len(ding)] += ding
    return out


def sfx_door():
    knock = _tone(150, 0.10, "sine", 0.5, f1=90, decay=0.05)
    creak = sweep_wave("saw", 130, 92, n_samp(0.55), vib=(5, 0.06))
    creak = lowpass(creak * env_ar(n_samp(0.55), 0.08, 0.15) * 0.30, 620)
    out = np.zeros(n_samp(0.72))
    out[:len(knock)] += knock
    out[int(0.10 * SR):int(0.10 * SR) + len(creak)] += creak
    return out


def sfx_chest():
    knock = _mix(_tone(185, 0.12, "sine", 0.55, f1=110, decay=0.06),
                 _nz(0.06, 0.3, decay=0.03, lp=900))
    ding = _tone(1046, 0.40, "sine", 0.40, decay=0.24)
    out = np.zeros(n_samp(0.58))
    out[:len(knock)] += knock
    out[int(0.14 * SR):int(0.14 * SR) + len(ding)] += ding
    return out


def sfx_bubble():
    return _tone(420, 0.30, "sine", 0.45, f1=980, vib=(22, 0.10), decay=0.16)


def sfx_zap():
    return _mix(_nz(0.20, 0.42, decay=0.06, hp=2200),
                _tone(3000, 0.16, "square", 0.26, f1=800, decay=0.07, cut=6000))


def sfx_fanfare():
    out = np.zeros(n_samp(1.25))
    notes = [262, 330, 392, 523, 659, 784]
    for i, f in enumerate(notes):
        s = int(i * 0.13 * SR)
        seg = _tone(f, 0.24, "square", 0.28, decay=0.14, cut=2600,
                    vib=(6, 0.015))
        out[s:s + len(seg)] += seg
    fin = _tone(1046, 0.45, "square", 0.30, decay=0.3, cut=2600, vib=(6, 0.02))
    s = int(6 * 0.13 * SR)
    out[s:s + len(fin)] += fin
    return out


def sfx_notify():
    out = np.zeros(n_samp(0.45))
    a = _tone(784, 0.16, "sine", 0.42, decay=0.10)
    b = _tone(1046, 0.30, "sine", 0.42, decay=0.20)
    out[:len(a)] += a
    out[int(0.13 * SR):int(0.13 * SR) + len(b)] += b
    return out


def sfx_error():
    out = np.zeros(n_samp(0.45))
    for i in range(2):
        s = int(i * 0.20 * SR)
        seg = _tone(220, 0.16, "square", 0.34, decay=0.09, cut=850)
        out[s:s + len(seg)] += seg
    return out


SFX = [
    ("ui_click", sfx_ui_click), ("ui_hover", sfx_ui_hover),
    ("ui_back", sfx_ui_back), ("success", sfx_success),
    ("fail", sfx_fail), ("pop", sfx_pop),
    ("coin", sfx_coin), ("whoosh", sfx_whoosh),
    ("explosion", sfx_explosion), ("splash", sfx_splash),
    ("laser", sfx_laser), ("thud", sfx_thud),
    ("sparkle", sfx_sparkle), ("countdown", sfx_countdown),
    ("whistle", sfx_whistle), ("buzzer", sfx_buzzer),
    ("powerup", sfx_powerup), ("jump", sfx_jump),
    ("land", sfx_land), ("shoot", sfx_shoot),
    ("hit", sfx_hit), ("heal", sfx_heal),
    ("unlock", sfx_unlock), ("door", sfx_door),
    ("chest", sfx_chest), ("bubble", sfx_bubble),
    ("zap", sfx_zap), ("fanfare", sfx_fanfare),
    ("notify", sfx_notify), ("error", sfx_error),
]


def sfx_engine_roar():
    """Seamless 4 s jet-roar loop (v0.9.1, Sky Traffic): lowpassed noise +
    low hum stack + slow prop wobble. Hum/LFO frequencies complete integer
    cycles in the final 4.0 s; the noise tail is crossfaded into the head
    for click-free looping. Played on a looping AudioStreamPlayer3D with
    distance-mapped volume, so it is NOT in the one-shot SFX registry."""
    dur, xf = 4.5, 0.5
    n = n_samp(dur)
    t = t_arr(n)
    rumble = lowpass(noise(n), 240) * 0.9
    hum = (osc("sine", 55.0, n) * 0.50 + osc("sine", 82.5, n) * 0.30
           + osc("sine", 110.0, n) * 0.22)
    wob = 0.75 + 0.25 * np.sin(2 * np.pi * 1.0 * t) * np.sin(2 * np.pi * 0.5 * t + 1.3)
    x = (rumble + hum) * wob
    k = int(xf * SR)
    ramp = np.linspace(0.0, 1.0, k)
    head = x[:k] * ramp + x[-k:] * (1.0 - ramp)
    x = np.concatenate([head, x[k:-k]])
    return finalize(x, 0.80)


# Looping ambient SFX (exempt from the one-shot duration assert).
LOOPS = [
    ("engine_roar", sfx_engine_roar),
]


# ================================================================ MUSIC ENGINE
# Small offline sequencer: 12-bar loops at per-genre tempo, modest intensity
# (background music, not lead). Layers: pad, bass, lead, percussion, texture.

def midi(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def place(buf, x, start_s: float):
    s = int(start_s * SR)
    if s >= len(buf):
        return
    e = min(len(buf), s + len(x))
    if e > s:
        buf[s:e] += x[:e - s]


def note(buf, start: float, dur: float, wave: str, m: float, gain: float = 0.28,
         attack: float = 0.01, rel: float = 0.06, cut=None, vib=None,
         detune: float = 0.0):
    n = n_samp(dur)
    f = midi(m)
    if detune > 0:
        x = 0.6 * osc(wave, f, n) + 0.4 * osc(wave, f * (1 + detune), n)
    elif vib is not None:
        x = sweep_wave(wave, f, f, n, vib=vib)
    else:
        x = osc(wave, f, n)
    x = x * env_ar(n, attack, min(rel, dur * 0.5)) * gain
    if cut:
        x = lowpass(x, cut)
    place(buf, x, start)


def kick(buf, t: float, gain: float = 0.5):
    n = n_samp(0.14)
    x = _clickfix(sweep_wave("sine", 130, 42, n) * env_decay(n, 0.05) * gain)
    place(buf, x, t)


def snare(buf, t: float, gain: float = 0.30, tone_gain: float = 0.5):
    n = n_samp(0.14)
    x = highpass(noise(n), 1400) * env_decay(n, 0.045) * gain
    x = x + osc("sine", 190, n) * env_decay(n, 0.03) * gain * tone_gain
    place(buf, _clickfix(x), t)


def hat(buf, t: float, gain: float = 0.13, open_: bool = False):
    d = 0.10 if open_ else 0.035
    n = n_samp(d)
    x = highpass(noise(n), 7500) * env_decay(n, 0.05 if open_ else 0.012) * gain
    place(buf, _clickfix(x), t)


def shaker(buf, t: float, gain: float = 0.11):
    n = n_samp(0.09)
    x = highpass(noise(n), 6000) * env_ar(n, 0.012, 0.06) * gain
    place(buf, _clickfix(x), t)


def bongo(buf, t: float, m: float, gain: float = 0.38):
    f = midi(m)
    n = n_samp(0.16)
    x = _clickfix(sweep_wave("sine", f, f * 0.55, n)
                  * env_decay(n, 0.07) * gain)
    place(buf, x, t)


def pluck(buf, start: float, dur: float, wave: str, m: float, gain: float = 0.32,
          cut: float = 2600, vib=None):
    note(buf, start, dur, wave, m, gain, attack=0.004, rel=dur * 0.75,
         cut=cut, vib=vib)


def pad(buf, start: float, dur: float, chord, gain: float = 0.13,
        cut: float = 1100, wave: str = "saw", attack: float = None,
        detune: float = 0.004):
    a = attack if attack is not None else dur * 0.30
    n = n_samp(dur)
    e = env_ar(n, a, dur * 0.30)
    for m in chord:
        x = (0.55 * osc(wave, midi(m), n)
             + 0.45 * osc(wave, midi(m) * (1 + detune), n))
        x = lowpass(x * e * gain / max(1, len(chord)) * 2.2, cut)
        place(buf, x, start)


def bell(buf, t: float, m: float, gain: float = 0.30, dur: float = 1.6):
    """FM-ish bell: sine + 2.4x partial, long decay."""
    n = n_samp(dur)
    f = midi(m)
    x = osc("sine", f, n) + 0.35 * osc("sine", f * 2.4, n)
    x = _clickfix(x * env_decay(n, dur * 0.45) * gain)
    place(buf, x, t)


def whale(buf, t: float, f0: float, f1: float, dur: float = 1.8,
          gain: float = 0.22):
    n = n_samp(dur)
    x = sweep_wave("sine", f0, f1, n, vib=(2.5, 0.03))
    x = x * env_ar(n, dur * 0.3, dur * 0.4) * gain
    place(buf, lowpass(x, 900), t)


def render_song(bpm: float, bars: int, compose_fn, seed: int):
    """Render `bars` bars. The final XF seconds crossfade into the track's own
    natural decay tail, so the wrap (last sample -> first sample) is a quiet
    bed flowing into the downbeat -- no click, and the downbeat stays intact.
    Compose functions must keep continuous beds periodic over the loop
    (see g_lofi / g_underwater) so the tail matches the head."""
    beat = 60.0 / bpm
    total = bars * 4 * beat
    xf = 0.5
    buf = np.zeros(n_samp(total + xf + 0.3))
    rng = np.random.default_rng(seed)
    compose_fn(buf, beat, bars, rng)
    n_total = n_samp(total)
    n_xf = n_samp(xf)
    out = buf[:n_total].copy()
    r = np.linspace(0.0, 1.0, n_xf)
    out[n_total - n_xf:] = (out[n_total - n_xf:] * (1.0 - r)
                            + buf[n_total:n_total + n_xf] * r)
    return finalize(out)


def _prog_roots(prog, bar_idx):
    return prog[bar_idx % len(prog)]


# ================================================================ GENRE LOOPS
# All original compositions (seeded RNG melodies on diatonic scales).
# 12 bars each so the raw total stays under ~15 MB.

def _walk(rng, scale, n_steps, start=0):
    idx = start
    out = []
    for _ in range(n_steps):
        out.append(scale[idx % len(scale)])
        idx = max(0, min(len(scale) - 1, idx + int(rng.integers(-2, 3))))
    return out


def g_chiptune(buf, beat, bars, rng):
    # 142 BPM square-wave energy: arp lead, driving 8th bass, 4-floor kick.
    prog = [(48, [0, 4, 7]), (43, [0, 4, 7]), (45, [0, 3, 7]), (41, [0, 4, 7])]
    penta = [60, 62, 64, 67, 69, 72, 74, 76, 79]
    mel = _walk(rng, penta, bars * 8, 4)
    for bar in range(bars):
        bt = bar * 4 * beat
        root, iv = _prog_roots(prog, bar)
        for s in range(8):  # 8th-note lead
            if rng.random() < 0.82:
                note(buf, bt + s * beat / 2, beat * 0.45, "square",
                     mel[bar * 8 + s], 0.20, cut=3400)
        for s in range(8):  # 8th-note bass
            note(buf, bt + s * beat / 2, beat * 0.4, "square", root,
                 0.24, cut=900)
        for b in range(4):
            kick(buf, bt + b * beat, 0.5)
            if b % 2 == 1:
                snare(buf, bt + b * beat, 0.26)
        for s in range(8):
            hat(buf, bt + s * beat / 2, 0.10)
        pad(buf, bt, beat, [root + 12 + i for i in iv], gain=0.07,
            cut=2400, wave="tri", attack=0.01)


def g_horror(buf, beat, bars, rng):
    # 88 BPM dread: detuned drone, sparse bells, tritone hits, noise swells.
    for bar in range(bars):
        bt = bar * 4 * beat
        if bar % 4 == 0:
            pad(buf, bt, 4 * 4 * beat, [38, 44, 50], gain=0.15, cut=700,
                attack=2.0)
        # sparse bell motif, one note per bar
        motif = [62, 60, 58, 57, 62, 58, 60, 55, 62, 60, 58, 62]
        bell(buf, bt + beat * 1.5, motif[bar % 12], 0.26)
        # sub rumble whole note
        note(buf, bt, 4 * beat, "sine", 26, 0.22, attack=1.0, rel=1.5)
        # deep taiko on phrase starts
        if bar % 4 == 0:
            kick(buf, bt, 0.55)
        # tritone stab every 8 bars
        if bar % 8 == 4:
            note(buf, bt, beat, "saw", 38, 0.20, cut=500)
            note(buf, bt, beat, "saw", 44, 0.20, cut=500)
        # noise swell each 4-bar phrase
        if bar % 4 == 2:
            n = n_samp(4 * beat)
            sw = lowpass(noise(n), 420) * np.sin(np.pi * t_arr(n)
                                                 / (4 * beat)) ** 2 * 0.20
            place(buf, sw, bt)


def g_tropical(buf, beat, bars, rng):
    # 104 BPM island: steel-drum lead, offbeat chops, shaker, bongos.
    prog = [(41, [0, 4, 7]), (48, [0, 4, 7]), (43, [0, 4, 7]), (41, [0, 4, 7])]
    penta = [65, 67, 69, 72, 74, 77, 79, 81]
    mel = _walk(rng, penta, bars * 8, 3)
    for bar in range(bars):
        bt = bar * 4 * beat
        root, iv = _prog_roots(prog, bar)
        for s in range(8):
            if rng.random() < 0.66:
                t = bt + s * beat / 2
                note(buf, t, beat * 0.4, "sine", mel[bar * 8 + s], 0.26)
                note(buf, t, beat * 0.4, "sine", mel[bar * 8 + s] + 12, 0.10)
        for b, off in [(0, 0.0), (1, 0.5), (3, 0.0)]:  # bass on 1, 2&, 4
            note(buf, bt + (b + off) * beat, beat * 0.35, "sine", root,
                 0.30, cut=700)
        for b in [1, 3]:  # offbeat chord chops
            t = bt + (b + 0.5) * beat
            for i in iv:
                note(buf, t, beat * 0.22, "tri", root + 12 + i, 0.10,
                     cut=2200)
        for s in range(16):
            shaker(buf, bt + s * beat / 4, 0.07 if s % 2 else 0.11)
        bongo(buf, bt, root + 12, 0.30)
        bongo(buf, bt + 1.75 * beat, root + 14, 0.24)
        bongo(buf, bt + 3.5 * beat, root + 12, 0.26)


def g_western(buf, beat, bars, rng):
    # 100 BPM frontier: twangy lead, walking bass, train beat.
    prog = [(43, [0, 4, 7]), (38, [0, 4, 7]), (43, [0, 4, 7]), (50, [0, 4, 7])]
    penta = [67, 69, 71, 74, 76, 79, 81]
    mel = _walk(rng, penta, bars * 8, 2)
    sw = 0.10
    for bar in range(bars):
        bt = bar * 4 * beat
        root, iv = _prog_roots(prog, bar)
        for s in range(8):
            if rng.random() < 0.72:
                t = bt + s * beat / 2 + (sw * beat / 2 if s % 2 else 0)
                pluck(buf, t, beat * 0.5, "square", mel[bar * 8 + s], 0.22,
                      cut=2400)
        for b in range(4):  # walking bass root-5th
            note(buf, bt + b * beat, beat * 0.42, "sine",
                 root + (7 if b % 2 else 0), 0.30, cut=600)
        for b in range(4):  # train beat
            if b % 2 == 0:
                kick(buf, bt + b * beat, 0.42)
            else:
                snare(buf, bt + b * beat, 0.24)
            hat(buf, bt + b * beat + (sw * beat if b % 2 == 0 else 0), 0.09)
            hat(buf, bt + b * beat + beat / 2, 0.07)
        pad(buf, bt, 4 * beat, [root + 12 + i for i in iv], gain=0.07,
            cut=900, wave="tri")


def g_underwater(buf, beat, bars, rng):
    # 80 BPM abyss: deep sine pads, whale calls, bubble arps, water bed.
    prog_roots = [33, 33, 29, 31]  # A1 A1 F1 G1
    penta = [57, 59, 61, 64, 66, 69, 71]
    for bar in range(bars):
        bt = bar * 4 * beat
        root = prog_roots[bar % 4]
        if bar % 4 == 0:
            pad(buf, bt, 4 * 4 * beat, [root, root + 7, root + 12, root + 16],
                gain=0.15, cut=600, wave="sine", attack=3.0)
        note(buf, bt, 4 * beat, "sine", root, 0.26, attack=1.2, rel=1.5)
        if bar in (2, 6, 10):
            whale(buf, bt + beat, 320, 620, 1.8, 0.18)
            whale(buf, bt + 2.6 * beat, 520, 260, 1.5, 0.14)
        # bubble arp: sparse rising blips
        for s in range(0, 16, 2):
            if rng.random() < 0.4:
                m = penta[(bar + s) % len(penta)]
                note(buf, bt + s * beat / 4, beat * 0.3, "sine", m, 0.11,
                     cut=3000)
    # water bed: exactly one loop period; LFO uses an integer number of
    # cycles per loop so the bed is periodic and wraps cleanly.
    n = n_samp(bars * 4 * beat)
    t = t_arr(n)
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * 4 * t / (n / SR))
    bed = lowpass(noise(n), 500) * lfo * 0.07
    buf[:n] += bed
    buf[:] = echo(buf, 0.31, 0.40, 0.22)


def g_epic(buf, beat, bars, rng):
    # 132 BPM battle: ostinato strings, brass stabs, timpani, choir pad.
    prog = [(38, [0, 3, 7]), (34, [0, 4, 7]), (41, [0, 4, 7]), (36, [0, 4, 7])]
    ost = [50, 50, 53, 50, 55, 53, 50, 48, 50, 50, 53, 57, 55, 53, 52, 50]
    for bar in range(bars):
        bt = bar * 4 * beat
        root, iv = _prog_roots(prog, bar)
        boost = 1.18 if 4 <= bar < 8 else 1.0
        for s in range(16):  # string ostinato
            note(buf, bt + s * beat / 4, beat * 0.24, "saw",
                 ost[s % 16] + (12 if bar >= 8 else 0), 0.15 * boost,
                 cut=1500)
        for b, bl in [(0, 1.0), (2, 0.8)]:  # brass stabs
            for i in iv:
                note(buf, bt + b * beat, beat * 0.5, "saw", root + 12 + i,
                     0.16 * boost, cut=1900)
        kick(buf, bt, 0.55 * boost)  # timpani-ish
        kick(buf, bt + 2 * beat, 0.45 * boost)
        kick(buf, bt + 3.5 * beat, 0.40 * boost)
        snare(buf, bt + 3 * beat, 0.22 * boost)
        bongo(buf, bt, root, 0.42 * boost)  # taiko on bar starts
        pad(buf, bt, 4 * beat, [root + 12 + i for i in iv], gain=0.11,
            cut=1200, detune=0.004)


def g_lofi(buf, beat, bars, rng):
    # 84 BPM chill: rhodes 7ths with swing, vinyl crackle, soft drums.
    chords = [[41, 45, 48, 52], [40, 43, 47, 50],
              [38, 41, 45, 48], [36, 40, 43, 47]]
    sw = 0.14
    # vinyl bed: exactly one loop period of noise -> periodic, wraps cleanly
    n = n_samp(bars * 4 * beat)
    vinyl = lowpass(noise(n), 4200) * 0.028  # vinyl bed
    pops = np.zeros(n)
    for _ in range(40):
        p = int(rng.integers(0, n))
        pops[p:p + 40] += np.linspace(0.5, 0, 40) * rng.random()
    buf[:n] += vinyl + pops * 0.05
    for bar in range(bars):
        bt = bar * 4 * beat
        ch = chords[bar % 4]
        for i, m in enumerate(ch):  # rhodes-ish chord, swung hits
            for hit, dl in [(0, 0.0), (1.5, sw), (3, 0.0)]:
                t = bt + (hit + dl) * beat
                note(buf, t, beat * 0.9, "sine", m, 0.13, cut=1500)
                note(buf, t, beat * 0.9, "tri", m, 0.08, cut=1500)
        kick(buf, bt, 0.42)
        kick(buf, bt + 2.5 * beat + sw * beat * 0.5, 0.34)
        snare(buf, bt + beat, 0.20)
        snare(buf, bt + 3 * beat, 0.20)
        for s in range(8):
            hat(buf, bt + s * beat / 2 + (sw * beat / 2 if s % 2 else 0),
                0.07)
        note(buf, bt, beat * 1.4, "sine", chords[bar % 4][0] - 12, 0.28,
             cut=500)
        note(buf, bt + 2.5 * beat, beat, "sine", chords[bar % 4][0] - 5,
             0.24, cut=500)


def g_carnival(buf, beat, bars, rng):
    # 126 BPM midway: calliope lead, oom-pah tuba, march snare.
    prog = [(48, [0, 4, 7]), (43, [0, 4, 7]), (48, [0, 4, 7]),
            (55, [0, 4, 7]), (48, [0, 4, 7])]
    scale = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76]
    mel = _walk(rng, scale, bars * 8, 5)
    for bar in range(bars):
        bt = bar * 4 * beat
        root, iv = _prog_roots(prog, bar)
        for s in range(8):
            if rng.random() < 0.85:
                note(buf, bt + s * beat / 2, beat * 0.42, "square",
                     mel[bar * 8 + s], 0.20, cut=3000)
                if bar >= 6:  # piccolo counter-melody, second half
                    note(buf, bt + s * beat / 2, beat * 0.4, "sine",
                         mel[bar * 8 + s] + 12, 0.07, cut=4200)
        for b in range(4):  # oom-pah tuba
            note(buf, bt + b * beat, beat * 0.45, "sine",
                 root + (7 if b % 2 else 0), 0.32, cut=550)
        for b in [1, 3]:  # offbeat chord stabs
            for i in iv:
                note(buf, bt + (b + 0.5) * beat, beat * 0.2, "square",
                     root + 12 + i, 0.09, cut=2400)
        for s in range(8):  # march snare 8ths + roll at phrase end
            snare(buf, bt + s * beat / 2, 0.16)
        if bar % 4 == 3:
            for k in range(6):
                snare(buf, bt + 3.5 * beat + k * beat / 12, 0.14)


def g_scifi(buf, beat, bars, rng):
    # 110 BPM orbit: space pads, 16th arp, sub pulses, pings.
    penta = [57, 60, 62, 64, 67, 69, 72]
    arp = _walk(rng, penta, bars * 16, 2)
    for bar in range(bars):
        bt = bar * 4 * beat
        if bar % 2 == 0:
            pad(buf, bt, 2 * 4 * beat, [45, 48, 52, 57], gain=0.13,
                cut=950, detune=0.005, attack=1.5)
        for s in range(16):
            note(buf, bt + s * beat / 4, beat * 0.22, "sine",
                 arp[bar * 16 + s], 0.14, cut=2500)
        for b in range(8):  # sub pulses
            note(buf, bt + b * beat / 2, beat * 0.2, "sine", 33, 0.20,
                 cut=300)
        for b in range(4):
            kick(buf, bt + b * beat, 0.34)
        for s in range(16):
            hat(buf, bt + s * beat / 4, 0.06)
        if rng.random() < 0.7:  # radar ping
            bell(buf, bt + rng.random() * 3 * beat, 81, 0.12, dur=1.2)
    buf[:] = echo(buf, 0.23, 0.32, 0.18)


def g_folk(buf, beat, bars, rng):
    # 116 BPM hoedown: plucked lead, fiddle answers, strummed backbeat.
    prog = [(43, [0, 4, 7]), (48, [0, 4, 7]), (43, [0, 4, 7]), (50, [0, 4, 7])]
    scale = [67, 69, 71, 72, 74, 76, 78, 79]
    mel = _walk(rng, scale, bars * 8, 3)
    for bar in range(bars):
        bt = bar * 4 * beat
        root, iv = _prog_roots(prog, bar)
        for s in range(8):
            if rng.random() < 0.78:
                pluck(buf, bt + s * beat / 2, beat * 0.55, "tri",
                      mel[bar * 8 + s], 0.28)
        if bar % 2 == 1:  # fiddle answer phrase
            for s in range(4):
                note(buf, bt + s * beat, beat * 0.8, "saw",
                     mel[bar * 8 + s * 2] + 12, 0.12, cut=2300,
                     vib=(6, 0.02))
        for b in [0, 2]:  # bass on 1 & 3
            note(buf, bt + b * beat, beat * 0.5, "sine",
                 root + (7 if b == 2 else 0), 0.30, cut=550)
        for b in [1, 3]:  # strummed backbeat ticks
            tick = _nz(0.05, 0.10, hp=2500)
            place(buf, tick, bt + b * beat)
            for i in iv:
                note(buf, bt + b * beat, beat * 0.25, "tri", root + 12 + i,
                     0.07, cut=2600)
        for s in range(8):
            shaker(buf, bt + s * beat / 2, 0.06)


def g_menu(buf, beat, bars, rng):
    # 96 BPM welcome: music-box chimes, warm pad, soft bass, no drums.
    scale = [72, 74, 76, 79, 81, 84]
    mel = _walk(rng, scale, bars * 4, 2)
    for bar in range(bars):
        bt = bar * 4 * beat
        for b in range(4):
            m = mel[bar * 4 + b]
            note(buf, bt + b * beat, beat * 0.9, "sine", m, 0.24)
            note(buf, bt + b * beat, beat * 0.9, "sine", m + 12, 0.07)
        pad(buf, bt, 4 * beat, [48, 52, 55, 60], gain=0.10, cut=1000,
            wave="tri")
        note(buf, bt, 4 * beat, "sine", 36, 0.24, attack=0.4, rel=1.0,
             cut=400)
        if bar >= 6:  # sparkle arp in the second half
            for s in range(0, 16, 4):
                note(buf, bt + s * beat / 4, beat * 0.3, "sine",
                     scale[(bar + s) % len(scale)] + 12, 0.07, cut=5000)
    buf[:] = echo(buf, 0.29, 0.30, 0.16)


GENRES = [
    ("chiptune", 142, g_chiptune),
    ("horror", 88, g_horror),
    ("tropical", 104, g_tropical),
    ("western", 100, g_western),
    ("underwater", 80, g_underwater),
    ("epic", 132, g_epic),
    ("lofi", 84, g_lofi),
    ("carnival", 126, g_carnival),
    ("scifi", 110, g_scifi),
    ("folk", 116, g_folk),
    ("menu_theme", 96, g_menu),
]
BARS = 12


# ---------------------------------------------------------------- main
def main():
    total_sfx = 0
    total_mus = 0
    print(f"sample rate {SR} Hz, 16-bit mono")
    print(f"--- SFX ({len(SFX)}) -> {SFX_DIR} ---")
    for name, fn in SFX:
        x = np.asarray(fn(), dtype=np.float64)
        assert x.ndim == 1 and x.size > 0, name
        dur, peak = write_wav(SFX_DIR / f"{name}.wav", x)
        total_sfx += (SFX_DIR / f"{name}.wav").stat().st_size
        assert 0.05 <= dur <= 1.6, f"{name}: odd duration {dur:.2f}s"
        print(f"  {name:12s} {dur:5.2f}s peak {peak:.2f}")
    for name, fn in LOOPS:
        x = np.asarray(fn(), dtype=np.float64)
        assert x.ndim == 1 and x.size > 0, name
        dur, peak = write_wav(SFX_DIR / f"{name}.wav", x)
        total_sfx += (SFX_DIR / f"{name}.wav").stat().st_size
        print(f"  {name:12s} {dur:5.2f}s peak {peak:.2f} (loop)")
    print(f"--- MUSIC ({len(GENRES)}, {BARS} bars) -> {MUS_DIR} ---")
    for i, (name, bpm, fn) in enumerate(GENRES):
        x = render_song(bpm, BARS, fn, seed=1000 + i)
        dur, peak = write_wav(MUS_DIR / f"{name}.wav", x)
        total_mus += (MUS_DIR / f"{name}.wav").stat().st_size
        print(f"  {name:12s} {bpm}bpm {dur:5.1f}s peak {peak:.2f}")
    print(f"TOTAL sfx: {total_sfx / 1e6:.2f} MB | "
          f"music: {total_mus / 1e6:.2f} MB (budget 15 MB)")


if __name__ == "__main__":
    main()
