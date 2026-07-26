---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3C
status: in-progress
approval: pending
summary: "3C opened. Tier 2 conditional RESOLVED by measurement: the burst latch is real and reproduced, so the hit-test rewrite is required, not optional. Lab restored after the test broke the Pulse lane."
---

## Tier 2 conditional: resolved, hit-test rewrite REQUIRED

The phase doc pre-authorized either outcome:

> **3A `burst` finding.** If `burst` proves healthy on this build, drop 3C's event hit-test
> rewrite and record the reversal against the AUTOPSIA finding. If stuck, implement the
> hit-test.

Re-measured rather than assumed, because 3B had just overturned the *other* 3A platform
finding (pointer injection) and it was reasonable to suspect this one too. It holds.

| step | `lfo4` | `energy` | `pulse` |
| --- | --- | --- | --- |
| before (3 samples) | 0.000 | 0.329 / 0.352 / 0.147 | 0.000 |
| `burst=1` | **1.000** | **1.000** | **1.000** |
| `burst=0` (3 samples) | **1.000** | **1.000** | **1.000** |
| after `force_reload` | **1.000** | **1.000** | **1.000** |

Fires, never releases, and survives a reload. `lfo_compute.hlsl:36,42` gate `lfo4` and
`energy` on it, so one press kills the Pulse lane and the energy readout for the session.

**Decision: implement the hit-test rewrite.** `type: button` is unusable in a shader on this
build.

### Why 3B's injection reversal does NOT rescue this

`sentinel_ui click method=mouse` works on Properties widgets, so it is tempting to conclude
burst can simply be clicked correctly. It cannot, and the distinction matters:

- The parameter write is not the problem. 3A recorded `sentinel_state get` returning 0 while
  `sentinel_pipeline info` returned 1 for the same parameter at the same instant. The
  StateTree value clears; the **shader-side injected global stays 1**.
- That matches AUTOPSIA's independent finding that `type: button` reads a constant 1.0 in
  HLSL. It is a binding defect, not an input-delivery defect, so a better click cannot fix it.

### Design consequence for the rebuild

3B established the rule "reach for `viewport.controls` before raw events" — but `button` is
exactly the control kind that rule cannot use here, because the kind is backed by
`type: button`. The rebuilt console should therefore use `viewport.controls` for its sliders,
toggle and XY pad (all sound), and a **raw hit-tested click for burst alone**, following
`modules/au_deck/state.hlsl`.

That split has a cost worth stating up front: the burst gesture will not be automatable from
MCP, because 3B also established there is no route to click an arbitrary point inside a module
preview. Criterion 2's three-point before/during/after readback is a **parameter-driven**
proof of the envelope; the click itself lands in the 3F hands-on pass.

## State restored

The test latched burst and broke the Pulse lane, as predicted. `force_reload` did not clear it
(confirming 3A a second time); a project reload did. `Motion_Console` now reads `lfo4=0.500`
with `energy` varying, so the lane is cycling again.

`Style_Authority` was a live node not saved into the project, so the reload dropped it. It was
recreated from the committed `modules/style_authority/` and is healthy with 16 control outputs.
No project file was written.

## Next

Build the rebuilt console: `viewport.controls` for sliders/toggle/pad, hit-tested burst,
four semantic lanes preserved, target at or below 2.0 ms against the 14.66 ms baseline.
