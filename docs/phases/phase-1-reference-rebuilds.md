---
type: phase
status: planned
phase: 1
slug: reference-rebuilds
summary: "Rebuild all 11 reference clips in refs/try_v20260706_2246 as faithful modular Sentinel scenes — momentum-first: rough the whole scene, then refine."
created: 2026-07-07
updated: 2026-07-07
---

# Phase 1 — Reference Rebuilds (11 clips)

> "Phase 1" numbers THIS workspace's dev-system, unrelated to the app repo's "phases 70-76".

## Overview
Recreate each of the 11 reference clips (`refs/try_v20260706_2246/video/`) as a **modular Sentinel
scene** — multiple modules, the right technique per element, wired and composited — driven by a
`/slash-goal` loop until all 11 read as their reference. Method is fixed by
`knowledge/reference-rebuild-guide.md` (governing spec): **rough the WHOLE scene end-to-end, then
refine the biggest gaps in whole-scene passes.** No per-element gating or vision_eval score-chasing.

## Problem (before → after)
- **Before:** `pulse_star` built a single hero module from the decomposition JSON, then either
  polished the wrong shape (score-chasing) or, once corrected, gated every micro-step and never
  assembled the whole. Slow, stuck, wrong. Scrapped.
- **After:** build from the reference image, as a modular scene, whole-first with momentum; refine in
  a few whole-scene passes; the human's eyes + final sign-off are the judge.

## Deliverables (one per clip)
| ID | Clip (stem) | Working title | Dominant technique lane(s) | Status |
| --- | --- | --- | --- | --- |
| C1 | `tg6SMjlAs3yrFGLN` | Pulsating Metallic Polyhedron | hero SDF + gradient bg + comp (CALIBRATION) | planned |
| C2 | `twitter_2061154961690431835` | Blueprint Circuit Board Data Flow | 2D field/line + post | planned |
| C3 | `twitter_2060419545714585879` | Glitchy Coordinate Network | 2D cloner + creative-coding | planned |
| C4 | `x8X82M4fonC5rKXl` | Psychedelic Botanical Vector | 3D NPR / SDF + post | planned |
| C5 | `twitter_2074184407192125741` | Psychedelic Pixel Art Deity | 2D atlas/palette-cycle, loop | planned |
| C6 | `b9sG41YMjGmkmAPY` | Generative Botanical Canvas w/ Lens | field + cloner + lens post | planned |
| C7 | `ZO_KolXjLDm-kMih` | Generative 3D Network Growth | blueprint/PNodes + spline | planned |
| C8 | `j3EeLsJrnNpevLRM` | Abstract Fluid Morphing Shader | single-pass shader | planned |
| C9 | `-E2xdaudahw7H7O6` | Abstract 3D Fragmented Collage | SDF/blueprint (re-study) | planned |
| C10 | `_XKysJjlZL4mbfsG` | Generative Wireframe Extrusion | spline/segment 3D (re-study) | planned |
| C11 | `twitter_2074099611313242227` | KidPix Chaotic Drawing Loop | 7–8 layers: feedback strokes + cloner atlas + 3D cube + post | planned |

## Per-clip method + DONE gate
Each clip follows the guide's loop: **quick read+plan → rough the WHOLE scene end-to-end (all
elements wired, composited, animating) → look at the whole vs the reference once → refine 2–3
whole-scene passes (geometry character → material → motion) → harvest.** No per-element checkpoints
or score-chasing.

A clip Cx is **DONE** when, at the reference's key frames, the WHOLE scene meets all four (checked
once at final sign-off; each is a visible/executing gate a mock can't clear):
1. **Silhouette+composition** — side-by-side shows the same elements, counts, orientation, layout;
   a whole-scene `vision_eval` content check confirms the specific shapes are present.
2. **Material/color** — value structure, hue/sat, gloss read as the reference (no matte-vs-gloss or
   hue mismatch; vision_eval names the colors/material).
3. **Motion** — `sweep_record` MP4 (`motion-eval`) matches per-element motion; loop seam ≤ mean
   adjacent-frame diff (`tools/verify_motion_energy.py`, positive control spikes).
4. **Harvest** — modules in `modules/`, an assembled `projects/<clip>/<clip>.sentinel` that opens and
   renders the look, ≥1 catalogue entry if novel, a devlog; row flipped to DONE.

## Files
- New (process): this doc, `docs/implementation-plan.md`. Modified: `knowledge/reference-rebuild-guide.md`.
- New per clip: `modules/<...>/`, `projects/<clip>/{<clip>.sentinel, PLAN.md}`, a devlog,
  `technique-catalogue.md` entries.
- Reuse: `modules/_shared/**`. Deleted: `modules/pulse_star/` (scrapped; C1 rebuilt fresh).

## Order
C1 (calibration) → C2 … → C11 (hardest). Re-study the under-decomposed ones (C9/C10, and C8) at read
time. **Once before building:** reconnect MCP (`sentinel_app ping`) and re-scan `list_types` +
`capabilities` to confirm the updated surface (`conductor`/`mux`/`atlas`, `sentinel_blueprint`,
`sentinel_conductor`).

## Verification
Whole-scene side-by-side stills + occasional whole-scene `vision_eval` content check; `sweep_record` +
`motion-eval` + `verify_motion_energy.py` for motion/loop; open the `.sentinel` and confirm the look.
Phase done: all 11 rows DONE; plan/catalogue/devlogs updated; `/end-session` audit clean.

## Autonomy & human-in-the-loop
Momentum-first; human spent at as few points as possible.
- **Checkpoints:** C1 — one after the rough whole scene is up, and final sign-off. C2–C11 — **final
  sign-off only.**
- **Gate tiers:** *self-serve* (continue, logged) — everything inside roughing + refining a scene:
  build, wire, capture, iterate, the occasional whole-scene vision_eval. *Conditional-proceed* — call a
  clip DONE when the four DONE gates pass on the whole scene. *Hard-stop* — a scene that won't read as
  the reference after a few whole-scene passes (escalate with the side-by-side), an ambiguous reference
  reading, tools down, or anything irreversible (git history, spec edits, deleting non-own work).
- **Pre-authorizations:** transcode/extract stills; create/destroy/recreate modules & scenes under
  `modules/`,`projects/`,`refs/`; `sentinel_state set` + captures; occasional whole-scene vision_eval;
  advance and finish clips when the DONE gates pass; commit by explicit path.
- **Hard blockers:** MCP won't reconnect / required type or tool missing; reference genuinely
  unreadable; a scene won't converge after a few whole passes — escalate, don't grind one element.

## Dependencies
`knowledge/reference-rebuild-guide.md` (spec); `modular-scene-authoring` + `procedural-geometry-authoring`
+ `module-authoring` + `shader-authoring`; `modules/_shared/{sdf,anim}`; `knowledge/{scene-system,
motion-choreography,precise-construction}.md`; live Sentinel MCP (`module`/`conductor`/`mux`/`atlas`,
`sentinel_blueprint`/`sentinel_conductor`); `vision-eval` MCP; `refs/try_v20260706_2246/`.
