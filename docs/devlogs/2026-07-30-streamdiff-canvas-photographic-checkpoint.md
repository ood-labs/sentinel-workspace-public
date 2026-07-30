---
type: devlog
date: 2026-07-30
phase: 6
subphase: 6M-streamdiff-canvas
status: in-progress
approval: pending
summary: "Checkpointed the user-approved live StreamDiff Canvas look and converted its collage prompt bank to isolated studio photography"
note_created: true
updated: 2026-07-30
---

**Goal**

Preserve the current live StreamDiff Canvas state before changing Paint Canvas
resolution behavior.

**Work Done**

- Rewrote all 64 Collage Diffusion prompts as isolated studio photographs on a
  uniform black field.
- Added explicit exclusions for illustration, drawing, engraving, screenprint,
  halftone, scanned-print, film-border, contact-sheet, and paper artifacts.
- Ended every prompt with `hyper-realistic, 4K`.
- Saved the live project in place through Sentinel with bundled relative Module
  paths, preserving the user's current parameter, layout, and graph edits.
- Captured the current Paint Canvas, Collage Diffusion, Pattern Canvas, and
  Pattern Depth SDF outputs under the ignored local checkpoint folder
  `captures/streamdiff_canvas_checkpoint_20260730/`.

**Verification**

- The saved project parses as JSON.
- The prompt bank contains 64 prompts and every entry satisfies the photographic
  isolation and suffix contract.
- The Sentinel checkpoint reported `project_saved: true` with no save warning.
- The live graph profile contained nine nodes; the saved project retains the
  user's additional `Pattern_Depth_SDF_1` node and current node dimensions.

**Remaining Work**

- Paint Canvas size and aspect-ratio control is intentionally not part of this
  checkpoint.
- Continue Phase 6M review and stop at the required G12 human gate.

This is a mid-work checkpoint, not a phase or subphase completion.
