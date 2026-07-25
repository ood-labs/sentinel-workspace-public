#!/usr/bin/env python3
"""Score a live Sentinel onset detector against the frozen Phase 2 corpus.

Reads the detector's `Hits` data output over Sentinel's IPC bridge, matches the
emitted `sample_position` values against each pattern's JSON sidecar, and
reports per-lane onset F1 at a +/-25 ms tolerance plus BPM error, metrical-level
correctness and CMLc/AMLc beat continuity.

The timebase is `sample_position` INSIDE the emitted records, differenced
against the sidecar. Wall-clock timing and poll order are never used, because
File mode is paced playback with no documented position or completion field.

Usage:
    python score_detector.py --selftest
    python score_detector.py --subphase 2A2
    python score_detector.py --subphase 2B --baseline scores/2A2.json
    python score_detector.py --subphase 2B --patterns four_on_floor_128
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np

import metrics
from sentinel_ipc import Sentinel, AudioRunner, SentinelError, reset_detector

HERE = Path(__file__).resolve().parent
CORPUS = HERE / "corpus"
SCORES = HERE / "scores"
MANIFEST = HERE / "corpus.sha256"
LANE_MAP = HERE / "lane_map.json"

HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}

# No sub-phase may reduce any previously committed per-lane F1 by more than this.
REGRESSION_TOLERANCE = 0.01


# ---------------------------------------------------------------------------
# Corpus integrity
# ---------------------------------------------------------------------------


def corpus_hash_check() -> str:
    """Refuse to run if any corpus file's hash has drifted. Returns a digest of
    the manifest itself, which every score table records."""
    if not MANIFEST.exists():
        sys.exit("corpus.sha256 missing - run generate_corpus.py first")
    expected = {}
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            digest, name = line.split("  ", 1)
            expected[name] = digest

    bad = []
    for name, want in expected.items():
        p = CORPUS / name
        if not p.exists():
            bad.append(f"missing: {name}")
            continue
        h = hashlib.sha256()
        with p.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        if h.hexdigest() != want:
            bad.append(f"modified: {name}")
    if bad:
        sys.exit("CORPUS HASH MISMATCH - the corpus is frozen.\n  " + "\n  ".join(bad))

    return hashlib.sha256(MANIFEST.read_bytes()).hexdigest()[:16]


def load_patterns(only: list[str] | None = None) -> list[dict]:
    out = []
    for jf in sorted(CORPUS.glob("*.json")):
        meta = json.loads(jf.read_text(encoding="utf-8"))
        if meta.get("role") != "pattern":
            continue
        if only and meta["name"] not in only:
            continue
        meta["_wav"] = jf.with_suffix(".wav")
        out.append(meta)
    return out


# ---------------------------------------------------------------------------
# Scoring one pattern
# ---------------------------------------------------------------------------


def score_pattern(meta: dict, hits: list[dict], cfg: dict,
                  tempo_samples: list[dict], compensate: bool) -> dict:
    sr = float(meta["sample_rate"])
    tol = cfg["tolerance_ms"] / 1000.0
    lane_ids = cfg["lanes"]
    latency = cfg.get("analysis_latency_ms", {}) if compensate else {}

    ref_by_lane: dict[str, list[float]] = {ln: [] for ln in lane_ids}
    for h in meta["hits"]:
        if h["lane"] in ref_by_lane:
            ref_by_lane[h["lane"]].append(h["sample"] / sr)

    est_by_lane: dict[str, list[float]] = {ln: [] for ln in lane_ids}
    est_beats: list[float] = []
    id_to_lane = {v: k for k, v in lane_ids.items()}
    for h in hits:
        lid = int(h["lane_id"])
        t = int(h["sample_position"]) / sr
        if lid == cfg.get("beat_lane", -1):
            est_beats.append(t - latency.get("beat", 0.0) / 1000.0)
        elif lid in id_to_lane:
            ln = id_to_lane[lid]
            est_by_lane[ln].append(t - latency.get(ln, 0.0) / 1000.0)

    lanes = {}
    for ln in lane_ids:
        lanes[ln] = metrics.f_measure(ref_by_lane[ln], est_by_lane[ln], tol)

    scored = [v for ln, v in lanes.items() if v["n_ref"] > 0 or v["n_est"] > 0]
    agg_f1 = float(np.mean([v["f1"] for v in scored])) if scored else 0.0

    # Tempo: median of the polled estimate over the steady window, excluding the
    # first quarter of the run so lock-in is not counted against the tracker.
    bpms = [s["bpm"] for s in tempo_samples if np.isfinite(s.get("bpm", float("nan")))]
    confs = [s["tempo_conf"] for s in tempo_samples
             if np.isfinite(s.get("tempo_conf", float("nan")))]
    steady = bpms[len(bpms) // 4:] if len(bpms) >= 4 else bpms
    est_bpm = float(np.median(steady)) if steady else 0.0

    tempo_meta = meta.get("tempo", {})
    ref_bpm = float(tempo_meta.get("bpm_start", 0.0))
    if tempo_meta.get("kind") == "ramp":
        ref_bpm = 0.5 * (float(tempo_meta["bpm_start"]) + float(tempo_meta["bpm_end"]))
    level_ok, ratio = metrics.metrical_level(est_bpm, ref_bpm) if ref_bpm else (False, "n/a")

    ref_beats = [b["sample"] / sr for b in meta.get("beats", [])]
    cont = metrics.continuity_scores(ref_beats, est_beats)

    return {
        "pattern": meta["name"],
        "held_out": meta.get("held_out", False),
        "lanes": lanes,
        "aggregate_f1": agg_f1,
        "bpm_ref": ref_bpm,
        "bpm_est": est_bpm,
        "bpm_error": abs(est_bpm - ref_bpm) if ref_bpm else float("nan"),
        "metrical_level_ok": level_ok,
        "metrical_ratio": ratio,
        "tempo_conf": float(np.median(confs)) if confs else 0.0,
        "n_est_beats": len(est_beats),
        "n_ref_beats": len(ref_beats),
        **cont,
    }


# ---------------------------------------------------------------------------
# Self-tests (2A2 criterion 2) - four ABSOLUTE checks, no Sentinel involved
# ---------------------------------------------------------------------------


def selftest(cfg: dict) -> int:
    print("Scorer self-test - four absolute checks\n")
    patterns = load_patterns()
    sr = 48000.0
    lane_ids = cfg["lanes"]
    hop_ms = 1000.0 * cfg["hop_size"] / cfg["sample_rate"]
    failures = []

    def synth_hits(meta, shift_ms=0.0, permute=False):
        """Feed the ground-truth annotations back in as the detection stream."""
        order = list(lane_ids)
        rot = {ln: lane_ids[order[(i + 1) % len(order)]]
               for i, ln in enumerate(order)}
        out = []
        for i, h in enumerate(meta["hits"]):
            if h["lane"] not in lane_ids:
                continue
            lid = rot[h["lane"]] if permute else lane_ids[h["lane"]]
            out.append({
                "lane_id": lid,
                "onset_serial": i + 1,
                "hop_index": 0,
                "sample_position": int(round(h["sample"] + shift_ms / 1000.0 * sr)),
            })
        return out

    def agg(shift_ms=0.0, permute=False):
        per_lane = []
        for meta in patterns:
            r = score_pattern(meta, synth_hits(meta, shift_ms, permute), cfg, [],
                              compensate=False)
            per_lane += [v["f1"] for v in r["lanes"].values() if v["n_ref"] > 0]
        return float(np.mean(per_lane)), min(per_lane)

    # (a) identity
    mean_f1, min_f1 = agg()
    ok = abs(mean_f1 - 1.0) < 1e-9 and abs(min_f1 - 1.0) < 1e-9
    print(f"  a. identity ........... mean F1 {mean_f1:.4f}  min lane F1 {min_f1:.4f}   "
          f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        failures.append("identity")

    # (b) window bracketing: +20 ms holds, +30 ms collapses
    f20, _ = agg(shift_ms=20.0)
    f30, _ = agg(shift_ms=30.0)
    ok = abs(f20 - 1.0) < 1e-9 and f30 < 0.10
    print(f"  b. window bracket ..... +20 ms F1 {f20:.4f} (expect 1.000)   "
          f"+30 ms F1 {f30:.4f} (expect ~0)   {'PASS' if ok else 'FAIL'}")
    if not ok:
        failures.append("window-bracket")

    # (c) one hop of shift barely moves the score
    fhop, _ = agg(shift_ms=hop_ms)
    ok = abs(fhop - 1.0) < 0.01
    print(f"  c. one-hop shift ...... {hop_ms:.2f} ms -> F1 {fhop:.4f}  "
          f"delta {abs(fhop - 1.0):.4f} (< 0.01)   {'PASS' if ok else 'FAIL'}")
    if not ok:
        failures.append("one-hop")

    # (d) permuted lane labels must collapse the score.
    #
    # Run on ISOLATED synthetic lanes, not on the corpus. In the corpus, kick,
    # snare and hat deliberately land on the same steps (four-on-floor puts a
    # hat on every kick, and kick_snare_coincident_124 exists precisely to make
    # them collide), so a permuted label still matches a coincident event and
    # the corpus figure floors out around 0.38 no matter how correct the scorer
    # is. Isolating the lanes removes that confound and makes the expected
    # result exactly zero, which is a STRICTER test than the corpus version.
    iso_meta = {
        "name": "_synthetic_isolated",
        "sample_rate": sr,
        "hits": [{"lane": ln, "sample": int((i * len(lane_ids) + k) * 0.20 * sr)}
                 for k, ln in enumerate(lane_ids) for i in range(24)],
        "beats": [],
        "tempo": {},
    }
    iso_ident = score_pattern(iso_meta, synth_hits(iso_meta), cfg, [], compensate=False)
    iso_perm = score_pattern(iso_meta, synth_hits(iso_meta, permute=True), cfg, [],
                             compensate=False)
    iso_i = float(np.mean([v["f1"] for v in iso_ident["lanes"].values()]))
    iso_p = float(np.mean([v["f1"] for v in iso_perm["lanes"].values()]))

    # And confirm the corpus permutation still collapses hard from identity,
    # reported so the coincidence floor is visible rather than hidden.
    fperm, _ = agg(permute=True)

    ok = abs(iso_i - 1.0) < 1e-9 and iso_p < 1e-9 and fperm < 0.5
    print(f"  d. label permutation .. isolated lanes: identity {iso_i:.4f} -> "
          f"permuted {iso_p:.4f} (expect 0)")
    print(f"                          corpus (lanes coincide): 1.0000 -> "
          f"{fperm:.4f}   {'PASS' if ok else 'FAIL'}")
    if not ok:
        failures.append("label-permutation")

    print()
    if failures:
        print("SELF-TEST FAILED:", ", ".join(failures))
        return 1
    print("SELF-TEST PASSED - scores from this harness are trustworthy.")
    return 0


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def print_table(results: list[dict], baseline: dict | None, lane_names: list[str]):
    base_by_pat = {}
    if baseline:
        base_by_pat = {r["pattern"]: r for r in baseline.get("results", [])}

    head = f"{'pattern':<28}"
    for ln in lane_names:
        head += f" {ln[:5]:>6}"
        if baseline:
            head += f" {'d':>6}"
    head += f" {'aggF1':>6} {'BPM':>7} {'err':>6} {'lvl':>5} {'CMLc':>5} {'AMLc':>5}"
    print(head)
    print("-" * len(head))

    for r in results:
        row = f"{r['pattern']:<28}"
        b = base_by_pat.get(r["pattern"])
        for ln in lane_names:
            v = r["lanes"].get(ln)
            if v is None or (v["n_ref"] == 0 and v["n_est"] == 0):
                row += f" {'-':>6}"
                if baseline:
                    row += f" {'':>6}"
                continue
            row += f" {v['f1']:>6.3f}"
            if baseline:
                if b and ln in b["lanes"]:
                    row += f" {v['f1'] - b['lanes'][ln]['f1']:>+6.3f}"
                else:
                    row += f" {'':>6}"
        row += f" {r['aggregate_f1']:>6.3f} {r['bpm_est']:>7.1f} {r['bpm_error']:>6.1f}"
        row += f" {'ok' if r['metrical_level_ok'] else r['metrical_ratio']:>5}"
        row += f" {r['CMLc']:>5.2f} {r['AMLc']:>5.2f}"
        if r["held_out"]:
            row += "  [held-out]"
        print(row)

    print("-" * len(head))
    means = {ln: np.mean([r["lanes"][ln]["f1"] for r in results
                          if r["lanes"].get(ln, {}).get("n_ref", 0) > 0] or [0])
             for ln in lane_names}
    summary = f"{'MEAN':<28}"
    for ln in lane_names:
        summary += f" {means[ln]:>6.3f}"
        if baseline:
            summary += f" {'':>6}"
    summary += f" {np.mean([r['aggregate_f1'] for r in results]):>6.3f}"
    print(summary)


def check_regression(results: list[dict], baseline: dict, lane_names: list[str]) -> int:
    base_by_pat = {r["pattern"]: r for r in baseline.get("results", [])}
    breaches = []
    for r in results:
        b = base_by_pat.get(r["pattern"])
        if not b:
            continue
        for ln in lane_names:
            if ln not in r["lanes"] or ln not in b["lanes"]:
                continue
            if b["lanes"][ln]["n_ref"] == 0:
                continue
            drop = b["lanes"][ln]["f1"] - r["lanes"][ln]["f1"]
            if drop > REGRESSION_TOLERANCE:
                breaches.append(f"{r['pattern']}/{ln}: -{drop:.3f}")
    if breaches:
        print(f"\nREGRESSION GATE FAILED (tolerance {REGRESSION_TOLERANCE}):")
        for b in breaches:
            print("  " + b)
        return 1
    print(f"\nRegression gate: PASS (no per-lane F1 dropped by more than "
          f"{REGRESSION_TOLERANCE})")
    return 0


# ---------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--subphase", help="write scores/<subphase>.json")
    ap.add_argument("--baseline", help="compare against a committed score table")
    ap.add_argument("--patterns", nargs="*", help="restrict to named patterns")
    ap.add_argument("--detector", help="override detector pipeline id")
    ap.add_argument("--fft-size", default="2048")
    # Committed tables are RAW by design. The ~12 ms analysis latency is a real,
    # measured property of the front end, but subtracting it is a knob, and the
    # same agent generates, scores and tunes here. Both detectors are scored
    # identically without it, so the comparison is unaffected and no number can
    # be improved by adjusting the constant. Compensation stays available for
    # analysis only.
    ap.add_argument("--compensate", action="store_true",
                    help="subtract the declared constant analysis latency "
                         "(analysis only; committed tables are raw)")
    ap.add_argument("--no-reset", action="store_true",
                    help="skip the per-pattern force_reload")
    args = ap.parse_args()

    cfg = json.loads(LANE_MAP.read_text(encoding="utf-8"))
    if args.detector:
        cfg["detector"] = args.detector
    lane_names = list(cfg["lanes"])

    if args.selftest:
        return selftest(cfg)

    corpus_id = corpus_hash_check()
    patterns = load_patterns(args.patterns)
    if not patterns:
        sys.exit("no patterns matched")

    sen = Sentinel()
    if not sen.ping():
        sys.exit("Sentinel is not reachable on tcp://127.0.0.1:5555")

    detector = cfg["detector"]
    runner = AudioRunner(sen, cfg["audio"], detector, hits_port=cfg["hits_port"])
    polls = {"bpm": "bpm", "tempo_conf": "tempo_conf"}

    print(f"detector={detector}  corpus={corpus_id}  fft_size={args.fft_size}  "
          f"tolerance=+/-{cfg['tolerance_ms']:.0f} ms  "
          f"latency_compensated={not args.no_compensate}\n")

    results = []
    for meta in patterns:
        if not args.no_reset:
            reset_detector(sen, detector, cfg["audio"], mel_slot=cfg["mel_slot"])
        runner.configure_file(meta["_wav"], fft_size=args.fft_size)
        run = runner.run_pattern(meta["_wav"], meta["duration_samples"],
                                 extra_polls=polls)
        r = score_pattern(meta, run["hits"], cfg, run["samples"],
                          compensate=args.compensate)
        r["n_hits_emitted"] = len(run["hits"])
        r["playback_completed"] = run["completed"]
        r["final_sample_position"] = run["final_sample_position"]
        results.append(r)
        flag = "" if run["completed"] else "  (playback did not reach EOF)"
        print(f"  scored {meta['name']:<28} {len(run['hits']):>4} records{flag}")

    print()
    print_table(results, None, lane_names)

    baseline = None
    if args.baseline:
        bp = Path(args.baseline)
        if not bp.is_absolute():
            bp = HERE / bp
        baseline = json.loads(bp.read_text(encoding="utf-8"))
        print(f"\nversus {bp.name} (corpus {baseline.get('corpus_id')}):\n")
        print_table(results, baseline, lane_names)

    table = {
        "subphase": args.subphase,
        "detector": detector,
        "corpus_id": corpus_id,
        "fft_size": args.fft_size,
        "tolerance_ms": cfg["tolerance_ms"],
        "latency_compensated": args.compensate,
        "analysis_latency_ms": cfg.get("analysis_latency_ms"),
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "aggregate_f1": float(np.mean([r["aggregate_f1"] for r in results])),
        "results": results,
    }

    rc = 0
    if baseline:
        rc = check_regression(results, baseline, lane_names)

    if args.subphase:
        SCORES.mkdir(exist_ok=True)
        out = SCORES / f"{args.subphase}.json"
        out.write_text(json.dumps(table, indent=2) + "\n", encoding="utf-8")
        print(f"\nwrote {out}")

    return rc


if __name__ == "__main__":
    raise SystemExit(main())
