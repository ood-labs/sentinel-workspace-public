---
type: devlog
date: 2026-07-15
phase: 1
subphase: 1C
status: complete
approval: pending
summary: "Modernize Living Room as the direct-manipulation scene reference"
---

## Done

- Rebuilt the furnishings editor as a full-bleed, aspect-correct Canvas with host-owned selection, durable transforms, move/rotate tools, snapping, fit/reset controls, and 12 logical furnishing assemblies.
- Upgraded the Architecture and Lighting authored panels, added four shared cameras plus a named Camera Switcher, organized the project inside one flat Scene Group, and authored project/node presets for layouts, performance, lighting, grading, and material review.
- Removed historical bundled-module copies, retained only the six active portable modules, refreshed the project guide and proof set, and preserved the user's compact graph arrangement and accepted visual treatment.

## Proof

- Clean project reload resolved all six relative Module paths; every Module compiled successfully, remained healthy, and advanced frames. Canvas render/content sizes matched their dock content, including the Lighting desk at `1033x667`.
- Furnishing node presets restored distinct 384-byte durable layouts. Six Scene Group presets restored complete looks, and a preset-state guard verified exact baseline restoration.
- Shared-camera proof showed private renderer camera overrides had no effect while bound to the Camera Switcher, while Conversation versus Reverse Media produced a finite `20.625590 dB` image difference.
- `tools/validate-official-examples.ps1 -Projects living_room_sdf -Json` passed with six active modules, no orphan modules, no absolute paths, no forbidden artifacts, and no stale generated UI. Full captures and assertions are indexed in `projects/living_room_sdf/proof/README.md`.

## Issue carried forward

- The saved project intentionally removes the one-way Scene Group expressions from the Lighting parameters so authored Canvas edits are not overwritten. Proper bidirectional group/member binding is deferred until Sentinel exposes a native two-way bind contract.
- Human viewport interaction and visual acceptance passed. MCP viewport edit automation still could not begin an edit transaction for this project, so no synthetic edit/undo claim is included.

## Next

- Sub-phase 1D modernizes Face Collage into the polished public-facing instrument reference, then the phase continues through every remaining official example in the contract.
