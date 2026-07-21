---
type: devlog
date: 2026-07-21
phase: examples
subphase: streamdiff-brush-canvas
status: in-progress
approval: pending
summary: "Checkpointed the interactive StreamDiff brush canvas and simplified displacement-driven Shape Maker"
note_created: true
updated: 2026-07-21
---

**Goal**

Build a portable StreamDiff workflow with two distinct authored tools: a controllable paint canvas for diffusion placement and a compact shape/depth generator that feeds the diffusion lane.

**Work Done**

- Created and saved `projects/streamdiff_brush_canvas/streamdiff_brush_canvas.sentinel` with bundled `Paint_Canvas` and `Shape_Maker` Modules.
- Reworked Paint Canvas into a full authored canvas with middle-drag panning, wheel zoom, Alt+wheel brush sizing, a synchronized brush reticle, corrected coordinate mapping, corrected rotation direction, and working clear controls.
- Slimmed the Paint Canvas toolbar and removed the previous oversized floating control panel.
- Replaced the abandoned Field Studio / Shape Studio direction with one compact Shape Maker rail and one responsive square preview.
- Changed Shape Maker output from patterned interior fill to a solid monochrome silhouette whose edge is deformed by traveling, orbiting, radial, or organic displacement.
- Added paired Video Guide and Depth Guide outputs plus a Depth preview toggle.
- Added preview drag positioning and wheel-based shape scaling, with effective center and size published as control outputs for downstream placement.
- Consolidated motion phase integration into the working persistent interaction buffer and confirmed live that speed `0` holds phase while speed `2` advances it.
- Renamed the authored motion control to `Speed` and changed its intended units to signed cycles per second (`0` stop, positive forward, negative reverse).
- Saved the live project in place after Sentinel restarted; both authored Modules were reported as already bundled.

**Current Proof**

- Sentinel responded to ping after restart and saved the project successfully.
- The generated Shape Maker UI validates with 14 authored controls.
- Before the final speed-semantics edit, live phase readback held exactly at `0.957747` with speed `0` and advanced from `0.006722` to `0.498006` with speed `2`.

**Remaining Work**

- Re-run the real compile check and force-reload Shape Maker after the crash; the final `Speed` label and cycles-per-second edit are saved on disk but were not compiled before this checkpoint.
- Visually inspect the responsive Shape Maker UI, solid Video Guide, and Depth Guide after reload.
- Remove obsolete unused Shape Maker shader files only after the replacement passes final live proof.

**Cross-References**

- Project: `projects/streamdiff_brush_canvas/streamdiff_brush_canvas.sentinel`
- Documentation: `projects/streamdiff_brush_canvas/README.md`
- Existing proof bundle: `projects/streamdiff_brush_canvas/proof/`
