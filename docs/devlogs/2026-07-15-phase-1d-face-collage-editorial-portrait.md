---
type: devlog
date: 2026-07-15
phase: 1
subphase: 1D
status: complete
approval: pending
summary: "Modernize Face Collage as a restrained editorial portrait example"
---

## Done

- Removed the disliked `Collage Finish` module and replaced it with a restrained editorial post pass feeding one real Group Output.
- Removed the separate Spout output, abandoned collage branches, orphan modules, caches, and all experimental Director, Canvas, picking, clone-selection, and transform work.
- Organized the twelve active nodes inside one flat Scene Group while preserving the user's low-alpha purple annotation color.
- Exposed only six direct member controls, with no duplicate authored UI authority: copies, stamp scale, motion, history, fresh-layer mix, and micro glitch.
- Added four Scene Group presets (`Performance`, `Editorial Drift`, `Temporal Echo`, and `Dense Study`) plus two project-scoped node presets.

## Proof

- All twelve live pipelines are enabled, healthy, running, and advancing frames; the Group Output is the sole final endpoint.
- Every active Module passed the real offline Sentinel compiler without lints.
- Preset recall was exercised live: `Performance` restored two clones, Noise motion, history off, and a 0.008 glitch amount before `Editorial Drift` restored the accepted baseline.
- The graph profile reports StreamDiff and MediaPipe as the only meaningful hotspots; the authored Module chain remains sub-millisecond in the CPU wall-clock profiler.
- `tools/validate-official-examples.ps1 -Projects face_collage -Json` passes with nine active Module dependencies, no orphans, no absolute paths, no forbidden artifacts, and a compact proof bundle.

## Taste rules carried forward

- Use one flat, low-alpha annotation and preserve user-set colors.
- Use the Scene Group as the default control surface; do not add authored dashboards unless the project specifically needs one.
- Never transplant selection, gizmos, or direct manipulation into a project that does not call for it.
- Official examples use Group Output as the sole final endpoint unless a separate output is explicitly requested.
- Keep exposed controls deliberately small and avoid duplicate control authority until true bidirectional binding exists.

## Next

- Sub-phase 1E modernizes Fruit Demo using the same restrained Scene Group and Group Output conventions.
