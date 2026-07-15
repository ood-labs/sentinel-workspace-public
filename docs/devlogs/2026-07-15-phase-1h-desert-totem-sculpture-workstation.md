---
type: devlog
date: 2026-07-15
phase: 1
subphase: 1H
status: complete
approval: pending
summary: "Modernize Desert Totem as a safe procedural sculpture workstation"
---

## Done

- Preserved the original layout, accent-field, renderer, signal, and post lanes while replacing the old macro preview with a responsive ochre/black Warp Deck.
- Upgraded `dada_layout` into a semantic editor for Crown, Upper, Mid Shelf, and Base assemblies. Move, rotate, and scale apply around assembly pivots so child primitives remain coherent.
- Added stable selection descriptors, real provider picking, four-phase viewport edits, durable transform overrides, atomic reset, and stale-event deduplication.
- Added Hero, Detail, Orbit, and Silhouette wireless cameras through one Camera Switcher and bound the renderer through `camera_ref`.
- Organized all twelve nodes in one flat low-alpha purple Scene Group with exactly one Group Output, eight non-conflicting controls, and six safe whole-scene presets.
- Added project-scoped layout, Warp Deck, renderer, and post presets with explicit parameter stacks; the two layout presets include a 128-byte durable state payload.
- Reduced the closed Warp Deck backing target to 480x270 while retaining full `follow_panel` scaling and a 960x540 authored proof capture.
- Replaced the obsolete notes with current beginner-facing documentation and bundled all portable dependencies.

## Proof

- Live object inspection returned four selectable descriptors and a synthetic pick returned Base id 4.
- Move, rotate, and scale transactions changed the expected durable records. The final render updated without detaching compound forms.
- Baseline and asymmetric state presets recalled with `durable_state` applied and no skipped fields. Repeated baseline readbacks stayed at zero offsets/rotations and unit scales.
- All six group presets recalled sequentially with 235 values applied per look and no crash/TDR. Their captures are visibly distinct and use four distinct shared camera framings.
- Performance caps resolution, march distance, shadows, and accent density; Fidelity restores the approved full-quality state. The graph remained healthy around 60 FPS during the audit.
- All six authored modules passed Sentinel `compile_check` with zero lints.
- A cache-free project reload resolved every bundled module path. The heavy renderer completed a real cold compile well below Sentinel's 120-second abandon limit after its FBM, horizon, and instance traversals were made explicit runtime loops; the final post output returned at 760x1140.

## Taste rules carried forward

- Give editable scenes stable semantic objects, not selectable raw primitives.
- Put scene-specific controls in one focused Canvas and do not duplicate their authority in the Scene Group.
- Camera control nodes remain wireless; do not invent video pins or decorative wiring.
- Keep one flat Scene Group, one Group Output, low-alpha purple annotation styling, and no nested groups.
- Safety presets should cap known expensive combinations instead of merely renaming an unsafe state.

## Next

- Sub-phase 1I packages Industrial Lattice as the compact beginner-facing official example.
