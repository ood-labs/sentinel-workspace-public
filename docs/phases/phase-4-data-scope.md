---
type: phase
phase: 4
title: "Data Scope - a reusable scrolling strip-chart component"
status: planned
approval: pending
created: 2026-07-26
updated: 2026-07-26
summary: "Lift the CHOP-style auto-ranging strip chart proved in modules/audio_bands into a documented sui3_trace kit component, with a worked example station and guards."
---

# Phase 4 - Data Scope

## Overview

`modules/audio_bands` (upstream, merged 2026-07-26) contains a strip chart that behaves the way a
TouchDesigner CHOP viewer does: it scrolls at the rate of the incoming data rather than the frame
rate, and it rescales itself continuously to the recent dynamics of the signal so a threshold stays
placeable whether the peaks are 4 dB or 24 dB.

That behaviour is buried in an audio detector. Nothing about it is audio-specific. This phase lifts
the four mechanisms that make it work into `modules/_shared/ui/sui3_trace.hlsli`, documents them, and
proves them on a station that plots a scalar stream over time.

**This phase delivers a reusable component plus one worked example.** It is substrate with a visible
proof attached, not a new creative instrument. The visible deliverable is the Data Scope station; the
durable deliverable is the kit header and its documentation.

## Motivation

Three things go wrong every time somebody plots a time series in a Module, and `audio_bands` solved
all three by measurement rather than by taste:

1. **Plotting per cook instead of per sample.** A module can cook at 60 Hz while its data arrives at
   187.5 Hz, or the reverse. Sampling the newest value once per cook aliases the signal and makes the
   time axis a lie. `audio_bands` catches up from a saved cursor to `_Data0_Generation`, validating
   each slot's own `generation_counter` before trusting it.
2. **A fixed full scale.** Measured peaks on real drums run past 24 dB while a quiet pad barely
   reaches 4. Either the loud case clips or the quiet case is a flat line. A slowly-decaying rolling
   peak, floored so silence cannot autoscale its own noise to full height, fixes both.
3. **Averaging a column that spans several samples.** At long spans one pixel column covers many
   samples, and averaging hides exactly the transient the plot exists to show.

There is a fourth, less obvious: the reference line has to participate in the scale. A threshold
drawn above the recent peak pins itself to the top border and stops reading as a threshold at all.

## Problem statement

**Before.** Plotting a stream means reimplementing ring addressing, catch-up, scaling and column
reduction per module, in HLSL, each time. `audio_bands` is the only correct implementation and it is
welded to a spectrum detector and to the `au_hud` text kit.

**After.** `sui3_trace.hlsli` provides the ring, the catch-up, the autoscale and the column reduce as
pure functions. A module supplies a buffer and a rect and gets a correct strip chart.

## Deliverables

| ID | Deliverable | Location | Status |
| --- | --- | --- | --- |
| D1 | `sui3_trace.hlsli` - ring addressing, generation catch-up, decaying-peak autoscale, max-reduce column fetch | `modules/_shared/ui/` | planned |
| D2 | `sui3Strip` draw helper in the sui3 idiom, geometry only | `modules/_shared/ui/` | planned |
| D3 | Documentation: the four mechanisms, the data contract, and when NOT to use it | `knowledge/ui-authoring.md` | planned |
| D4 | Data Scope station, the worked example | `modules/data_scope/`, Interaction Lab | planned |
| D5 | Guards covering scroll rate, autoscale, and transient survival | `tools/interaction-lab-guards.py` | planned |

**No text in the component.** `audio_bands` renders through `au_hud` while the lab is on `sui3`. The
component therefore draws geometry and returns numbers; labels, readouts and units stay with the
calling module. That is what lets both kits use it.

## Sub-phases

### 4A - Extract and document the component

Port the four mechanisms out of `audio_bands` into `sui3_trace.hlsli` as pure functions, with the
measured reasoning carried across rather than re-derived. Write D3 against the extracted code.

**Pass criteria**

1. `sui3_trace.hlsli` compiles standalone through `compile_check` in a module that declares no
   viewport events, proving it has no hidden interaction dependency (the failure `au_text.hlsli:9`
   records).
2. Every function is pure: no `_Resolution`, no parameter globals, no text. Verified by inspection
   and by the criterion-1 module supplying all extents as arguments.
3. `knowledge/ui-authoring.md` documents the ring layout, the catch-up contract, the autoscale
   floor, and the max-not-mean rule, each with the measurement that justifies it.

### 4B - The Data Scope station

A station that plots live scalar streams over time using only the component. Source is Audio In
(device or paced WAV from the frozen corpus) so the signal is real and reproducible; **no Pattern
source or diagnostic imagery**, per CLAUDE.md.

**Pass criteria**

