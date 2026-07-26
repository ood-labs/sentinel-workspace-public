---
type: devlog
date: 2026-07-26
phase: 2
subphase: 2E1
status: blocked
approval: pending
summary: "2E1 - criteria 1 and 2 pass; criteria 3 and 4 fail after two attempts (metrical level 7/11) and hats_only_150 is proven to carry no tempo information at all"
---

## Step 0 micro-proof (criterion 1): PASS, no fallback needed

Built as a throwaway module (`modules/pulse2_ringproof`) rather than inside the
analyzer, so a wrong assumption could not damage the scored detector.

**Partial-write persistence.** One pass writes only slot `n % 800` per cook.
Over a 91-cook window, **exactly 91 slots changed** and every other slot kept
its own older stamp; slots `n-1`, `n-2`, `n-3`, `n-5` and `n-10` all held the
generation they were written with. Persistent buffers keep what a dispatch does
not touch, so the onset ring needs no banked commit — the 800-element copy per
cook the phase doc held in reserve is not required.

**2D dispatch.** A 13x20 grid of 8x8 groups over a 100x160 domain: 16000 of
16640 threads in domain, 640 guarded out. Every cell recorded coordinates
matching its own index and a correct `tau * NTHETA + theta` flatten — 0 bad
coordinates, 0 bad flattens, 0 unwritten. The 1D fallback mapping is therefore
verified by the same run that verified the 2D one, so switching to it later
would be a change of dispatch shape only.

## Criterion 2 — comb parity: PASS

Compared against an offline float64 reference over a FROZEN ring (File mode goes
Inactive at end of file; `judged` was confirmed pinned at 3743 across 5 s).

| check | result |
| --- | --- |
| `CombMax` across two reads 0.7 s apart | **delta exactly 0** |
| row MEAN vs reference, all 16000 cells | **4.7e-7** |
| winning phase, per period | **0/100 mismatches** |
| row MAX vs reference | 8.1e-5, = **2.2 ulp of `tau`** |

The mean is the strong check: it is sensitive to every one of the 160 cells in a
row, so a partially-written comb row could not hide in it. The max sits on the
largest-magnitude cell and carries the arithmetic's own error.

**The tolerance is measured, not chosen.** Perturbing `tau` by one float32 ulp
in the reference moves the row max by 3.7e-5, so the observed 8.1e-5 is 2.2
ulp-equivalents — what a float32 `pow`/reciprocal chain delivers, amplified by a
lever arm of up to 750 hops. An earlier version of this test used an arbitrary
1e-5 threshold and reported FAIL; the threshold was wrong, not the code.

## A real bug this criterion caught: float32 generation precision

The first parity run diverged by **6.8e-2** with **8 of 100** periods picking a
different phase. That is not float noise, and the cause was not a race.

`ring_at` computed its sample position as `f = (float)newest - back`. Generation
numbers grow without bound at 187.5/s, and float32 has a 24-bit mantissa, so the
ULP of that position crosses:

| generation | runtime | ulp | |
| --- | --- | --- | --- |
| 200 000 | 18 min | 0.016 hops | fine |
| 1 180 236 | 1.75 h | **0.125 hops** | the run that failed |
| 6 750 000 | 10 h | **0.500 hops** | half a hop |

The interpolation fraction quantises with it, so the comb filter's phase
resolution **silently degrades the longer the instrument is left running** —
the worst possible failure shape for a live performance tool, and invisible to
any short test.

Confirmed offline rather than assumed: reproducing both index forms in Python
gives 8.6e-5 divergence at generation 7485 and **2.7e-2 at 1180236**, matching
the live measurement and its generation dependence.

**Fix**: index by integer subtraction on the generation number
(`gHi = newest - ib`) and take the interpolation fraction from `back`, which
stays under 750. The error is now independent of how long the session has run.

This is exactly the class of defect 2E2's 30-minute soak criterion exists to
find, caught one sub-phase early by a parity check.

## Design notes

- **`tau` is spaced geometrically**, not linearly: tempo is ratio-perceived, so a
  linear lag grid would waste resolution on slow tempi and leave the fast end
  coarse. 100 steps over 60..200 BPM is 1.22% per step, and an octave is exactly
  56.99 steps — rounded to 57 for the harmonic lookup, 0.02 of a step off.
