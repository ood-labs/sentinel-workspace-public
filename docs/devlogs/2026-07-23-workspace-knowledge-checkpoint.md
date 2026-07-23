---
type: devlog
date: 2026-07-23
status: in_progress
approval: pending
summary: "Checkpoint creative-source, Features-performance, graph-layout, and authored-UI guidance"
---

# 2026-07-23 - Workspace knowledge checkpoint

## Saved

- Clarified that built-in diagnostic imagery is limited to isolated technical diagnostics and must not enter visible creative, tracking, Features, or AI chains.
- Documented when whole-graph auto-layout is appropriate after later topology surgery while preserving visible one-node-at-a-time construction.
- Added explicit performance gates for Features and other heavy nodes, including baseline profiling, one-task-at-a-time tuning, bounded thresholds, and immediate rollback on regressions.
- Added the 1280x720 program plus 480x270 analysis-proxy pattern and the coordinate-normalization contract for downstream data consumers.
- Added semantic guidance for mapping blobs, corners, and lines through a previewable planning stage rather than rendering every record literally.
- Clarified that authored Canvas interfaces should prioritize direct manipulation and spatial performance gestures instead of duplicating ordinary Properties controls.
- Documented the canonical fixed-resolution Program plus flexible aspect-correct editor-Canvas architecture.

## Validation

- `git diff --check` passed for all four knowledge files.
- Verified the new guidance sections and diagnostic-source rule are present at their intended locations.

## Deliberately not included

- The live `scientific_organism.sentinel` save-state diff contains workspace-local and absolute Module paths plus volatile runtime state, so it is not part of this portable checkpoint.
- Untracked root Module experiments remain in progress and are not committed until they have a validated portable project or standalone acceptance contract.

## Still in progress

- Package and validate any exploratory Module chains that should graduate into maintained examples.
- Re-save Scientific Organism only from a portable bundled configuration if its live tuning changes are intentionally retained.
