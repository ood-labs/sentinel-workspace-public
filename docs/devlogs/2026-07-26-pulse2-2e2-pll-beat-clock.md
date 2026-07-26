---
type: devlog
date: 2026-07-26
phase: 2
subphase: 2E2
status: complete
approval: pending
summary: "PLL beat clock: structural fixes plus tempo outlier rejection; criteria 1/2/4 pass, criterion 3 (CMLc/AMLc) improves but still fails"
---

## Done

Built the dual-loop PLL (`pll.hlsl`) that turns the comb's per-frame tempo
estimate into a running beat clock, and fixed five defects found by measuring
the emitted beat train rather than the reported numbers.

**Criterion 1 — tempo_ramp without an octave jump: PASS.**
`tempo_ramp_120_132` tracks to 127.8 BPM, err 1.8, metrical level `ok`.

**Criterion 2 — honest under noise and silence: PASS.**
`test_noise_honesty.py`, both halves. After locking on real music at 127.60 BPM
/ conf 0.614: `tempo_conf` max 0.0000 over 8 s, BPM spread exactly 0.0000 with
offset 0.0619, and no counter advanced — including `beat_count`, so the beat
clock manufactures nothing from a −44 dBFS floor.

**Criterion 3 — CMLc ≥ 0.75 steady / AMLc ≥ 0.85 corpus-wide: FAIL.** See below.

**Criterion 4 — 30-minute soak: PASS as specified; a stronger check added
afterwards FAILS.** The criterion as written (BPM, phase and counters finite,
F1 within 0.02 of the first minute) passed on the full 30-minute run recorded
below. A post-audit hardening pass then added liveness and consistency
assertions to the same test, and one of them fails — see Issues. The original
clauses still pass; the new one describes a defect the criterion never asked
about.

```
    t+  5.0 min  laps   14  bpm 127.74  conf 0.372  beats 3646  issues 0
    t+ 10.0 min  laps   28  bpm 127.77  conf 0.379  beats 4245  issues 0
    t+ 15.0 min  laps   42  bpm 127.55  conf 0.608  beats 4844  issues 0
    t+ 20.0 min  laps   57  bpm 127.73  conf 0.472  beats 5441  issues 0
    t+ 25.0 min  laps   71  bpm 127.74  conf 0.372  beats 6040  issues 0
    t+ 30.0 min  laps   85  bpm 127.58  conf 0.574  beats 6633  issues 0
    soak done: 85 laps, 0 issues
```

85 laps of the frozen corpus file, zero issues. BPM stayed
within 127.55–127.77 for the whole run, `pll_phase` / `pll_period` stayed in
range and finite, every counter climbed monotonically, and F1 at minute 30 was
identical to minute 1 on all three lanes (kick 0.976, snare 0.833, hat 0.982,
all +0.000 against a ±0.02 tolerance). The file is restarted each lap rather than
looped seamlessly — there is no loop parameter — so each of the 85 laps also
exercised a restart discontinuity.

**Onset F1 held exactly.** Every lane in `scores/2E2.json` is +0.000 against
`scores/2E1f.json`; regression gate PASS.

### The five fixes

1. **Harness restart-cut (`sentinel_ipc.py`).** The cut that drops pre-restart
   records finds the restart by looking for a backwards step in sample position,
   which only exists in detection order — and I had started sorting by sample
   position first to merge the beat ring's independent serial sequence. That
   made the cut a silent no-op and left stale records as false positives. It
   presented as a 12-lane regression-gate failure with drops of 0.011–0.022 from
   a harness change with no detector change behind it, and I initially suspected
   the `signal_floor` raise. Cutting per lane, in serial order, then merging
   restored every lane to +0.000. **`signal_floor` 0.012 was innocent.**

2. **The phase correction crossed the wrap.** Beats are emitted when the
   accumulator crosses 1.0 inside the hop loop; a correction applied outside it
   that carried phase over either end added or removed a beat without going
   through that path. Measured: 10.3% of four_on_floor's intervals at 2× the
   period and 5.1% at one to four HOPS. Clamping instead of wrapping took
   spacing rejections to zero.

