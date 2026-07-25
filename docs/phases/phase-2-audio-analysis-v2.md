---
type: phase
phase_number: "2"
title: "Audio Analysis v2 (pulse2)"
status: planned
approval: pending
summary: "Build a reusable GPU audio analysis system with a scoring harness first: adaptive-whitened SuperFlux onset detection, click-to-place spectral region isolation, a multi-feature classifier for coincident hits, and comb-filter tempo with a dual-loop beat PLL."
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
3. **A Comb Filter Matrix** over `(τ, θ)` yields tempo period and beat phase from one structure and
   maps naturally to a 2D compute dispatch.

This phase delivers that architecture as a reusable system every future audio-reactive project
consumes, and — critically — delivers the scoring harness *first*, so "better" becomes a
measurement instead of an argument.

## Governing Contracts

The acceptance bar is measured behaviour, not the presence of an implementation.

- `knowledge/audio-reactivity.md`: consumers use `_DataN_Generation` / `_DataN_ValueCount` /
  `_DataN_HopCapacity` for ring catch-up and never element-zero generation; adaptive detectors gate
  on signal presence so steady noise cannot accumulate confident false triggers.
- `knowledge/module-pipeline.md`: every data-producing Module renders a legible preview of its own
  state; viewport events use the declared ABI; durable state survives serialization.
- `knowledge/ui-authoring.md`: authored Canvas panels own placement and painting rather than
  duplicating Properties sliders; rendered and manifest control rectangles agree; the panel remains
  legible at multiple extents.
- `knowledge/performance-proof.md`: health and frame progression are live; the graph profile exposes
  no unexplained hotspot; cadence is compared as rolling `cook_hz`, never as lifetime
  `frames_processed` between nodes created at different times.

## Measured Facts

Established live on 0.5.49 this session. These are inputs to the design, not open questions.

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
- Every change is scored against a synthetic corpus with exact ground truth; regressions are visible
  as numbers.
- Comb Filter Matrix tempo with a log-Gaussian prior and harmonic suppression holds the correct
  metrical level; a dual-loop PLL supplies continuous beat phase.
- Confidence collapses honestly on ambiguous input and the tracker free-wheels rather than
  hallucinating.

## Scope Fence

This phase does not:

- modify Sentinel application, MCP server, or engine source;
- edit `knowledge/*` contracts seeded from Sentinel core (corrections belong upstream);
- change `modules/cryo_pulse`, which is the scoring baseline and must not drift;
- fix the outstanding CRYOGRAM defects (unrendered snare noise burst; crucible `Probes`/`Shocks`
  graph-pin shift) — tracked separately by explicit decision;
- introduce neural models, external MIR datasets, or VST-rendered corpora;
- push any repository.

## Deliverables

| ID | Feature | Primary tools/actions | Status |
| --- | --- | --- | --- |
| D1 | Synthetic corpus generator and annotations | Python, `wave` | Planned |
| D2 | Automated scoring harness (onset F1, BPM error) | Python, `sentinel_state`, `capture_data_port`, File mode | Planned |
| D3 | `pulse2_analyzer` core detector | whitening, SuperFlux, peak-picking compute passes | Planned |
| D4 | Spectral region masks and lateral inhibition | structured buffers, region kernels | Planned |
| D5 | `pulse2_console` click-to-place spectrogram UI | Canvas panel, viewport events, `sui_*` helpers | Planned |
| D6 | Multi-feature instrument classifier | centroid, flatness, decay features | Planned |
| D7 | Comb Filter Matrix tempo and dual-loop beat PLL | 2D dispatch, PLL, honest confidence | Planned |
| D8 | `projects/pulse2` reference project and docs | project save, bundling, README | Planned |

## Sub-Phase 2A - Scoring Harness And Synthetic Corpus

**Blocking. No detector work begins until this passes.** The research places the harness last; that
ordering is deliberately rejected because building the detector first is precisely what failed.

`tools/audio_test/generate_corpus.py` synthesises ten 48 kHz stereo WAV patterns with JSON sidecars
carrying exact per-hit timestamps and lane labels. Voices are synthesised directly: kick as a
pitch-swept sine with a click transient, snare as filtered noise plus a tonal body, hat as a short
high-frequency noise burst. No external instruments required.