- **`theta` is normalised phase**, a fraction of a beat, so column j means the
  same musical position in every row and the matrix is genuinely rectangular.
- **The peak is refined parabolically in log-BPM.** The grid step at 120 BPM is
  1.46 BPM, marginal on its own against a 2 BPM target.
- **Confidence uses the RAW comb output**, not the prior-weighted or
  harmonic-suppressed one: those are assumptions this stage imposed, and letting
  them inflate confidence would report certainty about its own bias.
- **The tempo stage owns `tstate`** rather than writing pstate element 3, so the
  value cannot depend on which pass wrote pstate last.

## Session note

The live graph was lost when another project was loaded over it — the pulse2
graph had never been saved as a project, which is 2F's job. Recovered intact
from an autosave snapshot and immediately saved to
`projects/pulse2_wip.sentinel` as working insurance; 2F still owns the proper
bundled save.

## Criteria 3 and 4 — FAIL after two attempts. Stopped per the Autonomy rules.

Metrical level went **6/11 to 7/11** (`scores/2E1b.json`). The criterion is 11/11,
so 2E1 does not close. Per "if a sub-phase fails its pass criterion twice, stop
and report", work stopped here rather than continuing to loosen or to 2E2.

### Attempt 1 — pulse count fitted to the ring: REVERTED

With `NPULSE = 4` a 60 BPM candidate spans 750 of 800 ring hops and a 200 BPM
candidate only 225, which looks like the fast end being judged on a quarter of
the evidence. Fitting the count to the ring (4..12) made it **worse**:
`breakbeat_170`'s raw peak moved from 112.93 to **67.76** BPM, further from the
true 170.

The reasoning was wrong in a way worth keeping. Every row's score is a MEAN, so
a row averaging 4 samples has three times the variance of one averaging 12, and
argmax over the grid is biased toward whichever rows are noisiest. Making the
count depend on `tau` makes the variance depend on `tau` — a bias with no
musical meaning. A fixed count gives every candidate equal estimator variance,
which is what cross-row comparison actually needs. Reverted, and the reason is
now a comment in `comb.hlsl` so it is not re-attempted.

### Attempt 2 — measured prior and suppression: ADOPTED, still short

Rather than guess again, `dump_onsets.py` captures the REAL onset ring the comb
consumes for each non-held-out pattern, and `diag_tempo_rules.py` replays the
shader arithmetic offline. That made a 200-configuration sweep free instead of
12 s per pattern per idea.

| finding | evidence |
| --- | --- |
| **Harmonic suppression hurts.** Every `gamma > 0` scored worse at every sigma. | Took a correct `dense_140` (140.6) to 111.6 and a correct `sparse_90` (89.6) to 115.7. |
| **The prior at sigma 0.8 is too narrow.** | 0.8 and 1.0 score 6/8; 1.2 scores 7/8. At 0.8 the 0.415-octave penalty on a genuine 90 BPM outweighs `sparse_90`'s evidence. |
| **sigma 1.2 is an interior optimum, not an edge.** | 1.6 collapses `dense_140` and `tempo_ramp_120_132` to 62 BPM. |
| **Phase contrast (`rowmax - rowmean`) adds nothing.** | Identical scores to plain peak height in all 200 configurations. Tested offline, never shipped. |

Adopted under Tier 2 with both values recorded: `tempo_gamma` 0.5 -> **0.0**
(the mechanism stays implemented and exposed), `tempo_sigma` 0.8 -> **1.2**, now
a manifest parameter rather than a hard-coded constant.

Live re-score: `dense_140` 111.8 -> **140.2**, and the regression gate passes with
every per-lane F1 unchanged at +0.000. Onset detection is untouched by all of this.

### Criterion 4 is met wherever the level is right

On the seven patterns that lock to the correct metrical level the BPM error is
**at most 0.3** — far inside the 2 BPM target, which is the parabolic log-BPM
refinement doing its job. Every criterion-4 failure is a criterion-3 failure
wearing a large number: they are level errors, not precision errors.

## Two remaining failures, and they are NOT the same problem

