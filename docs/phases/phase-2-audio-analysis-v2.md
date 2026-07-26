---
type: phase
phase_number: "2"
title: "Audio Analysis v2 (pulse2)"
status: complete
approval: pending
summary: "Build a reusable GPU audio analysis system with a scoring harness first: adaptive-whitened SuperFlux onset detection, click-to-place spectral region isolation, a multi-feature classifier for coincident hits, and comb-filter tempo with a dual-loop beat PLL. All ten sub-phases implemented; two measured criteria gates remain open and unauthorized."
---

# Phase 2 - Audio Analysis v2 (`pulse2`)

## Overview And Motivation

Sentinel 0.5.49 exposes Audio In with `PCM`, `Spectrum`, and `Mel Bands` data ports plus
per-data-input generation uniforms. The first consumer built against it, `modules/cryo_pulse`,
works: it tracks tempo on real material and drives CRYOGRAM. But building it exposed a structural
problem that no amount of further tuning would fix.

**There was no way to tell whether a change made the detector better or worse.** Tuning was done by
watching traces. That produced circular work, a broken measurement layer downstream, a snare lane
that never functioned, and two real bugs that were only found by instrumenting after the fact. The
detector also reported 99% tempo confidence while receiving a noise floor, because adaptive
thresholds normalise to whatever is present.

Deep research (`docs/research_results/Production Grade GPU Audio Analysis...`) specifies an
architecture and resolves the three blocking questions:

1. **Adaptive spectral whitening** normalises every bin to 0..1 against its own running peak,
   removing the per-bin dynamic-range problem that made one global threshold floor simultaneously
   starve the hi-hat lane and over-trigger the kick lane.
2. **Snare requires a feature vector, not a better band.** Spectral centroid, spectral flatness and
   temporal decay discriminate a snare from a *coincident* kick. The earlier conclusion that this
   was an information limit was wrong; it was a feature limit.
3. **A Comb Filter Matrix** over `(tau, theta)` yields tempo period and beat phase from one
   structure and maps naturally to a 2D compute dispatch.

This phase delivers that architecture as a reusable system every future audio-reactive project
consumes, and - critically - delivers the scoring harness *first*, so "better" becomes a
measurement instead of an argument.

## Governing Contracts

The acceptance bar is measured behaviour, not the presence of an implementation. Each requirement
below is traced to an enforcing criterion in the Verification Plan.

- `knowledge/audio-reactivity.md`: consumers use `_DataN_Generation` / `_DataN_ValueCount` /
  `_DataN_HopCapacity` for ring catch-up and never element-zero generation; chronological catch-up
  resumes at the oldest retained generation when more than 64 hops behind; adaptive detectors gate
  on signal presence so steady noise cannot accumulate confident false triggers, and counters and
  pulse outputs stay inactive below that gate.
- `knowledge/module-pipeline.md`: every data-producing Module renders a legible preview of its own
  state (`has_preview_srv=true` is explicitly insufficient); viewport events use the declared ABI;
  durable `state_buffers` survive serialization into project, presets and undo; all per-cook rates
  are scaled by `_DeltaTime` because modules cook at a rate decoupled from the display.
- `knowledge/ui-authoring.md`: `tools/module-ui.ps1 validate` passes; rendered and manifest control
  rectangles agree; geometry is `_Resolution`-driven and legible at multiple panel extents.
- `knowledge/performance-proof.md`: health and frame progression are live; the node carries an
  explicit assigned share of the frame budget; cadence is compared as rolling `cook_hz`, never as
  lifetime `frames_processed` between nodes created at different times.

## Measured Facts

Established live on 0.5.49. These are inputs to the design, not open questions.

| Fact | Value | How established |
| --- | --- | --- |
| `Spectrum` bin count | always 1024, independent of `fft_size` | `capture_data_port` |
| `Spectrum` bin width | exactly `sample_rate / fft_size` | 440 Hz tone peaked at bin 37.5 (`fft_size` 4096) and bin 18.8 (`fft_size` 2048) |
| Coverage at `fft_size` 4096 | 11.7 Hz/bin, **0-12 kHz only** | derived and confirmed by the above |
| Coverage at `fft_size` 2048 | 23.4 Hz/bin, full 0-24 kHz | derived and confirmed by the above |
| `Mel Bands` shape | 64 hops x 138 bands, no header record | `get_data_schemas` |
| `Spectrum` shape | 64 hops x 1024 bins, no header record | `get_data_schemas` |
| Hop rate | 187.5 hops/s at `sample_rate` 48000, `hop_size` 256 | generation counter delta |
| Stereo contract | `0.5 * (left + right)` before analysis | `knowledge/audio-reactivity.md` |
| `cryo_pulse` outputs | `control_outputs` only; **no `data_outputs`** | `modules/cryo_pulse/manifest.yaml:108` |
| `force_reload` behaviour | drops data-port links, clears `ref()` drivers, resets params to manifest defaults; video links survive | `docs/lessons.md`, 2026-07-08 |
| `_shared/` bundling | `save_project bundle_modules` does **not** copy `modules/_shared/` | `docs/lessons.md`, 2026-07-05 |
| 2D dispatch precedent | exists: `dispatch: [32, 56, 1]` | `projects/face_collage/modules/face_cutout/manifest.yaml:93` |

