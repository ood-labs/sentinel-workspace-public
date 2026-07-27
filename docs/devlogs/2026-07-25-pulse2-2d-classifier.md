---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2D
status: complete
approval: pending
summary: "2D - classifier works (snare 0.523 -> 0.782, agg 0.873); criterion 1's +0.15 clause missed at +0.098, accepted by recorded human decision; two harness measurement bugs fixed"
---

## Outcome

The multi-feature classifier works and is a large, verified improvement.
**Criterion 1 is still not met**: it asks for a +0.15 rise in snare F1 on the
held-out `kick_snare_coincident_124`, and two independent models reached +0.086
and +0.068. Reported as a miss, not reinterpreted.

Criterion 3 (the Tier 2 hard stop) is **met**. Criterion 2 (console verdict
display) is not yet built.

| measure | 2C1 | 2D shipped |
| --- | --- | --- |
| snare, tuning mean | 0.531 | **0.769** |
| snare false positives (tuning) | 284 | **76** (-73%) |
| aggregate | 0.797 | **0.863** |
| kick / hat | 0.910 / 0.952 | **unchanged, +0.000** |
| held-out `halftime_shuffle_88` | 0.333 | **0.700** (+0.367) |
| held-out `kick_snare_coincident_124` | 0.690 | **0.776** (+0.086) |
| node wall time | ~0.6 ms | **0.486 ms** |

Every per-lane delta across all 11 patterns is >= 0. Regression gate PASS.

## Criterion 1, clause by clause

Measured under the FIXED harness with both sides re-run, so this is not a
fixed-harness detector against a truncated-harness baseline
(`scores/2D_h2.json` against `scores/2C1_h2.json`):

| clause | required | measured | |
| --- | --- | --- | --- |
| snare F1 absolute | >= 0.75 | **0.776** | PASS |
| rise over 2C1 | >= +0.15 | **+0.098** (0.678 -> 0.776) | **FAIL** |
| kick F1 drop | <= 0.02 | +0.000 (0.976 -> 0.976) | PASS |
| hat F1 drop | <= 0.02 | +0.000 (0.988 -> 0.988) | PASS |

The harness repair moved the rise from +0.086 to +0.098 and left the absolute
at 0.776 unchanged to three decimals. The shortfall is real, not a measurement
artefact — which is the thing that had to be established before accepting it.

The kick/hat clause holds **structurally**, not by tuning: mode 1 gates lane 1
only, so the other lanes are untouched by construction.

## Why the remaining gap is a RECALL problem

On the held-out pattern the classifier reaches **precision 1.000 with zero false
positives**; recall 0.634 (26 of 41) is the entire limit. With perfect precision
F1 = 2R/(1+R), so 0.840 needs only four more true snares kept.

The same over-rejection is visible on the tuning set -- `four_on_floor_128`
P 1.000 / R 0.667, `breakbeat_170` P 1.000 / R 0.643 -- so this is diagnosable
without touching held-out data.

Attempt 2 targeted exactly that and made the criterion WORSE (below).

## Approach: measure first, then design

2C3 failed three times by designing from a plausible story and measuring after.
2D inverted that. `diag_features.py` collects the feature vector at every snare
firing on the eight non-held-out patterns and labels each against ground truth;
`fit_classifier.py` fits a logistic model to that sample.

Separability, 115 true / 234 false firings:

| feature | AUC | best single split |
| --- | --- | --- |
| cent | 0.861 | keeps 67/115 true, admits 6/234 false |
| flatness | 0.844 | 93/115, 35/234 |
| centD (over arriving energy) | 0.843 | 76/115, **4/234** |
| energy | 0.828 | 69/115, 23/234 |
| decay | 0.584 | weak |
| flatD | 0.468 | useless |

## Attempt 1 - cent + flatness (SHIPPED)

Both weights positive, which is the physically expected sign: a snare is a noise
burst, so it sits higher in its band and is flatter than the kick tail it
competes with. Held-out coincident **0.776**.

## Attempt 2 - flatness + decay + centD (REJECTED)

Best in-sample model by the scorer's own metric (mean per-pattern F1 0.841,
recall 0.861 against attempt 1's 0.804). It made the criterion worse:

