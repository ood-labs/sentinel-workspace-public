---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2A1 + 2A2
status: complete
approval: pending
summary: "Frozen corpus, Hits export contract, scoring harness with four biting self-tests, and the committed cryo_pulse baseline"
---

# Phase 2 - 2A1 corpus and export contract, 2A2 scorer and baseline

## Done

**2A1.** `tools/audio_test/generate_corpus.py` writes eleven seeded 48 kHz stereo patterns plus
two aux files (-44 dBFS noise floor, digital silence) needed by the 2E2 honesty gate. Generated
once, SHA-256 gated, frozen. Aux files were made now rather than at 2E2 because regenerating the
corpus after 2A1 closes is a Hard Blocker.

- Criterion 1: `generate_corpus.py --verify` regenerates to a temp dir and confirms byte-identical
  output against `corpus.sha256`. PASS.
- Criterion 3: over a full `four_on_floor_128`, `cryo_pulse` and `cryo_pulse_baseline` produced
  identical lane counts (kick 34, snare 40, hihat 66, onset 140; delta 0 on every counter). PASS.
- Criterion 2: PARTIAL, see Issues.

`modules/cryo_pulse_baseline/` adds only a `Hits` data output (512-slot ring of
`{lane_id, onset_serial, hop_index, sample_position}`, lane 3 = PLL beat events). Detection maths
untouched.

**2A2.** `score_detector.py` drives Sentinel over its ZMQ bridge directly, so the harness runs
standalone and repeatedly rather than through an agent.

- Criterion 1: runs end to end over all eleven patterns, printing per-lane F1, BPM error, metrical
  level and CMLc/AMLc; writes `scores/2A2.json`. PASS.
- Criterion 2: all four absolute self-tests pass — identity F1 = 1.000; +20 ms holds 1.000 while
  +30 ms collapses to 0.000; one hop (5.33 ms) moves F1 by 0.0000; permuted labels give exactly
  0.000 on isolated lanes. PASS.
- Criterion 3: baseline committed at aggregate F1 **0.706** (kick 0.675, snare 0.676, hat 0.777),
  corpus `50e89b594f08b41a`, `fft_size` 2048. PASS.
- Criterion 4: `fft_size` comparison run and recorded. PASS.

Baseline highlight for 2B: `hats_under_loud_kick_150` scores hat F1 **0.058-0.157** and aggregate
0.219. That is the threshold-starvation failure whitening exists to fix, and it confirms the
pattern can fail for the reason it claims.

## Decisions

- **`fft_size` 2048 adopted provisionally, against the research's 4096 recommendation.** Measured:
  4096 lifts kick markedly (mean 0.675 -> 0.827) but collapses hat (0.777 -> 0.650) and snare
  (0.676 -> 0.610), for aggregate 0.692 versus 2048's 0.706. The hat collapse is the 0-12 kHz
  coverage truncation biting exactly where the Measured Facts table predicted. Re-confirmed at 2B
  on Spectrum data, per the phase doc.
- **Committed score tables are RAW, not latency-compensated.** The ~12 ms analysis latency is real
  and measured (kick 12.06, snare 11.98, hat 11.81 ms), but subtracting it is a knob, and the same
  agent generates, scores and tunes here. Both detectors are scored identically without it, so the
  comparison is unaffected. `--compensate` remains for analysis only.
- **Self-test (d) sharpened rather than loosened.** Permuting labels on the corpus floors at 0.377,
  not ~0, because kick/snare/hat deliberately coincide (four-on-floor puts a hat on every kick).
  The test now runs on isolated synthetic lanes where the expected result is exactly 0.000 — a
  stricter check — and reports the corpus figure alongside so the coincidence floor stays visible.

## Issues

- **2A1 criterion 2 cannot be met as written.** It asks for detections within +/-5 ms of ground
  truth. The hop grid is 5.33 ms, so +/-5 ms is below one hop of resolution and unreachable by any
  implementation. What was proven instead: `sample_position` is hop-aligned, serial-unique and
  monotonic, and sits a consistent ~12 ms after ground truth (window fill plus one flux frame),
  which is comfortably inside the +/-25 ms scoring window the harness actually uses. Recorded as a
  measured fact, not compensated away. Flagged for the phase-boundary review.

## Next

2B: `pulse2_analyzer` — split whitening / SuperFlux / peak-picking passes, scored against
`scores/2A2.json` with a delta column.