Nothing in the port metadata reveals the coverage truncation at `fft_size` 4096. It must be
documented for future consumers.

## Problem Statement

### Before

- A single global `threshold_floor` cannot serve kick and hi-hat simultaneously; the hat lane sits
  below threshold until the floor drops, at which point the kick lane over-triggers.
- Three fixed contiguous Mel lanes cannot isolate a snare from a coincident kick, or a snare body
  from a tom.
- Detector quality is assessed by eye. There is no precision, recall, F-measure, or BPM error.
- Autocorrelation tempo is prone to octave leaps and provides no principled phase estimate.
- Confidence is not honest: the detector reports high certainty on noise.
- Consumers must rebuild their own history ring because the producer retains only 64 hops.

### After

- Per-bin adaptive whitening removes threshold starvation structurally; no per-lane floor is needed.
- Instrument isolation is configured by drawing regions on a live spectrogram, and a multi-feature
  classifier separates instruments that share a band.
- Every change is scored against a frozen corpus with exact ground truth; regressions are visible
  as numbers and are gated.
- Comb Filter Matrix tempo with a log-Gaussian prior and harmonic suppression holds the correct
  metrical level; a dual-loop PLL supplies continuous beat phase, scored with CMLc/AMLc.
- Confidence collapses honestly on a real noise floor and the tracker free-wheels rather than
  hallucinating.

## Scope Fence

This phase does not:

- modify Sentinel application, MCP server, or engine source;
- edit `knowledge/*` contracts seeded from Sentinel core (corrections belong upstream);
- change `modules/cryo_pulse`, which is frozen (see 2A1 for the baseline mechanism);
- fix the outstanding CRYOGRAM defects (unrendered snare noise burst; crucible `Probes`/`Shocks`
  graph-pin shift) - tracked separately in `docs/state.md` by explicit decision;
- implement the research's "Learn Instrument" affordance. Deferred: it requires a trusted live
  input and a capture-and-fit flow that cannot be scored against the synthetic corpus, so it would
  ship unverified. Revisit after 2D proves the feature vector.
- implement HPSS unless 2D fails its snare target;
- introduce neural models, external MIR datasets, or VST-rendered corpora;
- push any repository.

## Deliverables

| ID | Feature | Primary tools/actions | Status |
| --- | --- | --- | --- |
| D1 | Frozen synthetic corpus, annotations, hash manifest | Python, `wave`, seeded RNG | Planned |
| D2 | Automated scoring harness (onset F1, BPM error, CMLc/AMLc) | Python, MCP, File mode | Planned |
| D3 | `pulse2_analyzer` core detector | whitening, SuperFlux, peak-picking compute passes | Planned |
| D4 | Spectral region masks and lateral inhibition | structured buffers, region kernels | Planned |
| D5 | `pulse2_console` click-to-place spectrogram UI | Canvas panel, viewport events, `sui_*` helpers | Planned |
| D6 | Multi-feature instrument classifier | centroid, flatness, decay features | Planned |
| D7 | Comb Filter Matrix tempo and dual-loop beat PLL | 2D dispatch, PLL, honest confidence | Planned |
| D8 | `projects/pulse2` reference project and docs | project save, bundling, README | Planned |
| D9 | Engine-side asks for Audio In, evidence-backed | `docs/engine-asks-audio-in.md` | Planned |

## Sub-Phase 2A1 - Corpus And Onset-Export Contract

**Blocking.** Substrate only: this sub-phase delivers no user-visible feature. Its companion is
2A2, which delivers the executing scorer.

`tools/audio_test/generate_corpus.py` synthesises eleven 48 kHz stereo WAV patterns from a **seeded
RNG**, each with a JSON sidecar of exact per-hit sample positions and lane labels. Voices are
synthesised directly: kick as a pitch-swept sine with a click transient, snare as filtered noise
plus a tonal body, hat as a short high-frequency noise burst.

