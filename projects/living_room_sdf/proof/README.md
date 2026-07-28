# Living Room proof

This proof set was refreshed from the running saved project on 2026-07-27.

- `plan_conversation.png` and `plan_offset_sofa.png` show the two durable
  project-scoped furnishing presets. The sofa and its three cushions move as one.
- `render_conversation.png` and `render_offset_sofa.png` show the corresponding
  graded 3D output.
- `camera_0.png` through `camera_3.png` prove four visibly distinct shared Camera
  Switcher selections.
- `scene_daylight.png` and `scene_warm_evening.png` prove distinct whole-scene
  lighting/camera/grade recalls.
- `lighting-desk.png` shows the responsive sui3 Lighting Canvas, its four
  manifest-aligned sliders, thin plan geometry, and six live light records.
- `bundle/` contains the captured final output, graph, link inventory, pipeline
  health, graph profile, expressions, and Sentinel window evidence.

Runtime assertions recorded during capture:

- `LR Group Output`: healthy, 1280x720 BGRA8, frames increasing.
- `LR SDF Renderer` Performance: 960x540, 64 ray steps, quality mode 0.
- `LR SDF Renderer` Fidelity: 1280x720, 112 ray steps, quality mode 1.
- `LR Furnishings`: 12 selectable logical objects and one 384-byte durable state
  buffer (12 records x 32 bytes).
- `LR Furnishings`: a real desktop drag moved object 1 from
  `[-0.65, 0.66, 2.35]` to `[0.85, 0.66, 1.85]`; the 384-byte edit survived a
  bundled save and fresh-process reload.
- `LR Lighting`: Canvas content and render extents matched at 1222x488 and
  366x429. All four rails reached their quarter/three-quarter parameter targets
  with matching pixel heads, all six Light Records remained live, and the
  current profile reported no hotspot.
- `LR Architecture`: 13 live PNode records; an actual middle-button desktop drag
  panned the control-free events Canvas and changed 12.62% of its narrow capture.
- With the renderer bound to `LR Camera Switcher`, two settled captures that moved
  its private camera from `[-20,-10,-20]` to `[20,10,20]` were pixel-identical
  (`PSNR = infinity`). Named Conversation and Reverse Media selections produced
  `20.625590 dB` instead, proving the shared camera changes the image; Left Side
  was restored afterward.
- All six whole-scene presets recalled 193 values with no failure. `Performance`
  remained healthy at 960x540; the other five settled at 1280x720.
- A temporary 384-byte state guard preserved a live twelve-object arrangement,
  both official presets were recalled, and guard recall restored every recorded
  offset and yaw exactly before the temporary preset was deleted.
- The portable project was saved with the zero-offset Conversation baseline and
  loaded from disk with no unresolved module directories. All six Modules compiled
  successfully, remained healthy, and advanced frames during a timed readback. A
  temporary library guard then restored the pre-save live arrangement exactly and
  was deleted.
- Furnishings, Lighting, and Architecture passed the real compile check with
  zero lints, and their Gallery copies match by normalized hash.
- The refreshed proof bundle reported a 95.74% Daylight/Warm Evening image
  difference. Its full-window screenshot was unavailable from the agent session
  and remains operator-unproven; the retained `window.jpg` is prior operator
  evidence, not evidence from this refresh.

No engine packs are required.
