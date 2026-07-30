---
type: devlog
date: 2026-07-30
phase: 6
subphase: 6N
status: complete
approval: pending
session_start: "07:55"
session_end: "08:16"
summary: "Assemble and clean-check the curated public workspace seed"
note_created: true
updated: 2026-07-30
---

## Goal

Turn the approved Phase 6 project slices into a committed public-workspace seed
that a newly placed agent can experience from a clean checkout.

## Work Done

- Reduced `projects/` to the twelve distributable projects plus the explicitly
  review-only `showcase_gallery`.
- Removed the five planned public exclusions, eleven additional non-curated
  project directories, obsolete duplicate project modules, and exclusive
  Procedural Building dependencies.
- Removed seven unreferenced Living Room legacy media files while preserving
  the approved procedural graph.
- Finalized the public README, synchronized entry manuals, portable Scientific
  Organism preset paths, and generated UI headers.
- Added reusable exact-set planning and release-audit tools covering secrets,
  links, file sizes, asset rights, and version/capability metadata.
- Committed the content assembly as `e6464ab1784ac51a0cedacafd3c8b4b51f2d54c0`.
- Created a separate detached checkout at that exact commit and reran the
  official validator, exact-set plan, and release audit with a clean Git status.

## Decisions Made

- The public seed contains only the approved distributable lineup; the gallery
  remains review-only and cannot be promoted.
- Unreferenced media with unresolved value or rights does not ship merely
  because it exists in earlier history.
- The dirty authoring worktree is not used as agent-experience proof. The
  exact-commit checkout is the authority.

## Approvals & Locks

- The user approved each included creative project and explicitly requested the
  complete local release assembly and clean agent-test state.
- The user confirmed redistribution clearance for the dancer clip and
  replacement Jellybeans image.
- No public push, tag, or release is authorized. G13 remains pending.

## Issues Encountered

- The release worktree looked visually final while still containing hundreds of
  staged removals, uncommitted tooling, and two untracked files.
- Living Room carried 92,503,555 bytes of duplicated legacy photo/video media
  despite its approved graph having zero external media references.

## Next Steps

- Let an agent operate Sentinel from the clean candidate checkout.
- Review the complete candidate at G13 and explicitly authorize or decline the
  public push.

## Cross-References

- `docs/phases/phase-6-public-workspace-curation-refresh.md`
- `docs/reviews/phase-6/release-candidate.json`
- `tools/audit-public-release.ps1`
- `tools/validate-official-examples.ps1`
