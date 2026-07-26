# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-25
- sentinel_commit: 468fa3a378d7dc52e14115d229524c620c94a3dc
- sentinel_commit_summary: docs(audio): approve Phase 99 through 99.G
- installed_build: 0.5.44
- pending_caveats:
  - The recorded installed build remains 0.5.44. Phase 96 through Phase 98 and synthetic ImGui input injection are documented with live-discovery or version gates; use the live capabilities surface on this installation.
  - Phase 99 Audio Reactivity is documented through approved 99.G at sentinel commit 468fa3a378d7dc52e14115d229524c620c94a3dc. The verified 0.5.49 installer remains a local unpublished candidate. Published stable 0.5.46 and nightly 0.5.48 builds do not carry Audio In; require an `audio` entry from live `sentinel_pipeline list_types` before using it.
  - The 0.5.31-to-0.5.36 delta (Phases 89.1 through 92) was never fully audited page-by-page; the 2026-07-22/23 sync covered Phases 94-98 and the user's curation but inherited that gap. A full-delta audit pass remains open.
  - Workspace scene/project content does not yet use binds; a follow-up content pass will adopt them.
  - node_examples remains on the public repo's phase-94-review branch pending user review; public main and the installer template exclude it.
