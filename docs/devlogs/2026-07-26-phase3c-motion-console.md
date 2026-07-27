---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3C
status: complete
approval: pending
summary: "Motion Console v3 rebuilt as a full-bleed follow_panel console; all six criteria measured, the station at 0.539 ms mean, and a whole-run text reject proven pixel-transparent (its speedup ratio retracted as attribution, see the correction)"
---

# Phase 3C - Motion Console v3

## Done

`modules/motion_console/` (live node `Motion_Console_V3`), the second v3 station. Four semantic
lanes preserved from v1 (Prompt / Energy / Camera / Pulse), fifteen host-owned
`viewport.controls`, and one raw hit-tested burst. All six pass criteria measured.

| # | Criterion | Result |
| --- | --- | --- |
| 1 | Four lanes cycling independently | 31 sample rounds / 10s at the live panel extent: lfo1 31 distinct 0.089-0.896, lfo2 31 distinct 0.062-0.752, lfo3 30 distinct 0.017-0.588. lfo4 shows exactly two values (0.000/0.500) because its shape is a square at amp 0.50 - correct, not stuck |
| 2 | Burst fires **and releases** | `env 0.555 / fires 2->3` on the rising edge, `0.000` by +0.2s, still `0.000` and `fires 3` after 1.0s **held high**, then `0.555 / fires 4` after release and re-trigger |
| 3 | At or below 2.0 ms | **0.539 ms mean** (0.446-0.623 over five samples) against v1 measured alongside it at 11.3-13.3 ms. **The ratio does not survive review, see the correction below** |
| 4 | Every lane's rate/amp/shape printed and matching | Capture reads `01.50 / 01.00 / shape 0`, `00.30 / 00.80 / 1`, `00.15 / 00.60 / 2`, `01.00 / 00.50 / 3` against identical manifest defaults |
| 5 | Pad Y agrees with the host widget | **Superseded, see the correction below.** As shipped: raw `motion_bias_y=0.9` draws the reticle at 0.90 of the well measured from its bottom and publishes `bias_y=0.9`; `0.1` draws at 0.08 and publishes `0.1`. Up = more, with the value unmodified on every surface |
| 6 | Extent survival (restated by Amendment 3) | `info.panel`: `effective_mode canvas`, `resolution_mode follow_panel`, `render_size == content_size == [1375, 809]`, criterion 1 holding there. Layout swept at 640x360, 900x820, 1600x900 and 1920x403 (4.8:1) with no label crossing another element. `module-ui.ps1 validate`: `OK Motion Console (15 controls)` |

## Decisions

**Amendment 1 is superseded by Amendment 3, at the user's correction.** 3A concluded from v1's
breakage that `follow_panel` was unsafe and made a canonical fixed extent a hard requirement for
every v3 station. That was the wrong diagnosis: v1 broke because its layout was hard-coded to
960x540, and a fixed extent hid the bug instead of fixing it. `ui-authoring.md:142` exempts
artwork "deliberately authored for arbitrary aspect ratios" and `:136` recommends Canvas plus
`follow_panel` for "a pixel-matched full-frame interface". A station whose product is control
outputs has no program image to letterbox, so the console takes the whole dock. Full detail and
the revised extent-proof contract are in the phase doc.

**Burst stays a bool rising edge rather than `type: button`.** 3C confirmed the button kind is a
one-way latch whose StateTree value clears while the injected shader global stays 1, so it is a
binding defect no amount of correct clicking fixes. A bool edge compared against a last-seen value
in the persistent `ui` buffer fires exactly once, and keeps OSC, cues, expressions and automated
proof - all of which a click-only control would have cost.

## Issues found and fixed

Three separate instances of one defect class: **a fixed-pixel label placed in a normalized gap**.

1. Master rate readout drawn outside the rail's right edge collided with the MUTE plate and
   clipped to `01`. A half-printed number is worse than none - it still reads as a value.
2. Header block in pixel units while lane bands are normalized: title crossed lane 1 at 640x360
   and the subtitle crossed the band at 1600x900. The header now sizes itself against the
   headroom above lane 1 and drops its subtitle when that headroom cannot hold it.
3. `SHAPE` and `BIAS` labels landing on the control above them at 1920x403, where the 0.015
   normalized gap is 6px. Added `mcLabelFits`; a label that cannot fit is dropped rather than
   drawn over its neighbour.

Text scale also came from `R.y` alone, which picked 2x on a canvas only 1.25x bigger. It now comes
from `min(W/1280, H/720)`, so a wide-and-short dock cannot get giant glyphs in a band too thin to
hold them.

