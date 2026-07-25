#!/usr/bin/env python3
"""Generate the frozen Phase 2 audio analysis test corpus.

Eleven 48 kHz stereo WAV patterns are synthesised from a seeded RNG, each with a
JSON sidecar carrying exact per-hit sample positions, lane labels and beat
positions. Two auxiliary files (a -44 dBFS noise floor and digital silence) are
generated alongside them for the 2E2 honesty gate; they carry no hits and are
not scored as patterns.

The corpus is generated ONCE, committed with a SHA-256 manifest, and frozen.
score_detector.py refuses to run if any hash mismatches. Re-running this script
from the same seed must produce byte-identical files.

Usage:
    python generate_corpus.py                 # write corpus/ and corpus.sha256
    python generate_corpus.py --verify        # regenerate to a temp dir and
                                              # compare against the manifest
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SAMPLE_RATE = 48000
CHANNELS = 2
BIT_DEPTH = 16
DURATION_S = 20.0
MASTER_SEED = 20260725

HERE = Path(__file__).resolve().parent
CORPUS_DIR = HERE / "corpus"
MANIFEST_PATH = HERE / "corpus.sha256"

# Voice levels in dBFS. These are peak levels of the normalised voice waveform,
# so a hit at gain_db = -6.0 peaks at 0.501 full scale.
KICK_DB = -6.0
SNARE_DB = -9.0
HAT_DB = -18.0


def db_to_lin(db: float) -> float:
    return float(10.0 ** (db / 20.0))


# ---------------------------------------------------------------------------
# Voice synthesis
# ---------------------------------------------------------------------------


def _normalise(x: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(x)))
    if peak <= 0.0:
        return x
    return x / peak


def make_kick(rng: np.random.Generator) -> np.ndarray:
    """Pitch-swept sine with a click transient."""
    dur = 0.35
    n = int(dur * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    f_start, f_end, tau_f = 150.0, 45.0, 0.030
    freq = f_end + (f_start - f_end) * np.exp(-t / tau_f)
    phase = 2.0 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    body = np.sin(phase) * np.exp(-t / 0.090)

    click_n = int(0.004 * SAMPLE_RATE)
    click = rng.standard_normal(click_n)
    sos = signal.butter(2, 2000.0, btype="highpass", fs=SAMPLE_RATE, output="sos")
    click = signal.sosfilt(sos, click)
    click *= np.exp(-np.arange(click_n) / SAMPLE_RATE / 0.0007)
    click = _normalise(click) * 0.45

    out = body.copy()
    out[:click_n] += click
    return _normalise(out)


def make_snare(rng: np.random.Generator) -> np.ndarray:
    """Band-passed noise plus a tonal body."""
    dur = 0.25
    n = int(dur * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    noise = rng.standard_normal(n)
    sos = signal.butter(
        3, [1200.0, 9000.0], btype="bandpass", fs=SAMPLE_RATE, output="sos"
    )
    noise = signal.sosfilt(sos, noise)
    noise *= np.exp(-t / 0.055)
    noise = _normalise(noise)

    body = (np.sin(2 * np.pi * 185.0 * t) + 0.7 * np.sin(2 * np.pi * 330.0 * t))
    body *= np.exp(-t / 0.045)
    body = _normalise(body)

    return _normalise(noise + 0.5 * body)


def make_hat(rng: np.random.Generator) -> np.ndarray:
    """Short high-frequency noise burst."""
    dur = 0.09
    n = int(dur * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    noise = rng.standard_normal(n)
    sos = signal.butter(4, 7000.0, btype="highpass", fs=SAMPLE_RATE, output="sos")
    noise = signal.sosfilt(sos, noise)
    noise *= np.exp(-t / 0.014)
    return _normalise(noise)


# ---------------------------------------------------------------------------
# Pattern definitions
# ---------------------------------------------------------------------------
#
# Each pattern places lanes on a step grid. `spb` is steps per beat, `bar` is
# the bar length in steps. Step indices are taken modulo `bar`.
#
# `level_db` optionally overrides the default per-lane level.
# `vel` entries scale individual steps (used for ghost notes).

PATTERNS = [
    {
        "name": "four_on_floor_128",
        "bpm": 128.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 4, 8, 12],
            "snare": [4, 12],
            "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        },
        "targets": "baseline; steady tempo reference",
    },
    {
        "name": "breakbeat_170",
        "bpm": 170.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 10],
            "snare": [4, 12],
            "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        },
        "vel": {"snare": {7: 0.16}},
        "extra": {"snare": [7]},
        "targets": "syncopation; tempo octave risk",
    },
    {
        "name": "sparse_90",
        "bpm": 90.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0],
            "snare": [8],
            "hat": [0, 8],
        },
        "targets": "low onset density; tempo stability",
    },
    {
        "name": "dense_140",
        "bpm": 140.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 3, 6, 10, 12],
            "snare": [4, 14, 15],
            "hat": list(range(16)),
        },
        "targets": "fills; double-trigger pressure",
    },
    {
        "name": "tempo_ramp_120_132",
        "bpm": 120.0,
        "bpm_end": 132.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 4, 8, 12],
            "snare": [4, 12],
            "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        },
        "targets": "tracker agility",
    },
    {
        "name": "quiet_intro_drop_128",
        "bpm": 128.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 4, 8, 12],
            "snare": [4, 12],
            "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        },
        "intro": {"until_s": 8.0, "gain_db": -24.0},
        "targets": "adaptive threshold across a loudness jump",
    },
    {
        "name": "syncopated_funk_105",
        "bpm": 105.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 3, 6, 11],
            "snare": [4, 12],
            "hat": [0, 2, 3, 6, 8, 10, 11, 14],
        },
        "targets": "off-beat accents",
    },
    {
        "name": "halftime_shuffle_88",
        "bpm": 88.0,
        "spb": 6,
        "bar": 24,
        "lanes": {
            "kick": [0, 14],
            "snare": [12],
            "hat": [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21, 23],
        },
        "held_out": True,
        "targets": "metrical-level disambiguation",
    },
    {
        "name": "kick_snare_coincident_124",
        "bpm": 124.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 4, 8, 12],
            "snare": [4, 6, 12, 14],
            "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        },
        "held_out": True,
        "targets": "coincident kick+snare on steps 4 and 12; isolated snare on 6 and 14",
    },
    {
        "name": "hats_only_150",
        "bpm": 150.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        },
        "targets": "HF-only sanity check",
    },
    {
        "name": "hats_under_loud_kick_150",
        "bpm": 150.0,
        "spb": 4,
        "bar": 16,
        "lanes": {
            "kick": [0, 4, 8, 12],
            "hat": list(range(16)),
        },
        "level_db": {"kick": -6.0, "hat": -30.0},
        "targets": "the whitening test: continuous hats at -30 dBFS under a -6 dBFS kick",
    },
]

AUX = [
    {"name": "noise_floor_44db", "kind": "noise", "gain_db": -44.0},
    {"name": "silence", "kind": "silence"},
]


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def step_times(bpm_start: float, bpm_end: float, duration_s: float, spb: int):
    """Step onset times in seconds, integrating a linear BPM ramp."""
    times = []
    t = 0.0
    while t < duration_s:
        times.append(t)
        frac = min(1.0, t / duration_s)
        bpm = bpm_start + (bpm_end - bpm_start) * frac
        t += 60.0 / (bpm * spb)
    return times


def render_pattern(spec: dict, voices: dict) -> tuple[np.ndarray, dict]:
    n_total = int(DURATION_S * SAMPLE_RATE)
    mono = np.zeros(n_total, dtype=np.float64)

    spb = spec["spb"]
    bar = spec["bar"]
    bpm_start = spec["bpm"]
    bpm_end = spec.get("bpm_end", bpm_start)
    levels = dict(kick=KICK_DB, snare=SNARE_DB, hat=HAT_DB)
    levels.update(spec.get("level_db", {}))
    vel_map = spec.get("vel", {})
    intro = spec.get("intro")

    times = step_times(bpm_start, bpm_end, DURATION_S, spb)

    lane_steps = {}
    for lane, steps in spec["lanes"].items():
        lane_steps[lane] = set(steps)
    for lane, steps in spec.get("extra", {}).items():
        lane_steps.setdefault(lane, set()).update(steps)

    hits = []
    for step_index, t in enumerate(times):
        pos = int(round(t * SAMPLE_RATE))
        if pos >= n_total:
            break
        step_in_bar = step_index % bar
        for lane in ("kick", "snare", "hat"):
            if lane not in lane_steps or step_in_bar not in lane_steps[lane]:
                continue
            vel = vel_map.get(lane, {}).get(step_in_bar, 1.0)
            gain_db = levels[lane]
            if intro is not None and t < intro["until_s"]:
                gain_db += intro["gain_db"]
            amp = db_to_lin(gain_db) * vel
            wav = voices[lane]
            end = min(n_total, pos + wav.size)
            mono[pos:end] += wav[: end - pos] * amp
            hits.append(
                {
                    "lane": lane,
                    "sample": pos,
                    "time": round(pos / SAMPLE_RATE, 9),
                    "gain_db": round(20.0 * np.log10(max(amp, 1e-12)), 3),
                    "step": step_index,
                }
            )

    hits.sort(key=lambda h: (h["sample"], h["lane"]))

    beats = []
    for step_index, t in enumerate(times):
        if step_index % spb != 0:
            continue
        pos = int(round(t * SAMPLE_RATE))
        if pos >= n_total:
            break
        beats.append({"index": len(beats), "sample": pos, "time": round(pos / SAMPLE_RATE, 9)})

    meta = {
        "name": spec["name"],
        "sample_rate": SAMPLE_RATE,
        "channels": CHANNELS,
        "bit_depth": BIT_DEPTH,
        "duration_samples": n_total,
        "duration_seconds": DURATION_S,
        "role": "pattern",
        "held_out": bool(spec.get("held_out", False)),
        "targets": spec["targets"],
        "tempo": {
            "kind": "ramp" if bpm_end != bpm_start else "constant",
            "bpm_start": bpm_start,
            "bpm_end": bpm_end,
        },
        "grid": {"steps_per_beat": spb, "bar_steps": bar},
        "levels_dbfs": levels,
        "lane_counts": {
            lane: sum(1 for h in hits if h["lane"] == lane)
            for lane in ("kick", "snare", "hat")
        },
        "beat_count": len(beats),
        "hits": hits,
        "beats": beats,
    }
    return mono, meta


def render_aux(spec: dict, rng: np.random.Generator) -> tuple[np.ndarray, dict]:
    n_total = int(DURATION_S * SAMPLE_RATE)
    if spec["kind"] == "silence":
        mono = np.zeros(n_total, dtype=np.float64)
        desc = "digital silence"
    else:
        # White noise scaled so its RMS sits at the requested dBFS.
        raw = rng.standard_normal(n_total)
        raw /= float(np.sqrt(np.mean(raw**2)))
        mono = raw * db_to_lin(spec["gain_db"])
        desc = f"white noise at {spec['gain_db']} dBFS RMS"

    meta = {
        "name": spec["name"],
        "sample_rate": SAMPLE_RATE,
        "channels": CHANNELS,
        "bit_depth": BIT_DEPTH,
        "duration_samples": n_total,
        "duration_seconds": DURATION_S,
        "role": "aux",
        "held_out": False,
        "targets": desc,
        "tempo": {"kind": "none"},
        "lane_counts": {"kick": 0, "snare": 0, "hat": 0},
        "beat_count": 0,
        "hits": [],
        "beats": [],
    }
    return mono, meta


def write_wav(path: Path, mono: np.ndarray) -> float:
    peak = float(np.max(np.abs(mono))) if mono.size else 0.0
    if peak > 0.999:
        raise SystemExit(f"{path.name}: peak {peak:.4f} would clip; adjust levels")
    # Identical L and R so Sentinel's 0.5 * (L + R) analysis mix equals the mono
    # signal exactly.
    quant = np.clip(np.rint(mono * 32767.0), -32768, 32767).astype("<i2")
    stereo = np.repeat(quant[:, None], CHANNELS, axis=1).reshape(-1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(CHANNELS)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(stereo.tobytes())
    return peak


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def generate(out_dir: Path) -> list[str]:
    out_dir.mkdir(parents=True, exist_ok=True)

    voice_rng = np.random.default_rng(MASTER_SEED)
    voices = {
        "kick": make_kick(voice_rng),
        "snare": make_snare(voice_rng),
        "hat": make_hat(voice_rng),
    }

    written = []
    rows = []
    for spec in PATTERNS:
        mono, meta = render_pattern(spec, voices)
        wav_path = out_dir / f"{spec['name']}.wav"
        json_path = out_dir / f"{spec['name']}.json"
        peak = write_wav(wav_path, mono)
        meta["peak_full_scale"] = round(peak, 6)
        json_path.write_text(
            json.dumps(meta, indent=2, sort_keys=False) + "\n", encoding="utf-8"
        )
        written += [wav_path.name, json_path.name]
        rows.append(
            (
                meta["name"],
                "held-out" if meta["held_out"] else "",
                meta["lane_counts"]["kick"],
                meta["lane_counts"]["snare"],
                meta["lane_counts"]["hat"],
                meta["beat_count"],
                peak,
            )
        )

    aux_rng = np.random.default_rng(MASTER_SEED + 1)
    for spec in AUX:
        mono, meta = render_aux(spec, aux_rng)
        wav_path = out_dir / f"{spec['name']}.wav"
        json_path = out_dir / f"{spec['name']}.json"
        peak = write_wav(wav_path, mono)
        meta["peak_full_scale"] = round(peak, 6)
        json_path.write_text(
            json.dumps(meta, indent=2, sort_keys=False) + "\n", encoding="utf-8"
        )
        written += [wav_path.name, json_path.name]
        rows.append((meta["name"], "aux", 0, 0, 0, 0, peak))

    print(f"{'pattern':<28} {'flag':<9} {'kick':>5} {'snare':>6} {'hat':>5} {'beats':>6} {'peak':>7}")
    for name, flag, k, s, h, b, peak in rows:
        print(f"{name:<28} {flag:<9} {k:>5} {s:>6} {h:>5} {b:>6} {peak:>7.4f}")

    return sorted(written)


def write_manifest(out_dir: Path, names: list[str], manifest_path: Path) -> None:
    lines = [
        "# Phase 2 audio corpus - SHA-256 manifest",
        f"# seed={MASTER_SEED} sample_rate={SAMPLE_RATE} duration_s={DURATION_S}",
        "# Frozen at sub-phase 2A1. Regenerating requires an explicit recorded decision.",
    ]
    for name in names:
        lines.append(f"{sha256_file(out_dir / name)}  {name}")
    manifest_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\nwrote {manifest_path} ({len(names)} files)")


def read_manifest(manifest_path: Path) -> dict[str, str]:
    entries = {}
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        digest, name = line.split("  ", 1)
        entries[name] = digest
    return entries


def verify(corpus_dir: Path, manifest_path: Path) -> int:
    """Regenerate into a temp dir and compare every file against the manifest."""
    if not manifest_path.exists():
        print("no manifest to verify against", file=sys.stderr)
        return 2
    expected = read_manifest(manifest_path)

    tmp = Path(tempfile.mkdtemp(prefix="corpus_verify_"))
    try:
        names = generate(tmp)
        ok = True
        for name in names:
            got = sha256_file(tmp / name)
            want = expected.get(name)
            if want is None:
                print(f"MISSING FROM MANIFEST: {name}")
                ok = False
            elif got != want:
                print(f"MISMATCH: {name}\n  manifest {want}\n  regen    {got}")
                ok = False
        for name in expected:
            if name not in names:
                print(f"MANIFEST EXTRA (not regenerated): {name}")
                ok = False
        # Also confirm the committed corpus dir matches the manifest.
        for name, want in expected.items():
            path = corpus_dir / name
            if not path.exists():
                print(f"MISSING ON DISK: {name}")
                ok = False
            elif sha256_file(path) != want:
                print(f"ON-DISK MISMATCH: {name}")
                ok = False
        print("\nVERIFY:", "reproducible, manifest matches" if ok else "FAILED")
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verify", action="store_true", help="regenerate and compare hashes")
    ap.add_argument("--out", default=str(CORPUS_DIR))
    args = ap.parse_args()

    if args.verify:
        return verify(Path(args.out), MANIFEST_PATH)

    names = generate(Path(args.out))
    write_manifest(Path(args.out), names, MANIFEST_PATH)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
