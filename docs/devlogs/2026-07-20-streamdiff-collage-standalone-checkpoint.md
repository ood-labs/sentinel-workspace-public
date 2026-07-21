---
type: devlog
date: 2026-07-20
session_end: "19:52"
phase: examples
subphase: streamdiff-collage-standalone
status: in-progress
approval: pending
summary: "Extracted the approved rapid food-poster build into a distinct portable StreamDiff Collage example"
note_created: true
updated: 2026-07-20
---

**Goal**

Preserve the approved rapid food-collage poster as a standalone example whose name and package no longer imply the obsolete Fruit Atlas workflow.

**Work Done**

- Loaded the approved `fruit_atlas_scatter` poster graph without modifying its source project.
- Renamed all five live pipeline identities to Collage-specific names through Sentinel so graph links, Scene Group membership, and preset pipeline references were rewritten safely.
- Renamed the Scene Group to `STREAMDIFF COLLAGE` and retained `Default` as its active preset.
- Saved a new `projects/streamdiff_collage/streamdiff_collage.sentinel` project with Module bundling enabled.
- Bundled only the two active authored dependencies as `modules/Collage_Guide` and `modules/Poster_Accumulator`; no Atlas, Fruit LFO, depth, or 3D card-renderer assets were copied.
- Cleared inherited dock-layout history and corrected stale panel anchors in the new saved file.
- Added a standalone README, root project index entry, and a current 1080x1350 output proof.

**Runtime Proof**

- Sentinel 0.5.41 loaded the source graph with all five pipelines healthy before extraction.
- The renamed Scene Group reports exactly five renamed pipelines and six presets: Default, Machine Gun, Giant Cuts, Night Press, Freeze Frame, and Performance.
- Machine Gun recalled 52 values with five bypass flags and no skipped pipelines; Default then recalled successfully to restore the intended handoff state.
- The Poster Accumulator produced a 1080x1350 proof capture showing accumulated food cutouts, overlapping frames, negative-space rectangles, and print misregistration.
- A cold load of the new standalone file resolved both relative Module directories, restored active `Default`, rebuilt the five-link graph, and reported all five pipelines healthy.

**Remaining Work**

- Keep the original Fruit Atlas path untouched until a separate decision is made about restoring or retiring that historical official example.

**Cross-References**

- Project: `projects/streamdiff_collage/streamdiff_collage.sentinel`
- Documentation: `projects/streamdiff_collage/README.md`
- Proof: `projects/streamdiff_collage/proof/output.png`