## Shared kit

`sui3_text.hlsli` gained `sui3RunMiss`, a whole-run bounding reject. Every label was previously
evaluating twelve font-table lookups for every pixel on the panel including the ~95% of rows it
cannot touch. Measured wall time fell **1.920 ms -> 0.539 ms** alongside it, and Style Authority to
~0.93 ms. **Read those as attribution, not as a proven speedup** - see the correction below; the
profiler cannot see GPU drawing cost, so it cannot establish that the guard caused the drop.

Proven transparent, not assumed: with `mute` on to freeze the frame, pre-guard and post-guard
captures differ by **0 pixels of 1,112,375**, `getbbox()` `None`, max channel delta 0. It is an
early-out, not a clip.

## Deferred

A live dock-drag reflow is gesture-dependent - `follow_panel` ignores resolution writes, no
dock-resize command exists in the MCP surface, and `windows-control` returns an empty window list
from this session. The forced-extent sweep exercises identical shader code and is recorded as a
layout proof, not a plumbing proof; the plumbing half is `info.panel` at the live extent. The
drag batches into 3F's hands-on pass with the deferred 3B.3 hover check.

Known limit, not a defect: host `viewport.controls` rects are static normalized values, so hit
regions scale proportionally and cannot reflow at breakpoints. Below roughly 1000px wide the
console stays legible but its hit targets fall under the 32px comfort minimum. Reflowing would
mean giving up host-owned controls and with them undo/redo, presets and OSC.

## Follow-on - Style Authority converted to match

Amendment 3 would have left the lab incoherent with one station full-bleed and one pinned to a
fixed extent, so Style Authority was converted in the same slice at the user's direction. It is a
live theme source and control reference - an interface, not artwork - so the same exemption
applies.

Its layout already derived from the host's control rects and the published pixel metrics, so the
conversion was small and the same three fixes applied:

- text scale from `min(W/1280, H/720)` instead of `R.y` alone;
- the title scale computed **after** the host rects, against the headroom above the pad, with the
  subtitle surrendered before the title shrinks. `titleScale` stays a ceiling: the published metric
  is what the operator asked for, and the layout only ever gives back less than the panel can hold;
- `saCapFits` guarding the PAD / RAIL / STATE / BANK captions.

Verified unchanged where it matters: the 1280x720 capture is identical to the pre-conversion
station - 2x title, subtitle, every caption present. At 640x360 it degrades to a 1x title with the
subtitle and crowded captions dropped, and at 1920x403 nothing overlaps. Live: `open true`,
`content == render == [1375, 809]`.

Before the panel was opened it reported `open false`, `content [0, 0]`, `render [1280, 720]` -
the documented fallback to the root resolution for an unsized panel, and the reason that root
`resolution:` is kept rather than removed.

## Next

3D, the Spline Editor - the heaviest interaction surface (selection, marquee, tangent modes, path
closing, undo/redo), preserving the `README.md:62` data contracts so `Spline_Output` keeps working
unmodified.


## Corrections after the 3F audit

**Criterion 5's result no longer describes the shipped build, and its criterion was rewritten.**
This entry recorded `motion_bias_y=0.05` publishing `bias_y=0.950` as the pass: a flip applied
between the parameter and the published output. That was the wrong reading of a criterion whose own
wording was wrong, and the operator reported the pad as flipped twice afterwards. The stored value
is now the host parameter unmodified on every surface, and the Y-up *direction* lives in one kit
function that converts value to pixel. See phase doc Amendment 6, and
`tools/interaction-lab-guards.py::guard_pad_direction`, which asserts the rendered reticle position
rather than a readback pair.

**The 22x and the 3.6x are attribution, not speedup.** `sentinel_graph action=profile` is a CPU
wall-clock profiler, and the drawing work these numbers claim to have removed is GPU work the
profiler cannot see. 3F later measured the same figure moving 9.63 to 15.87 ms on panel ownership
alone with no code change, and a control that disabled roughly 40% of the drawing moved nothing.
What stands from this sub-phase is the pixel-identity proof of the whole-run text reject: pre-guard
and post-guard captures differ by 0 pixels of 1,112,375, which is a correctness result and needs no
profiler. The `1.920 -> 0.539 ms` and `11.3-13.3 -> 0.539 ms` figures should be read as the cost
moving between accounting buckets, and neither should be quoted as a shader speedup. Phase doc
Amendment 4 now forbids quoting a per-node `wall_time_ms` without its panel state.
