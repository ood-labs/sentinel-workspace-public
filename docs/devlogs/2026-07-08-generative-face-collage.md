---
type: devlog
date: 2026-07-08
phase: 1
subphase: face-collage
status: complete
approval: approved
session_start: 2026-07-07
session_end: 2026-07-08
summary: "Live generative face-collage instrument: multi-SD atlas idea evolved into cut-out feature accumulation with a vector overlay and temporal delay line"
note_created: true
updated: 2026-07-08
---

## Goal
Build "crazy generative collage" from a mismatched-face reference (`refs/collage/…`): StreamDiff +
atlas + tracking, per the user's excitement about the new multi-StreamDiff surface. Followed
`modular-scene-authoring`. The build evolved substantially across the session as the user steered it
away from the original plan toward something better.

## Done — final architecture (`projects/face_collage/`)
Live, fully-generative, self-animating. One StreamDiff, no pre-render:
- **Hero face:** `face_guide` (procedural frontal-face structure plate) → `SD_Face` (StreamDiff, CN
  512×896 + IPA, prompt-bank of face styles, ControlNet-locked to the guide) → `Face_DS`
  (`modules/resample` downscaler, fixes the 2× SD output). `Prompt_LFO` (saw) sweeps `prompt_position`;
  `Scatter_LFO` was later superseded.
- **Tracking → placement:** `Face_Track` (mediapipe, 468 landmarks) → `face_stitch` (landmarks →
  48/56-byte `PNode` anchors at eye/mouth/nose, with velocity for latency correction).
- **The cutout engine (`face_cutout`):** cuts eye/mouth/nose patches from the live (downscaled) face
  and stamps **many independently-animated duplicates** — Shape (Circle/Square/Rounded), Motion
  (Orbit/Noise/Spiral/Wave/Static), Copies (1–16) + spread, animated Scale (Pulse/Noise, indep X/Y),
  frame-locked Border. Publishes a **`Clones` structured buffer** (compute pass writes it, draw pass
  renders from it → data + pixels always match). Final feature: a **ring-buffer temporal delay line**
  — copies sample progressively OLDER face frames (a 48-frame 256×448 ring) at a per-copy delay in
  seconds, interpolated, with the tracking UV delayed in tandem (a second anchor-UV ring) so old
  crops land correctly.
- **Persistent accumulation (`accum`):** a compute-composited persistent structured-buffer canvas
  (720×1280 float4 + ping-pong scratch) that bakes the cutouts forever (Decay 1 = keep, <1 = trails)
  with StreamDiff-style per-frame pan/zoom steering.
- **Vector overlay (`clone_overlay`):** reads the `Clones` buffer and draws dots + connecting lines
  with real web modes (Cage/Proximity/Nearest) + continuous **Catmull-Rom Spline/Loop** through all
  points, bezier bow, arc-length chase + dashes, and **occlusion-correct** corner/full boxes. Lifted
  the linework vocabulary from strata `wire_render`/`corner_thread`.
- **Compositing (`overlay_comp` → `collage_finish`):** stacks accum + **current cutout crisply on top**
  (fresh_amt) + overlay (premultiplied), preserving alpha; finish adds the periwinkle grid, glitch,
  grade. Spout out.
- **Reusable library modules extracted:** `modules/resample`, `modules/lfo`.

## Decisions Made
- **No StreamDiff-for-references rule doesn't apply** — this is a generative instrument where diffusion
  IS the medium, not a faithful recreation.
- **Dropped the original multi-SD element-atlas / tile-fragmentation plan** at the user's direction:
  one SD, cut features straight from the live morphing face, accumulate forever. Much stronger.
- **Persistent buffer, not graph feedback,** for cross-frame accumulation (see Lessons).
- **Frame-locked borders inside `face_cutout` + fresh-cutout-on-top compositing** to fix overlay/accum
  latency — borders drawn in the same draw pass as the stamps can't desync.
- **Time-based delay line** (Delay/Copy seconds + Capture Rate) over the first stepped ring-slot design,
  with the tracking UV delayed in tandem — the user's two specific complaints.

## Approvals & Locks
- User throughout: "ridiculously fucking sick", "this is fucking sick", "wow it works thats fucking
  sick" — signed off, requested `/end-session`, "this is a good example."
- Locked patterns: Clones data-buffer bridge; persistent-canvas accumulator; occlusion-correct overlay;
  time-delay-line with tandem UV delay.

## Issues Encountered
- **`force_reload` drops data-port links + expression drivers + resets params** — hit on nearly every
  `face_cutout`/`clone_overlay` reload; had to re-add Anchors/Clones links and restore params each time.
  → Lessons.
- **Graph self-loop feedback only carries one frame** — the naive `accum` feedback wiring didn't
  accumulate; rewrote as a persistent structured-buffer canvas. → Lessons.
- `line` is a reserved HLSL keyword (already in lessons) — hit twice, renamed.
- `color`/`point2D` params are `float3`/`float2` in HLSL (not `_r/_g/_b`/`_x/_y`); state paths keep the
  suffixes.
- Overlay compositor hardcoding `alpha=1.0` blackened the grid gaps downstream — output real coverage.

## Next Steps
- Optional polish: visually age older delay-line copies (desaturate/darken by age); age-mode
  (progressive/random/grouped); numbered labels / per-group colors on the overlay.
- Harvest `accum` / `clone_overlay` / the `face_cutout` clone+delay-line kit into `modules/` proper if
  a second scene wants them (currently project-local, catalogued as exemplars).

## Cross-References
- Reference: `refs/collage/2f5a27a3f0a46f830f21ebca20fdd849.jpg`
- Harvest: `knowledge/technique-catalogue.md` → "Generative feed collage (face_collage)" + `resample`/`lfo`
- Prior devlog: [[2026-07-07-kidpix-canvas-recreation]]
- Skill: `modular-scene-authoring`
