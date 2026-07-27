---
type: devlog
date: 2026-07-26
phase: 4
subphase: 4B
status: complete
approval: pending
summary: "Data Scope station live on real audio, with the 4B criteria asserted by a measuring harness"
---

## Done

`modules/data_scope/`, three auto-ranging strip charts driven by Audio In over the measured corpus,
wired as `Scope_Audio -> Data_Scope` in the Interaction Lab. `tools/data_scope_proof.py` reports
**8 passed, 0 failed**.

| Criterion | Result |
| --- | --- |
| 4B.2 samples_shown = span/hop_dt | 187.5 and 562.5, error 0.01% |
| 4B.2 sample rate follows the stream | 187.6/s against a 187.5 Hz stream, error 0.0% |
| 4B.3 full scale tracked the 24 dB step | fs 0.827 -> 1.134 = **24.0 dB** measured |
| 4B.3 plotted height unchanged across the step | 0.875 both sides, 0.0% difference |
| 4B.3 nothing clipped across a full loop | 0 of 14 captures pinned |
| 4B.3 silence does not autoscale | tallest lane 0.000 |
| 4B.4 transient survives the longest span | hat peak 0.719 @0.5s vs 0.872 @5.0s |
| 4B.5 follow_panel at two extents | clean at 1727x826 and 640x360; `module-ui.ps1 validate` OK |

**4B.1 is NOT complete.** The automated half is met -- the pixel measurement distinguishes an empty
plot (0.000), a healthy one (0.875, exactly the 1.15 headroom) and a clipping one (1.000). The
`vision_eval` content assertion could not run: no provider key is configured, and configuring one is
the operator's action, not something to request in chat. The taste and legibility half is a Tier 3
operator check regardless. Recorded as unproven rather than swapped for something weaker.

## Decisions

**Full scale is `max(windowMax, decayedPeak)`, not the decayed peak alone.** Measuring caught this:
the decay is anchored at the present while the plot shows history, so a short half-life against a
long span lets the scale fall below its own on-screen samples. At 5 s span and 0.25 s half-life the
decayed peak alone measured p95 1.000, fully clipped, where the combined term measured 0.855. The
lesson is in `sui3_trace.hlsli` and `knowledge/ui-authoring.md` with both numbers.

**Summed band energy, not mean.** Band 0 carries 0.0116 while band 20 is at 1e-5, so averaging a
48-band slice put the high lane 40 dB under the floor reading a flat zero. dB floor default moved to
-90 to match measured levels.

**Accent only above the reference.** The first cut tinted a whole column by whether its peak cleared
the reference, which on real material meant most of the frame was accent and the sui3 accent
contract was gone.

**Frame drawn last.** Drawn first it was overdrawn wherever the plot saturated, so the strip lost its
boundary exactly when something was wrong with it.

## Issues encountered

- **Audio In File mode does not loop.** It plays once and reports `Inactive`. A 20 s corpus file
  froze the scope 20 s after wiring, and the first harness run then reported a dead autoscale, a dead
  sample rate and a failing silence check -- three readings that all looked like module defects and
  none of which were. `tools/audio_test/make_loop.py` builds a longer signal, and every harness check
  now restarts the stream and asserts liveness before measuring.
- **The measuring tool was wrong twice, in ways that flattered the module.** Deriving lane bands from
  the fill made the tallest column 1.000 by construction. Then scanning down from the top found the
  floating dashed reference line on a silent input and reported 0.876 for an empty plot. Both now
  fixed and the tool is verified against all three states.
- **A "> 1.5x" autoscale assertion failed a module that was exactly right.** The lane value is
  normalized dB, so a 24 dB step is a 1.37x change in full scale. The check now asserts dB.

## Next

4C: a second consumer on a non-audio stream. The operator has asked specifically for the Motion
Console LFOs plotted as live trails, which is exactly the reusability proof 4C.1 calls for.

## Cross-references

- [[phase-4-data-scope]]
- [[2026-07-26-phase4a-trace-component]]
