# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-23
- sentinel_commit: 85f23992
- sentinel_commit_summary: docs(workspace-flow): flip refresh doctrine to public-repo source of truth
- installed_build: 0.5.44
- pending_caveats:
  - Phase 96 (plain-PowerShell empty launch command, matching Embedded Terminal settings tabs) and Phase 97 (unlicensed bug reports) are documented in ui-interactions.md and the sentinel-bug-report skill but ship in no installer yet; 0.5.44 carries Phase 95 only. Remove this caveat once the next nightly installs.
  - The 0.5.31-to-0.5.36 delta (Phases 89.1 through 92) was never fully audited page-by-page; the 2026-07-22/23 sync covered Phases 94-98 and the user's curation but inherited that gap. A full-delta audit pass remains open.
  - Workspace scene/project content does not yet use binds; a follow-up content pass will adopt them.
  - node_examples remains on the public repo's phase-94-review branch pending user review; public main and the installer template exclude it.
