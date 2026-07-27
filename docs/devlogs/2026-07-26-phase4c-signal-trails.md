---
type: devlog
date: 2026-07-26
phase: 4
subphase: 4C.1
status: complete
approval: pending
summary: "Signal Trails proves sui3_trace on a non-audio cook-rate stream, and surfaced two component defects"
---

## Done

`modules/signal_trails/`, four connected trails plotting Motion Console's LFOs through expression
drivers. Live in the Interaction Lab and saved into the project. Requested directly by the operator
during 4B, and it is exactly what 4C.1 calls for.

**4C.1 met.** The component is used unmodified by a consumer deliberately unlike the first one:

| | Data Scope | Signal Trails |
| --- | --- | --- |
| Source | Audio In data port | no data port at all |
| Rate | 187.5 Hz, many samples per cook | cook rate, one per cook |
| Drawing | filled area | connected trail |

Channels are plain float parameters driven by `ref("Motion_Console/control_outputs/lfo1")` and
friends, so the proof is that the component does not care where a scalar comes from.

**Regression gates after the component changed:** `_trace_probe` still compiles clean,
`data_scope_proof.py` still reports 8 passed / 0 failed, and the Interaction Lab suite is still
42 passed / 0 failed / 4 skipped.

## What the second consumer taught the component

**Max-reduce is only correct when downsampling.** At 60 Hz over an 8 s span the plot holds 481
samples across ~1600 px, so roughly three columns share each sample and every LFO drew as a
staircase with a three-pixel tread. Added `sui3TraceUpsampling` and `sui3TraceFrac`; the renderer
interpolates when there are more columns than samples and reduces otherwise. This is the value of
building a second consumer: the defect is invisible on an audio stream that always outpaces the cook
rate.

**A filled area hides a smooth signal.** Added `sui3StripTrail`, a segment spanning adjacent column
values. Drawing unconnected per-column marks instead gives a dotted scatter, because adjacent
columns take their maxima from different samples.

## Decisions

**Bipolar channels never autoscale.** Autoscaling one would move the baseline away from zero as the
signal grew, so a centred trace would drift off centre. Full scale pins to 1.0 in bipolar mode.

**No authored canvas controls on either scope.** A scope is a readout. `knowledge/ui-authoring.md`
reserves viewport UI for interactions Properties cannot express, and mirroring six sliders onto the
canvas is the anti-pattern that section names. Both modules validate at 0 controls.

## Open

- 4C.2 and 4C.3 not started: the guards for the 4B criteria exist as `tools/data_scope_proof.py` but
  are not yet folded into `interaction-lab-guards.py`, and each still needs to be watched failing
  against a broken variant. The window-max guard already has its failing run recorded (p95 1.000
  broken against 0.855 fixed); the others do not.
- The saved lab project references the generated loop WAV under `tools/audio_test/loops/`, which is
  gitignored. A fresh clone must run `tools/audio_test/make_loop.py` or repoint the Audio In file.
- 4B.1 still open on the operator taste check; `vision_eval` has no provider key.

## Cross-references

- [[phase-4-data-scope]]
- [[2026-07-26-phase4b-data-scope]]
