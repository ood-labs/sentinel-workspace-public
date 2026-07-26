---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3C
status: complete
approval: pending
summary: "Motion Console v3 rebuilt as a full-bleed follow_panel console; all six criteria measured, and a whole-run text reject cut it to 0.539 ms"
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
| 3 | At or below 2.0 ms | **0.539 ms mean** (0.446-0.623 over five samples) against v1 measured alongside it at 11.3-13.3 ms - 22x |
| 4 | Every lane's rate/amp/shape printed and matching | Capture reads `01.50 / 01.00 / shape 0`, `00.30 / 00.80 / 1`, `00.15 / 00.60 / 2`, `01.00 / 00.50 / 3` against identical manifest defaults |
| 5 | Y flip applied exactly once | raw `motion_bias_y=0.05` (reticle up) -> published `bias_y=0.950`; raw `0.95` -> `0.050`. Up = more |
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
cannot touch. Wall time fell **1.920 ms -> 0.539 ms** (3.6x), and Style Authority fell to ~0.93 ms
for free.

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

## Next

3D, the Spline Editor - the heaviest interaction surface (selection, marquee, tangent modes, path
closing, undo/redo), preserving the `README.md:62` data contracts so `Spline_Output` keeps working
unmodified.
