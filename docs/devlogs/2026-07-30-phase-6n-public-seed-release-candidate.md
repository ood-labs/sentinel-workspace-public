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

## Post-Landing Audit + Fixes

The first clean-checkout claim was invalid. A real agent test discovered
`modules/zaha_architectural_renderer` and used it as creative authority. The
release checks had enforced an exact project set but had not enforced an exact
root Module set; `.gitignore` also hid newly created projects from ordinary Git
status. The candidate contained 308 tracked top-level Module directories.

Corrective work:

- Removed the root `modules/` directory completely, including ignored shader
  caches that kept deleted directories physically visible.
- Bundled `data_scope` and `signal_trails` into Interaction Lab and all thirteen
  Scientific Organism dependencies into that project. Rewrote every affected
  saved `project_dir` to `modules/<id>`.
- Removed the review-only Showcase Gallery, the stray root Sentinel project,
  excluded Procedural Building blueprints, stale Gallery tooling, and the
  obsolete `pulse2`/`cryo_pulse` audio-test corpus and harness.
- Changed the release audit to require exactly twelve project directories,
  exactly their configured `.sentinel` files, and zero tracked or filesystem
  root Modules. New projects are no longer hidden by `.gitignore`.
- Regenerated the installed-workspace manifest from an explicit managed-path
  policy: twelve projects, no root Modules, and deletion tombstones for prior
  managed files.
- Updated the manuals, knowledge, and mirrored skills to require
  project-local bundled Modules. Removed obsolete skill frontmatter and passed
  the current skill validator for all eleven public skills.

Proof in the corrective working tree:

- Official validator: 12/12 portable, 73 active project-local Modules, zero
  shared-root dependencies, zero orphan Modules, zero absolute paths.
- Sentinel compile-check: 15/15 moved Modules compiled, with clean manifests and
  zero lints.
- Release regression suite: passed.
- Release audit: exact twelve-project set, zero tracked root Modules, zero
  filesystem root Modules, and exact 702-file workspace manifest. Its remaining
  failures are intentionally the dirty audit tree plus the retained
  `bureau_impossible_signals`, captures, and local `vision.json` evidence.

No commit was created during this audit. The next release step is a corrective
commit, manifest regeneration against that exact commit, and a genuinely fresh
checkout audit. No public push, tag, or release is authorized.

The exact staged index was then exported with `git checkout-index` into a new
disposable repository, committed as a content snapshot, and followed by a
separate manifest-binding commit to prove the non-self-referential release
sequence. That isolated repository reported:

- clean Git status (zero porcelain lines);
- exactly 12 project directories and zero root Module files;
- 12/12 projects portable;
- release regression suite passed;
- release audit passed;
- workspace manifest exact with 702 managed files and its source commit reachable
  as the content commit ancestor.

This proves the staged candidate without deleting or laundering the failed
agent-test evidence. The disposable hashes are proof-only; the public candidate
must still receive its own corrective content commit and manifest-binding commit.
