#!/usr/bin/env python3
"""v0.11.0 per-game SFX synthesis for the 5 new NEXUS ARCADE games.
Reuses tools/gen_audio.py helpers (numpy/scipy, no licensed assets).
Outputs 16-bit mono WAV at 22050 Hz into assets/audio/sfx/.
Run: python3 tools/gen_v0110_audio.py
"""
import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from gen_audio import (
    n_samp, t_arr, env_ar, env_decay, osc, sweep_wave, noise,
    lowpass, highpass, echo, _clickfix, finalize, write_wav,
    _tone, _nz, _mix, SR,
)

SFX_DIR = ROOT / "assets" / "audio" / "sfx"


# ------------------------------------------------------- NULL-G LEAGUE ---
def sfx_nullg_throw():
    # Rising airy whoosh: filtered noise sweep up + soft sine lift.
    n = n_samp(0.45)
    sw = sweep_wave("sine", 300, 900, n) * env_ar(n, 0.05, 0.2) * 0.35
    nz = _clickfix(highpass(noise(n), 800)) * env_ar(n, 0.02, 0.25) * 0.4
    return _mix(sw, nz)


def sfx_nullg_catch():
    # Soft glove thump + click.
    return _mix(_tone(180, 0.12, "sine", 0.7, decay=0.05),
                _nz(0.03, 0.35, hp=2500))


