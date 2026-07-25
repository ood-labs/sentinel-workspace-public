# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-24
- sentinel_commit: 57b6dc4b3d2991120787b9459d6f12fd21167930
- sentinel_commit_summary: feat(audio): add stock reactive modules
- installed_build: 0.5.44
- pending_caveats:
  - The recorded installed build remains 0.5.44. Phase 96 through Phase 98 and synthetic ImGui input injection are documented with live-discovery or version gates; use the live capabilities surface on this installation.
  - Phase 99 Audio Reactivity is documented from feature/audio-reactivity through sentinel commit 57b6dc4b3d2991120787b9459d6f12fd21167930. Published stable 0.5.46 and nightly 0.5.48 builds do not carry Audio In; require an `audio` entry from live `sentinel_pipeline list_types` before using it.
  - The 0.5.31-to-0.5.36 delta (Phases 89.1 through 92) was never fully audited page-by-page; the 2026-07-22/23 sync covered Phases 94-98 and the user's curation but inherited that gap. A full-delta audit pass remains open.
  - Workspace scene/project content does not yet use binds; a follow-up content pass will adopt them.
  - node_examples remains on the public repo's phase-94-review branch pending user review; public main and the installer template exclude it.
