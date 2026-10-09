"""Minigolf SFX + music synthesis for NEXUS GREENS.
Reuses tools/gen_audio.py helpers (numpy/scipy, no licensed assets).
Outputs to assets/audio/sfx/ and assets/audio/music/.
Specs: ~/workspace/design/minigolf/MINIGOLF_JUICE_PLAN.md
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
MUS_DIR = ROOT / "assets" / "audio" / "music"


def sfx_putt_thock():
    # 18ms sine burst at 220Hz + 8ms noise click. Pitch scaled at play time.
    return _mix(_tone(220, 0.09, "sine", 0.75, decay=0.018),
                _nz(0.03, 0.4, hp=2500))


def sfx_cup_rattle():
    # 3 short noise bursts 40ms apart, lowpassed, pitch drop on each.
    out = np.zeros(n_samp(0.35))
    for i, f in enumerate([900, 700, 520]):
        seg = _clickfix(lowpass(noise(n_samp(0.05)), f) * env_decay(n_samp(0.05), 0.015) * 0.6)
        s = int(i * 0.04 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_fanfare():
    # Brass-ish fanfare, 1.1s. Original melody.
    out = np.zeros(n_samp(1.2))
    notes = [(523.25, 0.0, 0.16), (659.25, 0.14, 0.16), (783.99, 0.28, 0.16),
             (1046.5, 0.42, 0.5)]
    for f, start, dur in notes:
        seg = _mix(_tone(f, dur, "saw", 0.28, decay=dur * 0.7, cut=2400),
                   _tone(f * 2.0, dur, "sine", 0.12, decay=dur * 0.7))
        s = int(start * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_crowd_swell():
    # Filtered noise bed + detuned "voice" oscillators, 1.8s swell.
    n = n_samp(1.8)
    t = t_arr(n)
    swell = np.sin(np.pi * np.clip(t / 1.8, 0, 1)) ** 1.5
    bed = lowpass(noise(n), 900) * 0.35
    voices = np.zeros(n)
    for detune in [0.94, 0.97, 1.0, 1.03, 1.06, 0.91, 1.09, 1.0]:
        f = 220.0 * detune
        vib = 1.0 + 0.02 * np.sin(2 * np.pi * 5.3 * t)
        voices += osc("saw", f * vib, n) * 0.05
    voices = lowpass(voices, 1400)
    return (bed + voices) * swell * 0.5


def sfx_crowd_gasp():
    # Inhale swell for lip-outs: rising filtered noise, 0.7s.
    n = n_samp(0.7)
    t = t_arr(n)
    rise = np.clip(t / 0.7, 0, 1) ** 2
    x = highpass(noise(n), 1200) * 0.3 + lowpass(noise(n), 600) * 0.25
    return x * rise * env_ar(n, 0.02, 0.15) * 0.6


def sfx_rail_click():
    # Crisp rail bounce click.
    return _mix(_tone(1800, 0.04, "sine", 0.4, decay=0.015),
                _nz(0.02, 0.3, hp=3000))


def sfx_splash_hazard():
    # Water hazard drop.
    n = n_samp(0.5)
    x = lowpass(noise(n), 1600) * env_decay(n, 0.18) * 0.55
    drop = sweep_wave("sine", 600, 180, n_samp(0.3)) * env_decay(n_samp(0.3), 0.15) * 0.3
    out = np.zeros(n)
    out[:len(drop)] += drop
    return _mix(x, out[:n] * 0 + np.pad(drop, (0, n - len(drop))))


def sfx_tee_pop():
    # Ball placed / tee pickup: soft pop.
    return _mix(_tone(440, 0.08, "sine", 0.4, f1=880, decay=0.03),
                _nz(0.02, 0.2, hp=3000))


def sfx_powerup_collect():
    # Magical pickup shimmer.
    out = np.zeros(n_samp(0.5))
    for i, f in enumerate([880, 1174.7, 1568]):
        seg = _tone(f, 0.18, "sine", 0.3, decay=0.1)
        s = int(i * 0.07 * SR)
        out[s:s + len(seg)] += seg
    return out


def sfx_powerup_fire():
    # Power-up activation: rising zap.
    return _mix(sweep_wave("saw", 200, 1200, n_samp(0.35)) * env_ar(n_samp(0.35), 0.02, 0.1) * 0.4,
                _nz(0.1, 0.25, hp=2000))


def sfx_wind_gust():
    # Wind zone gust bed (loopable-ish, 2s).
    n = n_samp(2.0)
    t = t_arr(n)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t)
    x = lowpass(noise(n), 500) * swell * 0.4
    return _clickfix(x, a=0.3, r=0.3)


def loop_ball_roll():
    # Seamless rolling loop (2s); pitch/volume modulated at play time.
    n = n_samp(2.0)
    x = lowpass(noise(n), 700) * 0.30
    x = _clickfix(x, a=0.4, r=0.4)
    return x


MINIGOLF_SFX = [
    ("mg_putt_thock", sfx_putt_thock),
    ("mg_cup_rattle", sfx_cup_rattle),
    ("mg_fanfare", sfx_fanfare),
    ("mg_crowd_swell", sfx_crowd_swell),
    ("mg_crowd_gasp", sfx_crowd_gasp),
    ("mg_rail_click", sfx_rail_click),
    ("mg_splash_hazard", sfx_splash_hazard),
    ("mg_tee_pop", sfx_tee_pop),
    ("mg_powerup_collect", sfx_powerup_collect),
    ("mg_powerup_fire", sfx_powerup_fire),
    ("mg_wind_gust", sfx_wind_gust),
]

MINIGOLF_LOOPS = [
    ("mg_ball_roll", loop_ball_roll),
]


def main():
    print(f"--- MINIGOLF SFX ({len(MINIGOLF_SFX)}) -> {SFX_DIR} ---")
    for name, fn in MINIGOLF_SFX:
        x = np.asarray(fn(), dtype=np.float64)
        dur, peak = write_wav(SFX_DIR / f"{name}.wav", x)
        print(f"  {name:22s} {dur:5.2f}s peak {peak:.2f}")
    for name, fn in MINIGOLF_LOOPS:
        x = np.asarray(fn(), dtype=np.float64)
        dur, peak = write_wav(SFX_DIR / f"{name}.wav", x)
        print(f"  {name:22s} {dur:5.2f}s peak {peak:.2f} (loop)")
    print("MINIGOLF_AUDIO_DONE")


if __name__ == "__main__":
    main()
