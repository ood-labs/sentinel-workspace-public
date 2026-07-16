# 2026-07-16: Parameter Binds Documentation Refresh

Targeted documentation update covering the Parameter Binds system that shipped in Sentinel 0.5.35 (Phase 91). Scoped to docs only; scene and project content adoption is a separate follow-up pass.

## What changed

- `knowledge/expressions-and-drivers.md`: reframed the intro around the two linking mechanisms (one-directional expressions, bidirectional binds) and added a full Parameter Binds section: `set_bind` (pair and endpoints forms), `list_binds`, `clear_bind` (removes the whole network), network merge on overlap, validation rules (type match, identical enum lists, Button/String/`enabled`/control-output/read-only rejection), once-per-frame propagation with the one-frame OSC lag note, whole-network undo, persistence across rename/delete/import/module reload, late-registering endpoint seeding, the at-most-one-expression-driver rule, Scene Group exposes as binds with automatic legacy ref() migration, the Properties bind badge, and the at-or-below-0.5.34 absence caveat.
- `knowledge/FEATURE-MAP.md`: added binds to the signal-kinds list and the wiring guidance.
- `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`: bind paragraph in Control Outputs And Expressions; Scene Groups section now states exposes are bidirectional binds on installs newer than 0.5.34, with the legacy one-way behavior noted for older installs.
- `.claude/skills/mcp-automation/SKILL.md` and `.agents/skills/mcp-automation/SKILL.md`: `sentinel_expression` entry now lists all seven actions with the bind semantics summarized.

All action names and semantics were verified against the shipped implementation (`mcp-server-rs/sentinel-mcp/src/tools/expression.rs`, the `SET_BIND`/`LIST_BINDS`/`CLEAR_BIND` handlers in `AutomationBridge.cpp`).

Every file was edited in sentinel-workspace-public (the seed source of truth) first and mirrored here with normalized content compares, so the next provisioning pass cannot regress it once the template mirror re-syncs.

## Still in progress

- The full 0.5.31-to-0.5.36 doc refresh (Phases 89.1 through 92: input tiles, canvas panels, gig gate, compile Queued state, workspace manifest reseeds) remains pending; the SYNC-ANCHOR commit was deliberately not advanced.
- The sentinel repo template mirror re-sync (`tools/sync_workspace_template.py`) waits for the running phase loop to release that tree.
- Scene/project content adoption of binds is a separate agent pass.

This is a documentation refresh checkpoint, not a phase or subphase completion.
