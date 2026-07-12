# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-12
- sentinel_commit: 52ac446da78d1fcee70be50e75832bf42d740469
- sentinel_commit_summary: merge: Properties global reset into master
- installed_build: 0.5.29
- pending_caveats:
  - Authored viewport events (Phase 88: viewport.interactions "events", viewport.input, bindings) are documented with a "builds newer than 0.5.29" caveat in the agent manuals, module-pipeline knowledge, and module-authoring skill; remove the caveats once an installer ships Phase 88.
  - The sentinel repo seed edits behind this refresh are uncommitted at sync time; if a release is built before they land, provisioning will regress these workspace docs (see the workspace-refresh skill's regression note).
