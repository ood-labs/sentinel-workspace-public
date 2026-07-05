# Sentinel Workspace

The reference / seed workspace for the **Sentinel** agent environment. Sentinel is a
GPU-accelerated live-video application for performance and interactive visuals (Spout/NDI/
camera/pattern/video sources, real-time AI generation, tracking, depth, segmentation, object
detection, HLSL shader modules, and Spout/NDI output).

This is a **private development copy** maintained under `ood-labs`. End users do **not** clone
this repo — they receive a provisioned copy of the workspace through the Sentinel installer.
This repo is where that seed content is authored, curated, and versioned before it ships.

## Curation policy

This is a curated repo, not a mirror of a local machine. `modules/` and `projects/` are
**allowlisted** in [`.gitignore`](.gitignore): everything under them is ignored by default, and
only blessed, shippable (or reference-example) content is committed. Local experiments stay
untracked. To promote work into the repo, add a matching `!` line in `.gitignore` (or
`git add -f <path>`).

Generated artifacts (`captures/`, recovery snapshots, `*.previous` backups, logs) are never
committed.

## Layout

| Path | What it is |
| --- | --- |
| `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` | Identical agent entry manuals (start here) |
| `.claude/skills/`, `.agents/skills/` | Curated user-facing authoring skills |
| `knowledge/` | Product reference docs — start with `knowledge/FEATURE-MAP.md` |
| `docs/` | Additional documentation |
| `modules/` | Curated Module library (HLSL multi-pass projects). `_shared/` holds common includes (e.g. the scientifica font). |
| `projects/` | Curated example `.sentinel` shows / bundled module graphs |
| `shaders/` | Example shader graphs |
| `tools/` | Workspace helper tooling |
| `.mcp.json` | Connects an agent to the bundled `sentinel-mcp.exe` |

## Included examples

- **`projects/topographic_hud/`** — a 15-module sci-fi topographic-HUD scene built as a modular
  graph (shared height field → contours / grid / nodes / links / labels → HUD / atmosphere →
  compositor → post), with a control-output "signal bus" driving reactive parameters. See its
  `DEBRIEF.md` for the build write-up.

## Getting started (for an agent)

Read `CLAUDE.md`. In short: the live MCP surface is the source of truth for a given build —
use `sentinel_app action=ping`, `sentinel_pipeline action=list_types`, and
`sentinel_app action=capabilities` to discover what the running install can actually do before
building anything.