`diag_tempo_stability.py` samples BPM per poll through the real harness instead
of taking one median, which separates "wrong" from "right but unstable" — they
need different fixes, and only one of them is 2E2's job.

| pattern | median | p10..p90 | at ref | at 2/3 | conf |
| --- | --- | --- | --- | --- | --- |
| `four_on_floor_128` | 127.7 | 127.7..127.9 | **100%** | 0% | 0.571 |
| `syncopated_funk_105` | 105.0 | 104.9..140.1 | 76% | 0% | 0.349 |
| `dense_140` | 140.4 | 93.1..140.4 | 67% | 24% | 0.333 |
| `sparse_90` | 124.5 | 89.6..135.1 | 24% | 0% | **0.024** |
| `breakbeat_170` | 113.3 | 113.1..113.4 | 9% | **90%** | 0.353 |

**Confidence tracks correctness monotonically** — 0.571 when perfect, ~0.35 when
mostly right, 0.024 when lost. The confidence measure is honest, which is the
2E2 precondition that matters.

**`sparse_90` is unstable, not wrong.** It reaches the true 90 BPM but will not
hold it, and reports 0.024 confidence while failing. Temporal integration is
the designed fix and it is exactly what 2E2's PLL and free-wheel are for.

**`breakbeat_170` is confidently wrong, and 2E2 will not fix it.** It sits at
2/3 tempo for 90% of frames with a p10..p90 spread of 0.3 BPM. A PLL would lock
onto it harder. The cause is structural, not a tuning miss:

- Its accent skeleton is identical every bar: kick at 16ths 0 and 10, snare at 4
  and 12. Hats occupy **every even 16th**, so any even period at an even phase
  lands on an onset 100% of the time — period 4 (170 BPM) and period 6 (113 BPM,
  a dotted quarter) are both perfect against the hats. Only the kick/snare
  accents can break the tie, and the accent intervals are 4, 6, 2, 4: the run
  4 -> 10 -> 16 is two consecutive 6s, so the dotted-quarter reading is genuinely
  well supported by the audio.
- It is a **3:2 relation, not an octave** — 33 grid steps away, not 57. The
  specified `C(tau/2) + C(2 tau)` suppression cannot address it in principle.
  Extending suppression to the 3:2 relatives was tried offline and fixed nothing.
- **Accent dynamics are not the missing ingredient.** Weighting onsets by true
  amplitude instead of equally makes 170 *worse* (ratio 0.750 vs 0.853), so this
  is not whitening flattening the accent hierarchy.
- It is not hopeless: with ideal ground-truth onsets, 170 wins at NPULSE 4 (1.75
  vs 1.50) and by 1.83x at NPULSE 8. The information survives in a clean onset
  train and is lost in the flux envelope — which points at feeding the comb the
  PICKED onsets rather than raw summed flux, a design change, not a constant.

## `hats_only_150` cannot be solved by any algorithm

Proven from the audio, not argued: the file is **100 byte-identical hats at
exactly 9600-sample spacing** (`max |seg_k - seg_10| = 0` over all 99 later
hats; per-hat peak and RMS spread both 0%). The signal is exactly periodic at
0.2 s, so 60, 75, 100, 150 and 300 BPM explain it *identically*. The reference
150 is a fact about the generator's intent that is not present in the waveform,
and the pattern's own metadata calls it an "HF-only sanity check" — it was
authored to test the hat lane with no kick or snare, not to test tempo.

Criterion 3 as written ("11/11") therefore cannot be met by any tempo algorithm.
This is a corpus/criterion conflict, and resolving it is a human decision:
regenerating the corpus is a Hard Blocker without an explicit recorded decision,
and so is loosening a pass criterion.

## Attempt 3 (authorized) — picked onsets. breakbeat_170 FIXED

Three decisions were taken at the block, and all three are recorded here:
criterion 3 is recast as **10/10 excluding `hats_only_150`**; the comb may be
fed picked onsets as an authorized third attempt; `sparse_90` carries into 2E2.

The comb now correlates against the picker's accepted onsets rather than the
summed flux envelope. `scores/2E1f.json`:

