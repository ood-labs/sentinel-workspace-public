# Industrial Lattice proof

Proof captured from the live Sentinel project on 2026-07-15.

- `01-box-frame.png`, `02-heavy-steel.png`, `03-concrete-haze.png`, `04-fidelity.png`, and `05-performance.png` show the five complete Scene Group presets.
- `camera-hero.png`, `camera-lookup.png`, `camera-deep-grid.png`, and `camera-fly.png` show the four shared-camera framings.

Runtime assertions:

- The final graph contains two bundled authored Modules, four Camera nodes, one Camera Switcher, and one Group Output in a single flat Scene Group with zero child groups.
- The Group Output receives the real post texture and reports a healthy 1280x720 Fidelity output with increasing frames.
- Eight exposed controls cover structure, junction detail, surface, lighting, fog, and bloom without duplicating a custom UI.
- Each of the five group presets recalled 156 pipeline parameters, eight exposed parameters, and eight bypass flags with no skipped child state.
- The two required project-scoped node presets capture the approved lattice core and monochrome finish explicitly.
- Fidelity uses 1280x720, 4x4 AA, shadows, panels, junctions, and bolts. Performance uses 960x540, 1x1 AA, no shadows, no bolts, a shorter march distance, and reduced surface detail.
- Both bundled Module directories passed Sentinel's real `compile_check` with zero lints.
- No object descriptors or picking surface are declared because the infinite repeated field has no stable unique instances.

No engine packs are required.
