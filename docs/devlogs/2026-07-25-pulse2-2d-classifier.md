---
type: devlog
date: 2026-07-25
phase: 2
subphase: 2D
status: blocked
approval: pending
summary: "2D - classifier works (snare 0.531 -> 0.769, agg 0.863); criterion 1's +0.15 clause missed at +0.086"
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

| clause | required | measured | |
| --- | --- | --- | --- |
| snare F1 absolute | >= 0.75 | **0.776** | PASS |
| rise over 2C1 | >= +0.15 | **+0.086** | **FAIL** |
| kick F1 drop | <= 0.02 | +0.000 | PASS |
| hat F1 drop | <= 0.02 | +0.000 | PASS |

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

## Still open

- **Criterion 2** -- the console does not yet render the per-hit verdict
  (centroid, flatness, decay) at the moment of firing. The data is already
  exported: the trace ring carries the three features plus the verdict score in
  its spare fields, and a `Features` data port exposes the full vector.
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

## Next

Human decision on criterion 1. Criterion 2's console verdict display is
independent and can proceed either way.
