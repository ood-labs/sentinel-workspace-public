---
type: devlog
date: 2026-07-07
session_start: "11:15"
session_end: "12:11"
phase: workspace-knowledge
subphase: modular-scene-layout-harvest
status: complete
approval: pending
summary: "Captured the clean four-flower modular graph layout pattern in workspace skills and knowledge"
note_created: true
updated: 2026-07-07
---

**Goal**

Bank the clean graph layout pattern from the generative garden build so future sessions know how to make modular scene graphs readable, inspectable, and easy to extend.

**Work Done**

- Updated both workspace copies of `modular-scene-authoring` with a new graph layout contract.
- Updated `knowledge/graph-wiring.md` to clarify that `auto_layout` is only a first-pass unstacking tool for authored modular scenes, followed by explicit `set_node_geometry`.
- Added a technique-catalogue entry for the organic family plan + renderer branch pattern proven by the four-flower garden graph.
- Recorded the proof pattern: structured plan node, matching renderer node, compositor input order matching visible vertical order, manual annotation bounds, data-port readbacks, final capture, and real Sentinel window screenshot.

**Decisions Made**

- Treat graph layout as part of scene authoring, not after-the-fact cleanup.
- Prefer explicit authored coordinates for polished graphs after node bounds are known.
- Keep repeated branches in the same vertical order through plan, render, and compositor columns.
- Use manual annotation geometry for polished boxes instead of relying on group-wrap annotation helpers.

**Approvals & Locks**

- User approved the observed result as clean and asked to preserve the pattern in the workspace skills and knowledge.
- No formal project phase transitioned.

**Issues Encountered**

- The first nodegraph screenshot request used an element name that did not exist in the UI registry.
- A broad `window_title: "Sentinel"` screenshot matched the terminal window because its title contained the same substring. The reliable capture used the exact app title `Sentinel - Untitled`.
- `projects/topographic_hud/topographic_hud.sentinel` was already dirty before this closeout and was left unstaged.

**Next Steps**

- For the next modular build, start with the graph layout contract in `modular-scene-authoring`: plan semantic columns first, wire by pin names, then lock positions with `set_node_geometry`.
- If this garden technique is reused a second time, harvest the actual generic modules into `modules/` rather than only documenting the pattern.

**Cross-References**

- Skill: `.claude/skills/modular-scene-authoring/SKILL.md`
- Skill: `.agents/skills/modular-scene-authoring/SKILL.md`
- Knowledge: `knowledge/graph-wiring.md`
- Catalogue: `knowledge/technique-catalogue.md`
