---
type: devlog
date: 2026-07-23
phase: creative-examples
subphase: scientific-organism
status: complete
approval: approved
session_start: "2026-07-22 21:50"
session_end: "01:19"
summary: "Shipped the Scientific Organism Features-driven performance instrument"
note_created: 2026-07-23
updated: 2026-07-23
---

# Scientific Organism Example

## Goal

Build an ambitious TouchDesigner-style Sentinel composition as a visible chain
of semantic authored nodes, with the real Features pipeline driving meaningful
downstream structure and polished interfaces for editing and performance.

## Work Done

- Built a fifteen-node live instrument from Seed Lab through Biotic Source,
  analysis proxy, native Features, temporal agents, topology, synaptic field,
  canonical renderer, memory, relief, archive, semantic glyphs, final grade,
  performance deck, and Scene Group output.
- Kept the Features branch at 480x270 while preserving a 1280x720 Program lane;
  tuned bounded blobs, corners, and lines against live profiles.
- Added a follow-panel Seed Lab with persistent stimuli, direct dragging,
  per-seed wheel radius, Alt+wheel strength, and a non-overlapping right-aligned
  toolbar.
- Fixed the Biotic Source simulation coordinate contract by deriving the
  half-resolution field extent from the texture rather than `_Resolution`.
- Captured still, motion, raw-field, interaction, graph, health, and performance
  proof. The signed-off motion recording contains 478 frames with zero drops.
- Normalized the saved project to one project-local Module set, removed
  machine-specific paths from the committed JSON, and compile-checked all
  thirteen bundled authored Modules.

## Decisions Made

- Keep structured Stimuli records normalized to the canonical 16:9 stage.
- Keep the Biotic Source feedback field at half resolution for performance, but
  derive its UVs, bounds, and aspect from its actual texture dimensions.
- Treat raw intermediate captures as required coordinate proof whenever a later
  full-resolution overlay could conceal an upstream mapping error.
- Preserve dense numeric shaping in Properties and use Canvas only for spatial
  editing and performative macro gestures.

## Approvals & Locks

- The user approved this run as a solid reusable example.
- The technical monochrome scientific-instrument direction, warm accent, real
  Features causality, and modular graph structure are the signed-off identity.

## Issues Encountered

- Fixing Seed Lab panel mapping aligned its marker but did not align Biotic
  Source deformation. The real cause was a half-resolution feedback pass using
  the root 1280x720 `_Resolution`, which doubled normalized positions and made
  only the upper-left quarter effective.
- Repeated checkpoints accumulated numbered bundle copies and later saves
  restored workspace-relative Module paths. The committed example was
  explicitly normalized to one clean project-local bundle and verified again.
- The initial Seed Lab toolbar occupied the title region; moving both manifest
  control rectangles and generated UI geometry to the upper-right resolved it.

## Next Steps

- Cold-load the committed project from a clean checkout before promoting it to
  the public workspace or official example gallery.
- If promoted, retain the curated proof set and avoid committing local
  intermediate captures or obsolete numbered checkpoint bundles.

## Cross-References

- `projects/scientific_organism/README.md`
- `projects/scientific_organism/scientific_organism.sentinel`
- [[2026-07-22-signal-cut-feature-analysis]]
- [[../lessons]]
- [[../state]]