def sfx_nullg_goal():
    # Airy goal fanfare: rising major arpeggio, breathy.
    out = np.zeros(n_samp(1.1))
    for i, f in enumerate([392.0, 523.25, 659.25, 783.99]):
        seg = _mix(_tone(f, 0.35, "sine", 0.4, decay=0.3),
                   _tone(f * 2.0, 0.35, "sine", 0.12, decay=0.3))
        s = int(i * 0.11 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_nullg_wallpush():
    # Deep soft thud (pushing off a wall).
    return _mix(_tone(90, 0.25, "sine", 0.8, f1=45, decay=0.18),
                _nz(0.06, 0.25, lp=500))


def sfx_nullg_buzzer():
    # Match horn: two detuned saws, 0.7s.
    n = n_samp(0.7)
    x = (osc("saw", 196, n) + osc("saw", 207, n)) * 0.25
    return lowpass(x, 1200) * env_ar(n, 0.02, 0.15)


def sfx_nullg_tick():
    return _tone(1200, 0.06, "sine", 0.5, decay=0.03)


# ------------------------------------------------------- CHRONO HEIST ---
def sfx_chrono_loopstart():
    # Time-reverse sweep + chime: sweep down then a bright ping.
    n = n_samp(0.8)
    sw = sweep_wave("sine", 1200, 200, n) * env_ar(n, 0.01, 0.4) * 0.3
    chime = _tone(1568, 0.5, "sine", 0.4, decay=0.4)
    out = np.zeros(n_samp(1.0))
    out[:n] += sw
    s = int(0.45 * SR)
    out[s:s + len(chime)] += chime
    return out


def sfx_chrono_paradox():
    # Harsh paradox static: crushed noise burst + dissonant cluster.
    n = n_samp(0.6)
    nz = np.sign(noise(n)) * 0.5  # bit-crushed static
    nz = highpass(nz, 400) * env_decay(n, 0.25)
    cl = (_tone(466, 0.6, "saw", 0.2, decay=0.5) +
          _tone(492, 0.6, "saw", 0.2, decay=0.5))
    return _mix(nz, cl)


def sfx_chrono_keycard():
    # Double accept beep.
    out = np.zeros(n_samp(0.3))
    for i, f in enumerate([880, 1320]):
        seg = _tone(f, 0.09, "sine", 0.5, decay=0.07)
        s = int(i * 0.11 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_chrono_safe():
    # Tumbler clicks + heavy vault clunk.
    out = np.zeros(n_samp(0.9))
    for i in range(3):
        seg = _mix(_tone(2200, 0.03, "sine", 0.4, decay=0.015),
                   _nz(0.02, 0.3, hp=3000))
        s = int(i * 0.16 * SR)
        out[s:s + len(seg)] += seg
    clunk = _mix(_tone(70, 0.4, "sine", 0.9, f1=35, decay=0.3),
                 _nz(0.08, 0.3, lp=400))
    s = int(0.5 * SR)
    out[s:s + len(clunk)] += clunk
    return out


def sfx_chrono_loot():
    # Soft treasure jingle.
    out = np.zeros(n_samp(0.6))
    for i, f in enumerate([1568, 2093, 2637]):
        seg = _tone(f, 0.2, "sine", 0.25, decay=0.18)
        s = int(i * 0.07 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_chrono_alarm():
    # Tripwire alarm: alternating two-tone, 0.8s.
    n = n_samp(0.8)
    t = t_arr(n)
    alt = (np.sin(2 * np.pi * 6 * t) > 0).astype(float)
    f = 660 + alt * 220
    return osc("square", 0, n, 0) * 0 + _clickfix(
        np.sin(2 * np.pi * f * t) * 0.35) * env_ar(n, 0.01, 0.1)


# ---------------------------------------------------- SIEGE ENGINEER ---
def sfx_siege_snap():
    # Wood knock: short resonant knock.
    return _mix(_tone(320, 0.09, "sine", 0.6, decay=0.05),
                _tone(640, 0.06, "sine", 0.25, decay=0.03),
                _nz(0.02, 0.3, hp=2000))


def sfx_siege_collapse():
    # Wood crash rumble: noise + low thumps.
    n = n_samp(1.0)
    nz = lowpass(noise(n), 700) * env_decay(n, 0.5) * 0.6
    out = nz.copy()
    for i in range(4):
        th = _tone(110 - i * 15, 0.2, "sine", 0.5, decay=0.15)
        s = int((0.05 + i * 0.18) * SR)
        out[s:s + len(th)] += th
    return out


def sfx_siege_launch():
    # Creak + release whoosh.
    n = n_samp(0.6)
    t = t_arr(n)
    creak = np.sin(2 * np.pi * (90 + 40 * np.sin(2 * np.pi * 7 * t)) * t)
    creak = lowpass(creak, 900) * env_ar(n, 0.15, 0.05) * 0.3
    whoosh = _clickfix(highpass(noise(n_samp(0.4)), 1000)) * env_ar(n_samp(0.4), 0.05, 0.15) * 0.5
    out = np.zeros(n_samp(0.7))
    out[:n] += creak
    s = int(0.28 * SR)
    out[s:s + len(whoosh)] += whoosh
    return out


def sfx_siege_hit():
    # Brick smash: noise crack + stone thud.
    return _mix(_nz(0.08, 0.7, hp=1200),
                _tone(140, 0.18, "sine", 0.6, f1=60, decay=0.12))


def sfx_siege_win():
    # Small victory flourish.
    out = np.zeros(n_samp(0.9))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        seg = _tone(f, 0.25, "sine", 0.4, decay=0.2)
        s = int(i * 0.13 * SR)
        out[s:s + len(seg)] += seg
    return out


# ----------------------------------------------------- SPECTRAL FILES ---
def sfx_spectral_emf():
    # EMF spike beep (geiger-like tick burst).
    out = np.zeros(n_samp(0.5))
    for i in range(5):
        seg = _tone(2000, 0.03, "sine", 0.45, decay=0.015)
        s = int(i * 0.09 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_spectral_static():
    # Spirit-box static wash with buried "voice" warble.
    n = n_samp(1.2)
    nz = highpass(noise(n), 900) * 0.35
    t = t_arr(n)
    voice = np.sin(2 * np.pi * (180 + 60 * np.sin(2 * np.pi * 4 * t)) * t)
    voice = lowpass(voice, 800) * 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * 2 * t))
    gate = (np.sin(2 * np.pi * 1.5 * t) > -0.2).astype(float)
    return _clickfix((nz + voice) * gate) * env_ar(n, 0.1, 0.3)


def sfx_spectral_shutter():
    # Camera shutter: two clicks.
    out = np.zeros(n_samp(0.25))
    c1 = _mix(_nz(0.02, 0.5, hp=2500), _tone(3000, 0.02, "sine", 0.3, decay=0.01))
    c2 = _mix(_nz(0.02, 0.4, hp=2500), _tone(2400, 0.02, "sine", 0.3, decay=0.01))
    out[:len(c1)] += c1
    s = int(0.09 * SR)
    out[s:s + len(c2)] += c2
    return out


def sfx_spectral_sting():
    # Horror sting: dissonant cluster swell.
    n = n_samp(1.4)
    t = t_arr(n)
    swell = np.sin(np.pi * np.clip(t / 1.4, 0, 1)) ** 2
    x = np.zeros(n)
    for f in [110, 116.5, 233, 247]:
        x += osc("saw", f, n) * 0.12
    return lowpass(x, 2000) * swell * env_ar(n, 0.05, 0.4)


def sfx_spectral_knock():
    # Ghost knock: three hollow knocks.
    out = np.zeros(n_samp(0.8))
    for i in range(3):
        seg = _mix(_tone(180, 0.1, "sine", 0.6, decay=0.06),
                   _nz(0.02, 0.3, hp=1500))
        s = int(i * 0.22 * SR)
        out[s:s + len(seg)] += seg
    return out


# --------------------------------------------------------- TERRAFORM ---
def sfx_terra_sculpt():
    # Low earth rumble morph.
    n = n_samp(0.7)
    nz = lowpass(noise(n), 300) * env_ar(n, 0.1, 0.3) * 0.6
    rumble = sweep_wave("sine", 60, 120, n) * env_ar(n, 0.1, 0.3) * 0.5
    return _mix(nz, rumble)


def sfx_terra_paint():
    # Soft brush sweep.
    n = n_samp(0.4)
    return _clickfix(highpass(noise(n), 2500)) * env_ar(n, 0.08, 0.2) * 0.35


def sfx_terra_seed():
    # Sparkle pop: bright pluck + shimmer.
    return _mix(_tone(1320, 0.12, "sine", 0.4, f1=1980, decay=0.1),
                _tone(2640, 0.15, "sine", 0.2, decay=0.13))


def sfx_terra_disaster():
    # Deep meteor boom.
    n = n_samp(1.2)
    boom = sweep_wave("sine", 120, 30, n) * env_decay(n, 0.7) * 0.9
    nz = lowpass(noise(n), 500) * env_decay(n, 0.5) * 0.5
    return _mix(boom, nz)


def sfx_terra_epoch():
    # Time fast-forward whoosh: long rising sweep.
    n = n_samp(1.0)
    sw = sweep_wave("sine", 200, 1600, n) * env_ar(n, 0.2, 0.3) * 0.35
    nz = _clickfix(highpass(noise(n), 1200)) * env_ar(n, 0.2, 0.3) * 0.3
    return _mix(sw, nz)


SPECS = [
    # (file stem, fn)
    ("nullg_throw", sfx_nullg_throw),
    ("nullg_catch", sfx_nullg_catch),
    ("nullg_goal", sfx_nullg_goal),
    ("nullg_wallpush", sfx_nullg_wallpush),
    ("nullg_buzzer", sfx_nullg_buzzer),
    ("nullg_tick", sfx_nullg_tick),
    ("chrono_loopstart", sfx_chrono_loopstart),
    ("chrono_paradox", sfx_chrono_paradox),
    ("chrono_keycard", sfx_chrono_keycard),
    ("chrono_safe", sfx_chrono_safe),
    ("chrono_loot", sfx_chrono_loot),
    ("chrono_alarm", sfx_chrono_alarm),
    ("siege_snap", sfx_siege_snap),
    ("siege_collapse", sfx_siege_collapse),
    ("siege_launch", sfx_siege_launch),
    ("siege_hit", sfx_siege_hit),
    ("siege_win", sfx_siege_win),
    ("spectral_emf", sfx_spectral_emf),
    ("spectral_static", sfx_spectral_static),
    ("spectral_shutter", sfx_spectral_shutter),
    ("spectral_sting", sfx_spectral_sting),
    ("spectral_knock", sfx_spectral_knock),
    ("terra_sculpt", sfx_terra_sculpt),
    ("terra_paint", sfx_terra_paint),
    ("terra_seed", sfx_terra_seed),
    ("terra_disaster", sfx_terra_disaster),
    ("terra_epoch", sfx_terra_epoch),
]


def main():
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    for stem, fn in SPECS:
        x = finalize(fn())
        write_wav(SFX_DIR / (stem + ".wav"), x)
        print("wrote", stem)


if __name__ == "__main__":
    main()
