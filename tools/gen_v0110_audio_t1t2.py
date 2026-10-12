#!/usr/bin/env python3
"""v0.11.0 Tier-1/Tier-2 per-game SFX pack for NEXUS ARCADE.

Complements tools/gen_v0110_audio.py (which covered the 5 shipped new
games). This pack covers the Tech-Demo Engineer's T1 (duel, swarm,
ar-defender) and T2 (rhythm-boxer, sky_traffic, light_painter,
wizard_academy, mech_pilot, holo-dungeon, sky_pirates, ar_detective).

Reuses tools/gen_audio.py helpers (numpy/scipy, no licensed assets).
16-bit mono WAV at 22050 Hz into assets/audio/sfx/.
Run: python3 tools/gen_v0110_audio_t1t2.py
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


def _metallic_hit(freqs, dur, gain=0.5, decay=0.25):
    """Inharmonic partial stack + noise burst: swords, bells, clangs."""
    n = n_samp(dur)
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        x += osc("sine", f * (1.0 + 0.003 * i), n) * (gain / (i + 1))
    x = x * env_decay(n, decay)
    nz = _nz(0.03, 0.35, hp=3000)
    out = np.zeros(n)
    out += x
    out[:len(nz)] += nz
    return _clickfix(out)


# ------------------------------------------------------------- DUEL ---
def sfx_duel_swing():
    # Energy-blade swing: airy noise sweep up + low sine lift.
    n = n_samp(0.35)
    sw = sweep_wave("sine", 200, 1100, n) * env_ar(n, 0.03, 0.12) * 0.30
    nz = _clickfix(highpass(noise(n), 1500)) * env_ar(n, 0.02, 0.12) * 0.35
    return _mix(sw, nz)


def sfx_duel_clash():
    # Blade-on-blade: bright inharmonic clang + crack.
    return _metallic_hit([523, 831, 1244, 1866, 2493], 0.7, gain=0.45,
                         decay=0.35)


def sfx_duel_parry():
    # Shorter, higher deflection ring.
    return _metallic_hit([784, 1244, 1866, 2794], 0.45, gain=0.40,
                         decay=0.22)


def sfx_duel_block():
    # Forearm block: low thud + dull ring.
    return _mix(_tone(140, 0.20, "sine", 0.7, f1=70, decay=0.14),
                _metallic_hit([392, 587, 880], 0.35, gain=0.25,
                              decay=0.18))


def sfx_duel_hit():
    # Clean hit on opponent: zap crack + energy bloom.
    return _mix(_nz(0.06, 0.6, hp=1500),
                sweep_wave("sine", 400, 1600, n_samp(0.25))
                * env_ar(n_samp(0.25), 0.005, 0.15) * 0.45,
                _tone(120, 0.22, "sine", 0.6, f1=60, decay=0.16))


def sfx_duel_hum():
    # Seamless saber-hum loop: 100 Hz + harmonics + airy shimmer.
    secs = 2.0
    n = n_samp(secs)
    t = t_arr(n)
    x = (np.sin(2 * np.pi * 100 * t) * 0.30
         + np.sin(2 * np.pi * 200 * t) * 0.16
         + np.sin(2 * np.pi * 300 * t) * 0.09)
    shimmer = highpass(noise(n), 5000) * 0.04
    x = (x + shimmer) * 0.5
    # proper tail-into-head crossfade so the loop is click-free
    xf = int(0.1 * SR)
    tail = x[-xf:].copy()
    for i in range(xf):
        wgt = i / xf
        x[i] = x[i] * wgt + tail[i] * (1.0 - wgt) * 0.9
        x[n - xf + i] *= (1.0 - wgt)
    return _clickfix(x)


# ------------------------------------------------------------ SWARM ---
def sfx_swarm_die():
    # Alien pop: descending square blip + splat.
    return _mix(_tone(600, 0.18, "square", 0.35, f1=150, decay=0.14),
                _nz(0.08, 0.4, lp=1200))


def sfx_swarm_wave():
    # Wave-start siren: two-tone rise, 0.9 s.
    n = n_samp(0.9)
    t = t_arr(n)
    alt = (np.sin(2 * np.pi * 3 * t) > 0).astype(float)
    f = 520 + alt * 260
    return _clickfix(np.sin(2 * np.pi * f * t) * 0.28) * env_ar(n, 0.05, 0.2)


def sfx_swarm_base_hit():
    # Base takes damage: deep alarm thud.
    return _mix(_tone(90, 0.4, "sine", 0.8, f1=45, decay=0.3),
                _tone(220, 0.3, "square", 0.25, decay=0.2),
                _nz(0.1, 0.3, lp=800))


def sfx_swarm_overdrive():
    # Power surge pickup: rising power whine.
    n = n_samp(0.5)
    sw = sweep_wave("saw", 200, 1800, n) * env_ar(n, 0.05, 0.2) * 0.25
    return _clickfix(lowpass(sw, 3000))


# ------------------------------------------------------ AR-DEFENDER ---
def sfx_def_place():
    # Tower placement thunk: wood knock + stone settle.
    return _mix(_tone(320, 0.10, "sine", 0.55, decay=0.06),
                _tone(150, 0.18, "sine", 0.5, f1=80, decay=0.12),
                _nz(0.03, 0.3, hp=2000))


def sfx_def_die():
    # Enemy destroyed: crunchy pop.
    return _mix(_tone(500, 0.12, "square", 0.3, f1=200, decay=0.09),
                _nz(0.06, 0.45, hp=1200))


def sfx_def_horn():
    # Wave horn: low brass-ish blast.
    n = n_samp(0.8)
    x = (osc("saw", 146, n) + osc("saw", 155, n)) * 0.22
    return lowpass(x, 900) * env_ar(n, 0.08, 0.25)


def sfx_def_base_hit():
    # Base hit alarm: urgent two-tone + thud.
    n = n_samp(0.7)
    t = t_arr(n)
    alt = (np.sin(2 * np.pi * 5 * t) > 0).astype(float)
    f = 740 + alt * 180
    tone = _clickfix(np.sin(2 * np.pi * f * t) * 0.32) * env_ar(n, 0.02, 0.15)
    return _mix(tone, _tone(100, 0.3, "sine", 0.6, f1=50, decay=0.22))


# ------------------------------------------------------ RHYTHM-BOXER ---
def sfx_boxer_hit():
    # Glove connect: low thump + leather snap.
    return _mix(_tone(160, 0.14, "sine", 0.75, f1=70, decay=0.09),
                _nz(0.04, 0.5, hp=1800))


def sfx_boxer_combo():
    # Combo milestone: rising 3-note blip.
    out = np.zeros(n_samp(0.4))
    for i, f in enumerate([660, 880, 1174]):
        seg = _tone(f, 0.12, "sine", 0.45, decay=0.09)
        s = int(i * 0.08 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_boxer_bell():
    # Round bell: three metallic strikes.
    out = np.zeros(n_samp(1.9))
    for i in range(3):
        seg = _metallic_hit([1046, 1568, 2093, 2637], 0.8, gain=0.35,
                            decay=0.5)
        s = int(i * 0.45 * SR)
        e = min(s + len(seg), len(out))
        out[s:e] += seg[:e - s]
    return out


def sfx_boxer_block():
    # Glove block: dull padded thud.
    return _mix(_tone(220, 0.12, "sine", 0.6, f1=110, decay=0.08),
                _nz(0.03, 0.3, lp=1500))


# ------------------------------------------------------- SKY-TRAFFIC ---
def sfx_traffic_ping():
    # Radar ping: soft sine ping with echo tail.
    x = _tone(1320, 0.30, "sine", 0.45, decay=0.25)
    return echo(x, delay_s=0.22, fb=0.3, wet=0.3)


def sfx_traffic_pass():
    # Jet flyby: doppler-ish noise sweep, 2 s.
    n = n_samp(2.0)
    t = t_arr(n)
    # amplitude swell then fall = pass
    swell = np.sin(np.pi * np.clip(t / 2.0, 0, 1)) ** 1.5
    nz = _clickfix(lowpass(noise(n), 1100))
    return nz * swell * 0.55


# ------------------------------------------------------ LIGHT-PAINTER ---
def sfx_paint_stroke():
    # Brush sweep: soft filtered noise, 0.3 s.
    n = n_samp(0.3)
    return _clickfix(highpass(noise(n), 2800)) * env_ar(n, 0.06, 0.15) * 0.35


def sfx_paint_color():
    # Color-pick blip: two-note chime.
    out = np.zeros(n_samp(0.3))
    for i, f in enumerate([1046, 1568]):
        seg = _tone(f, 0.12, "sine", 0.4, decay=0.1)
        s = int(i * 0.07 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_paint_clear():
    # Canvas clear: reverse sweep (falling).
    n = n_samp(0.5)
    sw = sweep_wave("sine", 1400, 300, n) * env_ar(n, 0.05, 0.2) * 0.3
    return _clickfix(sw)


# ---------------------------------------------------- WIZARD-ACADEMY ---
def sfx_wiz_cast():
    # Spell cast shimmer: rising arpeggio + sparkle.
    out = np.zeros(n_samp(0.7))
    for i, f in enumerate([523, 659, 784, 1046, 1318]):
        seg = _tone(f, 0.25, "sine", 0.3, decay=0.2)
        s = int(i * 0.06 * SR)
        out[s:s + len(seg)] += seg
    return _clickfix(out)


def sfx_wiz_hit():
    # Spell impact: zap crack + arcane bloom.
    return _mix(_nz(0.07, 0.55, hp=1400),
                sweep_wave("sine", 900, 180, n_samp(0.3))
                * env_ar(n_samp(0.3), 0.005, 0.2) * 0.4,
                _tone(110, 0.25, "sine", 0.55, f1=55, decay=0.18))


def sfx_wiz_brew():
    # Potion brewing: bubbling blips.
    n = n_samp(1.0)
    out = np.zeros(n)
    rng = np.random.default_rng(7)
    for _ in range(14):
        f = float(rng.uniform(300, 900))
        dur = float(rng.uniform(0.04, 0.10))
        seg = _tone(f, dur, "sine", 0.35, f1=f * 1.6, decay=dur * 0.8)
        s = int(rng.uniform(0, 0.85) * SR)
        e = min(s + len(seg), n)
        out[s:e] += seg[:e - s]
    return _clickfix(out)


# -------------------------------------------------------- MECH-PILOT ---
def sfx_mech_step():
    # Heavy servo step: low thud + servo whine.
    n = n_samp(0.4)
    t = t_arr(n)
    servo = np.sin(2 * np.pi * 90 * t) * 0.12 * env_ar(n, 0.02, 0.1)
    return _mix(_tone(80, 0.3, "sine", 0.8, f1=40, decay=0.22),
                _clickfix(servo),
                _nz(0.05, 0.25, lp=500))


def sfx_mech_fire():
    # Shoulder cannon: punchy blast.
    return _mix(_tone(120, 0.35, "sine", 0.85, f1=45, decay=0.25),
                _nz(0.15, 0.5, lp=2000))


def sfx_mech_alarm():
    # Cockpit warning: urgent three-tone.
    out = np.zeros(n_samp(0.9))
    for i, f in enumerate([880, 660, 880]):
        seg = _tone(f, 0.18, "square", 0.28, decay=0.14)
        s = int(i * 0.25 * SR)
        out[s:s + len(seg)] += seg
    return _clickfix(out)


def sfx_mech_jump():
    # Jump jets: rising noise burst.
    n = n_samp(0.6)
    nz = _clickfix(lowpass(noise(n), 1200)) * env_ar(n, 0.15, 0.2) * 0.55
    sw = sweep_wave("sine", 150, 600, n) * env_ar(n, 0.15, 0.2) * 0.25
    return _mix(nz, sw)


# ------------------------------------------------------- HOLO-DUNGEON ---
def sfx_dung_sword():
    # Sword swing + hit: metal sweep then clang.
    n = n_samp(0.5)
    sw = sweep_wave("saw", 800, 2400, n_samp(0.2)) * 0.15
    sw = lowpass(sw, 4000) * env_ar(n_samp(0.2), 0.02, 0.1)
    out = np.zeros(n)
    out[:len(sw)] += sw
    clang = _metallic_hit([660, 990, 1320, 1980], 0.4, gain=0.4, decay=0.25)
    s = int(0.12 * SR)
    e = min(s + len(clang), len(out))
    out[s:e] += clang[:e - s]
    return _clickfix(out)


def sfx_dung_door():
    # Stone door grind: low rumble, 1 s.
    n = n_samp(1.0)
    nz = lowpass(noise(n), 250) * env_ar(n, 0.2, 0.3) * 0.6
    grind = (osc("saw", 55, n) * 0.12) * env_ar(n, 0.2, 0.3)
    return _clickfix(nz + grind)


def sfx_dung_key():
    # Key jingle: metallic ticks.
    out = np.zeros(n_samp(0.4))
    rng = np.random.default_rng(11)
    for _ in range(6):
        f = float(rng.uniform(2200, 4200))
        seg = _tone(f, 0.05, "sine", 0.3, decay=0.035)
        s = int(rng.uniform(0, 0.3) * SR)
        e = min(s + len(seg), len(out))
        out[s:e] += seg[:e - s]
    return _clickfix(out)


# -------------------------------------------------------- SKY-PIRATES ---
def sfx_pirate_cannon():
    # Broadside cannon: deep boom + crack.
    return _mix(_tone(70, 0.6, "sine", 0.9, f1=30, decay=0.45),
                _nz(0.2, 0.5, lp=1500))


def sfx_pirate_sail():
    # Sail flap: cloth noise bursts.
    n = n_samp(0.7)
    t = t_arr(n)
    flap = np.abs(np.sin(2 * np.pi * 6 * t)) ** 2
    nz = _clickfix(lowpass(noise(n), 900)) * flap * env_ar(n, 0.1, 0.25) * 0.5
    return nz


def sfx_pirate_board():
    # Boarding clash: wood + steel.
    return _mix(_tone(280, 0.15, "sine", 0.5, decay=0.1),
                _metallic_hit([523, 784, 1046], 0.4, gain=0.35, decay=0.25),
                _nz(0.05, 0.35, lp=2500))


# ------------------------------------------------------- AR-DETECTIVE ---
def sfx_detect_clue():
    # Clue found: magnifier ding (bright bell, short).
    return _metallic_hit([1568, 2093, 2637, 3136], 0.6, gain=0.35,
                         decay=0.4)


def sfx_detect_magnify():
    # Zoom blip: quick up-chirp.
    n = n_samp(0.18)
    return _clickfix(sweep_wave("sine", 600, 1400, n)
                     * env_ar(n, 0.02, 0.08) * 0.4)


def sfx_detect_dust():
    # Dusting for prints: soft brush taps.
    out = np.zeros(n_samp(0.5))
    rng = np.random.default_rng(13)
    for _ in range(8):
        seg = _nz(0.03, 0.25, hp=3000)
        s = int(rng.uniform(0, 0.42) * SR)
        e = min(s + len(seg), len(out))
        out[s:e] += seg[:e - s]
    return _clickfix(out)


SPECS = [
    ("duel_swing", sfx_duel_swing), ("duel_clash", sfx_duel_clash),
    ("duel_parry", sfx_duel_parry), ("duel_block", sfx_duel_block),
    ("duel_hit", sfx_duel_hit), ("duel_hum", sfx_duel_hum),
    ("swarm_die", sfx_swarm_die), ("swarm_wave", sfx_swarm_wave),
    ("swarm_base_hit", sfx_swarm_base_hit),
    ("swarm_overdrive", sfx_swarm_overdrive),
    ("def_place", sfx_def_place), ("def_die", sfx_def_die),
    ("def_horn", sfx_def_horn), ("def_base_hit", sfx_def_base_hit),
    ("boxer_hit", sfx_boxer_hit), ("boxer_combo", sfx_boxer_combo),
    ("boxer_bell", sfx_boxer_bell), ("boxer_block", sfx_boxer_block),
    ("traffic_ping", sfx_traffic_ping), ("traffic_pass", sfx_traffic_pass),
    ("paint_stroke", sfx_paint_stroke), ("paint_color", sfx_paint_color),
    ("paint_clear", sfx_paint_clear),
    ("wiz_cast", sfx_wiz_cast), ("wiz_hit", sfx_wiz_hit),
    ("wiz_brew", sfx_wiz_brew),
    ("mech_step", sfx_mech_step), ("mech_fire", sfx_mech_fire),
    ("mech_alarm", sfx_mech_alarm), ("mech_jump", sfx_mech_jump),
    ("dung_sword", sfx_dung_sword), ("dung_door", sfx_dung_door),
    ("dung_key", sfx_dung_key),
    ("pirate_cannon", sfx_pirate_cannon), ("pirate_sail", sfx_pirate_sail),
    ("pirate_board", sfx_pirate_board),
    ("detect_clue", sfx_detect_clue), ("detect_magnify", sfx_detect_magnify),
    ("detect_dust", sfx_detect_dust),
]


def main():
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    for stem, fn in SPECS:
        x = finalize(fn())
        write_wav(SFX_DIR / (stem + ".wav"), x)
        print("wrote", stem)


if __name__ == "__main__":
    main()
