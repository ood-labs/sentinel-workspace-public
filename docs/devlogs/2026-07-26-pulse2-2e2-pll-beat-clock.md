---
type: devlog
date: 2026-07-26
phase: 2
subphase: 2E2
status: complete
approval: pending
summary: "PLL beat clock: five structural fixes, criteria 1/2/4 pass, criterion 3 (CMLc/AMLc) fails and is a hard stop"
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

**Criterion 4 — 30-minute soak: PASS.** `test_soak.py` (the run log is
gitignored, so the progress samples are reproduced here):

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

## Issues

**Criterion 3 fails and I stopped rather than keep tuning.** Steady-pattern CMLc
lands ~0.37–0.83 against ≥ 0.75, and AMLc ~0.02–0.83 against ≥ 0.85. Best
corpus-wide figures are in `scores/2E2.json`.

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

`drop_signal` / `drop_ring` / `beat_cycles` control outputs were added and kept —
they are what proved no beat was ever being suppressed, which is invisible in any
summary statistic.

## Next

Blocked on human checkpoint 2 (criterion 3). 2F — bundled project, README,
portability — is unblocked and independent.
