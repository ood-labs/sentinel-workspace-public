---
type: devlog
date: 2026-07-30
phase: examples
subphase: touchdesigner-new-project
status: in-progress
approval: pending
summary: "Added a compact TouchDesigner starter-graph recreation with an animated scope, displacement, and interactive SDF cube"
note_created: true
updated: 2026-07-30
---

**Goal**

Publish a small, readable Sentinel example that recreates the semantics and
visual character of TouchDesigner's classic new-project sample.

**Work Done**

- Added the portable `touchdesigner_new_project` project and bundled media.
- Added a full-panel Hermite signal Canvas based on the Interaction Lab and
  Audio Bands plotting language, with responsive Scientifica numerals, tick
  marks, edge-to-edge trace rendering, and visible leftward animation.
- Added a typed signal-to-texture converter and an animated vertical
  displacement node.
- Added a procedural SDF cube renderer at world origin with a native Fly
  camera, true perspective-occluded coordinate axes, coordinate labels,
  host-owned selection, and an Interaction Lab-style transform gizmo.
- Added the intentionally transparent Geometry Pass output and final Out node.
- Added user-facing documentation and the repository project allowlist entry.

**Runtime Proof**

- All five authored Modules passed the live compiler and reported healthy.
- The signal Canvas matched its live panel extent at 1309x679.
- Signal samples changed materially across one second and graph captures
  measured 24.7 dB PSNR.
- Displaced-image captures across the same interval measured 21.4 dB PSNR,
  proving the animation propagated through the converter and displacement.
- Numeric gizmo rotation produced exactly 30 degrees about Y and was then
  restored to the saved zero rotation.
- The full graph ran at approximately 57-60 cooks per second with no reported
  hotspots.
- The project was checkpointed through Sentinel with relative bundled paths.

**Remaining Work**

- Gather user feedback from a clean-clone load.
- Extend the graph only if a future teaching goal warrants more complexity.

**Cross-References**

- Project: `projects/touchdesigner_new_project/touchdesigner_new_project.sentinel`
- Documentation: `projects/touchdesigner_new_project/README.md`
- Signal Canvas: `projects/touchdesigner_new_project/modules/Hermite_Signal/`
- SDF renderer: `projects/touchdesigner_new_project/modules/Geometry_Pass/`

This is a mid-work checkpoint, not a phase or subphase completion.
