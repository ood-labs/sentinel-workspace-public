# Workspace Doc Sync Anchor

Read and updated by the sentinel repo `workspace-refresh` skill. It records the sentinel repo commit these workspace docs were last audited against, so the next refresh can scope its work to `git log <sentinel_commit>..HEAD`. Do not edit by hand mid-refresh.

- last_sync_date: 2026-07-11
- sentinel_commit: 390b3302961dfb64e93f023b6f81b4996468833d
- sentinel_commit_summary: fix(86): polish preset save interactions
- installed_build: 0.5.28
- pending_caveats:
  - sentinel_preset is documented with a "builds newer than 0.5.28" caveat in the agent manuals and mcp-automation skill; remove the caveat and add the tool to FEATURE-MAP.md once an installer ships it.
