---
type: devlog
date: 2026-07-30
phase: examples
subphase: streamdiff-canvas
status: in-progress
approval: pending
summary: "Added a lightweight StreamDiff collage canvas example with centralized generation controls and mask-safe depth accumulation"
note_created: true
updated: 2026-07-30
---

**Goal**

Publish a smaller, easier-to-understand StreamDiff collage example derived
from the brush-canvas workflow without modifying the original project.

**Work Done**

- Added the standalone `streamdiff_canvas` project with its required modules
  bundled locally.
- Removed audio reactivity from the Paint Canvas and Pattern Canvas workflow.
- Added a compact full-panel Generation Controller for Manual, Interval, and
  Continuous generation, prompt travel, linked generation/stamping, and
  independent stamp speed.
- Added a deliberately simple Radial Gradient source with optional multiplied
  Smooth, Fractal, or Grain noise, including scale, amount, and colored-noise
  controls.
- Reworked the prompt bank around single isolated editorial cutout
  illustrations instead of photographs or paper-backed compositions.
- Masked accumulated depth with the subject matte so background depth does not
  contaminate the Pattern Canvas depth output.
- Tightened the Generation Controller layout and removed unused panel space.
- Added project documentation and the repository allowlist entry.

**Runtime Proof**

- All authored modules compiled successfully in the live Sentinel graph.
- The Radial Gradient was captured with noise disabled, monochrome fractal
  multiplication, and colored grain multiplication; its default remains the
  original noise-free gradient.
- A generated isolated hand produced a clean subject-shaped depth result
  against a near-black background without a rectangular backing plane.
- Pattern Canvas accumulated-depth proof showed black outside the stamped
  subject silhouettes after clearing and regenerating the feedback state.
- The complete project was saved through Sentinel with bundled module paths.

**Remaining Work**

- Gather broader user feedback after the example is used from a clean clone.
- Revisit prompt wording only if additional subjects consistently introduce
  unwanted background structure.

**Cross-References**

- Project: `projects/streamdiff_canvas/streamdiff_canvas.sentinel`
- Documentation: `projects/streamdiff_canvas/README.md`
- Generation controller: `projects/streamdiff_canvas/modules/Generation_Controller/`
- Radial gradient: `projects/streamdiff_canvas/modules/Radial_Gradient/`
- Pattern canvas: `projects/streamdiff_canvas/modules/Pattern_Canvas/`

This is a mid-work checkpoint, not a phase or subphase completion.
