# Topographic Operations proof

Program proof was refreshed on 2026-07-27 from the live Sentinel 0.5.49
project. The standalone `signal` node now uses a fixed 480 x 270 passive bus
preview with zero authored controls; all editing is in Properties. The two
editor captures remain the 2026-07-15 interaction proof.

- `survey.png`, `threat.png`, `night-vision.png`, `minimal.png`, and `performance.png` show the five visually distinct Scene Group presets.
- `operations-console.png` is historical evidence for the superseded Signal
  Canvas and is not the current shipping interface.
- `signal-bus.png` is the current 480 x 270 passive preview.
- `priority-node-editor.png` shows the host-selectable priority-node editor.
- `survey-label-editor.png` shows the host-selectable label editor.
- Current live proof reports Standard panel mode, a 480 x 270 render target,
  and healthy advancing frames for `signal`. Module UI validation reports zero
  controls.
- Synthetic host edit transactions moved both a priority node and a survey label through the real begin/preview/commit path.
- `Priority Baseline` and `Priority Offset Study` recalled distinct durable node offsets with no skipped values; each preset carries both the 192-byte offset buffer and 48-byte edit-state buffer.
- Final structure: fifteen original semantic Modules, one Conductor, one Group
  Output, one flat Scene Group, zero child groups, eight live group controls,
  five recalled group presets, and zero Signal Bus gestures.