| pattern | 2E1 (flux) | now | |
| --- | --- | --- | --- |
| **`breakbeat_170`** | 113.3 | **170.4** | err 0.4, **ok** |
| `dense_140` | 111.8 | 140.3 | ok |
| `four_on_floor_128` | 127.7 | 127.6 | ok |
| `hats_under_loud_kick_150` | 150.0 | 149.7 | ok |
| `kick_snare_coincident_124` | 124.2 | 124.1 | ok (held-out) |
| `quiet_intro_drop_128` | 127.7 | 127.7 | ok |
| `syncopated_funk_105` | 105.0 | 105.0 | ok |
| `tempo_ramp_120_132` | 128.3 | 127.8 | ok |
| `sparse_90` | 111.9 | 135.9 | off — **carried to 2E2** |
| `halftime_shuffle_88` | 105.2 | 153.9 | off — held-out |
| `hats_only_150` | 100.1 | 100.0 | excluded by decision |

Metrical level 6/11 -> **8/11**. Per-lane onset F1 unchanged at +0.000 across
the whole corpus: this changes only what the comb reads, never what the picker
decides.

**Criterion 4 is met on every pattern that locks.** Maximum BPM error across all
eight correct-level patterns is **0.4**, against a 2 BPM target.

### Three defects found by measuring rather than reasoning

- **The hits ring is keyed by `hop_index`, which is not the generation the onset
  ring is indexed by.** They sit a constant 3 apart, which rejected every
  deposit and left the ring empty — surfacing not as an error but as a comb
  pinned to `BPM_MIN`. The generation now rides in a spare field of the hit
  record, so the 4-field 2A1 export contract is untouched.
- **Depositing detection strength re-imports the amplitude hierarchy the comb
  does not want.** Weighting an ideal onset train by true amplitude moves
  breakbeat_170's 170-vs-113 ratio from 0.853 to 0.750 — away from the right
  answer. Each accepted onset now counts 1.0, which is what the offline study
  actually measured (the Hits export declares no strength field).
- **A width chosen from hits arrays did not survive contact with the live ring.**
  The offline study called half-width 1 an interior optimum at 8/8; on the live
  ring breakbeat_170 resolves 170.75 unwidened and collapses to 85.37 widened.
  Smearing is now a swept parameter (`onset_smear`), shipped at 0. The lesson is
  that a single 4.27 s window is too noisy to choose a constant on — the live
  scored median disagreed with it on `syncopated_funk_105` too.

### Criterion 3 still not met: `halftime_shuffle_88`

The remaining failure is the other named octave trap, at 153.9 against a
reference 88. It is **held-out**, so it may only be improved by a generic change
validated on permitted patterns, never tuned against.

One principled candidate was tested and rejected: the smear kernel is a fixed
number of hops, so it is 1.5% of a beat at 170 BPM but 0.8% at 88, which is
inconsistent with the ratio-based reasoning that makes the tau grid geometric.
A kernel held constant as a fraction of the beat is the consistent form, and it
changes **nothing** — 6/8 at every width from 0 to 5% of a beat on the live
rings. With no measured benefit on permitted data there is no honest case for
shipping it, and adopting it because it happened to move a held-out pattern
would be exactly the tuning the rails forbid.

Stopped rather than making an unauthorized fourth attempt.

## Next

All three original questions were decided and acted on. One failure remains
against the recast criterion 3 (10/10 excluding `hats_only_150`, with
`sparse_90` carried to 2E2): **`halftime_shuffle_88` at 153.9 against 88**, so
the required set stands at 8 of 9.

It is held-out, which constrains what may honestly be done about it:

1. Proceed to 2E2 and re-test it there. Its sibling failure `sparse_90` is
   already carried on the grounds that per-frame argmax cannot be stable on
   sparse evidence, and a shuffle's triplet grid is the same class of problem —
   a PLL with free-wheel is the designed fix for both. This is the recommended
   path, and it matches the 2C3 -> 2D precedent.
2. Or authorize a fourth 2E1 attempt aimed at it specifically. This is worth
   naming as the risky option: the only remaining lever is a design change
   judged against a pattern that exists to be the evaluation, and the one
   principled generic idea available has already been measured at zero effect.