| Pattern | Targets |
| --- | --- |
| `four_on_floor_128` | baseline; steady tempo reference |
| `breakbeat_170` | syncopation; tempo octave risk |
| `sparse_90` | low onset density; tempo stability |
| `dense_140` | fills; double-trigger pressure |
| `tempo_ramp_120_132` | tracker agility |
| `quiet_intro_drop_128` | adaptive threshold across a loudness jump |
| `syncopated_funk_105` | off-beat accents |
| `halftime_shuffle_88` | **held out**; metrical-level disambiguation |
| `kick_snare_coincident_124` | **held out**; the classifier test |
| `hats_only_150` | HF-only sanity check |
| `hats_under_loud_kick_150` | **the real whitening test**: continuous hats at -30 dBFS under a -6 dBFS kick |

The corpus is generated **once**, committed with a SHA-256 manifest, and frozen. `score_detector.py`
refuses to run if any hash mismatches. The two held-out patterns are not inspected and not tuned
against; they are scored only at sub-phase close.

Because `modules/cryo_pulse` publishes no `data_outputs`, MCP-polled scalar counters cannot supply
per-hit times at 25 ms resolution. This sub-phase therefore creates `modules/cryo_pulse_baseline/`,
a byte-identical copy of `cryo_pulse` with **one** addition: a `Hits` `data_output` ring carrying
`{lane_id, onset_serial, hop_index, sample_position}`. No detection maths changes. The frozen copy
is the baseline; the live `cryo_pulse` is never edited.

The same `Hits` contract is the export format `pulse2_analyzer` implements in 2B, so the scorer is
detector-agnostic.

**Pass criteria**

1. All eleven WAVs and sidecars generate reproducibly: a second run from the same seed produces
   byte-identical files, and the SHA-256 manifest matches.
2. `capture_data_port` on `cryo_pulse_baseline`'s `Hits` port returns records whose
   `sample_position` values, converted to seconds, land within +/-5 ms of the sidecar ground truth
   for `four_on_floor_128`. This is false unless the export contract actually carries usable timing.
3. `cryo_pulse_baseline` scores identically to `cryo_pulse` on lane counts over one full pattern,
   proving the copy is behaviourally frozen.

## Sub-Phase 2A2 - Scorer And Baseline

`tools/audio_test/score_detector.py` drives Audio In File mode, reads `Hits` records, and computes
onset F1 at a +/-25 ms tolerance window plus BPM error, metrical-level correctness, and CMLc/AMLc
beat-tracking continuity metrics.

The timebase is `sample_position` **inside the emitted records**, differenced against the sidecar.
The harness never uses wall-clock timing or MCP poll order, because File mode is *paced* playback
with no documented position or completion field. Completion is detected by `sample_position`
reaching the WAV length; `restart_file` is issued before each run.

Lane naming is not hardcoded: the scorer reads a lane-map (`corpus label -> lane_id`) from a config
file so later user-named regions score without code changes.

Because `force_reload` drops data-port links, clears `ref()` drivers and resets params, the harness
re-adds every link, re-applies every expression, restores non-default params, and asserts
`_Data0_Generation` is advancing before each scoring run.

Score tables are written to `tools/audio_test/scores/<subphase>.json`. Later sub-phases compare via
`score_detector.py --baseline scores/<subphase>.json`, which prints a delta column.

**Pass criteria**

1. `score_detector.py` RUNS end to end and PRINTS a per-lane F1 table, BPM error, and CMLc/AMLc for
   all eleven patterns, writing `scores/2A2.json`.
2. **Scorer self-test bites absolutely.** All four must hold:
   a. Feeding the ground-truth annotations back in as the detection stream scores exactly
      F1 = 1.000 on every lane of every pattern.
   b. Shifting all detections by +20 ms holds F1 = 1.000; shifting by +30 ms collapses it toward 0.
      This brackets the +/-25 ms window empirically.
   c. Shifting by exactly one hop (5.33 ms) changes F1 by less than 0.01, proving the
      hop-to-seconds conversion.
   d. Permuting lane labels drops every lane to approximately 0.
   Only after these does a disabled-lane run mean anything, and that run targets
   `cryo_pulse_baseline`, never `cryo_pulse`.
3. Baseline scores for `cryo_pulse_baseline` are captured to `scores/2A2.json` and committed as the
   number to beat, recording the corpus hash and the `fft_size` in force.
4. The `fft_size` 4096-versus-2048 comparison is run and recorded. This result is **provisional**:
   the 2A detector consumes Mel Bands, while `pulse2_analyzer` consumes Spectrum where the
   0-12 kHz truncation actually bites. The decision is re-confirmed in 2B.

## Sub-Phase 2B - `pulse2_analyzer` Core Detector

Compute passes, deliberately split:

