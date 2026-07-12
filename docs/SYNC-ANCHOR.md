# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-12
- sentinel_commit: b4159c69309ee4dfb0376ad8a4e32704d0628e8b
- sentinel_commit_summary: docs(release): close 0.5.30 dist build
- installed_build: 0.5.30
- pending_caveats:
  - The sentinel repo seed edits behind this refresh are uncommitted at sync time; if a release is built before they land, provisioning will regress these workspace docs a third time (it already happened with 0.5.29 and 0.5.30). Commit the sentinel seeds.