3. **The loop gains were per-cook, not per-beat.** A cook covers ~3 hops and a
   beat ~85, so `mu_phase` 0.15 was a loop gain near 3.0 per beat — overdamped
   to the point that the accumulator parked on the observation and resisted
   advancing. dense_140 completed 28 phase cycles where its (correct) period
   implied 46, with not one beat suppressed by either gate. This was also a
   frame-rate dependency: the loop tracked differently at 60 fps than at 30.

4. **Circular smoothing was applied to the wrong quantity.** `phaseObs` is
   measured backwards from the newest hop, so a stationary beat grid still makes
   it sweep a full turn — it rotates by construction and its circular mean is
   uniform. Vector strength sat at 0.15 on *every* pattern, steady and dense
   alike. Smoothing the phase *error* instead took coherence to 0.997 on steady
   patterns.

5. **`tempo.hlsl` published a period inconsistent with its own BPM.** `o.a` is
   held at the last value that cleared `lock_conf` while the period came from the
   current argmax, so the two described different tempi — a reported 127.6 BPM
   alongside a published 93.7-hop period, which is 120.1 BPM. The phase loop
   spent whole patterns pushing against that gap.

**Constant changed from the phase doc (Tier 2).** The doc specifies
`mu_tempo = 0.02`; shipped at **0.2**. Fix 3 changed the gains' units — they are
now fractions of the error corrected per *beat* rather than per *cook*, so 0.02
would mean fifty beats to re-acquire a tempo, which is longer than most patterns
in the corpus. `mu_phase` stays at the specified 0.15. Both are exposed and
documented in the manifest.

Also tried and **rejected on measurement**: integrating phase error into the
period (a PI loop). With an observation whose phase scatters by a quarter beat
the integral is a noise amplifier — dense_140's continuity fell 0.32 → 0.10. The
parameter was removed rather than left at zero.

## Post-landing audit + fixes

Three parallel agents audited the landed work (code correctness, spec alignment,
test coverage). No ship-blocking defect. Fixes applied:

- **`_continuity` normalised by `len(est)`** (`tools/audio_test/metrics.py`).
  Three beats against a hundred reference beats scored a perfect 1.0. Now
  `max(len(ref), len(est))`, matching mir_eval. This moved every continuity
  number in `scores/2E2.json` **down**; lane F1 is untouched.
- **Loop gains were scaled by the wrong span** (`pll.hlsl`). `advanced` used
  `judged - start` while the accumulator advances `start - limit`; with a snap
  window open that inflated both gains by roughly an order of magnitude per
  cook. Identical at the shipped `beat_snap = 0`, so no default behaviour
  changed. Retesting the snap with it fixed helped one pattern (dense_140
  0.43 → 0.55) and left the rest worse, so the snap stays disabled — but its
  most likely mechanical cause is now ruled out.
- **Cold-start guard was dead code** (`pll.hlsl`). `clamp(periodObs, 1.0, ...)`
  then `if (period < 1.0)` can never fire, so a comb period of zero on the first
  cooks became a period of 1.0 — one beat per hop, ~187 a second, flooding the
  ring. Now gated on the observation being sane.
- **Unsigned underflow if `judged` regresses below the persisted resume point**
  (`pll.hlsl`). `beats` is persistent and `judged` is not derived from it, so an
  asymmetric clear could wrap the span to ~4.3e9 and stall the accumulator
  permanently. One-line `start = min(start, judged)`.
- **Three tempo defects were invisible to the regression gate**, which only
  covered lane F1 — every 2E2 bug left all three F1s at +0.000. The gate now
  also fails on BPM error worsening by more than 0.5 or a metrical level
  regressing from ok. Continuity is deliberately **not** gated: repeat runs on
  unchanged code swing by 0.3 CMLc, so any useful threshold would fire on noise.
- **Two new app-free test suites**, 18 tests, no running app required:
  `test_metrics.py` and `test_ipc_cut.py`. The restart cut was extracted from
  inside `run_pattern` into `cut_pre_restart()` so it could be tested at all;
  one test asserts the exact failure mode that produced this session's false
  twelve-lane regression failure.
- **Both live tests could pass while dead.** `test_noise_honesty.py` now asserts
  the detector was genuinely locked beforehand and is still cooking after, since
  frozen confidence and flat counters are also what a crash produces.
  `test_soak.py` now asserts the beat count keeps advancing while locked, since
  its lane scores never included beats at all.

Considered and rejected: gating continuity in the regression table (too noisy,
above); a behavioural test for the disabled `beat_snap` path (inert at default,
better written when it is enabled).