- Pass A - whitening only. `P[n,k] = max(r * P[n-1,k], |X[n,k]|)`, `r ~= 0.992`,
  `Y = |X| / max(P, 1e-4)`, `P` clamped to `[1e-4, 1e4]`. Per-bin recursion over hops is
  thread-local and safe. Writes a completed 64 x 1024 whitened buffer.
- Pass B - SuperFlux. `D[n,k] = max(0, Y[n,k] - max_{m in [-2,2]} Y[n-1,k+m])`, reading only the
  completed buffer from Pass A. **This split is mandatory**: a fused pass would have thread `k`
  read `Y[n-1, k+/-2]` produced by other threads, crossing thread-group boundaries at four seams
  with no available sync, and would be silently wrong there.
- Pass C - peak-picking, single thread, bounded to at most 16 lanes. Moving median over a fixed
  small window with literal-initialised arrays, plus `lambda * mean + alpha`, local-maximum with a
  one-hop (5.33 ms) lookahead, per-lane refractory.

All dynamic-range transforms use `log(1 + gamma * X)`. Ring catch-up uses `_Data0_Generation` /
`_ValueCount` / `_HopCapacity` exclusively. Emits the 2A1 `Hits` contract.

Fixed lanes are retained here so the comparison against the baseline is like-for-like.

**Pass criteria**

1. `pulse2_analyzer` beats `cryo_pulse_baseline` on aggregate onset F1, printed side by side with a
   delta column against `scores/2A2.json`.
2. **Whitening is proven where starvation actually occurs.** On `hats_under_loud_kick_150`, hat
   F1 >= 0.85 with **no per-lane threshold floor configured**, using the *identical constant set*
   applied to all eleven patterns - one config, all patterns, printed. Kick and hat F1 on
   `dense_140` must not drop versus `scores/2A2.json`.
3. **Visible gate.** Focus `pulse2_analyzer` and `open_window`; its preview shows per-lane whitened
   flux, the live adaptive threshold, and accepted-onset marks. Captures during
   `four_on_floor_128` playback and during silence are visibly different, asserted by a vision
   content check. A blank, constant or absent preview fails this criterion.
4. **Cook-rate independence.** Onset counts over a full pattern are identical at unthrottled cook
   rate and at a forced ~20 Hz cook rate, and across an injected stall longer than 341 ms. Rates
   are `_DeltaTime`-scaled.
5. **Budget.** `pulse2_analyzer` `wall_time_ms` averaged over five profile samples is <= 0.6 ms,
   and the graph frame total is unchanged within 0.5 ms versus the analyzer bypassed. Rolling
   `cook_hz` matches the graph rate across two differenced samples.
6. `fft_size` is re-confirmed on Spectrum data and the final choice recorded with numbers.

## Sub-Phase 2C1 - Region Masks And Evaluation

Regions defined **programmatically** (manifest parameters plus a region buffer), with no UI, so this
sub-phase is scorable independently of 2C2. Rectangular and Gaussian profiles. Region rectangles are
stored in **spectrogram coordinates** (hop index, bin index), never panel UV, and one shared
transform converts to panel space - reused later by render, pick and drag.

**Pass criterion**

1. A region placed programmatically over the kick band scores kick F1 at least equal to the 2B
   fixed-lane kick F1 in `scores/2B.json`, printed with a delta column.

## Sub-Phase 2C2 - Spectrogram Console

`modules/pulse2_console` with `panel: { mode: canvas, output: UI, resolution: follow_panel }`.
Display pipeline: logarithmic frequency rebinning, per-bin running-peak equalisation, power-law
compression at `gamma = 0.45`. Region rectangles are durable `state_buffers`.

Palette is the workspace default monochrome scientific-instrument look with one warm accent, per
`CLAUDE.md`, **not** the research's Magma/Inferno. Perceptual contrast is achieved through the
equalisation and gamma stages rather than hue.

**Pass criteria**

1. **The display is audio-driven, not decorative.** Two captures under identical panel state, one
   during `hats_only_150` and one during `four_on_floor_128`. A vision check asserts energy
   concentrated in the upper third for the first and the lower third for the second, and the two
   images differ by a stated diff percentage. A static or synthetic-looking image fails.
2. **A human can DO the placement.** Real click-drag on the panel creates a visible region box at
   the clicked coordinates, asserted by a vision check, and `sentinel_viewport action=info` shows a
   non-zero delivered boundary count.
3. **Regions are durable.** Placed regions survive save, close and reopen byte-identically;
   `sentinel_viewport action=state` reports non-zero captured bytes; undo of a region drag restores
   it.
4. Firing feedback is visible: a region border flashes on detection, `_DeltaTime`-scaled so it is
   perceptible at any cook rate, confirmed in a capture taken during playback.
5. Each region carries a live mini-trace of its flux `O_i[n]` against its threshold `delta_i[n]`,
   so over- and under-triggering are visible without ground truth.
