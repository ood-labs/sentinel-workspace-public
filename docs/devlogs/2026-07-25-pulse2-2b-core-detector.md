---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2B
status: complete
approval: pending
summary: "pulse2_analyzer core detector - aggregate onset F1 0.774 vs 0.706 baseline, all six 2B criteria met"
---

## Done

`modules/pulse2_analyzer/` implements the split whitening / SuperFlux / peak-picking
detector against Audio In's Spectrum port and emits the 2A1 `Hits` contract.
All six 2B pass criteria are met.

1. **Beats the baseline.** Aggregate onset F1 **0.774 vs 0.706** (`scores/2B.json`
   against `scores/2A2.json`, delta column printed). Per lane: kick 0.834,
   snare 0.522, hat 0.959.
2. **Whitening proven where starvation occurs.** `hats_under_loud_kick_150` hat
   F1 **0.982** (>= 0.85) with no per-lane threshold floor, one config across all
   eleven patterns. `dense_140` did not drop: kick 0.818 (+0.081), hat 0.981 (+0.326).
3. **Visible gate.** Preview shows three lanes of SuperFlux, the picker's own
   adaptive threshold, and accepted-onset ticks over ~1.4 s of hop history.
   Playback vs silence captures asserted different by vision check
   (`captures/2B_preview_playback.png`, `captures/2B_preview_silence.png`; note
   `captures/` is gitignored). Silence accumulates **0 onsets over 6 s** with the
   gate closed.
4. **Cook-rate independence.** Onset counts **identical** at 60 Hz and forced
   ~20 Hz (42/63/84, full run and 0.5 s-inset interior), with two same-rate
   repeats as the control (`measure_cookrate2.py`). A 600 ms stall (> the 341 ms
   ring) resyncs cleanly: serials strictly increasing, unique, `sample_position`
   monotonic; 1 hat onset lost to the overwritten ring, which is unrecoverable by
   construction (`measure_cookrate.py`).
5. **Budget.** Analyzer `wall_time_ms` mean **0.520** (max 0.569) <= 0.6, graph
   frame total delta **0.184 ms** <= 0.5, rolling `cook_hz` 60-61 vs graph 60
   (`measure_budget.py`, interleaved enabled/disabled sampling).
6. **fft_size re-confirmed on Spectrum.** 2048 **0.774** vs 4096 **0.761**
   (`scores/2B_fft4096.json`). 4096 helps kick 0.850 and snare 0.576 but collapses
   hat 0.962 -> 0.860, exactly the documented 0-12 kHz truncation biting the
   7 kHz hat bursts. 2048 stands.

## Issues

**Two real defects found, both silent.** The detector first scored 0.403 while an
offline numpy mirror of the same maths scored 0.882. Bisecting by feeding the
offline picker the GPU's own flux series localised it to the flux stage, not the
picker.

- `flux.hlsl` and `pick.hlsl` read `sample_rate` / `fft_size` / `hop_size` from
  `_Data0[0]` — an arbitrary unvalidated ring slot. When it read zero the
  `max(x, 1u)` guards yielded `binHz = 1.0`, silently reinterpreting bin indices
  as Hz: the kick lane became bins 25-199 (~0.6-4.7 kHz) and the hat lane emptied.
  The header is now captured by the whitening pass, which is the only pass that
  validates the slot.
- `flux.hlsl` decided which hop a spec slot held from the live producer ring,
  which advances between dispatches, so it computed flux for generations the
  whitening pass had never whitened — differencing a fresh frame against a slot a
  full ring old. This kept the flux *distribution* plausible (matching p99) while
  destroying its time structure: correlation with the offline reference was
  0.30/0.51/0.43. Pass A now stamps the generation into each slot and pass B
  trusts only that stamp. Correlation is now 0.94/0.98/0.97.

**Snare lane is the known deficit** and regressed against the baseline on every
pattern (worst `sparse_90` -0.311). Recall is 1.000, precision 0.31-0.34: on
`four_on_floor_128` the lane emits 61 for 21 true snares, ≈ 21 snares + 43 kicks,
because the kick's broadband click transient lands squarely in 200-2400 Hz. Band
narrowing cannot remove a broadband click. The regression tolerance was **not**
loosened; this is carried into 2C3 lateral inhibition, which exists for exactly
this cross-lane leakage.

**`peak_floor` reasoning corrected.** The earlier note chose the floor from the
magnitude median and landed on 1e-6. That was wrong: the floor's job is to stop a
band with no signal normalising its own dither to full scale. Swept on
non-held-out patterns to 5e-5, which removed the phantom kick/snare onsets on
`hats_only_150` (0.000 -> excluded) with per-lane F1 unchanged elsewhere.

## Next

2C1 - region masks and evaluation.