1. **Visible and behavioural.** With a real signal playing, a human can SEE the trace scroll right to
   left, and the plotted peak height visibly rescales within a few seconds when the input dynamics
   change. Proven by a `vision_eval` content check asserting the capture contains a scrolling trace
   with a visible waveform, not a flat line and not a clipped block.
2. **Scroll rate follows the data, not the cook.** Forcing the cook rate down must not change how
   much signal history the plot shows. Measured as the number of samples spanned at two cook rates,
   from the control outputs.
3. **Autoscale is real and bounded.** The same waveform at two amplitudes 20 dB apart must plot to
   within 15% of the same peak height; a silent input must NOT autoscale to full height.
4. **Transients survive the longest span.** A single-sample spike must remain visible at the maximum
   trace span, asserted from a capture rather than by eye.
5. Station is `follow_panel` Canvas with no absolute pixel sizes, and `module-ui.ps1 validate` exits
   clean at 640x360 and 1920x403.

### 4C - Second consumer and guards

Prove reusability by a second, different stream, and land D5.

**Pass criteria**

1. A second module plots a non-audio scalar stream through the same component with no changes to the
   component. Candidate: Motion Console lane values, or Gizmo Desk transform deltas.
2. Guards for 4B criteria 2, 3 and 4 run in `interaction-lab-guards.py` and each is proven to FAIL
   against a deliberately broken variant before being kept. (Phase 3 lesson: a guard that has never
   been watched to fail is not evidence.)
3. Full suite green, with any skip named and justified.

## Files summary

**New:** `modules/_shared/ui/sui3_trace.hlsli`; `modules/data_scope/` (manifest, render, state,
README); a second consumer under 4C.

**Modified:** `knowledge/ui-authoring.md` (D3); `tools/interaction-lab-guards.py` (D5);
`projects/interaction_lab/interaction_lab.sentinel` and its bundled modules.

**Explicitly NOT modified:** `modules/audio_bands/`. It shipped upstream two commits ago and works.
Refactoring it onto the new component is a tempting reusability proof and a bad trade this phase;
revisit once the component has a second consumer and guards. `modules/_shared/ui/sui_*.hlsli` (v1
kit) and `modules/_shared/au_hud/` stay untouched.

## Implementation order

4A, then 4B, then 4C. 4A first because writing the docs against the extracted code is what surfaces a
leaky abstraction while it is still cheap to change.

## Verification plan

| Criterion | Method |
| --- | --- |
| 4A.1, 4A.2 | `compile_check` on a minimal consumer; inspection |
| 4A.3 | Doc review against the extracted source |
| 4B.1 | `sentinel_vision eval_pipeline` content assertion on a live capture |
| 4B.2 | Control-output readback at two cook rates |
| 4B.3 | Two captures, plotted peak height measured in pixels |
| 4B.4 | Capture with an injected single-sample spike at max span |
| 4B.5 | `module-ui.ps1 validate`; `info.panel` render/content convergence |
| 4C.1 | Second module live and healthy on the same header |
| 4C.2 | Each guard watched to fail against a broken variant, then pass |

## Autonomy and human-in-the-loop

**Tier 1, self-serve (log the verdict, `approval: pending`, continue):** every criterion above except
4B.1. Component design choices, buffer sizing, the second consumer's identity, guard authorship.

**Tier 2, conditional-proceed (pre-authorized):**
- Adopt whatever ring capacity and decay half-life the measurement supports, provided the chosen
  values are recorded with the numbers that chose them. `audio_bands` uses 512 samples and a ~4 s
  half-life; treat those as the starting point, not a requirement.
- If the component cannot stay text-free without an ugly interface, let it return layout numbers the
  caller draws, and record the deviation. Do NOT pull `au_hud` or `sui3_text` into it.
- If a criterion proves unmeasurable with the available tools, record the negative result and mark
  the criterion unproven rather than substituting a weaker check that passes.

**Tier 3, hard stop:**
- **4B.1 taste and legibility.** The station has to be judged by a human looking at it.
- Any change to `modules/audio_bands/`, `au_hud`, or the v1 `sui_*` kit.
- Promotion of anything here to the public workspace.
- Editing the Phase 3 contract, or approving Phase 3 or Phase 4.

## Dependencies

- Upstream merge `1d2b438`, which brought `modules/audio_bands` into this workspace.
- Audio In (`audio` pipeline type) present in the live `list_types`.
- The sui3 kit. **Phase 3's open host pad defect does not block this**: the component draws a trace,
  not an XY pad, and does not use `sui3PadPoint`.
- Phase 3 remains open at its hands-on gesture blocker. Phase 4 does not depend on that closing, but
  it also must not be used as a reason to consider Phase 3 done.

## Cross-references

- [[phase-3-interaction-lab-v2]] - the sui3 kit and the lab this plugs into
- `modules/audio_bands/README.md` - the source of every mechanism here
- [[ui-authoring]] - where D3 lands
