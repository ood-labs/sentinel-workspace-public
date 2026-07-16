# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-12
- sentinel_commit: ebbbbac2f2a8c22f08cf1aacca534c4681825720
- sentinel_commit_summary: docs(release): 0.5.31 dist build devlog and status updates
- installed_build: 0.5.31
- pending_caveats:
  - The sentinel repo seed edits behind these refreshes are uncommitted at sync time; installers built without them regress the workspace on provisioning (already happened with 0.5.29, 0.5.30, and the dev build). Commit the sentinel seeds.
  - 2026-07-16: Parameter Binds (Phase 91) documentation added out-of-band in expressions-and-drivers.md, FEATURE-MAP.md, the manuals, and the mcp-automation skill, sourced from and mirrored to sentinel-workspace-public (now the seed source of truth; the tools/dist seed paths named above are retired). The anchor commit was NOT advanced: the full 0.5.31-to-0.5.36 delta (Phases 89.1 through 92) is still unaudited and needs a full refresh. The sentinel repo template mirror (tools/dist/workspace) was not re-synced yet because a phase loop holds that tree; run tools/sync_workspace_template.py after it completes.
  - Workspace scene/project content does not yet use binds; a follow-up content pass will adopt them.