| Pattern | Targets |
| --- | --- |
| `four_on_floor_128` | baseline; steady tempo reference |
| `breakbeat_170` | syncopation; tempo octave risk |
| `sparse_90` | low onset density; tempo stability |
| `dense_140` | fills; double-trigger pressure |
| `tempo_ramp_120_132` | tracker agility |
| `quiet_intro_drop_128` | adaptive threshold across a loudness jump |
| `syncopated_funk_105` | off-beat accents |
| `halftime_shuffle_88` | metrical-level disambiguation |
| `kick_snare_coincident_124` | the classifier test: simultaneous kick and snare |
| `hats_only_150` | the whitening test: HF-only, the lane that used to starve |

`tools/audio_test/score_detector.py` drives Audio In File mode deterministically, reads detector
control outputs and data ports, and computes onset F1 with a +/-25 ms tolerance window plus BPM
error and metrical-level correctness.

**Pass criteria**

1. `score_detector.py` RUNS end to end and PRINTS a per-lane F1 table plus BPM error for all ten
   patterns.
2. **Scorer self-test bites:** with one detector lane deliberately disabled, that lane's printed F1
   drops to approximately zero while the others are materially unchanged. A scorer that cannot
   detect a broken detector is not a scorer, and this criterion is false unless scoring is real.
3. The `fft_size` 4096-versus-2048 question is settled by scoring the same detector at both settings
   and printing both tables. The winner is recorded with its numbers.
4. Baseline `cryo_pulse` scores are captured and committed as the number to beat.

## Sub-Phase 2B - `pulse2_analyzer` Core Detector

Compute passes: whitening (`[4,1,1]`, 1024 threads) -> region flux -> peak-picking (`[1,1,1]`).
Tempo remains stubbed until 2E.

- Adaptive whitening: `P[n,k] = max(r * P[n-1,k], |X[n,k]|)` with `r ~= 0.992`; `Y = |X| / max(P, 1e-4)`.
- SuperFlux: `D[n,k] = max(0, Y[n,k] - max_{m in [-2,2]} Y[n-1,k+m])`.
- Peak-picking: moving median + `lambda` * mean + `alpha`, local-maximum condition with a **one-hop
  (5.3 ms) lookahead**, per-lane refractory.
- Ring catch-up strictly via `_Data0_Generation` / `_ValueCount` / `_HopCapacity`.

Fixed lanes are retained at this stage so the comparison against `cryo_pulse` is like-for-like.

**Pass criteria**

1. `pulse2_analyzer` beats `cryo_pulse` on aggregate onset F1, printed side by side by the 2A harness.
2. `hats_only_150` hat F1 >= 0.85 **with no per-lane threshold floor configured**, proving whitening
   removed the starvation structurally rather than hiding it behind a tuned constant.
3. `sentinel_graph profile` shows no hotspot, and the module's rolling `cook_hz` matches the graph
   rate measured across two differenced samples.

## Sub-Phase 2C - Region Masks And Spectrogram Console

`modules/pulse2_console` with `panel: { mode: canvas, output: UI, resolution: follow_panel }`.

Display pipeline: logarithmic frequency rebinning, per-bin running-peak equalisation, power-law
compression at `gamma = 0.45`. Regions support rectangular and Gaussian profiles first; freeform
multi-band is added only if cheap. Each region assigns to a named control output.

Lateral inhibition `O^_i = max(0, O_i - sum_{j != i} beta_ji * O_j)` is applied before peak-picking
so a single full-kit transient cannot fire every lane.

**Pass criteria**

1. A human can **SEE** a live scrolling spectrogram in the panel in which kick, snare and hat energy
   are simultaneously visible. Verified by a vision check asserting three distinct horizontal energy
   bands are present in the captured image, not merely that a capture was taken.
2. A human can **DO** the placement: real click-drag on the panel creates a visible region box that
   persists across cooks, and `sentinel_viewport action=info` shows the delivered gesture with a
   non-zero boundary count.
3. A region placed over the kick band scores kick F1 at least equal to the 2B fixed-lane kick F1 on
   the same corpus.
4. Firing feedback is visible: a region's border flashes when it fires, confirmable in a capture
   taken during playback.
5. With inhibition enabled, `kick_snare_coincident_124` shows fewer cross-lane false positives than
   with it disabled, printed as a number.

## Sub-Phase 2D - Multi-Feature Classifier

Per-region feature vector computed each hop: whitened flux magnitude, spectral centroid, spectral
flatness (Wiener entropy), and temporal decay ratio. A weighted decision replaces bare flux
thresholding. Snare presents high flatness, high centroid and fast decay; kick presents the inverse.