6. `./tools/module-ui.ps1 validate modules/pulse2_console` exits clean, and criterion 1 passes at
   both a 640x360 and a 1600x900 panel extent.

## Sub-Phase 2C3 - Lateral Inhibition

`O^_i = max(0, O_i - sum_{j != i} beta_ji * O_j)` applied before peak-picking.

**Pass criterion**

1. On `kick_snare_coincident_124`, enabling inhibition reduces cross-lane false positives by
   **>= 40%** while per-lane recall drops by less than 0.03, printed as before/after numbers.

## Sub-Phase 2D - Multi-Feature Classifier

Per-region feature vector each hop: whitened flux, spectral centroid, spectral flatness computed as
`exp(mean(log(max(Y, eps)))) / mean(Y)`, and temporal decay ratio. Features are computed in a
parallel pass, not in the single-threaded peak-picker. A weighted decision replaces bare flux
thresholding.

**Pass criteria**

1. Snare F1 on `kick_snare_coincident_124` reaches **>= 0.75 absolute** and rises by **>= 0.15
   absolute** over `scores/2C1.json`, with kick and hat F1 each dropping by no more than 0.02.
2. The console shows the classifier's per-hit verdict (centroid, flatness, decay) at the moment of
   firing, legible in a capture taken during coincident playback.
3. If 2B's aggregate-F1 deficit was carried forward under the Tier 2 clause, it is cleared here.
   This is a hard stop.

## Sub-Phase 2E1 - Comb Filter Matrix And Tempo

Onset history ring of 800 hops (~4.26 s) in its own persistent buffer, separate from a small header
buffer, so any commit copy stays a few elements rather than 800. Comb Filter Matrix over
`(tau, theta)` as a 2D dispatch, allocated rectangular (about 100 lags x 160 phases) with invalid
threads returning early. Log-Gaussian tempo prior peaked at 120 BPM, `sigma = 0.8` octaves;
harmonic suppression `C^(tau) = C(tau) - gamma * (C(tau/2) + C(2 tau))`.

**Step 0 micro-proof, before any of the above.** A throwaway persistent structured buffer where one
pass writes only slot `n % 800`; `capture_data_port` confirms slots `n-1` and `n-2` survive
untouched. This proves partial-write persistence rather than assuming it. If it fails, fall back to
banked commit and record the change. A throwaway 2D-dispatch pass is `compile_check`ed at the same
time; a 1D-flattened `tau * 160 + theta` fallback is retained in reserve.

**Pass criteria**

1. Step 0 micro-proof passes, or the fallback is adopted and recorded.
2. Comb matrix ping-pong parity: a single-step run matches a reference computed offline in Python,
   proving no pass reads partially-updated state.
3. Correct metrical level on **11/11** patterns, explicitly including `halftime_shuffle_88` and
   `breakbeat_170`, which exist to trip octave errors.
4. BPM error below 2 BPM, reported as the median over the steady window excluding lock-in, on all
   steady patterns.

## Sub-Phase 2E2 - Dual-Loop PLL, Confidence, Free-Wheel

Dual-loop PLL, `mu_phase = 0.15`, `mu_tempo = 0.02`, phase wrapped with `frac()`. Confidence as
normalised peak-to-average ratio of the comb output, with a free-wheel hold state below threshold.

**Pass criteria**

1. `tempo_ramp_120_132` is tracked through the ramp without an octave jump.
2. **Honest uncertainty on a real noise floor, not just digital zero.** On a -44 dBFS white-noise
   floor *and* on digital silence: `tempo_conf` decays below 0.1, BPM holds its last trusted value,
   and `kick_count` / `snare_count` / `hihat_count` / `beat_pulse` do not advance. This is the exact
   condition `cryo_pulse` failed when it reported 99% confidence at -44 dBFS.
3. CMLc >= 0.75 on steady patterns and AMLc >= 0.85 corpus-wide.
4. **Soak.** After a 30-minute continuous File-mode run, BPM, phase and counters remain finite, and
   F1 is within 0.02 of the first minute.

## Sub-Phase 2F - Project, Documentation, Portability

`projects/pulse2/` saved with bundled modules, a README documenting the data contract and the
`fft_size` coverage trap, a proof capture, and a stated build requirement. `.gitignore` gains
`!projects/pulse2/`.

`modules/_shared/ui/` is copied manually into `projects/pulse2/modules/_shared/ui/` because
`save_project bundle_modules` does not follow shared include directories.

`docs/engine-asks-audio-in.md` (D9) records the engine-side requests re-prioritised against measured
harness evidence: specifically which corpus patterns magnitude-only analysis provably cannot score.

**Pass criteria**

