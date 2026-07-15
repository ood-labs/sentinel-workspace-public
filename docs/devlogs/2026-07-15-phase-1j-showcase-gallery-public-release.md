---
type: devlog
date: 2026-07-15
phase: 1
subphase: 1J
status: complete
approval: pending
summary: "Ship the portable seven-look Showcase Gallery and local public release"
---

## Done

- Built `projects/showcase_gallery/showcase_gallery.sentinel` with seven flat aesthetic Scene Groups, one groups-mode Mux, 51 bundled active Modules, seven final-output captures, and runtime crossfade/freeze proof in `projects/showcase_gallery/proof/runtime-switching.json`.
- Baked each standalone active group preset into the imported graph and removed 50 stale source-group expressions while preserving live LFO/control-output expressions. Private and public validators pass all nine official projects with zero errors or warnings; public release commit: `4dc72d2`.

## Next

- Run the phase-wide audit and `/end-session` closeout for Phase 1.

## Post-landing audit + fixes

Three parallel reviewers audited code/safety, specification alignment, and verification coverage. They found two implementation blockers, four regression-prevention gaps, and two missing release-proof slices. All small workspace-owned fixes were applied; the clean-public runtime sweep exposed one Sentinel application crash that is recorded but cannot be fixed in this workspace phase.

- Fruit swarm picking now tests every rendered clone trajectory and maps hits back to the owning durable atlas-card record. Both standalone and Gallery copies compile through Sentinel with six passes and no lints; live synthetic picks hit multiple moving logical fruit ids.
- Gallery repair now reads strict UTF-8, writes through an atomic replacement, preserves per-pipeline enabled/bypass state, and no longer corrupts the seven annotation separators. A disposable regeneration baked 85 bypass states and retained all seven UTF-8 annotation bodies without mojibake.
- The validator now rejects workspace-escaping Module paths, duplicate root project files, malformed Gallery output ownership/links, missing or non-Groups Mux configuration, incomplete allow-lists, and disabled `solo_upstream`. The deterministic fixture exercises each failure plus real LF-to-CRLF generated-UI hash invariance.
- The Face Collage contract and standard now match the user-approved restrained design: one Scene Group control surface, no artificial clone selection/gizmos, and no separate Director Canvas. Its README now includes concrete tracking, engine-pack, and black-output diagnostics.
- Mid-fade retarget proof records Industrial -> Topographic -> Face. At retarget, `from_group` becomes `snapshot`, demonstrating current-image continuity; the 3.96-second MP4 and state samples are retained under `projects/showcase_gallery/proof/`.
- A detached clean public worktree at `07f26bb` was clean before load. Interaction Lab, Living Room, and Face loaded with zero unresolved paths and healthy frame progression; Fruit loaded with zero unresolved paths. Sentinel then exited during the Topographic post-load sample. The app was relaunched without a kill action, the private Gallery was restored, and its two contention-prone Modules compiled successfully one at a time. Full evidence is in `clean-public-runtime-audit.json`.

Items considered and rejected: descriptor pivots remain world-space because that is the host contract; only clone coverage in the pick loop was wrong. The audit did not add more project dashboards, nested Scene Groups, extra output nodes, or artificial picking. A reusable machine-readable runtime harness and the Sentinel cold-load crash belong in later application/tooling work rather than this content-only phase.