**Pass criterion**

1. Snare F1 on `kick_snare_coincident_124` and `dense_140` rises measurably versus the 2C result,
   printed before and after. This single number decides whether the phase solved the original
   problem that motivated it.

## Sub-Phase 2E - Comb Filter Matrix Tempo And Dual-Loop PLL

Onset history ring of 800 hops (~4.26 s), maintained in a persistent structured buffer with no
per-cook copy of history. Comb Filter Matrix over `(tau, theta)` as a 2D dispatch. Log-Gaussian
tempo prior peaked at 120 BPM with `sigma = 0.8` octaves; harmonic peak suppression
`C^(tau) = C(tau) - gamma * (C(tau/2) + C(2 tau))`. Dual-loop PLL with `mu_phase = 0.15` and
`mu_tempo = 0.02`. Confidence as normalised peak-to-average ratio of the comb output, with a
free-wheel hold state below threshold.

**Pass criteria**

1. Correct metrical level on at least 90% of the corpus; BPM error below 2 BPM on steady patterns.
2. `tempo_ramp_120_132` is tracked through the ramp without an octave jump.
3. On digital silence, `tempo_conf` decays toward zero and the reported BPM **holds** its last
   trusted value rather than wandering. This is the honest-uncertainty gate that `cryo_pulse`
   failed when it reported 99% confidence on a noise floor.
4. Comb matrix ping-pong is verified: a single-step run matches a reference computed offline in
   Python, proving no pass reads partially-updated state.

## Sub-Phase 2F - Project, Documentation, Portability

`projects/pulse2/` saved with bundled modules, a README documenting the data contract and the
`fft_size` coverage trap, a proof capture, and a stated build requirement. `.gitignore` gains
`!projects/pulse2/` because `projects/*` is ignored behind a curated allowlist.

**Pass criteria**

1. The project loads from a clean path with relative `project_dir` values and all nodes healthy.
2. `score_detector.py` reproduces the committed score table from that clean load.

## Files Summary

### New

- `docs/phases/phase-2-audio-analysis-v2.md` (this document)
- `tools/audio_test/generate_corpus.py`, `tools/audio_test/score_detector.py`
- `tools/audio_test/corpus/*.wav` and `*.json` (generated; evaluate whether to commit or regenerate)
- `modules/pulse2_analyzer/`, `modules/pulse2_console/`
- `projects/pulse2/`

### Modified

- `docs/implementation-plan.md` (phase overview table and Phase 2 body section)
- `docs/state.md` (current focus, active sub-phase, decisions pending)
- `.gitignore` (add `!projects/pulse2/`)

### Unchanged, with reasons

- `modules/cryo_pulse` — the scoring baseline; any drift invalidates the comparison.
- `knowledge/audio-reactivity.md` — seeded from Sentinel core; the corrected consumer-loop example
  already landed upstream in 0.5.49 and further corrections belong there.
- `projects/cryogram/` — its two known defects are tracked separately by explicit decision.

### Reuse rather than rewrite

- `modules/_shared/ui/sui_core.hlsli` and `sui_typography.hlsli` for console drawing. Note that
  `sui_v2.hlsli` transitively includes `sui_interaction.hlsli`, which requires
  `_ViewportControlFlags` and only compiles when the manifest declares `viewport.controls`.
- `modules/cryo_pulse/tempo.hlsl` as the proven one-thread-per-lag parallel pattern.
- `modules/click_ripples/` as the reference for the events reduction pattern.

## Implementation Order

1. 2A corpus generator, then scorer, then baseline capture. Nothing else starts first.
2. 2B core detector, scored against the 2A baseline.
3. 2C regions and console, with the first human taste checkpoint after it.
4. 2D classifier.
5. 2E tempo and beat PLL, with the second human taste checkpoint after it.
6. 2F project assembly and portability proof.

## Verification Plan

| Requirement | Proof |
| --- | --- |
| Detector quality is measured | `score_detector.py` prints per-lane F1 and BPM error; self-test proves the scorer responds to a broken lane |
| Whitening removed threshold starvation | `hats_only_150` hat F1 >= 0.85 with no per-lane floor configured |
| Snare problem solved | Snare F1 rise on `kick_snare_coincident_124`, printed before and after 2D |
| Spectrogram is usable | Vision check asserts three distinct energy bands; real click-drag creates a persistent region; `sentinel_viewport` shows delivered gestures |
| Tempo is honest | BPM holds and confidence decays on silence; ramp tracked without octave jump |
| Performance is acceptable | `sentinel_graph profile` shows no hotspot; rolling `cook_hz` compared across two differenced samples |
| Ring consumption is correct | Generation uniforms used exclusively; no element-zero generation read anywhere in the sources |
| Project is portable | Clean-path load with relative `project_dir`, all nodes healthy, score table reproduced |