## Issues

**Criterion 3 fails and I stopped rather than keep tuning.** CMLc lands
**0.00–0.78** against ≥ 0.75, and AMLc 0.02–0.78 against ≥ 0.85. Only
`hats_under_loud_kick_150` (0.78) comes close; `breakbeat_170` scores 0.02 and
`four_on_floor_128` 0.19. Per-pattern figures in `scores/2E2.json`.

An earlier draft of this entry quoted a floor of 0.37, which was wrong twice
over: it silently excluded the two steady-tempo patterns that score near zero,
and it predated a metric fix. `_continuity` normalised the longest correct run
by `len(est)` alone, so a tracker emitting three beats against a hundred
reference beats scored a perfect 1.0. The denominator is now
`max(len(ref), len(est))`, matching mir_eval. Lane F1 is unaffected and the
regression gate still passes at +0.000; only the continuity columns moved, and
they moved down.

What the beat train looks like after the fixes, on four_on_floor_128: 100% of
intervals normal (458.7–506.7 ms, spread ±5%), **zero spacing rejections**, and
every rejection a placement one — beats sit at a mean +0.122 beat with sd 0.106
against a ±0.175 tolerance. The clock is sound; its *anchoring* is not.

The anchoring error is not a fixed convention offset, which is what I expected
and tested for. Measured beat-vs-the-detector's-own-kick, it is neither constant
in time nor in beats:

| pattern | BPM | offset | in beats |
| --- | --- | --- | --- |
| four_on_floor_128 | 128 | +72.0 ms | +0.154 |
| dense_140 | 140 | +18.7 ms | +0.044 |
| syncopated_funk_105 | 105 | −48.0 ms | −0.084 |
| sparse_90 | 90 | +202.7 ms | +0.304 |

four_on_floor also moved 56 → 72 ms between two identical runs, and CMLc is
itself unstable run to run (syncopated_funk 0.06 → 0.46 across two full corpus
passes). The residual is scatter in the comb's own phase estimate — a 160-column
argmax over a 4-pulse train — not a constant I can derive and correct, and not
something a loop gain reaches. Six gain combinations were swept; every one traded
one pattern's continuity for another's.

Per the standing rail I stopped after the second failed attempt rather than
loosen the criterion, and did not tune against the two held-out patterns.
**Human checkpoint 2 falls here**, so the decision is the user's: accept the
deficit and carry it, re-scope the criterion, or authorise work on the comb's
phase estimator itself (a finer theta grid, or anchoring emission to the nearest
picked onset instead of the accumulator crossing).

**The "PLL period does not converge" defect is RESOLVED — see the follow-up
section below.** It was not a PLL bug at all. The entry that stood here reported
the loop settling 5.6% above its target as unexplained; the explanation is that
an exponential tracker converges to the MEAN of its input and I had compared it
against the MEDIAN.

`drop_signal` / `drop_ring` / `beat_cycles` control outputs were added and kept —
they are what proved no beat was ever being suppressed, which is invisible in any
summary statistic.

## Follow-up: tempo-loop outlier rejection

The period defect reported above is fixed, and the fix moved continuity
substantially — but **not far enough to pass criterion 3**.

**The defect was in the observation, not the loop.** An exponential tracker
converges to the mean of its input; every summary I had written compared it to
the median. Measured on four_on_floor_128:

```
beat_period  median  88.16  mean  95.83  min  87.95  max 131.77
pll_period   median  93.66  mean  93.56
obs samples: [88.1, 131.8, 88.2, 88.2, 88.2, 131.7, 88.2, 88.2, 88.2, 88.0,
              88.2, 88.2, 88.2, 131.7, 88.1, 88.1, 88.1]
```

The PLL's 93.56 tracks the observation's mean of 95.83 almost exactly. It was
averaging correctly the whole time. The real fault is that the comb
intermittently returns a metrical RELATIVE instead of the beat — 131.8 hops
against a true 88.2, a 3:2 dotted quarter, on about one cook in six — and those
excursions drag the mean 6% away from a period that looked perfect in every
median-based summary.

**Fix: reject outliers instead of averaging them** (`tempo_reject`, default
0.18). A 3:2 relative is 50% away and a 2:1 is 100%, so the window rejects every
metrical neighbour while leaving room for real drift, and it travels with the
period so a ramp is still tracked normally.