1. `compile_check` run against the **bundled** directory `projects/pulse2/modules/pulse2_console`
   succeeds, proving standalone compilation including `_shared` includes.
2. The project loads from a clean path with relative `project_dir` values and all nodes healthy.
3. Regions placed before save reload byte-identically after a clean load.
4. `score_detector.py --baseline scores/2E2.json` reproduces the committed table from that clean
   load, within the standing regression tolerance.

## Files Summary

### New

- `docs/phases/phase-2-audio-analysis-v2.md` (this document)
- `docs/engine-asks-audio-in.md`
- `tools/audio_test/generate_corpus.py`, `tools/audio_test/score_detector.py`
- `tools/audio_test/corpus/*.wav`, `*.json`, `corpus.sha256`
- `tools/audio_test/scores/2A2.json`, `2B.json`, `2C1.json`, `2C3.json`, `2D.json`, `2E1.json`, `2E2.json`
- `tools/audio_test/lane_map.json`
- `modules/cryo_pulse_baseline/` (frozen copy plus a `Hits` data output)
- `modules/pulse2_analyzer/`, `modules/pulse2_console/`
- `projects/pulse2/`

### Modified

- `docs/implementation-plan.md`, `docs/state.md`, `.gitignore`

### Unchanged, with reasons

- `modules/cryo_pulse` - frozen; the baseline lives in `cryo_pulse_baseline`.
- `knowledge/audio-reactivity.md` - seeded from Sentinel core; corrections belong upstream.
- `projects/cryogram/` - its two known defects are tracked in `docs/state.md`.

### Reuse rather than rewrite

- `modules/_shared/ui/sui_core.hlsli` and `sui_typography.hlsli`. `sui_v2.hlsli` transitively
  includes `sui_interaction.hlsli`, which requires `_ViewportControlFlags` and only compiles when
  the manifest declares `viewport.controls`.
- `modules/cryo_console/` as the working precedent for canvas + `follow_panel` + events +
  `state_buffers` + control outputs read from a structured buffer.
- `modules/cryo_pulse/tempo.hlsl` as the proven one-thread-per-lag parallel pattern.
- `modules/click_ripples/` as the events reduction reference.

## Implementation Order

1. 2A1 corpus and export contract.
2. 2A2 scorer and committed baseline. Nothing else starts first.
3. 2B core detector.
4. 2C1 region masks and evaluation.
5. 2C2 spectrogram console. **Human checkpoint 1.**
6. 2C3 lateral inhibition.
7. 2D multi-feature classifier.
8. 2E1 comb matrix and tempo.
9. 2E2 PLL, confidence, free-wheel. **Human checkpoint 2.**
10. 2F project assembly and portability proof.

## Verification Plan

| Governing requirement | Enforcing criterion |
| --- | --- |
| Generation uniforms, never element-zero | 2B; source review asserts no element-zero generation read |
| Catch-up resumes when >64 hops behind | 2B.4 injected stall longer than 341 ms |
| Signal gate keeps counters and pulses inactive | 2E2.2 on a -44 dBFS noise floor |
| Legible intermediate preview | 2B.3 vision-asserted, playback versus silence |
| `_DeltaTime` scaling of all per-cook rates | 2B.4 cook-rate independence; 2C2.4 flash perceptible |
| Durable `state_buffers` survive serialization | 2C2.3 and 2F.3 |
| `module-ui.ps1 validate`, multiple extents | 2C2.6 |
| Explicit share of frame budget | 2B.5 numeric budget and bypass comparison |
| Rolling `cook_hz`, not lifetime counters | 2B.5 two differenced samples |
| Beat tracking scored, not eyeballed | 2A2.1 CMLc/AMLc columns; 2E2.3 thresholds |
| Numerical stability over long runs | 2B clamps and `log(1+gamma X)`; 2E2.4 soak |

**Standing regression gate.** No sub-phase may reduce any previously committed per-lane F1 by more
than 0.01. `score_detector.py --baseline` enforces this and exits non-zero on breach.

**Synthetic-corpus blind spots.** The corpus cannot represent live timing drift, natural snare
bleed, or real mix density. Human checkpoint 2 is the only cover for these, and final 2E2 numbers
are additionally confirmed on at least one real music file with hand-annotated hits.

Two traps from the CRYOGRAM session are explicit verification steps:

- Compare cadence as rolling `cook_hz` over a differenced window. Comparing lifetime
  `frames_processed` between nodes created at different times produced a false diagnosis.
- Trigger downstream consumers on accepted-onset **counters**, never on an envelope crossing a
  threshold. An envelope must decay below its threshold before it can re-arm, which silently
  swallows hits at tempo, and lowering the threshold makes it worse rather than better.

