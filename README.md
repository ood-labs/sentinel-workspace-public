# Sentinel Workspace

The public authoring workspace for Sentinel: concise agent instructions,
product knowledge, portable example projects, and a small set of local
authoring tools.

Sentinel is distributed separately. This repository contains workspace content,
not the application, model engines, or proprietary source.

## Requirements

- Sentinel 0.5.52 or newer on Windows 10 or 11.
- A supported NVIDIA GPU.
- An MCP-capable coding agent for the included automation workflows.

## Start here

1. Start Sentinel in the interactive Windows desktop.
2. Open this workspace in your coding agent.
3. Verify the live build:

   ```text
   sentinel_app action=ping
   sentinel_pipeline action=list_types
   sentinel_app action=capabilities
   ```

4. Read `AGENTS.md` and `knowledge/FEATURE-MAP.md`.
5. Use `knowledge/EXAMPLE-MAP.md` to find a relevant teaching project.

The live MCP catalog is authoritative for the installed build.

## Repository layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Identical entry instructions for common agents |
| `.agents/skills/`, `.claude/skills/` | Identical Sentinel authoring skills |
| `knowledge/` | Product and workflow reference |
| `projects/` | Fifteen curated, self-contained example projects |
| `examples/` | Small generic blueprint and skill fixtures |
| `tools/` | Supported authoring and release-validation helpers |
| `.release/` | Maintainer approval records; not installed into user workspaces |

## Examples are references

The curated projects teach architectures and techniques. They are not a stock
Module catalog. Inspect a relevant graph and component map, then invent a
solution for the current user's source material, interaction, and aesthetic.
Only copy a project-specific Module when the user explicitly asks for a fork or
remix of that example.

Generic infrastructure such as licensed font data or the neutral UI scaffold
may be vendored into the owning project. Every project keeps its active Modules,
recursive shader includes, runtime assets, and licenses under its own directory.
See `knowledge/example-authoring.md`.

## Example collection

| Project | Primary lesson |
| --- | --- |
| `autopsia` | Closed-loop feature analysis, stable agents, 3D relief, and performance control |
| `camera_reference` | Native internal Fly/Orbit camera behavior and efficient reference grid |
| `cloth_lab` | Audio-driven XPBD cloth, grabbing, tearing, and native camera interaction |
| `face_collage` | MediaPipe-guided StreamDiff collage, accumulation, cutout, and editorial compositing |
| `industrial_lattice` | Compact procedural SDF structure and post-processing |
| `interaction_lab` | Responsive Canvas UI, splines, selection, gizmos, audio scope, and traces |
| `living_room_sdf` | Modular architectural records, spatial editing, lighting, materials, and SDF rendering |
| `matik_plate` | Interactive plan authority, hybrid record contracts, organisms, circuitry, and technical-plate rendering |
| `prism_reliquary` | Interactive plan authority, authored HDR lighting, filmic SDF rendering, depth of field, and layered antialiasing |
| `scientific_organism` | Long modular analysis-to-render chain with temporal memory and a final Scene Group output |
| `soft_vitrine` | Hybrid 2D/3D sculpture staging, coverage lanes, and seeded arrangement randomization |
| `strata` | Feature-reactive modular 2D composition |
| `streamdiff_canvas` | Persistent painting and patterned depth control for photographic StreamDiff collage |
| `streamdiff_workflows` | Six focused StreamDiff routing and conditioning studies |
| `touchdesigner_new_project` | Typed signal-to-texture modulation and geometry displacement |

The detailed source, pipeline, connection, output, engine, and remix map is in
`knowledge/EXAMPLE-MAP.md`. Each project README contains its own exact component
map.

## Create a responsive UI Module

From the repository root:

```powershell
./tools/module-ui.ps1 new projects/my_project/modules/my_ui -Name "My UI"
./tools/module-ui.ps1 validate projects/my_project/modules/my_ui
```

The helper accepts only project-local targets. It creates the Module
transactionally and vendors a neutral, licensed UI dependency set into that
project. Replace the placeholder visual language to suit the work.

## Local data

Captures, shader caches, recovery files, and provider configuration are ignored
and must not be committed. Keep provider keys in the ignored `vision.json` file
or supported environment variables.

## License

Original repository content is available under the [MIT License](LICENSE).
Scientifica-derived font tables remain covered by the SIL Open Font License
notice beside every bundled copy.
