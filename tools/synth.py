"""
Jumping Jack — procedural sound design pipeline.

Renders the 58 game sounds listed in `sound_prompts_elevenlabs.txt` into
44.1 kHz WAVs, then converts them to MP3 via ffmpeg. The DSP layer is a
small but expressive synth library: multi-oscillator, ADSR envelopes,
biquad filters, FM, noise textures, simple convolutional reverb, and
linear/exp pitch glides. The recipes at the bottom are deliberately
compact so each sound is easy to tweak.

Run from the project root:

    python3 tools/synth.py            # render all
    python3 tools/synth.py ui_click   # render one by name

WAVs land in tools/audio_out/, MP3s land in assets/audio/.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable, Iterable

import numpy as np
from scipy import signal
from scipy.io import wavfile

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------

SR = 44_100                                      # sample rate
HERE = os.path.dirname(os.path.abspath(__file__))
WAV_DIR = os.path.join(HERE, "audio_out")
MP3_DIR = os.path.abspath(os.path.join(HERE, "..", "assets", "audio"))

os.makedirs(WAV_DIR, exist_ok=True)
os.makedirs(MP3_DIR, exist_ok=True)


# -----------------------------------------------------------------------------
# Oscillators
# -----------------------------------------------------------------------------

def t_array(seconds: float) -> np.ndarray:
    """Time axis sampled at SR."""
    return np.arange(int(seconds * SR)) / SR


def sine(freq, seconds, phase=0.0, sr=SR):
    """Sine — `freq` can be a scalar or a same-length array (FM/glide)."""
    t = np.arange(int(seconds * sr)) / sr
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * t + phase)
    # Integrate the instantaneous frequency for time-varying pitch.
    phase_arr = 2 * np.pi * np.cumsum(freq) / sr + phase
    return np.sin(phase_arr)


def square(freq, seconds, duty=0.5, sr=SR):
    t = np.arange(int(seconds * sr)) / sr
    if np.isscalar(freq):
        return signal.square(2 * np.pi * freq * t, duty=duty)
    phase = 2 * np.pi * np.cumsum(freq) / sr
    return signal.square(phase, duty=duty)


def saw(freq, seconds, sr=SR):
    t = np.arange(int(seconds * sr)) / sr
    if np.isscalar(freq):
        return signal.sawtooth(2 * np.pi * freq * t)
    phase = 2 * np.pi * np.cumsum(freq) / sr
    return signal.sawtooth(phase)


def triangle(freq, seconds, sr=SR):
    t = np.arange(int(seconds * sr)) / sr
    if np.isscalar(freq):
        return signal.sawtooth(2 * np.pi * freq * t, width=0.5)
    phase = 2 * np.pi * np.cumsum(freq) / sr
    return signal.sawtooth(phase, width=0.5)


def noise(seconds, sr=SR, color="white"):
    n = int(seconds * sr)
    w = np.random.uniform(-1, 1, n).astype(np.float64)
    if color == "white":
        return w
    if color == "pink":
        # Voss–McCartney-ish pink noise via low-pass cascade.
        b, a = signal.butter(2, 1000 / (sr / 2), btype="low")
        return signal.lfilter(b, a, w) * 2.0
    if color == "brown":
        return np.cumsum(w) / max(1.0, np.abs(np.cumsum(w)).max())
    raise ValueError(f"unknown noise color: {color}")


# -----------------------------------------------------------------------------
# Envelopes & shaping
# -----------------------------------------------------------------------------

def env_adsr(seconds, a=0.005, d=0.05, s=0.7, r=0.05, sr=SR):
    """Standard ADSR envelope. Attack/Decay/Sustain/Release in seconds (s = level)."""
    n = int(seconds * sr)
    na = max(1, int(a * sr))
    nd = max(1, int(d * sr))
    nr = max(1, int(r * sr))
    ns = max(0, n - na - nd - nr)
    e = np.concatenate([
        np.linspace(0, 1, na, endpoint=False),
        np.linspace(1, s, nd, endpoint=False),
        np.full(ns, s),
        np.linspace(s, 0, nr, endpoint=True),
    ])
    if len(e) < n:
        e = np.concatenate([e, np.zeros(n - len(e))])
    return e[:n]


def env_exp(seconds, decay=12.0, attack=0.003, sr=SR):
    """Fast attack + exponential decay — perfect for percussive hits."""
    n = int(seconds * sr)
    na = max(1, int(attack * sr))
    e = np.empty(n)
    e[:na] = np.linspace(0, 1, na)
    t = np.arange(n - na) / sr
    e[na:] = np.exp(-decay * t)
    return e


def env_linear(seconds, fade_in=0.0, fade_out=0.0, sr=SR):
    n = int(seconds * sr)
    fi = max(0, int(fade_in * sr))
    fo = max(0, int(fade_out * sr))
    e = np.ones(n)
    if fi:
        e[:fi] = np.linspace(0, 1, fi)
    if fo:
        e[-fo:] = np.linspace(1, 0, fo)
    return e


def env_curve(values: list[float], seconds: float, sr=SR):
    """Piecewise-linear envelope over `seconds`, interpolating `values`."""
    n = int(seconds * sr)
    xs = np.linspace(0, n - 1, len(values))
    return np.interp(np.arange(n), xs, values)


# -----------------------------------------------------------------------------
# Frequency curves (for time-varying pitch)
# -----------------------------------------------------------------------------

def glide(f0, f1, seconds, shape="linear", sr=SR):
    n = int(seconds * sr)
    if shape == "linear":
        return np.linspace(f0, f1, n)
    if shape == "exp":
        return f0 * (f1 / f0) ** np.linspace(0, 1, n)
    raise ValueError(shape)


def freq_curve(points: list[tuple[float, float]], seconds: float, sr=SR):
    """List of (t_norm, freq) anchors — interpolates linearly across the buffer."""
    n = int(seconds * sr)
    xs = np.array([p[0] * (n - 1) for p in points])
    ys = np.array([p[1] for p in points])
    return np.interp(np.arange(n), xs, ys)


# -----------------------------------------------------------------------------
# Filters
# -----------------------------------------------------------------------------

def lowpass(x, cutoff, q=0.707, sr=SR):
    cutoff = max(20, min(cutoff, sr / 2 - 100))
    b, a = signal.iirfilter(2, cutoff, btype="low", fs=sr, ftype="butter")
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, sr=SR):
    cutoff = max(20, min(cutoff, sr / 2 - 100))
    b, a = signal.iirfilter(2, cutoff, btype="high", fs=sr, ftype="butter")
    return signal.lfilter(b, a, x)


def bandpass(x, low, high, sr=SR):
    low = max(20, low)
    high = min(sr / 2 - 100, high)
    b, a = signal.iirfilter(2, [low, high], btype="band", fs=sr, ftype="butter")
    return signal.lfilter(b, a, x)


def resonator(x, freq, q=8.0, sr=SR):
    """Sharp band-pass for the "metallic" tone in clicks/pings."""
    bw = freq / q
    return bandpass(x, freq - bw / 2, freq + bw / 2, sr=sr)


# -----------------------------------------------------------------------------
# Effects
# -----------------------------------------------------------------------------

def delay(x, time_s, feedback=0.35, mix=0.35, sr=SR):
    n = len(x)
    d = int(time_s * sr)
    y = x.copy().astype(np.float64)
    buf = np.zeros(n + d)
    buf[:n] = x
    for i in range(d, n):
        buf[i] += feedback * buf[i - d]
    y = (1 - mix) * x + mix * buf[:n]
    return y


def reverb(x, decay=0.35, sr=SR):
    """Schroeder-style reverb: 4 parallel comb filters + 2 series allpass.

    Implementation rewritten for stability — the previous all-pass had a
    recursive bug that could blow up on long buffers (NaN cascades).
    """
    decay = float(np.clip(decay, 0.0, 0.95))

    def _comb(sig, delay_s, fb):
        d = max(1, int(delay_s * sr))
        out = np.zeros(len(sig))
        buf = np.zeros(d)
        idx = 0
        for i, s in enumerate(sig):
            out[i] = buf[idx]
            buf[idx] = s + buf[idx] * fb
            idx = (idx + 1) % d
        return out

    def _allpass(sig, delay_s, gain=0.5):
        d = max(1, int(delay_s * sr))
        out = np.zeros(len(sig))
        buf = np.zeros(d)
        idx = 0
        for i, s in enumerate(sig):
            delayed = buf[idx]
            v = s + delayed * (-gain)
            out[i] = delayed + v * gain
            buf[idx] = v
            idx = (idx + 1) % d
        return out

    combs = [0.0297, 0.0371, 0.0411, 0.0437]
    fb = 0.78 + decay * 0.18  # 0.78 → ~0.96
    wet = np.zeros(len(x))
    for c in combs:
        wet += _comb(x, c, fb)
    wet /= len(combs)
    wet = _allpass(wet, 0.005, 0.5)
    wet = _allpass(wet, 0.0017, 0.5)
    # Sanitise: if anything went out-of-range (extreme combo of inputs)
    # we clamp instead of letting NaN/Inf propagate to save_wav.
    wet = np.nan_to_num(wet, nan=0.0, posinf=0.0, neginf=0.0)
    return 0.7 * x + 0.3 * wet


def bitcrush(x, bits=8):
    levels = 2 ** bits
    return np.round(x * levels) / levels


def soft_clip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


# -----------------------------------------------------------------------------
# Mix / output
# -----------------------------------------------------------------------------

def mix(*tracks: np.ndarray) -> np.ndarray:
    """Sum equal-length (or padded) buffers."""
    longest = max(len(t) for t in tracks)
    out = np.zeros(longest)
    for t in tracks:
        if len(t) < longest:
            t = np.pad(t, (0, longest - len(t)))
        out += t
    return out


def normalize(x, peak_db=-3.0):
    peak = np.max(np.abs(x))
    if peak < 1e-9:
        return x
    target = 10 ** (peak_db / 20)
    return x * (target / peak)


def fade(x, fade_in=0.005, fade_out=0.01, sr=SR):
    return x * env_linear(len(x) / sr, fade_in=fade_in, fade_out=fade_out, sr=sr)


def make_loop_friendly(x, crossfade_s=0.05, sr=SR):
    """Crossfade head into tail so the file loops without click."""
    n = int(crossfade_s * sr)
    n = min(n, len(x) // 4)
    if n < 4:
        return x
    head = x[:n].copy()
    tail = x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    x = x.copy()
    x[-n:] = tail * (1 - ramp) + head * ramp
    return x[:-n]  # drop the head bit we folded in


def save_wav(name: str, x: np.ndarray, sr=SR, stereo=False):
    x = normalize(x).astype(np.float32)
    if stereo and x.ndim == 1:
        x = np.stack([x, x], axis=-1)
    out_path = os.path.join(WAV_DIR, f"{name}.wav")
    wavfile.write(out_path, sr, (x * 32767).astype(np.int16))
    return out_path


def wav_to_mp3(name: str, bitrate_kbps: int = 128):
    src = os.path.join(WAV_DIR, f"{name}.wav")
    dst = os.path.join(MP3_DIR, f"{name}.mp3")
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", src,
            "-codec:a", "libmp3lame",
            "-b:a", f"{bitrate_kbps}k",
            "-ar", str(SR),
            dst,
        ],
        check=True,
    )
    return dst


# =============================================================================
# Recipes — one function per sound, returning the audio buffer.
# =============================================================================

# ---- 2. UI / Navigation -----------------------------------------------------

def ui_click():
    n = noise(0.08) * env_exp(0.08, decay=80, attack=0.0005)
    body = sine(1800, 0.08) * env_exp(0.08, decay=60, attack=0.0005)
    y = mix(0.6 * highpass(n, 1500), 0.4 * body)
    return fade(y, 0.001, 0.01)


def ui_hover():
    y = sine(2400, 0.06) * env_exp(0.06, decay=110, attack=0.0005)
    return fade(0.7 * y, 0.001, 0.01)


def ui_back():
    f = glide(880, 440, 0.18, shape="exp")
    a = triangle(f, 0.18) * env_exp(0.18, decay=12, attack=0.002)
    b = sine(f * 2, 0.18) * env_exp(0.18, decay=14, attack=0.002) * 0.4
    return fade(mix(a, b), 0.002, 0.02)


def ui_confirm():
    f1 = glide(440, 660, 0.10)
    f2 = glide(660, 990, 0.15)
    a = triangle(f1, 0.10) * env_exp(0.10, decay=20, attack=0.002)
    b = triangle(f2, 0.15) * env_exp(0.15, decay=14, attack=0.002)
    pad = np.zeros(int(0.10 * SR))
    y = mix(a, np.concatenate([pad, b]))
    return fade(y, 0.002, 0.02)


def ui_toggle():
    click1 = ui_click() * 0.6
    pause = np.zeros(int(0.04 * SR))
    click2 = ui_click() * 0.6
    return np.concatenate([click1, pause, click2])


# ---- 3. Player actions ------------------------------------------------------

def charge_loop():
    # v3 — rhythmic ascending arpeggio (C5-E5-G5-C6) on a warm sub.
    # Reads as a "power meter filling". When AudioManager nudges the
    # playback rate up with chargeLevel, the pulses naturally speed up
    # AND climb in pitch → satisfying buildup without being aggressive
    # (no saw, no clip, no noise — pure sine + triangle + sub).
    seconds = 1.0
    n = int(seconds * SR)
    y = np.zeros(n)
    notes = [523.25, 659.25, 783.99, 1046.50]  # C5 E5 G5 C6
    pulse_dur = 0.20
    for i, f in enumerate(notes):
        start = int(i * 0.25 * SR)
        body = sine(f, pulse_dur) * env_exp(pulse_dur, decay=18, attack=0.004)
        harm = (triangle(f * 2, pulse_dur)
                * env_exp(pulse_dur, decay=22, attack=0.004) * 0.25)
        seg = body + harm
        end = min(n, start + len(seg))
        y[start:end] += seg[:end - start] * 0.32
    sub = sine(65, seconds) * 0.35
    raw = mix(y, sub)
    raw = lowpass(raw, 2200)
    raw *= env_linear(seconds, fade_in=0.02, fade_out=0.0)
    return make_loop_friendly(raw, crossfade_s=0.04)


def charge_max():
    f = freq_curve([(0.0, 1200), (0.4, 2400), (1.0, 1800)], 0.4)
    a = sine(f, 0.4) * env_exp(0.4, decay=10, attack=0.002)
    sparkle = sine(f * 3, 0.4) * env_exp(0.4, decay=14, attack=0.002) * 0.3
    return fade(mix(a, sparkle), 0.002, 0.02)


def jump_release():
    f = glide(220, 880, 0.3, shape="exp")
    body = square(f, 0.3, duty=0.4) * env_exp(0.3, decay=10, attack=0.001)
    whoosh = highpass(noise(0.3), 1200) * env_exp(0.3, decay=8) * 0.5
    return fade(mix(0.7 * body, 0.5 * whoosh), 0.002, 0.02)


def land_soft():
    thump = lowpass(noise(0.25), 350) * env_exp(0.25, decay=18, attack=0.001)
    sub = sine(80, 0.25) * env_exp(0.25, decay=12, attack=0.001)
    return fade(mix(1.0 * thump, 0.6 * sub), 0.001, 0.02)


def land_hard():
    thump = lowpass(noise(0.35), 600) * env_exp(0.35, decay=14, attack=0.0005)
    sub = sine(60, 0.35) * env_exp(0.35, decay=10, attack=0.0005)
    crack = highpass(noise(0.04), 2000) * env_exp(0.04, decay=80, attack=0.0001)
    return fade(mix(1.1 * thump, 0.8 * sub, 0.5 * crack), 0.001, 0.02)


def bouncy_boing():
    f = freq_curve([(0.0, 280), (0.4, 880), (1.0, 660)], 0.45)
    body = triangle(f, 0.45) * env_exp(0.45, decay=6, attack=0.005)
    sub = sine(f / 2, 0.45) * env_exp(0.45, decay=5, attack=0.005) * 0.5
    return fade(mix(body, sub), 0.005, 0.04)


def wall_bounce():
    f = freq_curve([(0.0, 900), (1.0, 720)], 0.15)
    tone = sine(f, 0.15) * env_exp(0.15, decay=30, attack=0.0005)
    tick = highpass(noise(0.02), 3000) * env_exp(0.02, decay=150, attack=0.0001)
    return fade(mix(0.7 * tone, 0.5 * tick), 0.001, 0.02)


def fall_swoosh():
    seconds = 1.2
    nz = noise(seconds, color="pink")
    cutoff = freq_curve([(0.0, 4000), (1.0, 600)], seconds)
    # Time-varying low-pass is hand-rolled via segmented filtering.
    out = np.zeros_like(nz)
    chunk = 1024
    for i in range(0, len(nz), chunk):
        c = float(np.mean(cutoff[i:i + chunk]))
        out[i:i + chunk] = lowpass(nz[i:i + chunk], c)
    out *= env_linear(seconds, fade_in=0.05, fade_out=0.0)
    return make_loop_friendly(out, crossfade_s=0.1)


# ---- 4. Pickups -------------------------------------------------------------

def pickup_star():
    # Two-note arpeggio C6 → E6.
    seg1 = sine(1046.5, 0.12) * env_exp(0.12, decay=16, attack=0.002)
    seg2 = sine(1318.5, 0.30) * env_exp(0.30, decay=10, attack=0.002)
    pad = np.zeros(int(0.08 * SR))
    a = seg1
    b = np.concatenate([pad, seg2])
    return fade(mix(a, b), 0.002, 0.04)


def pickup_crystal():
    seconds = 0.8
    f = glide(440, 1760, seconds, shape="exp")
    body = sine(f, seconds) * env_exp(seconds, decay=4, attack=0.005)
    shimmer = sine(f * 2.01, seconds) * env_exp(seconds, decay=5, attack=0.005) * 0.4
    raw = mix(body, shimmer)
    return fade(reverb(raw, decay=0.5), 0.005, 0.06)


def slow_time_active():
    seconds = 6.0
    f = freq_curve([(0.0, 40), (0.5, 45), (1.0, 40)], seconds)
    a = sine(f, seconds)
    b = sine(f * 2.01, seconds) * 0.4
    lfo = (np.sin(2 * np.pi * 0.3 * np.arange(int(seconds * SR)) / SR) + 1) / 2
    cutoff = 200 + lfo * 400
    out = np.zeros_like(a)
    chunk = 2048
    for i in range(0, len(a), chunk):
        c = float(np.mean(cutoff[i:i + chunk]))
        out[i:i + chunk] = lowpass((a + b)[i:i + chunk], c)
    out *= env_linear(seconds, fade_in=0.3, fade_out=0.0)
    return make_loop_friendly(out, crossfade_s=0.2)


def slow_time_end():
    f = glide(220, 880, 0.35, shape="exp")
    body = sine(f, 0.35) * env_exp(0.35, decay=8, attack=0.005)
    shimmer = highpass(noise(0.35), 4000) * env_exp(0.35, decay=10) * 0.3
    return fade(mix(body, shimmer), 0.005, 0.04)


def pickup_heart():
    seconds = 0.5
    # Two warm pulses.
    p1 = sine(523.25, 0.18) * env_exp(0.18, decay=10, attack=0.01)
    p2 = sine(659.25, 0.30) * env_exp(0.30, decay=8, attack=0.01)
    pad = np.zeros(int(0.10 * SR))
    return fade(mix(p1, np.concatenate([pad, p2])), 0.005, 0.04)


def pickup_vision():
    seconds = 0.6
    notes = [880, 1108.7, 1318.5, 1760]
    y = np.zeros(int(seconds * SR))
    for i, f in enumerate(notes):
        start = int(i * 0.08 * SR)
        seg = sine(f, 0.4) * env_exp(0.4, decay=10, attack=0.003)
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start] * 0.7
    return fade(reverb(y, decay=0.3), 0.005, 0.05)


def pickup_warp():
    seconds = 0.5
    f = glide(200, 1400, seconds, shape="exp")
    body = saw(f, seconds) * env_exp(seconds, decay=6, attack=0.005)
    raw = lowpass(body, 2500)
    raw = soft_clip(raw, drive=1.5)
    return fade(raw, 0.005, 0.04)


def teleport_arrive():
    sparkle = sine(2200, 0.3) * env_exp(0.3, decay=15, attack=0.002)
    impact = lowpass(noise(0.08), 800) * env_exp(0.08, decay=30, attack=0.0005)
    high = highpass(noise(0.2), 4000) * env_exp(0.2, decay=10) * 0.4
    return fade(mix(0.7 * sparkle, 1.0 * impact, high), 0.002, 0.03)


# ---- 5. Combo & rewards -----------------------------------------------------

def _combo_tick_at(freq):
    body = sine(freq, 0.15) * env_exp(0.15, decay=18, attack=0.001)
    overtone = sine(freq * 2.01, 0.15) * env_exp(0.15, decay=22, attack=0.001) * 0.3
    return fade(reverb(mix(body, overtone), decay=0.15), 0.001, 0.02)


def combo_tick_a():   return _combo_tick_at(523.25)   # C5
def combo_tick_b():   return _combo_tick_at(659.25)   # E5
def combo_tick_c():   return _combo_tick_at(783.99)   # G5
def combo_tick_d():   return _combo_tick_at(987.77)   # B5


def combo_x5_plus():
    seconds = 0.8
    notes = [(0.0, 523.25), (0.12, 659.25), (0.24, 783.99), (0.36, 1046.5)]
    y = np.zeros(int(seconds * SR))
    for t, f in notes:
        start = int(t * SR)
        seg = mix(
            saw(f, 0.45) * env_exp(0.45, decay=6, attack=0.005) * 0.5,
            sine(f * 2, 0.45) * env_exp(0.45, decay=7, attack=0.005) * 0.3,
        )
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    return fade(reverb(y, decay=0.3), 0.005, 0.05)


def combo_break():
    f = glide(880, 220, 0.5, shape="exp")
    body = triangle(f, 0.5) * env_exp(0.5, decay=5, attack=0.005)
    crack = highpass(noise(0.06), 3000) * env_exp(0.06, decay=40) * 0.5
    return fade(mix(body, crack), 0.005, 0.05)


def _bouncy_chain_at(root):
    seconds = 0.5
    notes = [(0.0, root), (0.12, root * 1.5), (0.24, root * 2.0)]
    y = np.zeros(int(seconds * SR))
    for t, f in notes:
        start = int(t * SR)
        seg = sine(f, 0.35) * env_exp(0.35, decay=8, attack=0.005)
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    return fade(reverb(y, decay=0.25), 0.005, 0.04)


def bouncy_chain_a():   return _bouncy_chain_at(440)
def bouncy_chain_b():   return _bouncy_chain_at(587.33)
def bouncy_chain_c():   return _bouncy_chain_at(739.99)


def comeback_reward():
    f = freq_curve([(0.0, 440), (0.4, 880), (0.7, 1320), (1.0, 1100)], 0.6)
    body = triangle(f, 0.6) * env_exp(0.6, decay=4, attack=0.01)
    overtone = sine(f * 2, 0.6) * env_exp(0.6, decay=5, attack=0.01) * 0.3
    return fade(reverb(mix(body, overtone), decay=0.3), 0.005, 0.05)


def wall_rebond_reward():
    p1 = sine(880, 0.15) * env_exp(0.15, decay=20, attack=0.001)
    p2 = sine(1318.5, 0.20) * env_exp(0.20, decay=18, attack=0.001)
    pad = np.zeros(int(0.08 * SR))
    return fade(mix(p1, np.concatenate([pad, p2])), 0.002, 0.03)


def score_milestone():
    f = 880
    body = sine(f, 0.7) * env_exp(0.7, decay=3.5, attack=0.005)
    overtones = sum(
        sine(f * h, 0.7) * env_exp(0.7, decay=4 + h, attack=0.005) * (1 / (h * 1.5))
        for h in [2, 3, 4]
    )
    return fade(reverb(mix(body, overtones), decay=0.5), 0.005, 0.05)


def new_best_score():
    seconds = 1.5
    notes = [(0.0, 523.25), (0.2, 659.25), (0.4, 783.99), (0.6, 1046.5)]
    y = np.zeros(int(seconds * SR))
    for t, f in notes:
        start = int(t * SR)
        seg = mix(
            triangle(f, 0.7) * env_exp(0.7, decay=4, attack=0.005),
            sine(f * 2, 0.7) * env_exp(0.7, decay=5, attack=0.005) * 0.3,
        )
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    sparkle = np.zeros(int(seconds * SR))
    for i, f in enumerate([2093, 2637, 3136, 4186]):
        start = int(0.7 * SR) + i * 1500
        seg = sine(f, 0.15) * env_exp(0.15, decay=20)
        end = min(len(sparkle), start + len(seg))
        sparkle[start:end] += seg[:end - start]
    return fade(reverb(y + 0.4 * sparkle, decay=0.4), 0.005, 0.05)


# ---- 6. Tension & danger ----------------------------------------------------

def danger_low_heartbeat():
    seconds = 2.0
    n = int(seconds * SR)
    out = np.zeros(n)
    # Two thumps per cycle.
    for t0 in [0.0, 0.20, 1.0, 1.20]:
        start = int(t0 * SR)
        thump = sine(60, 0.18) * env_exp(0.18, decay=20, attack=0.002)
        thump = lowpass(thump, 200)
        end = min(n, start + len(thump))
        out[start:end] += thump[:end - start]
    return make_loop_friendly(out, crossfade_s=0.05)


def platform_crack():
    n = noise(0.06)
    cutoff = freq_curve([(0.0, 4000), (1.0, 1500)], 0.06)
    out = np.zeros_like(n)
    chunk = 256
    for i in range(0, len(n), chunk):
        c = float(np.mean(cutoff[i:i + chunk]))
        out[i:i + chunk] = bandpass(n[i:i + chunk], max(100, c - 1000), c + 500)
    out *= env_exp(0.06, decay=40, attack=0.0005)
    return fade(out, 0.001, 0.01)


def platform_explode():
    boom = lowpass(noise(0.3), 400) * env_exp(0.3, decay=12, attack=0.0005)
    sub = sine(55, 0.3) * env_exp(0.3, decay=10, attack=0.0005)
    crack = highpass(noise(0.08), 2500) * env_exp(0.08, decay=40) * 0.5
    debris = noise(0.45) * env_exp(0.45, decay=4) * 0.15
    return fade(mix(1.1 * boom, 0.8 * sub, crack, debris), 0.001, 0.03)


def wind_ambient():
    seconds = 10.0
    nz = noise(seconds, color="pink")
    cutoff = freq_curve([
        (0.0, 700), (0.2, 1200), (0.4, 800), (0.6, 1500),
        (0.8, 900), (1.0, 700)
    ], seconds)
    out = np.zeros_like(nz)
    chunk = 4096
    for i in range(0, len(nz), chunk):
        c = float(np.mean(cutoff[i:i + chunk]))
        out[i:i + chunk] = lowpass(nz[i:i + chunk], c)
    out *= env_linear(seconds, fade_in=0.5, fade_out=0.0)
    return make_loop_friendly(out, crossfade_s=0.5) * 0.7


# ---- 7. Death & game over ---------------------------------------------------

def death_fall():
    # Short "piwwww" zap — sharp attack, fast exponential pitch dive
    # from 2 kHz to 200 Hz, square-wave body for that retro arcade
    # zing. Total ~0.3 s, no impact tail, no whistle. Reads as a quick
    # "you died" sting rather than a long Looney-Tunes fall.
    seconds = 0.3
    f = glide(2200, 180, seconds, shape="exp")
    body = square(f, seconds, duty=0.35) * env_exp(seconds, decay=11, attack=0.001)
    # A touch of high-end noise for "fizz" without dirt.
    fizz = highpass(noise(seconds), 1500) * env_exp(seconds, decay=10) * 0.18
    return fade(mix(body, fizz), 0.001, 0.02)


def death_crushed():
    body = lowpass(noise(0.25), 800) * env_exp(0.25, decay=8, attack=0.001)
    sub = sine(70, 0.25) * env_exp(0.25, decay=10, attack=0.001)
    squelch_f = glide(900, 200, 0.2, shape="exp")
    squelch = saw(squelch_f, 0.2) * env_exp(0.2, decay=14, attack=0.001)
    squelch = lowpass(squelch, 1200) * 0.4
    return fade(mix(body, 0.8 * sub, squelch), 0.001, 0.03)


def gameover_jingle():
    seconds = 2.5
    notes = [(0.0, 659.25, 0.6), (0.5, 523.25, 0.6), (1.0, 392.00, 0.8)]
    y = np.zeros(int(seconds * SR))
    for t, f, dur in notes:
        start = int(t * SR)
        seg = mix(
            triangle(f, dur) * env_adsr(dur, a=0.02, d=0.1, s=0.7, r=0.3),
            sine(f * 2, dur) * env_adsr(dur, a=0.02, d=0.1, s=0.4, r=0.3) * 0.3,
        )
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    return fade(reverb(y, decay=0.4), 0.01, 0.1) * 0.85


def revive_ready():
    seconds = 0.6
    # Reverse-played heartbeat-ish thump.
    thump = sine(60, 0.3) * env_exp(0.3, decay=18, attack=0.002)
    sparkle_f = glide(440, 1760, 0.35, shape="exp")
    sparkle = sine(sparkle_f, 0.35) * env_exp(0.35, decay=6, attack=0.005)
    pad = np.zeros(int(0.25 * SR))
    return fade(mix(thump, np.concatenate([pad, sparkle])), 0.005, 0.04)


# ---- 8. Battle Royale -------------------------------------------------------

def lobby_player_join():
    f = glide(440, 880, 0.2, shape="exp")
    body = sine(f, 0.2) * env_exp(0.2, decay=14, attack=0.005)
    return fade(body, 0.005, 0.03)


def lobby_player_leave():
    f = glide(880, 330, 0.2, shape="exp")
    body = sine(f, 0.2) * env_exp(0.2, decay=14, attack=0.005)
    return fade(body, 0.005, 0.03)


def lobby_countdown_tick():
    tick = highpass(noise(0.02), 3000) * env_exp(0.02, decay=100, attack=0.0002)
    body = sine(2400, 0.12) * env_exp(0.12, decay=40, attack=0.0005)
    return fade(mix(1.0 * tick, 0.4 * body), 0.0005, 0.01)


def countdown_321():
    body = sine(783.99, 0.25) * env_exp(0.25, decay=10, attack=0.002)  # G5
    overtone = sine(1567.98, 0.25) * env_exp(0.25, decay=12) * 0.3
    return fade(mix(body, overtone), 0.002, 0.03)


def countdown_go():
    f = freq_curve([(0.0, 1046.5), (0.3, 2093.0), (1.0, 1568.0)], 0.5)
    body = mix(
        sine(f, 0.5) * env_exp(0.5, decay=6, attack=0.002),
        sine(f * 2, 0.5) * env_exp(0.5, decay=8, attack=0.002) * 0.4,
    )
    whoosh = highpass(noise(0.5), 1200) * env_exp(0.5, decay=5) * 0.4
    return fade(mix(body, whoosh), 0.002, 0.05)


def kill_confirmed():
    ding = sine(2400, 0.25) * env_exp(0.25, decay=18, attack=0.001)
    overtone = sine(4800, 0.25) * env_exp(0.25, decay=22, attack=0.001) * 0.4
    thump = sine(80, 0.1) * env_exp(0.1, decay=20, attack=0.001)
    return fade(mix(ding, overtone, 0.7 * thump), 0.002, 0.03)


def kill_streak():
    seconds = 0.6
    notes = [(0.0, 523.25), (0.15, 783.99), (0.30, 1046.5)]
    y = np.zeros(int(seconds * SR))
    for t, f in notes:
        start = int(t * SR)
        seg = mix(
            saw(f, 0.35) * env_exp(0.35, decay=6, attack=0.003) * 0.6,
            sine(f * 2, 0.35) * env_exp(0.35, decay=8, attack=0.003) * 0.3,
        )
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    return fade(reverb(y, decay=0.25), 0.005, 0.04)


def got_crushed():
    sub_f = glide(120, 40, 0.5, shape="exp")
    sub = sine(sub_f, 0.5) * env_exp(0.5, decay=6, attack=0.0005)
    impact = lowpass(noise(0.4), 600) * env_exp(0.4, decay=8, attack=0.0005)
    crunch = bandpass(noise(0.2), 800, 2500) * env_exp(0.2, decay=14) * 0.6
    return fade(mix(1.2 * sub, impact, crunch), 0.001, 0.04)


def opponent_died():
    bell = sine(440, 0.4) * env_exp(0.4, decay=6, attack=0.005)
    overtone = sine(880, 0.4) * env_exp(0.4, decay=7, attack=0.005) * 0.4
    return fade(reverb(mix(bell, overtone), decay=0.4), 0.005, 0.04)


def safe_zone_end():
    seconds = 0.8
    # Two-tone alarm pulse.
    seg1 = square(660, 0.18, duty=0.45) * env_adsr(0.18, a=0.005, d=0.02, s=0.8, r=0.05)
    pause = np.zeros(int(0.04 * SR))
    seg2 = square(880, 0.18, duty=0.45) * env_adsr(0.18, a=0.005, d=0.02, s=0.8, r=0.05)
    pause2 = np.zeros(int(0.04 * SR))
    seg3 = square(660, 0.18, duty=0.45) * env_adsr(0.18, a=0.005, d=0.02, s=0.8, r=0.05)
    pause3 = np.zeros(int(0.04 * SR))
    seg4 = square(880, 0.22, duty=0.45) * env_adsr(0.22, a=0.005, d=0.02, s=0.7, r=0.18)
    out = np.concatenate([seg1, pause, seg2, pause2, seg3, pause3, seg4])
    out = lowpass(out, 2500)
    return fade(out, 0.003, 0.04) * 0.6


def leader_changed():
    whoosh = highpass(noise(0.25), 1500) * env_exp(0.25, decay=8) * 0.5
    chime = sine(1760, 0.3) * env_exp(0.3, decay=12, attack=0.05)
    overtone = sine(2637, 0.3) * env_exp(0.3, decay=14, attack=0.05) * 0.4
    return fade(reverb(mix(whoosh, chime, overtone), decay=0.3), 0.002, 0.04)


def victory_win():
    seconds = 3.0
    # Power chord arpeggio C-E-G-C plus held chord.
    arp = [(0.0, 523.25), (0.15, 659.25), (0.30, 783.99), (0.45, 1046.5)]
    y = np.zeros(int(seconds * SR))
    for t, f in arp:
        start = int(t * SR)
        seg = mix(
            saw(f, 0.5) * env_exp(0.5, decay=6, attack=0.005) * 0.45,
            sine(f * 2, 0.5) * env_exp(0.5, decay=7, attack=0.005) * 0.25,
        )
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    # Sustained chord starting at 0.6.
    chord_start = int(0.6 * SR)
    chord_dur = seconds - 0.6
    chord = sum(
        triangle(f, chord_dur) * env_adsr(chord_dur, a=0.05, d=0.3, s=0.6, r=0.5) * 0.3
        for f in [523.25, 659.25, 783.99, 1046.5]
    )
    end = min(len(y), chord_start + len(chord))
    y[chord_start:end] += chord[:end - chord_start]
    # Sparkle cascade.
    for i, f in enumerate([2093, 2637, 3136, 4186, 5274]):
        start = int((1.0 + i * 0.08) * SR)
        seg = sine(f, 0.4) * env_exp(0.4, decay=10, attack=0.005) * 0.35
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    return fade(reverb(y, decay=0.5), 0.01, 0.15) * 0.85


def defeat_placement():
    seconds = 1.5
    f = freq_curve([(0.0, 392.0), (1.0, 261.6)], seconds)
    body = triangle(f, seconds) * env_adsr(seconds, a=0.05, d=0.2, s=0.5, r=0.6)
    overtone = sine(f * 2, seconds) * env_adsr(seconds, a=0.05, d=0.2, s=0.3, r=0.6) * 0.3
    return fade(reverb(mix(body, overtone), decay=0.3), 0.01, 0.1) * 0.7


# ---- 9. Ambient / feel ------------------------------------------------------

def cube_idle_blip():
    f = freq_curve([(0.0, 440), (0.5, 660), (1.0, 440)], 0.25)
    body = sine(f, 0.25) * env_adsr(0.25, a=0.04, d=0.05, s=0.6, r=0.12)
    return fade(body, 0.005, 0.05) * 0.5


def pickup_spawn_chime():
    body = sine(1318.5, 0.35) * env_exp(0.35, decay=8, attack=0.02)
    overtone = sine(2637.0, 0.35) * env_exp(0.35, decay=10, attack=0.02) * 0.3
    return fade(reverb(mix(body, overtone), decay=0.3), 0.005, 0.05) * 0.6


# ---- 1. MUSIC TRACKS -------------------------------------------------------

# Chiptune-style melodies — square/saw + triangle bass + noise hat.
# Built so that every track loops cleanly (designed in 4 or 8 bars).

def _chiptune_track(
    bpm: float,
    bars: int,
    melody_notes: list[tuple[float, float, float]],  # (start_beat, freq, length_beats)
    bass_pattern: list[tuple[float, float, float]],
    chord_pattern: list[tuple[float, float, float]],  # (start_beat, freq, length_beats)
    hat_pattern: list[float],                          # hit beats
    swing: float = 0.0,
):
    beat = 60.0 / bpm
    seconds = bars * 4 * beat
    n = int(seconds * SR)
    y = np.zeros(n)

    def add_note(start_b, freq, length_b, osc, amp):
        start = int(start_b * beat * SR)
        dur = length_b * beat
        wave = osc(freq, dur)
        env = env_adsr(dur, a=0.005, d=0.05, s=0.7, r=min(0.1, dur * 0.4))
        seg = wave * env * amp
        end = min(n, start + len(seg))
        y[start:end] += seg[:end - start]

    for b, f, l in melody_notes:
        add_note(b, f, l, square, 0.30)
    for b, f, l in bass_pattern:
        add_note(b, f, l, triangle, 0.45)
    for b, f, l in chord_pattern:
        add_note(b, f, l, lambda fr, du: square(fr, du, duty=0.25), 0.18)
    for b in hat_pattern:
        start = int(b * beat * SR)
        hit = highpass(noise(0.04), 4000) * env_exp(0.04, decay=80, attack=0.001) * 0.35
        end = min(n, start + len(hit))
        y[start:end] += hit[:end - start]

    y = soft_clip(y, drive=1.2)
    return make_loop_friendly(y, crossfade_s=0.05)


def menu_loop():
    # Key: C major, 110 BPM, 8 bars.
    # Melody: C-E-G-E-A-G-E-D pattern.
    mel = []
    notes = [523.25, 659.25, 783.99, 659.25, 880.0, 783.99, 659.25, 587.33]
    for bar in range(8):
        for i, f in enumerate(notes):
            mel.append((bar * 4 + i * 0.5, f, 0.5))
    bass = []
    bass_notes = [130.81, 196.00, 220.00, 196.00]  # C2-G2-A2-G2
    for bar in range(8):
        bass.append((bar * 4, bass_notes[bar % 4], 1.0))
        bass.append((bar * 4 + 2, bass_notes[bar % 4], 1.0))
    chord = []
    chords = [(261.63, 329.63, 392.00), (220.0, 277.18, 329.63),
              (174.61, 220.0, 261.63), (196.0, 246.94, 293.66)]
    for bar in range(8):
        c = chords[bar % 4]
        for f in c:
            chord.append((bar * 4 + 0, f, 2.0))
            chord.append((bar * 4 + 2, f, 2.0))
    hats = [b * 0.5 for b in range(8 * 8)]
    return _chiptune_track(110, 8, mel, bass, chord, hats) * 0.6


def solo_loop():
    # Key: A minor, 122 BPM, 8 bars, more energetic.
    mel = []
    melody_seq = [880, 1046.5, 880, 1318.5, 1174.66, 1046.5, 988.0, 880]
    for bar in range(8):
        for i, f in enumerate(melody_seq):
            mel.append((bar * 4 + i * 0.5, f, 0.5))
    bass = []
    bass_seq = [110.0, 146.83, 164.81, 130.81]
    for bar in range(8):
        bass.append((bar * 4, bass_seq[bar % 4], 0.5))
        bass.append((bar * 4 + 1, bass_seq[bar % 4], 0.5))
        bass.append((bar * 4 + 2, bass_seq[bar % 4], 0.5))
        bass.append((bar * 4 + 3, bass_seq[bar % 4], 0.5))
    chord = []
    chord_seq = [(220.0, 261.63, 329.63), (293.66, 349.23, 440.0),
                 (329.63, 392.0, 493.88), (261.63, 311.13, 392.0)]
    for bar in range(8):
        c = chord_seq[bar % 4]
        for f in c:
            chord.append((bar * 4, f, 4.0))
    hats = []
    for bar in range(8):
        for i in range(8):
            hats.append(bar * 4 + i * 0.5)
    return _chiptune_track(122, 8, mel, bass, chord, hats) * 0.6


def br_loop():
    # Darker, 134 BPM, 8 bars — minor key, more tribal kick pattern.
    mel = []
    melody_seq = [659.25, 587.33, 523.25, 587.33, 659.25, 783.99, 698.46, 659.25]
    for bar in range(8):
        for i, f in enumerate(melody_seq):
            mel.append((bar * 4 + i * 0.5, f, 0.5))
    bass = []
    for bar in range(8):
        for sub in [0, 0.75, 1.5, 2.25, 3.0]:
            bass.append((bar * 4 + sub, 82.41 if bar % 2 == 0 else 73.42, 0.5))
    chord = []
    chord_seq = [(164.81, 196.0, 246.94), (146.83, 174.61, 220.0)]
    for bar in range(8):
        c = chord_seq[bar % 2]
        for f in c:
            chord.append((bar * 4, f, 4.0))
    hats = []
    for bar in range(8):
        for i in range(16):
            hats.append(bar * 4 + i * 0.25)
    return _chiptune_track(134, 8, mel, bass, chord, hats) * 0.55


def win_fanfare():
    seconds = 3.0
    notes = [
        (0.00, 523.25, 0.25),
        (0.25, 659.25, 0.25),
        (0.50, 783.99, 0.25),
        (0.75, 1046.5, 0.75),
        (1.50, 880.0, 0.30),
        (1.80, 1046.5, 0.30),
        (2.10, 1318.5, 0.85),
    ]
    y = np.zeros(int(seconds * SR))
    for t, f, dur in notes:
        start = int(t * SR)
        seg = mix(
            triangle(f, dur) * env_adsr(dur, a=0.005, d=0.05, s=0.7, r=0.1) * 0.6,
            sine(f * 2, dur) * env_adsr(dur, a=0.005, d=0.05, s=0.4, r=0.1) * 0.25,
        )
        end = min(len(y), start + len(seg))
        y[start:end] += seg[:end - start]
    # Big chord at the end.
    chord_start = int(2.1 * SR)
    chord_dur = seconds - 2.1
    chord = sum(
        triangle(f, chord_dur) * env_adsr(chord_dur, a=0.01, d=0.2, s=0.6, r=0.5) * 0.25
        for f in [523.25, 659.25, 783.99, 1046.5]
    )
    end = min(len(y), chord_start + len(chord))
    y[chord_start:end] += chord[:end - chord_start]
    return fade(reverb(y, decay=0.4), 0.005, 0.1)


# =============================================================================
# Registry — maps filename → builder function.
# =============================================================================

@dataclass
class Recipe:
    name: str
    fn: Callable[[], np.ndarray]
    stereo: bool = False
    bitrate: int = 128


RECIPES: list[Recipe] = [
    # 1. Music
    # NOTE: menu_loop / solo_loop / br_loop are sourced externally from
    # OpenGameArt CC0 (see assets/audio/CREDITS.md) — the procedural
    # chiptune versions are kept available via `python3 tools/synth.py
    # menu_loop` if someone explicitly asks for them, but they are
    # excluded from the bulk render so a re-run doesn't overwrite the
    # curated tracks.
    Recipe("win_fanfare", win_fanfare, stereo=True, bitrate=160),
    # 2. UI
    Recipe("ui_click", ui_click),
    Recipe("ui_hover", ui_hover),
    Recipe("ui_back", ui_back),
    Recipe("ui_confirm", ui_confirm),
    Recipe("ui_toggle", ui_toggle),
    # 3. Player actions
    Recipe("charge_loop", charge_loop),
    Recipe("charge_max", charge_max),
    Recipe("jump_release", jump_release),
    Recipe("land_soft", land_soft),
    Recipe("land_hard", land_hard),
    Recipe("bouncy_boing", bouncy_boing),
    Recipe("wall_bounce", wall_bounce),
    Recipe("fall_swoosh", fall_swoosh),
    # 4. Pickups
    Recipe("pickup_star", pickup_star),
    Recipe("pickup_crystal", pickup_crystal),
    Recipe("slow_time_active", slow_time_active),
    Recipe("slow_time_end", slow_time_end),
    Recipe("pickup_heart", pickup_heart),
    Recipe("pickup_vision", pickup_vision),
    Recipe("pickup_warp", pickup_warp),
    Recipe("teleport_arrive", teleport_arrive),
    # 5. Combo & rewards
    Recipe("combo_tick_a", combo_tick_a),
    Recipe("combo_tick_b", combo_tick_b),
    Recipe("combo_tick_c", combo_tick_c),
    Recipe("combo_tick_d", combo_tick_d),
    Recipe("combo_x5_plus", combo_x5_plus),
    Recipe("combo_break", combo_break),
    Recipe("bouncy_chain_a", bouncy_chain_a),
    Recipe("bouncy_chain_b", bouncy_chain_b),
    Recipe("bouncy_chain_c", bouncy_chain_c),
    Recipe("comeback_reward", comeback_reward),
    Recipe("wall_rebond_reward", wall_rebond_reward),
    Recipe("score_milestone", score_milestone),
    Recipe("new_best_score", new_best_score, bitrate=160),
    # 6. Tension & danger
    Recipe("danger_low_heartbeat", danger_low_heartbeat),
    Recipe("platform_crack", platform_crack),
    Recipe("platform_explode", platform_explode),
    Recipe("wind_ambient", wind_ambient),
    # 7. Death & game over
    Recipe("death_fall", death_fall),
    Recipe("death_crushed", death_crushed),
    Recipe("gameover_jingle", gameover_jingle, bitrate=160),
    Recipe("revive_ready", revive_ready),
    # 8. Battle Royale
    Recipe("lobby_player_join", lobby_player_join),
    Recipe("lobby_player_leave", lobby_player_leave),
    Recipe("lobby_countdown_tick", lobby_countdown_tick),
    Recipe("countdown_321", countdown_321),
    Recipe("countdown_go", countdown_go),
    Recipe("kill_confirmed", kill_confirmed),
    Recipe("kill_streak", kill_streak),
    Recipe("got_crushed", got_crushed),
    Recipe("opponent_died", opponent_died),
    Recipe("safe_zone_end", safe_zone_end),
    Recipe("leader_changed", leader_changed),
    Recipe("victory_win", victory_win, stereo=True, bitrate=160),
    Recipe("defeat_placement", defeat_placement),
    # 9. Ambient
    Recipe("cube_idle_blip", cube_idle_blip),
    Recipe("pickup_spawn_chime", pickup_spawn_chime),
]


def render(only: Iterable[str] | None = None):
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg not found on PATH — install via Homebrew: brew install ffmpeg")
    only_set = set(only) if only else None
    for r in RECIPES:
        if only_set is not None and r.name not in only_set:
            continue
        print(f"  • {r.name:<24} …", end=" ", flush=True)
        try:
            buf = r.fn()
            save_wav(r.name, buf, stereo=r.stereo)
            wav_to_mp3(r.name, bitrate_kbps=r.bitrate)
            print("ok")
        except Exception as exc:
            print(f"FAIL: {exc}")
            raise


if __name__ == "__main__":
    np.random.seed(0)  # deterministic noise so re-runs match
    targets = sys.argv[1:] if len(sys.argv) > 1 else None
    render(targets)
    print(f"\nMP3s written to: {MP3_DIR}")