## Autonomy And Human-In-The-Loop

### Human-Intervention Points

Batched to two taste checkpoints, placed at seams that actually carry taste.

1. After **2C2**, review the spectrogram console for legibility and interaction feel.
2. After **2E2**, review musical feel against real music. Scores can be good while the result still
   feels wrong; this is a judgement only a person can make, and it is the only cover for the
   synthetic corpus's blind spots.

### Gate Tiers

#### Tier 1 - Self-Serve

- Corpus generation (once), harness execution, score capture.
- Compile checks, health inspection, profiling, data-port reads.
- Authoring inside `modules/pulse2_*`, `modules/cryo_pulse_baseline/`, `projects/pulse2/`,
  `tools/audio_test/`.
- Parameter sweeps and constant tuning driven by scores, **on non-held-out patterns only**.
- Proof captures, devlogs, per-sub-phase local commits.

#### Tier 2 - Conditional-Proceed

- Adopt `fft_size` 4096 if the 2B Spectrum-based comparison shows it at least equal to 2048 on
  aggregate F1; otherwise adopt 2048 and record the reversal against the research recommendation.
- If a literature constant (`r`, `lambda`, `mu_phase`, `alpha_comb`, `gamma`) scores worse than a
  swept alternative, adopt the measured value and record both.
- **2B fallback.** If 2B meets criteria 2 through 6 but loses aggregate F1 to the baseline, record
  the deficit and proceed to 2C1 and 2D, which are the designed fixes. The aggregate criterion is
  re-tested at 2D.3 and becomes a hard stop there.
- If 2D meets its snare target, skip HPSS entirely rather than implementing it speculatively.
- If the 2E1 step-0 micro-proof fails, adopt banked commit and record the change.
- If vision evaluation is unavailable, substitute a deterministic band-energy histogram assertion
  over the captured PNG and note the substitution. Do not downgrade to "a capture exists".
- If a sub-phase fails its pass criterion twice, stop and report. Do not loosen the criterion.

### Pre-Authorizations

- Create `pulse2_*` modules and `cryo_pulse_baseline` with the `Hits` addition only.
- Switch Audio In between Device and File mode during scoring, restoring Device mode and the
  previously selected endpoint afterward.
- Change `fft_size`, `hop_size` and window during comparison, re-measuring any baseline captured
  under a different setting.
- Commit locally per sub-phase using explicit paths.

### Hard Blockers

- Modifying Sentinel application, MCP server, or engine source.
- Editing `knowledge/*` contracts seeded from Sentinel core.
- Any change to `modules/cryo_pulse` (the frozen original).
- **Regenerating or modifying the corpus after 2A1 closes** without an explicit recorded decision;
  every score table records the corpus hash.
- **Tuning against the two held-out patterns.**
- Any network push or Git history rewrite.
- A pass criterion that cannot be met after two attempts.

## Example Agent Workflow

1. Generate the corpus; verify reproducibility and the hash manifest.
2. Create `cryo_pulse_baseline` with the `Hits` output; confirm +/-5 ms timing recovery.
3. Run the four scorer self-tests; only then trust any score.
4. Capture the baseline table to `scores/2A2.json`.
5. Author `pulse2_analyzer`; `compile_check` before create; `compile_status` after.
6. After any `force_reload`: re-add links, re-apply expressions, restore params, assert generation
   advancing. Then score.
7. Compare with `--baseline`; iterate on measured numbers, never on appearance.
8. Profile with five samples; confirm budget and rolling `cook_hz`.
9. Commit the sub-phase; write the devlog; continue.

## Dependencies

1. Sentinel 0.5.49 or newer, with `audio` in `list_types` and per-data-input generation uniforms.
2. Python 3 for corpus generation and scoring.
3. A WASAPI endpoint for live verification; File mode for deterministic scoring.
4. `modules/cryo_pulse` present and unmodified as the source for the frozen baseline copy.
5. Shared UI headers under `modules/_shared/ui/`.
6. `tools/module-ui.ps1` for console validation.

## Plan Audit Findings

Four parallel agents audited this plan before implementation: spec-alignment, acceptance-bar /
proof-altitude, toolchain-feasibility, and sub-phase decomposition.

**Verdict: JUDGEMENT CALLS TO REVIEW.** 24 derived fixes applied, 5 judgement calls applied,
0 open questions, 2 findings considered and rejected on verification.

### Derived fixes applied

1. Resolved a self-contradiction: Hard Blockers forbade changing `cryo_pulse` while the Example
   Agent Workflow instructed disabling one of its lanes.
2. `cryo_pulse` publishes no `data_outputs` (verified at `manifest.yaml:108`), so MCP-polled
   counters cannot supply +/-25 ms timing. Added the `Hits` export contract.
