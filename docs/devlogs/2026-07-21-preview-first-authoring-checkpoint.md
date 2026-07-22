---
type: devlog
date: 2026-07-21
phase: workspace
subphase: preview-first-authoring-behavior
status: in-progress
approval: pending
summary: "Checkpointed workspace 0.5.43 metadata, interactive launch safety, preview-first graph authoring, camera ownership, and curated Scene Group controls"
note_created: true
updated: 2026-07-21
---

**Goal**

Make live Sentinel graph authoring visible and inspectable at every node, prevent ambiguous camera ownership, and keep user-facing Scene Group controls concise.

**Work Done**

- Updated workspace seed metadata to Sentinel 0.5.43 and refreshed manifest hashes for edited distributed files.
- Added active-interactive-session launch safety to the mirrored MCP automation skills and entry manuals.
- Restored and strengthened the visible node-construction contract across `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`.
- Required one-node-at-a-time creation, focus, open-window inspection, control exercise, and meaningful intermediate preview proof.
- Defined blank, constant, generic, misleading, or illegible data-node previews as blocking authoring defects; `has_preview_srv` alone is not sufficient.
- Required generator, layout, plan, assembly, and data-transform nodes to visualize the structured data they publish.
- Established a single-camera-owner rule and prohibited promotion of camera controls to Scene Group or top-level interfaces.
- Limited initial Scene Group interfaces to roughly four to eight high-impact creative controls and required every exposed control to be tested in the open Properties panel.
- Updated the mirrored `module-authoring` and `modular-scene-authoring` skills plus graph, Module, and scene-system knowledge.

**Verification**

- `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are byte-identical.
- Claude and Codex copies of both edited authoring skills are byte-identical.
- The workspace manifest parses and its hashes match all edited distributed files.
- `git diff --check` reports no whitespace errors.
- The live Sentinel graph is empty and no disposable creative artifacts remain in the workspace.

**Remaining Work**

- No phase or subphase is approved by this checkpoint.
- Apply the preview-first cycle and camera/control-surface rules on the next live creative graph.

**Cross-References**

- Entry manuals: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- Skills: `.agents/skills/module-authoring/`, `.agents/skills/modular-scene-authoring/`
- Knowledge: `knowledge/graph-wiring.md`, `knowledge/module-pipeline.md`, `knowledge/scene-system.md`