Two traps from the CRYOGRAM session must not recur and are explicit verification steps:

- Compare cadence as rolling `cook_hz` over a differenced window. Comparing lifetime
  `frames_processed` between nodes created at different times produced a false diagnosis.
- Trigger downstream consumers on accepted-onset **counters**, never on an envelope crossing a
  threshold. An envelope must decay below its threshold before it can re-arm, which silently
  swallows hits at tempo, and lowering the threshold makes it worse rather than better.

## Autonomy And Human-In-The-Loop

### Human-Intervention Points

Batched to two taste checkpoints. Everything else runs without stopping.

1. After **2C**, review the spectrogram console for legibility and interaction feel.
2. After **2E**, review the overall musical feel against real music. Scores can be good while the
   result still feels wrong; this is a judgement only a person can make.

Sub-phase completion reviews, harness runs, and devlogs are self-serve and do not pause work.

### Gate Tiers

#### Tier 1 - Self-Serve

- Corpus generation, harness execution, and score capture.
- Compile checks, health inspection, profiling, data-port reads.
- Authoring files inside `modules/pulse2_*`, `projects/pulse2/`, and `tools/audio_test/`.
- Parameter sweeps and constant tuning driven by scores.
- Proof captures, devlogs, and per-sub-phase local commits.

Record the result, leave `approval: pending`, and continue.

#### Tier 2 - Conditional-Proceed

- Adopt `fft_size` 4096 **if** the 2A comparison shows it at least equal to 2048 on aggregate F1;
  otherwise adopt 2048 and record the reversal against the research recommendation with its numbers.
- If a literature constant (`r`, `lambda`, `mu_phase`, `alpha_comb`, `gamma`) scores worse than a
  swept alternative, adopt the measured value and record both. Literature values are starting
  points, not measurements.
- If 2D reaches its snare target, skip HPSS entirely rather than implementing it speculatively.
- If a sub-phase fails its pass criterion twice, stop and report. Do not loosen the criterion.
- If vision evaluation is unavailable for the 2C check, substitute a deterministic image assertion
  (band-energy histogram over the captured PNG) and note the substitution. Do not downgrade to
  "a capture exists".

### Pre-Authorizations

- Create `pulse2_*` modules, buffers, passes, and control outputs as the sub-phases require.
- Generate, regenerate and overwrite the synthetic corpus.
- Switch Audio In between Device and File mode during scoring, restoring Device mode and the
  previously selected endpoint afterward.
- Change `fft_size`, `hop_size` and window on the Audio In node during 2A comparison.
- Commit locally per sub-phase using explicit paths.

### Hard Blockers

- Modifying Sentinel application, MCP server, or engine source.
- Editing `knowledge/*` contracts seeded from Sentinel core.
- Any change to `modules/cryo_pulse` while it serves as the baseline.
- Any network push or Git history rewrite.
- A pass criterion that cannot be met after two attempts.

## Example Agent Workflow

1. Generate the corpus; verify one WAV plus sidecar by inspection.
2. Point Audio In at a corpus file in File mode; confirm `signal_present` and advancing generations.
3. Run the scorer against `cryo_pulse`; commit the baseline table.
4. Disable one `cryo_pulse` lane; re-run; confirm that lane's F1 collapses. Restore.
5. Author `pulse2_analyzer`; `compile_check` before create; `compile_status` after.
6. Score; compare to baseline; iterate on measured numbers rather than on appearance.
7. Profile with two differenced samples; confirm `cook_hz` and absence of hotspots.
8. Commit the sub-phase; write the devlog; continue.

## Dependencies

1. Sentinel 0.5.49 or newer, with `audio` present in `list_types` and per-data-input generation
   uniforms injected.
2. Python 3 available for corpus generation and scoring.
3. A WASAPI endpoint for live verification; File mode for deterministic scoring.
4. `modules/cryo_pulse` present and unmodified as the baseline.
5. Shared UI headers under `modules/_shared/ui/`.
