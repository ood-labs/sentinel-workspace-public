---
type: devlog
date: 2026-07-26
phase: 4
subphase: 4C.2
status: complete
approval: pending
summary: "Four scope guards folded into the lab suite, each watched failing against a deliberately broken module"
---

## Done

Four guards added to `tools/interaction-lab-guards.py`, covering the two defects
the operator caught by eye and the two component mechanisms that have no other
runtime assertion. Suite is 46 passed / 0 failed / 4 skipped; the four skips are
the pre-existing pointer-gesture gaps, unchanged.

Each guard was watched FAILING against a deliberately broken build before being
kept, then watched passing again after `git checkout` and a `force_reload`. A
guard that has never been seen to fail is not evidence, and two of these four
did not bite on the first attempt.

| Guard | Break injected | Broken | Healthy |
| --- | --- | --- | --- |
| `scope: autoscale covers the window` | `peak = max(peak, winMax)` deleted | peaks 1.000 / 1.000 / 1.000 | 0.885 / 0.886 / 0.886 |
| `scope: reference participates in scale` | `sui3FullScale(peak, 0.0, ...)` | fs 0.827 at reference 0.95 | fs 1.093 |
| `trails: time axis is stable` | raw `_DeltaTime` for the sample interval | 11.40% swing in `samples_shown` | 0.12% |
| `trails: live edge is not stale` | `sui3TraceClampIndex` removed | 19/24 edge columns over 6 lit px, tallest 40 | 0/24, tallest 6 |

## Issues Encountered

**Two guards passed against their own break on the first attempt.** Both were
measuring something adjacent to the mechanism rather than the mechanism.

The reference guard set `reference = 0.95` and asserted full scale rose to
match. It passed with the reference deleted from the computation entirely,
because the material's own peak was 0.985 and set the same scale unaided. The
obvious fix, raising `db_floor` to suppress the signal, does not work either:
the floor compresses toward 0 dB and this material's transients reach it, so
the peak stayed at 0.985. It now measures in the loop's quiet intro, rewinding
the WAV and shrinking span and half-life so the peak reflects only what has
played since. The peak reads 0.719 there, safely under the reference, and the
precondition is asserted so a future run cannot pass vacuously.

The live-edge guard assumed the stale sample would show up as a step in plotted
height. It measured 1 hit in 16 channel-frames against the break, because the
stale column coincides with the frame hairline that the column classifier
discards. The signature is not a shifted height at all: the trail connects
consecutive columns, so one stale sample renders as a near-vertical bar. A
controlled A/B over 6 frames x 4 channels separated cleanly on lit-run length
(mean 13.8 and 23.3 in the last two columns broken, 3.7 and 4.3 restored;
22/24 and 20/24 columns over 6 lit px versus 0/24 and 0/24), and the guard now
measures that. Numbers recorded in `edge_segment_lit`'s docstring.

**A guard failed a correct module.** The first live-edge rule flagged a
discontinuity near the right edge in all four channels at once. That was real
data: `guard_presets` runs immediately before and recalls Motion Console
presets, resetting the LFO phases, so every channel legitimately stepped
together. The guard now settles for 2 s and samples across frames and channels
rather than trusting one capture.

**The measurement tool needed fixing before any of this could be trusted.** The
right-edge search stopped on the frame hairline and read it as a plotted value
of 0.0, which showed up as a 0.4 discontinuity in every lane. This is the fourth
time a measurement in this phase has been wrong in the direction that flatters
or accuses the module without cause; the tool is not evidence until it has been
watched discriminating.

## Next

4B.1 remains open: the operator taste and legibility check. `vision_eval` has no
provider key on this install, so it is recorded unproven rather than substituted
with a weaker check.

## Cross-References

- [[2026-07-26-phase4c-signal-trails]]
- [[phase-4-data-scope]]
