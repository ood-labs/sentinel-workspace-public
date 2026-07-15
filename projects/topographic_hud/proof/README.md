# Topographic Operations proof

Proof captured on 2026-07-15 from the live Sentinel project.

- `survey.png`, `threat.png`, `night-vision.png`, `minimal.png`, and `performance.png` show the five visually distinct Scene Group presets.
- `operations-console.png` shows the responsive cyan-and-orange Signal Canvas.
- `priority-node-editor.png` shows the host-selectable priority-node editor.
- `survey-label-editor.png` shows the host-selectable label editor.
- Manual and Conductor authority were exercised live; their published energy and sweep values changed while the expression-driven final HUD remained healthy.
- Synthetic host edit transactions moved both a priority node and a survey label through the real begin/preview/commit path.
- `Priority Baseline` and `Priority Offset Study` recalled distinct durable node offsets with no skipped values; each preset carries both the 192-byte offset buffer and 48-byte edit-state buffer.
- Final structure: fifteen original semantic Modules, one Conductor, one Group Output, one flat Scene Group, zero child groups, eight group controls, and five group presets.