3. Split 2A into 2A1 (corpus and export contract) and 2A2 (scorer and baseline).
4. Split 2C into 2C1 (regions, scorable without UI), 2C2 (console), 2C3 (inhibition).
5. Split 2E into 2E1 (comb matrix and tempo) and 2E2 (PLL, confidence, free-wheel), so the
   ping-pong parity gate is verifiable before later layers obscure it.
6. Added `tools/audio_test/scores/<subphase>.json` persistence and a `--baseline` delta flag;
   comparisons previously named baselines that nothing stored.
7. Added a lane-map config so no lane name is hardcoded.
8. Strengthened the scorer self-test from one relative check to four absolute ones (identity,
   window bracketing, one-hop conversion, label permutation).
9. Added `hats_under_loud_kick_150`; the old whitening gate used an HF-only pattern with no loud
   low-frequency competitor, so it could not fail for the reason it claimed.
10. Added a visible preview criterion to 2B, enforcing `module-pipeline.md`.
11. Quantified 2D from "rises measurably" to absolute and delta thresholds with a no-regression
    clause on other lanes.
12. Raised metrical-level from "at least 90%" (9/10, permitting exactly the two trap patterns to
    fail) to 11/11 naming those patterns.
13. Changed the honesty gate from digital silence to a -44 dBFS noise floor, the condition that
    actually defeated `cryo_pulse`, and extended it to counters and pulses.
14. Added CMLc/AMLc to the harness and to 2E2; beat phase was the headline output and was unscored.
15. Replaced "no hotspot" with a numeric budget plus a bypass comparison.
16. Added `state_buffers` and serialization criteria; regions could previously vanish while the
    project still loaded "healthy".
17. Added precision and stability requirements (`P` clamped to `[1e-4, 1e4]`, `frac()` phase
    wrapping, `log(1+gamma X)`) and a 30-minute soak.
18. Added cook-rate-independence and hitch-resync criteria per the `_DeltaTime` rule.
19. Mandated the two-pass whitening/SuperFlux split; a fused pass would read across thread groups
    at four seams with no sync.
20. Added the 2E1 step-0 micro-proof for partial-write persistence and a 2D-dispatch compile check
    with a 1D-flattened fallback.
21. Added the `_shared/` bundling step to 2F; `bundle_modules` does not copy it.
22. Added post-`force_reload` re-wiring to the harness; reload drops links, clears drivers and
    resets params.
23. Added the 40% quantification to lateral inhibition and the live flux/threshold mini-trace to
    2C2.
24. Added `module-ui.ps1 validate`, dual panel extents, spectrogram-coordinate region storage, a
    standing regression gate, and D9 engine-asks.

### Judgement calls applied - review these

1. **Frozen baseline copy.** Created `modules/cryo_pulse_baseline/` rather than allowing edits to
   `cryo_pulse`. Alternative: relax the Hard Blocker and add `Hits` to `cryo_pulse` directly, which
   is simpler but lets the baseline drift. Revert by deleting the copy and amending the blocker.
2. **Corpus frozen and two patterns held out.** The same agent generates, scores and tunes against
   this corpus, so every numeric gate was otherwise reachable by moving the corpus. Alternative:
   leave regeneration pre-authorized and accept the conflict of interest. Revert by removing the
   hash gate and the held-out designation.
3. **Monochrome palette over the research's Magma/Inferno.** `CLAUDE.md` mandates the monochrome
   scientific-instrument default. Alternative: adopt Inferno for perceptual contrast and take an
   explicit exception. Revert by changing 2C2's palette line.
4. **"Learn Instrument" deferred with a stated reason** rather than dropped silently or included.
   Alternative: include it in 2C2. Revert by moving it out of the Scope Fence.
5. **2B fallback path added.** If 2B loses aggregate F1 but passes everything else, work proceeds to
   2C1/2D with the deficit recorded and re-tested as a hard stop at 2D.3. Alternative: halt at 2B.
   Revert by deleting the Tier 2 fallback clause.

### Considered and rejected on verification

1. The toolchain agent reported no 2D-dispatch precedent in the workspace. Verified false:
   `projects/face_collage/modules/face_cutout/manifest.yaml:93` uses `dispatch: [32, 56, 1]` and
   `thread_group_y: 8` is common. The agent grepped `modules/` and missed `projects/`. A compile
   check is retained as cheap insurance, but the risk is lower than reported.
2. The toolchain agent reported the 512 MiB structured-buffer cap as uncited. It is documented in
   the `sentinel_pipeline compile_check` tool description, which lints it. No plan change needed;
   the related `element_size` versus HLSL struct stride risk is real and is covered by the
   field-offset assertion.
