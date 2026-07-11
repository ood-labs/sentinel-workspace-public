# Living Room Pass 2 — Crash Recovery

Recovered the modular living-room scene after a live shader hot-reload crash and established a safer refinement workflow.

## Changes

- Removed nested SDF visibility raymarches from the seating and media lighting paths.
- Kept material microtexture, normal variation, slimmer furniture radii, cushion piping, rug trim, wall slats, improved plant geometry, artwork placement, and stronger grounding.
- Integrated modules serially with the renderer and grade disabled during compilation.
- Restored the subdued material and grade palette.
- Updated the Performance preset to 640x360, 64 ray steps, and 1.8 AO for stable interactive Fly navigation.
- Preserved Fly as the default camera mode and the established room-entry camera pose.
- Re-bundled the six-node project from the verified live graph.

## Proof

- All source and bundled modules pass `compile_check` with no lints.
- Six pipelines healthy with seven expected graph links.
- Renderer and grade produce fresh 640x360 output.
- Live graph profile recovered to approximately 60 fps with no hotspots.
- Recovery capture: `captures/living_room_pass2_safe_tuned.png`.

## Follow-up

Run future high-fidelity evaluations through temporary capture overrides or a deliberately selected Fidelity preset. Do not edit/reload heavy renderer shaders while the graph is dispatching at evaluation resolution.