**The counter decays, it does not reset** (`tempo_reacquire_cooks`, default 60,
counted as NET disagreement). A consecutive-run test turns rejection into a trap:
the loop needs only one agreeing sample now and then to hold a wrong period
forever. syncopated_funk_105 did exactly that — parked at 80.3 hops while the
comb reported 107.2 for the majority of the run, its counter climbing to 146 and
being knocked to zero before it could ever re-acquire. The threshold also has to
be reachable on sparse material, where the counter only advances while locked: at
200, sparse_90 peaked at 102 and stayed frozen on the *previous pattern's*
period, because `beats` is persistent and a period outlives the pattern that
produced it.

Period convergence afterwards, PLL median against observed median:

| pattern | observed | PLL | coherence |
| --- | --- | --- | --- |
| four_on_floor_128 | 88.19 | 88.31 | 0.996 |
| dense_140 | 80.14 | 80.15 | 0.660 |
| syncopated_funk_105 | 107.16 | 107.17 | 0.929 |
| breakbeat_170 | 65.96 | 66.12 | 0.698 |
| sparse_90 | 125.52 | 102.80 | 0.389 |

Four of five converge onto their observation. sparse_90 does not, and it is
already one of the patterns failing 2E1's metrical-level criterion.

**Onset F1 is untouched: +0.000 on every lane of all eleven patterns**
(`scores/2E2fix.json`), mean kick 0.913 / snare 0.782 / hat 0.969.

**Continuity improved on seven of eleven patterns and criterion 3 still fails:**

| pattern | CMLc before | after |
| --- | --- | --- |
| breakbeat_170 | 0.02 | 0.65 |
| quiet_intro_drop_128 | 0.09 | 0.60 |
| four_on_floor_128 | 0.19 | 0.44 |
| hats_under_loud_kick_150 | 0.78 | 0.90 |
| tempo_ramp_120_132 | 0.71 | 0.83 |
| kick_snare_coincident_124 [held-out] | 0.02 | 0.67 |
| dense_140 | 0.03 | 0.08 |
| syncopated_funk_105 | 0.09 | 0.00 |

Criterion 3 asks CMLc >= 0.75 on steady patterns and AMLc >= 0.85 corpus-wide.
four_on_floor_128 reaches 0.44, dense_140 0.08, syncopated_funk_105 0.00. **The
criterion is not met and is not loosened.** Per the standing rail this is the
second failed attempt at it, so I stopped rather than continue tuning.

The one regression the gate flagged, `sparse_90/bpm +5.73`, is run-to-run noise
rather than a change in behaviour: three identical runs of that pattern gave
89.6 BPM (error 0.4, metrical level **ok**), 111.5 (21.5, off) and 117.2 (27.2,
off). It never locks, so its reported tempo is whatever the argmax last held.

## The measurement that was not a regression

Before the above landed, six consecutive full-corpus runs showed every lane
collapsing — kick down 0.24, hat down 0.32, BPM reading ~103 on all eleven
patterns — and survived reverting the change under test, a clean project reload,
`--no-reset`, and byte-comparing both module copies. It looked like the committed
table had stopped being reproducible.

**`score_detector.py --lane-map` defaulted to `lane_map.json`, which names
`pulse_baseline`.** Every one of those runs measured the Phase 1 detector and
printed the result under a pulse2 subphase heading. The numbers were entirely
plausible for that detector, which is what made it survive four rounds of
bisection. The flag is now **required**, the chosen map is recorded in every
written table, and comparing against a baseline scored on a different detector is
a hard error rather than a table.

Two real defects fell out of chasing it:

- **`classify_mode` defaulted to Off while the shipped project runs it at 1.**
  A module whose own default does not reproduce its own published numbers is a
  trap — scoring from manifest defaults drops snare F1 by 0.33 while kick and hat
  reproduce at +0.000, which reads as a snare-specific regression. Default is
  now 1.
- **`force_reload` does not reset parameters to manifest defaults**, contrary to
  what `reset_detector` documented. A live `beat_snap` of 0.15, left behind by
  the earlier snap experiments, survived every reload. `reset_detector` now
  WRITES the manifest defaults rather than assuming them.

## Next

Blocked on human checkpoint 2 (criterion 3), with the continuity numbers above
as the current position rather than the ones this entry originally carried.
