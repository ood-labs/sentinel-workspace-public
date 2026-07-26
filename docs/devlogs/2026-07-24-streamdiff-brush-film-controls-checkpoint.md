---
type: devlog
date: 2026-07-24
phase: examples
subphase: streamdiff-brush-film-controls
status: in-progress
approval: pending
summary: "Checkpointed the real bloom/flare post stack and consolidated Pattern Canvas performance controls"
note_created: true
updated: 2026-07-24
---

**Goal**

Save the tuned StreamDiff Brush Canvas state after the film-post pass and keyboard performance controls became usable together.

**Work Done**

- Added `Film Grade Post` after `Pattern Spatial SDF`.
- Replaced sparse highlight taps with quarter-resolution RGBA16F highlight extraction, separable Gaussian glow, flare pre-softening, and a long horizontal anamorphic convolution.
- Fixed the flare pass order so every stage consumes the current frame rather than the previous frame.
- Removed the fixed high-frequency grain lattice and changed grain reseeding to a new persistent frame seed on every cook.
- Preserved filmic grading, edge resolve, chromatic aberration, organic lens dirt, and live-tuned glow/flare controls.
- Consolidated Pattern Canvas performance controls:
  - `X` holds the feedback kick/zoom envelope.
  - `Z` immediately generates and spawns, then repeats at `Seconds Per Stamp` while held.
  - `C` toggles persistent auto-run on and off.
- Made automatic StreamDiff cadence follow the same auto-run state, preventing hidden generation while trigger mode is idle.
- Saved the live project with its bundled modules and current camera/grade/control state.

**Proof**

- `Film_Grade_Post` compiled with eight passes and reported healthy at the live output resolution.
- `Pattern_Canvas` compiled with thirteen passes and reported healthy.
- The viewport bindings advertise X kick, C auto-run, and Z generate/spawn.
- The live project was saved after the final control remap.

**Remaining Work**

- Continue creative tuning and performance play from this saved look.

**Cross-References**

- Project: `projects/streamdiff_brush_canvas/streamdiff_brush_canvas.sentinel`
- Pattern controls: `projects/streamdiff_brush_canvas/modules/Pattern_Canvas/`
- Film post: `projects/streamdiff_brush_canvas/modules/Film_Grade_Post/`
