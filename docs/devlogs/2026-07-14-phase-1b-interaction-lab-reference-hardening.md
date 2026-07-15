---
type: devlog
date: 2026-07-14
phase: 1
subphase: 1B
status: complete
approval: pending
summary: "Harden Interaction Lab as the viewport, Canvas UI, state, selection, and preset reference"
---

## Done

- Converted the three feature stations into independently controllable, flat Scene Groups with one preset per station.
- Added six project-scoped node presets: two UI density/style looks, two durable spline arrangements, and two durable gizmo arrangements. Added Spline Editor `Path Weight` and host-selection body dragging in Gizmo Lab.
- Replaced stale machine-specific proof bundles with a compact portable proof set and documented the human, MCP, preset, Canvas, and flat-group workflows in the project README and proof index.

## Proof

- Reloaded the saved project from disk and confirmed all six modules compiled successfully, stayed healthy with frames advancing, and the five Canvas panels reported matching content and render sizes at their live dock sizes.
- A real pointer drag moved spline knot 2, changed the linked Spline Output by `0.3604841820987654%`, and one undo restored both the baseline anchors and an exact `0%` downstream image difference. After save/reload, `Spline Default Wave` and `Spline Offset Wave` recalled distinct durable knot positions with no skipped values.
- A synthetic viewport pick hit visible Gizmo object 7 in two frames. A real viewport edit moved its X position from `0.725` to `1.280556`; selection, object descriptors, and durable state agreed, and one undo restored `0.725`. After save/reload, `Gizmo Grid` and `Gizmo Offset Lead` recalled distinct durable transforms with no skipped values.
- Disabling the UI station affected only its three member nodes while the spline and gizmo stations remained enabled and healthy. The saved project contains exactly three independent station groups and no nested group.
- `tools/module-ui.ps1 validate` passed all five authored UI modules. `tools/validate-official-examples.ps1 -Projects interaction_lab -Json` passed 58 files with portability, generated-header, orphan-module, and final-output exemption checks clean. A public promotion dry-run passed and left the sibling public checkout unchanged.

## Next

- Sub-phase 1C modernizes Living Room SDF into the direct-manipulation editor reference with host-owned selection/state/edit, plan Canvas, shared cameras, Scene Groups, and expanded presets.
