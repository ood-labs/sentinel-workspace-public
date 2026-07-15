---
type: devlog
date: 2026-07-15
session_start: "04:23"
session_end: "08:09"
phase: 1
subphase: closeout
status: complete
approval: pending
summary: "Close Phase 1 implementation after a full audit, release hardening, and local public promotion"
note_created: 2026-07-15
updated: 2026-07-15
---

# Phase 1 Closeout

## Goal

Finish all official example modernizations, assemble the seven-look Showcase Gallery, audit the complete phase, promote the portable release locally, and leave both repositories in a recoverable handoff state without pushing.

## Work Done

- Completed sub-phases 1A-1J with one flat Scene Group per aesthetic example, no nested groups, exactly one Group Output per aesthetic look, curated controls/presets, current READMEs, and representative proof.
- Built and proved the groups-mode Showcase Gallery with seven look groups, exact allow-list switching, 0.75-second fades, current-image retarget continuity, and non-selected StreamDiff freezing.
- Ran parallel code/safety, spec/plan, and verification audits. Fixed clone-aware Fruit picking, Gallery UTF-8 regeneration and bypass baking, workspace path traversal, duplicate project files, and Gallery-specific structural validation.
- Promoted the release to `sentinel-workspace-public`, which is locally committed through `d2ea3a0`; no remote push occurred.
- Recovered Sentinel after the clean-public cold-load crash without issuing a kill action, restored the private Gallery, and compiled `Fruit_LFO` plus `dada_render` successfully in series.

## Decisions Made

- Face Collage remains a restrained procedural instrument controlled by its Scene Group, without clone gizmos or a separate Director Canvas.
- Scene Groups remain flat until nested groups are explicitly supported. Annotation colors stay user-owned and low-alpha.
- The phase is implementation-complete but remains approval-pending because the clean-public runtime sweep crashed Sentinel before every project could be resampled.
- Public publication remains a separate user decision; local commits do not authorize a network push.

## Approvals & Locks

- Living Room's final architecture, furnishings, camera layout, lighting blueprint, and interaction direction were accepted by the user.
- The user directed the no-nesting rule, Group Output-only endpoint rule, restrained UI rule, low-alpha purple annotation treatment, and Face Collage simplification; these are now part of the governing contracts.
- Existing Interaction Lab and `modules/quasi_*` work remains untouched and unstaged.

## Issues Encountered

- Imported Scene Group expressions referenced source annotation ids that were absent after project import, forcing imported parameters toward zero until active preset values were baked.
- Windows PowerShell's implicit text decoding corrupted UTF-8 annotation separators during Gallery regeneration; strict UTF-8 reads and atomic replacement fixed it.
- Gallery cold-load compilation timed out for `Fruit_LFO` and `dada_render` under concurrency but both compiled successfully when reloaded serially.
- A detached clean-public load sequence exited Sentinel during the Topographic HUD post-load sample. This requires Sentinel application investigation and is outside the workspace-only phase scope.

## Next Steps

1. Investigate the Topographic cold-load crash in the Sentinel application repository using the retained sequence in `projects/showcase_gallery/proof/clean-public-runtime-audit.json`.
2. Rerun the remaining clean-public runtime-load samples and move Phase 1 from approval-pending to approved if they pass.
3. Push the public repository only after explicit user authorization.

## Cross-References

- [Phase 1 contract](../phases/phase-1-official-examples-modernization.md)
- [Official example standard](../official-example-standard.md)
- [Gallery release devlog](2026-07-15-phase-1j-showcase-gallery-public-release.md)
- [Gallery README](../../projects/showcase_gallery/README.md)
