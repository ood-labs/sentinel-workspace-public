# Living Room proof

This proof set was captured from the running saved project on 2026-07-15.

- `plan_conversation.png` and `plan_offset_sofa.png` show the two durable
  project-scoped furnishing presets. The sofa and its three cushions move as one.
- `render_conversation.png` and `render_offset_sofa.png` show the corresponding
  graded 3D output.
- `camera_0.png` through `camera_3.png` prove four visibly distinct shared Camera
  Switcher selections.
- `scene_daylight.png` and `scene_warm_evening.png` prove distinct whole-scene
  lighting/camera/grade recalls.
- `lighting-desk.png` shows the responsive authored Lighting Canvas, its four
  manifest-aligned sliders, thin plan geometry, and six live light records.
- `bundle/` contains the captured final output, graph, link inventory, pipeline
  health, graph profile, expressions, and Sentinel window evidence.

Runtime assertions recorded during capture:

- `LR Group Output`: healthy, 1280x720 BGRA8, frames increasing.
- `LR SDF Renderer` Performance: 960x540, 64 ray steps, quality mode 0.
- `LR SDF Renderer` Fidelity: 1280x720, 112 ray steps, quality mode 1.
- `LR Furnishings`: 12 selectable logical objects and one 384-byte durable state
  buffer (12 records x 32 bytes).
- `LR Lighting`: Canvas content and render extents matched at 1009x615 before the
  final save and 1033x667 after reload; all six Light Records were enabled and the
  live graph profile reported no hotspot.
- With the renderer bound to `LR Camera Switcher`, two settled captures that moved
  its private camera from `[-20,-10,-20]` to `[20,10,20]` were pixel-identical
  (`PSNR = infinity`). Named Conversation and Reverse Media selections produced
  `20.625590 dB` instead, proving the shared camera changes the image; Left Side
  was restored afterward.
- Both furnishing presets recalled ordinary parameters and `durable_state` with no
  skipped fields; the offset preset also recalled successfully onto a fresh
  compatible instance.
- A temporary 384-byte state guard preserved a live twelve-object arrangement,
  both official presets were recalled, and guard recall restored every recorded
  offset and yaw exactly before the temporary preset was deleted.
- The portable project was saved with the zero-offset Conversation baseline and
  loaded from disk with no unresolved module directories. All six Modules compiled
  successfully, remained healthy, and advanced frames during a timed readback. A
  temporary library guard then restored the pre-save live arrangement exactly and
  was deleted.
- Source and bundled furnishing Modules passed the real eight-pass compile check
  with zero lints.

No engine packs are required.