| | attempt 1 | attempt 2 |
| --- | --- | --- |
| held-out coincident | **0.776** | 0.758 |
| snare mean | 0.765 | 0.781 |
| aggregate | 0.863 | 0.868 |
| `four_on_floor_128` | 0.800 | **0.600** |
| `quiet_intro_drop_128` | 0.811 | **0.667** |

Better on average, worse exactly on the kick-coincident patterns the criterion
is measured on. Leave-one-pattern-out cross-validation had warned: in-sample
0.864 against LOPO 0.747, a 0.117 overfit gap, versus 0.002 for the simpler
model. Its negative `decay` weight was a correlation artefact, the same failure
mode as the earlier negative `flatness` weight. **Without LOPO I would have
shipped the worse model believing it was better.**

## Four errors of mine, all caught by measurement

1. **`centroid` is a reserved HLSL interpolation modifier.** Compile error;
   renamed to `cent`.
2. **The raw decay ratio `E[n]/E[n-2]` reached 1.2e6** on near-silent hops,
   swamping any weighted sum and destroying its own rank statistic. Replaced
   with the bounded `E[n]/(E[n]+E[n-2])`.
3. **The first logistic fit was unstandardised**, diverged to weights of +96 and
   -164 with an `exp()` overflow, and scored WORSE (0.661) than a single
   hand-thresholded feature (0.726). A broken fit that looked like a weak
   feature set.
4. **`SP.d` is not per-bin SuperFlux.** The buffer comment says it is, but
   nothing writes it: `flux.hlsl` reduces the difference straight into the lane
   buffer, and `.d` on bins 0..2 carries the producer header. Reading it gave
   two dead features at AUC 0.362 -- a wrong assumption that measured as a flat
   line rather than raising an error. SuperFlux is now recomputed inline with
   the same 5-tap max filter.

## Performance: a regression found and fixed

Adding the flux moments took the node from ~0.6 ms to **1.39 ms**, breaking the
budget 2B criterion 5 had met. Two changes restored it to **0.486 ms**
(five samples: 0.520 0.465 0.503 0.492 0.450):

- the flux sweep is skipped unless `w_centD`/`w_flatD` are non-zero, so the
  shipped model pays nothing for features it does not use;
- the decay feature READS the earlier hop's energy from the persistent `fstate`
  buffer instead of recomputing a second full region sweep, guarded by the
  `.gen` stamp so it cannot compare against an unrelated hop a ring-lap away.

## Verification after the performance fixes

The decay feature's computation changed (read rather than recompute), so the
whole corpus was re-scored rather than assumed unaffected. It reproduces attempt
1 exactly on 10 of 11 patterns, including both held-out numbers: coincident
0.776, halftime 0.700.

`tempo_ramp_120_132` moved: kick 0.976 -> 0.988, snare 0.800 -> 0.833, hat
0.982 -> 0.988. **The classifier cannot touch the kick lane in mode 1**, so a
kick change is by construction not attributable to this edit -- it is
harness run-to-run variance, most visible on the one pattern whose tempo is
changing under the analysis. Worth knowing that the scorer is not perfectly
deterministic on that pattern: earlier 2C1 re-runs reproduced at +0.000
everywhere, so the variance is small but real, and a future +/-0.01 result on
`tempo_ramp` should not be read as a code effect.

## On the criterion itself

Stated as an observation, not a request to move the bar. The +0.15 clause was
written against an assumed starting point, and 2C1's snare on this pattern
(0.690) already sits far above its own corpus-wide snare mean (0.531). The
clause therefore demands 0.840 on the single pattern where kick/snare confusion
is hardest by construction, while the same detector gains +0.367 on the other
held-out pattern and +0.34 or more on four tuning patterns. Whether the target
or the approach should move is a human decision.

## Criterion 2 - console verdict display: MET

Two surfaces, both live in `pulse2_console`:

- a **readout card** naming the classified lane and showing centroid, flatness,
  decay, the score, and ACCEPT/REJECT;
- a **verdict strip** along the top of that lane's band, one tick per decision
  on the same time axis as the spectrogram: white kept, accent suppressed.

