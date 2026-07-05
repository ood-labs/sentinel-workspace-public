---
type: devlog
status: complete
session_start: "10:15"
session_end: "11:50"
summary: "Finished the topographic-HUD build, wrote a mined debrief, and turned the workspace into a private ood-labs GitHub repo with an allowlist gitignore"
updated: 2026-07-05
---

# 2026-07-05 - Workspace Repo Setup + Topographic-HUD Debrief

## Context

Continuation of the modular topographic-HUD build (a 15-module sci-fi HUD scene, see
`projects/topographic_hud/`). This session closed out the build, produced a debrief mined from the
actual build transcript, switched the session model to the full 1M compact window, and — the main
tangible outcome — turned this workspace into a private Git repo under the `ood-labs` org.

## What we did

- **Finished topographic-HUD P8.** Ran `proof_bundle` on the `post` node
  (`captures/topographic_hud_proof/`), confirmed the graph healthy at 60fps / 1.55ms / 0 hotspots,
  and copied `modules/_shared/` (scientifica font + os_text/os_terminal includes) into
  `projects/topographic_hud/modules/_shared/` so the bundled show compiles standalone (the
  `save_project bundle_modules` step doesn't copy `_shared`).
- **Wrote `projects/topographic_hud/DEBRIEF.md`** from evidence mined out of the pre-compaction
  session transcript (parsed the JSONL with a Python script), not from memory. Key numbers: 15
  modules, 0 compile-error signatures across 19 compile results, only 2 shaders needed a post-write
  Edit, 22 live param sets for all aesthetic tuning (zero recompiles for the look), 4 control-output
  expressions forming the "signal bus", 3 hard tool errors total.
- **Switched model config.** Already on `claude-opus-4-8[1m]`; raised `autoCompactWindow` 400000 ->
  1000000 in `~/.claude/settings.json`. 1M env gate confirmed clear at all scopes.
- **Created the repo.** `git init` on the workspace, authored an allowlist `.gitignore` and a
  human-facing `README.md`, and pushed to `github.com/ood-labs/sentinel-workspace` (private).
- **Curated surgically.** The repo is a seed, not a disk mirror: `modules/*` and `projects/*` are
  ignored by default and only blessed content is re-included. First push = base seed + `_shared` +
  the 15 topographic modules + `projects/topographic_hud/`. 68 experiment modules and 10 other
  projects stayed untracked. Excluded `captures/` (633MB), `**/shader_cache/` (47 compiled .bin),
  `*.previous`, recovery snapshots, logs. Result: 157 files / 1.1MB tracked, down from 662MB.

## Decisions made

- **This repo is the curated seed, not a mirror.** Users receive a provisioned copy via the Sentinel
  installer; they do not clone this repo. Only shippable / reference-example work gets committed.
- **Allowlist `.gitignore` over deny-list.** Ignore all of `modules/*` / `projects/*`, re-include by
  name. Makes curation explicit and future-proof — a stray experiment can never sneak into a commit,
  and promoting work is a one-line `!` (or `git add -f`).
- **First push scope = topographic_hud only.** Portal (BLINK26) E/F and the reference/donor modules
  were deliberately held back (Portal was client-gig work); add later if blessed.
- **Keep `.claude/settings.local.json`** — it only enables the `sentinel-mcp` server (no secrets),
  so provisioned users get MCP working out of the box.
- **Exclude compiled shader caches** (`**/shader_cache/`) — regenerated on load, build/GPU-specific.

## Approvals & locks

- User approved: repo name `sentinel-workspace`, private, `ood-labs` org, exclude-generated, first
  push scope "just topographic_hud". Repo created and pushed; local `main` in sync with `origin/main`.

## Issues encountered

- `save_project bundle_modules=true` does not copy `modules/_shared/` into the bundle, so a bundled
  show that `#include`s the shared font would fail to compile standalone until `_shared` is copied in
  manually. Worked around by copying it.
- A naive `git add -A` on this workspace would have staged the 633MB `captures/` folder and 47
  compiled `shader_cache/*.bin` files. The allowlist `.gitignore` (written before the first `add`)
  prevented this; always gate a large asset-bearing workspace before the first stage.

## Next steps

- Decide whether the loose `modules/field_gen`..`modules/signal` copies AND the bundled
  `projects/topographic_hud/modules/` copies should both live in the repo long-term (currently both
  tracked — loose = reusable library, bundle = self-contained show), or collapse to one source.
- Optionally add a `.gitattributes` for consistent line endings (Git flagged LF->CRLF on text files).
- When ready, promote further blessed work (Portal E/F, reference modules) via `.gitignore` `!` lines.
- The DEBRIEF's MCP tooling-gap list (fix `set_many`, bake-live->manifest-defaults, layout-on-create,
  signal-bus inspector, tune-loop front door, smart connect) is worth handing to whoever owns the MCP
  server — overlaps with the prior poster-v3 devlog's tooling requests.

## Cross-references

- [[2026-07-04-modular-poster-v3-workflow]] — prior modular build; its tooling-improvement list
  overlaps heavily with this session's debrief gaps (bulk param snapshot/restore, contract migration,
  capture diffing).
- `projects/topographic_hud/DEBRIEF.md` — full mined write-up.
- Memory: `topographic-hud-system`, `portal-shader-blink26`.
