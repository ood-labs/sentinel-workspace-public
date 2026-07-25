---
type: devlog
date: 2026-07-25
status: in_progress
approval: pending
summary: "Refresh the private workspace with approved Phase 99.G audio hardening guidance"
---

# 2026-07-25 - Phase 99.G audio hardening workspace refresh

## Progress saved

- Fast-forwarded the clean private workspace against `origin/main`.
- Audited Sentinel from the prior Phase 99.F anchor through approved Phase
  99.G commit `468fa3a378d7dc52e14115d229524c620c94a3dc`.
- Corrected Spectrum and Mel consumer guidance to use
  `_DataN_Generation`, `_DataN_ValueCount`, and `_DataN_HopCapacity`.
- Documented chronological ring catch-up, stereo analysis semantics, adaptive
  detector signal gating, and the separation between capture health and
  content presence.
- Added the Audio In diagnostics contract for endpoint identity, activity,
  packet freshness, retries, migrations, device loss, gap fill, overruns, and
  silence duration.
- Added rolling `cook_hz`, `cooks_in_window`, and `cook_window_ms` guidance to
  the MCP and performance-proof surfaces.
- Added a resolution table to the CRYOGRAM field report separating landed
  99.G repairs from deferred analysis ideas.
- Kept `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` byte-identical, and kept both
  agent skill trees byte-identical.
- Advanced the sync anchor through the final Phase 99 closeout commit.

## Availability boundary

- The workspace anchor continues to record installed build 0.5.44.
- The verified 0.5.49 installer remains a local unpublished candidate.
- Published stable 0.5.46 and nightly 0.5.48 builds do not include Audio In.
- Agents must require an `audio` entry from live
  `sentinel_pipeline action=list_types` before creating the node.
- No new top-level MCP tool or action was introduced by Phase 99.G.

## Still in progress

- Promote the curated private documentation to `sentinel-workspace-public`
  when requested.
- Regenerate Sentinel's installer workspace mirror only after the public
  repository carries the promoted documentation.
- Remove the Phase 99 availability caveat after an installer containing Audio
  In is published and installed.

This is a documentation refresh checkpoint, not a phase or subphase completion.