Proof: `captures/2D_verdict/console_coincident_02.png`, taken during
`kick_snare_coincident_124` playback. Card reads CENT 0.48 / FLAT 0.93 /
DECAY 0.84 / SCORE 0.92 / ACCEPT, with both tick colours visible in the strip.
`console_coincident_01.png` is the REJECT case, SCORE -3.21.

### Three things the design had to get right

**Rejections are traced, not just firings.** `pick.hlsl` now encodes a
classifier-vetoed candidate as `f2 = -1`. Without it a classifier doing nothing
and one rejecting everything look identical on screen. `-1` rather than `2` so
every existing `f2 > 0.5` reader (the firing flash, `diag_features.py`) keeps
meaning exactly "fired".

**The card holds its last verdict, and shows its age.** A snare arrives every
~0.5 s, so a still capture grabbed between two would otherwise be blank and
prove nothing. A held card with no elapsed time is indistinguishable from a
frozen one, so the seconds since the latch are displayed beside it.

**The score is the picker's own number.** It rides the trace rather than being
recomputed in the shader, so the card cannot disagree with the detector it
exists to explain. Verified: over 60 events, `|recomputed - traced|` peaks at
**2e-6**. ACCEPT/REJECT is exactly the sign of the displayed score, so the two
fields check each other.

### What the strip is actually showing, against ground truth

Read back from the live Trace port during coincident playback and labelled
against the corpus sidecar:

| | count | real snares | on a kick |
| --- | --- | --- | --- |
| accepted (white) | 21 | **21** | - |
| rejected (accent) | 39 | 10 | **26** |

Precision 1.000 on the accepted set, matching the corpus table independently.
Two thirds of the rejections sit on a kick -- the kick-decay false positives the
classifier was built for -- and the 10 real snares among them are the recall
loss criterion 1 measures. The display is showing the real decision, not a
plausible-looking one.

### Scope note

The strip and the flux mini-trace cover the newest 256 hops (1.37 s), the depth
of the analyzer's trace ring, while the display holds 768 hops (4.1 s). The
older two thirds carry no ticks. Pre-existing, inherited from 2C2, and left
alone: deepening the ring is analyzer surgery with scoring consequences.
`console_coincident_02.png` sets `hist_hops` to 256 so the two windows match.

## Two harness measurement bugs, found while re-scoring

Both were found the same way: a number moved that the code change could not
have moved. Neither is a detector defect, and both had been silently corrupting
every table in this phase.

### 1. End-of-file truncation

Re-scoring after the `pick.hlsl` edit showed 10 of 11 patterns reproducing
exactly and `tempo_ramp_120_132` moving by up to 0.033 — three times the
standing 0.01 regression tolerance. The edit is write-only telemetry, and the
KICK lane moved, which `classify_mode = 1` cannot touch by construction, so the
cause had to be elsewhere. It was the harness.

`run_pattern` broke out of its poll loop the first time the playback head landed
within `EOF_SLACK_SAMPLES` (32768, 0.68 s) of the end. The poll cadence is 1 s,
so the break point fell anywhere in the last second of audio and **every onset
after it was simply never analysed**. Confirmed, not inferred: two runs recorded
`final_sample_position` 954368 and 941056 — 13312 samples apart, 0.28 s, more
than half a beat at 126 BPM — and differed by exactly one beat's worth of hits,
one kick, one snare, one hat, with zero change in false positives.

It lands hardest on `tempo_ramp_120_132` because that is the pattern whose
onsets get densest at the end.

**Fix**: wait for the playback head to actually STOP rather than merely get
close. File mode goes Inactive at end of file, so the head freezes and the
existing stall path fires; two stalled polls after entering the EOF window let
the remaining audio play out and the analyser drain. Verified deterministic:
141 records on both of two runs, against 135 and 138 before.

### 2. Whitening state inherited from the previous pattern

With truncation fixed, `sparse_90` still moved — on the HAT lane, which
`classify_mode = 1` cannot touch. Repeat runs exposed the shape of it: the run
that followed `syncopated_funk_105` scored 0.636 / 0.636 / 0.933, and two
consecutive runs that followed *itself* both scored 0.609 / 0.667 / 0.903.
Deterministic given the same predecessor, different across predecessors.

