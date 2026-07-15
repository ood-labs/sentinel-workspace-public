---
type: devlog
date: 2026-07-15
phase: 1
subphase: 1I
status: complete
approval: pending
summary: "Package Industrial Lattice as a compact beginner-facing official example"
---

## Done

- Preserved the strong two-node monochrome render and bundled both root-level Module dependencies into the project.
- Added Hero, Lookup, Deep Grid, and Fly wireless cameras through one Camera Switcher and bound the lattice renderer with `camera_ref`.
- Added exactly one Group Output and organized all eight nodes in one flat low-alpha purple Scene Group with no nested groups.
- Exposed eight controls spanning structural spacing/profile, junction detail, surface grime, local light, fog, and post bloom.
- Authored Box Frame, Heavy Steel, Concrete Haze, Fidelity, and Performance as complete whole-group presets.
- Added focused project-scoped node presets for the approved lattice core and monochrome finish.
- Replaced the stale build notes with current beginner-facing documentation and a proof index.

## Proof

- All four cameras produced distinct usable framings; Lookup is the approved Fidelity default and Fly remains directly navigable.
- All five presets recalled 156 pipeline parameters, eight exposed controls, and eight bypass flags successfully.
- Fidelity restored the healthy 1280x720 4x4-AA state; Performance visibly reduced resolution, AA, shadows, bolts, march distance, and detail.
- The Group Output received the real post texture and reported increasing frames.
- Both bundled modules passed Sentinel `compile_check` with zero lints.
- Portability validation found no private absolute paths, missing active modules, orphan modules, or forbidden cache artifacts.

## Taste rules carried forward

- A compact example does not need a custom UI when Scene Group controls already provide the honest authoring surface.
- Do not invent selection or gizmos for fields without stable object identity.
- Shared cameras are wireless controls, not decorative video nodes.
- Keep one flat Scene Group, one Group Output, and a restrained low-alpha annotation.

## Next

- Sub-phase 1J assembles the public showcase gallery and runs the clean-clone release proof.
