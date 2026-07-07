---
type: devlog
date: 2026-07-07
phase: 1
subphase: kidpix
status: complete
approval: pending
summary: "Recreate Kid Pix chaotic canvas reference as a modular 2D plate scene"
---

## Goal
Recreate `refs/try_v20260706_2246/video/twitter_2074099611313242227.gif` — a chaotic *Kid Pix*
paint-program canvas — as a fully modular Sentinel scene (never a monolith), following
`recreate-reference` + `modular-scene-authoring`.

## Done
- Built a **2D composite-of-layers** scene at 1200×960, 6s self-animating seamless loop, 11 nodes,
  one module per visual language wired premultiplied-alpha → compositor:
  - `kidpix_comp` — premult over-stack, opaque white canvas base, 7 inlets (back→front: roil, trail,
    stroke, scribble, swarm, cube, ui).
  - `kidpix_roil` — hard-edged multicolor "wacky brush" roil as a wide horizontal rainbow band
    (elongated orbiting color lobes, domain-warped, even 6-crayon spread).
  - `kidpix_trail` — writhing Catmull-Rom loop with a procedural palm glyph stamped along arc-length
    (lower-left snake).
  - `kidpix_stroke` — thick black draw-on brush: round-brush SDF along an authored hook/"7" bezier
    path with arc-length reveal + per-loop redraw.
  - `kidpix_scribble` — pink/black radial spiky star-burst clusters, loop-synced rotate + jitter.
  - `kidpix_stamp_atlas` (4×4 procedural icon atlas: heart/star/ghost/bulb/sun/fish/flower/smiley/
    diamond/moon/cloud/tree/arrow/house/drop/spiral) + `kidpix_swarm` (per-instance stepped-jitter
    cloner) consuming reused `pl_grid`(Scatter) → `pl_spawn`(Jitter) PNode placements.
  - `kidpix_cube` — ray-box tumbling cube, flat-unlit Kid Pix pattern faces (checker/solid/halftone),
    pattern-cycle timer, 2 turns/loop.
  - `kidpix_ui` — static window chrome: crown + real **"File Edit Goodies"** text (shared
    scientifica font), varied tool-icon palette, rainbow color strip + pattern swatches, border.
- All 11 modules `compile_check` clean → `compile_status ok`; whole scene proven by capture.
- Loop proof: `scratch/kp_loop.mp4` (6.0s) — seam diff 15.7 vs 6.9 normal adjacent-frame; the extra
  is the black stroke's intentional per-loop **redraw** (matches the reference decomposition). Cube
  rotation, roil, palms, scribbles and stamp jitter are loop-synced and seamless.
- Saved bundled show `projects/kidpix_canvas/kidpix_canvas.sentinel` (11 modules + `_shared` copied
  in for standalone compile) and allowlisted it in `.gitignore`.

## Decisions Made
- 2D composite-of-layers, not a 3D scene — the canvas is flat; the cube is the one 3D element but
  renders as its own premult plate (no shared lighting/occlusion), so layers is correct.
- UI chrome = **procedural stylized** (user-confirmed) over faithful-icon or cropped-bitmap; used the
  shared scientifica font for real menu text rather than hand-rolling glyphs.
- No post grade — Kid Pix is flat/hard-edged; skipped the `post` bloom stack deliberately.
- Seamless loop via loop-synced motion (`an_loop_noise`, `frac(_Time/loop)` phases) in every module;
  accepted the stroke redraw discontinuity as faithful to the reference.

## Approvals & Locks
- User: "came out really good … very impressive" — signed off, requested `/end-session`.
- Locked: reused `pl_grid`/`pl_spawn` for swarm placement; premult plate + over-compositor pattern.

## Issues Encountered
- None costly — prior lessons (never declare injected `_Data0`/`_Tex0`; unique pass binding slots;
  bundle `_shared` manually) were internalized, so all modules compiled first try. Minor: initially
  launched `modular-scene-authoring` before `recreate-reference`; corrected.

## Next Steps
- Optional polish if revisited: denser upper-right swarm cluster + a flowing stamp stream; a bolder
  explicit "7" stroke path; more overlapping/streaky roil strokes.
- Next reference in the `try_v20260706_2246` set.

## Cross-References
- Reference + decomposition: `refs/try_v20260706_2246/decompositions/twitter_2074099611313242227.json`
- Harvest: `knowledge/technique-catalogue.md` → "Paint-canvas & 2D stamp motion (kidpix_canvas)"
- Prior devlog: [[2026-07-07-c1-pulsating-metallic-polyhedron]]
- Reused kit: [[technique-catalogue]] Layout kit (`pl_grid`/`pl_spawn`)