`reset_detector` calls `force_reload`, which does not clear `persistent: true`
buffers. The per-bin whitening running peaks therefore arrive carrying the
previous pattern's spectrum, and whitening is exactly the stage that decides
what counts as an onset.

**Fix**: play each pattern once as a throwaway pre-roll before the scored run,
so the peaks adapt to its own content. `whiten_decay` 0.992 at 187.5 hops/s is
a 0.67 s time constant, so `PREROLL_S = 2.0` is three of them.

Verified on the case that exposed it — prime with `syncopated_funk_105`, then
run `sparse_90` three times: **0.636 / 0.667 / 0.966 on all three**, first run
included.

Note the hat lane came out at 0.966, above BOTH earlier values. This was never
just jitter: a foreign whitening state was actively degrading the score, so
every table in this phase has been reading low by an unknown per-pattern amount
wherever the corpus order put an ill-matched predecessor.

### Why this was worth stopping for

2E1 asserts BPM error under 2 BPM and 11/11 metrical levels; 2E2 asserts F1
within 0.02 after a 30-minute soak. None of those are measurable against a
~0.03 noise floor arriving from poll phase and corpus ordering. 2A2's whole
premise was making "better" a measurement rather than an argument, and the
measurement had two holes in it.

### Restated under the fixed harness

Both configurations re-run end to end. `classify_mode=0` IS the 2C1 detector,
so this isolates the classifier with everything else held identical:

| corpus mean | 2C1 (`classify_mode=0`) | 2D shipped | delta |
| --- | --- | --- | --- |
| snare | 0.523 | **0.782** | **+0.259** |
| aggregate | 0.802 | **0.873** | +0.071 |
| kick | 0.913 | 0.913 | +0.000 |
| hat | 0.969 | 0.969 | +0.000 |

Kick and hat are identical to three decimals across every pattern, which is the
expected result: mode 1 gates lane 1 only, so the other lanes are untouched by
construction rather than by tuning.

The repaired harness also raised the shipped detector's own numbers, because
both defects were suppressing real detections:

| | old harness | fixed harness |
| --- | --- | --- |
| snare mean | 0.769 | **0.782** |
| hat mean | 0.960 | **0.969** |
| aggregate | 0.865 | **0.873** |
| `sparse_90` hat | 0.933 | **0.966** |
| `tempo_ramp` snare | 0.833 | **0.865** |
| `four_on_floor` snare | 0.800 | **0.833** |

Earlier committed tables (2A2, 2B, 2C1, 2D) were measured under the broken
harness. They remain valid *relative to each other* — every comparison in those
devlogs was like-for-like — but they read LOW, and `scores/2D_h2.json` is the
reference 2E is measured against.

## Still open

- **`hats_under_loud_kick_150` keeps all 48 false positives.** The classifier
  does nothing on the loudest kick. Unexplained; it is the one pattern where the
  approach shows no effect at all.

## Files

- `modules/pulse2_analyzer/features.hlsl` — parallel feature pass
- `modules/pulse2_analyzer/pick.hlsl` — weighted decision, gates acceptance only
  and deliberately not the refractory
- `modules/pulse2_analyzer/manifest.yaml` — `Features` data port, 8 classifier params
- `tools/audio_test/diag_features.py` — labelled separability study
- `tools/audio_test/fit_classifier.py` — logistic fit, standardised
- `tools/audio_test/scores/2D.json`, `2D_v2.json` — both attempts

## Outcome

| criterion | verdict |
| --- | --- |
| 1 — held-out snare, absolute + rise + no lane regression | **3 of 4 clauses PASS**, the +0.15 rise clause misses at +0.098 |
| 2 — console per-hit verdict, legible in a capture | **MET** |
| 3 — 2B aggregate deficit cleared (hard stop) | **MET**, 0.873 against the 2A2 baseline 0.7063 |

Criterion 1's miss was reported, not reinterpreted, and the target was not
loosened. Closing 2D with it outstanding is a recorded human decision ("accept
2D, build criterion 2, move on"), taken after two independent models reached
+0.086 and +0.068 and after the measurement itself was rebuilt and re-run.

## Next

2E1 — comb filter matrix and tempo, beginning with the mandated step-0
persistence micro-proof.
