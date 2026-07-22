---
type: devlog
date: 2026-07-22
phase: workspace
subphase: procedural-building-system-example
status: complete
approval: approved
session_start: "2026-07-21 20:00"
session_end: "04:53"
summary: "Shipped a modular procedural building example and codified its reusable construction workflow"
note_created: true
updated: 2026-07-22
---

**Goal**

Build and refine a detailed modular procedural building system, finish it as a curated example, and turn the session's interaction, camera, rendering, and StreamDiff discoveries into a reusable construction standard.

**Work Done**

- Built a six-node graph: editable massing, facade, materials, lighting, architectural renderer, and optional StreamDiff detail/relight.
- Published typed `PNodes`, facade, material, and light records so the renderer consumes semantic data instead of hidden intermediate textures.
- Added meaningful Canvas previews and host-backed spatial selection, picking, durable state, and drag behavior for massing, facade, and lighting.
- Corrected facade feature placement so its visible marker, selected bay/floor element, descriptor, picker, and drag inversion share one mapping.
- Replaced dense authored slider rails with full-width spatial canvases while preserving every tuning parameter in Properties.
- Locked the renderer to Sentinel's native Fly camera contract and removed alternate renderer-authored camera modes.
- Kept linear HDR shading internal while publishing an 8-bit sRGB color output and a separate native depth output.
- Rewired StreamDiff so sRGB feeds Video/Style and native depth feeds Depth ControlNet, with automatic depth disabled, live processing, and frame skip one.
- Archived obsolete bundled module copies from the project folder into ignored `scratch/` storage and retained only the active portable graph.
- Added the project to the repository allowlist, example index, official-example validator configuration, proof collection, and reusable modular-procedural authoring guidance.

**Decisions Made**

- Canvas is for spatial manipulation; Properties owns dense numeric and color tuning.
- Every semantic data node must remain independently understandable through its own live preview.
- Render, descriptor, pick, and drag paths must share one coordinate transform.
- A procedural renderer must be a useful deterministic endpoint before optional AI interpretation is added.
- The renderer owns one native camera and saves Fly as the default.
- Display color and structural depth are separate consumer contracts.

**Approvals & Locks**

- The final full-width Canvas direction, dark monochrome styling, compact tool strips, Properties-based tuning, and optional StreamDiff branch were explicitly approved during the session.
- The project is approved as the canonical technical reference for future modular procedural systems.

**Issues Encountered**

- Fixed off-center facade selection caused by mismatched semantic/elevation transforms.
- Preserved lighting meaning while expanding the Canvas by migrating persistent normalized positions through world space.
- Worked around the zero-control `_ViewportControlFlags` compile edge case by using a control-free UI include set in the Material Library.
- Removed fragile fixed normalized slider rails after aspect-ratio testing showed they did not scale cleanly.
- Corrected StreamDiff's input color space and replaced duplicated color conditioning with native procedural depth.

**Verification**

- All five authored Module directories passed `sentinel_pipeline compile_check` without lints.
- All six live pipelines reported healthy with advancing frames and preview outputs.
- Massing, facade, material, and lighting Canvas outputs were captured after the slider removal.
- Synthetic provider picks hit the exact visible facade and lighting handles without physical mouse automation.
- Renderer proof includes aligned 1920x1080 sRGB and native-depth outputs.
- The repository static official-example validator passes for `procedural_building_system`.

**Next Steps**

- Start the next, more ambitious modular procedural system from `knowledge/modular-procedural-systems.md`.
- Extend semantic record types and editors only where each new node remains independently inspectable and reusable.
- Revisit responsive authored parameter layouts only when Sentinel can keep host hit rectangles and shader layout synchronized.

**Cross-References**

- `projects/procedural_building_system/README.md`
- `projects/procedural_building_system/CAMERA-TEMPLATE.md`
- `projects/procedural_building_system/STREAMDIFF-REFERENCE.md`
- `knowledge/modular-procedural-systems.md`
- `docs/official-example-standard.md`
- `.agents/skills/modular-scene-authoring/SKILL.md`
