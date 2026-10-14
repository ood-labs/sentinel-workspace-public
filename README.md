# Sentinel Workspace

The public authoring workspace for Sentinel: concise agent instructions,
product knowledge, portable example projects, and a small set of local
authoring tools.

Sentinel is distributed separately. This repository contains workspace content,
not the application, model engines, or proprietary source.

## Requirements

- Sentinel 0.5.61 or newer on Windows 10 or 11.
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
5. When project-level research would resolve an open design question, use
   `knowledge/EXAMPLE-MAP.md` to select the strongest teaching reference.

The live MCP catalog is authoritative for the installed build.

## Repository layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Identical entry instructions for common agents |
| `.agents/skills/`, `.claude/skills/` | Identical Sentinel authoring skills |
| `knowledge/` | Product and workflow reference |
| `projects/` | Thirteen curated, self-contained example projects |
| `tools/templates/` | Starters to copy into a project: Module includes, DMX and fixture Modules, blueprints, the UI kit, and Script templates such as the clip sequencer |
| `tools/` | Supported authoring and release-validation helpers |
| `.release/` | Maintainer approval records; not installed into user workspaces |

## Examples are references

The curated projects are the reference set for this build: the projects to study
for technique and quality, and the floor to build past. Installing a build adds
and refreshes them in the default workspace and retires the examples it drops.
A project with the same name as an example is replaced or retired, and a copy
you changed moves to `.sentinel/workspace-backups/upgrade-to-<version>/projects/`,
so keep your own changes to an example in a copy under another name. Every
other project stays, and older projects in a workspace are not references
unless you point your agent at one. The map in
`knowledge/EXAMPLE-MAP.md` lists the current collection and the retired examples.

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
| `breathing_room` | A realistic SDF parlour that trips: six plan-authority editors over persistent records, a ray-marched room, Lipschitz-safe warps and a replication-trip lens |
| `camera_reference` | Native internal Fly/Orbit camera behavior and efficient reference grid |
| `cloth_lab` | Audio-driven XPBD cloth, grabbing, tearing, and native camera interaction |
| `formicary` | A foraging ant colony from a macro photograph: stigmergic pheromone trails, planted six-leg gait, stations placed on a plan or on the program image, and a macro lens |
| `interaction_lab` | Fourteen interface stations on one UI foundation: host-owned controls, ordered events and durable state, 3D picking, editors, patching, and multi-view sequencers |
| `kuka_cell` | A floor of six-axis arms: plan over elevation at one scale, a randomizer that perturbs the lattice instead of coordinates, choreography phased by floor position, a shared beach-ball authority, and per-tile instance culling |
| `laser_mapping_lab` | Laser-to-surface mapping against a projected grid (corners, scanner correction, handles, zoning masks), laser/projector sync, and laser looks (shapes and traced line art) previewed on a simulated galvo laser in haze |
| `phage_stage` | Kinetic concert rig of 561 GDTF fixtures imported from an MVR, whose render is its DMX: 64 programmed looks in four energy tiers, layered per-fixture programming, a desk panel, a Script-node Push 2 surface, and a documented optimisation that cut GPU time from 41 ms to 5.8 ms per frame |
| `simple_stage` | A club stage sized like a real club on PHAGE's show system: two rows of hung beams, a pixel wall and strobes in 7 universes, 64 symmetric looks with held formations, a desk panel and a Push 2 surface |
| `soft_vitrine` | Hybrid 2D/3D sculpture staging, coverage lanes, and seeded arrangement randomization |
| `spectral_bench` | 2D spectral ray tracing (dispersion, Fresnel, total internal reflection) drawn as a studio photograph, with a bench plan over a spectral rail that draws its own failure modes |
| `streamdiff_canvas` | Persistent painting and patterned depth control for photographic StreamDiff collage |
| `streamdiff_workflows` | Six focused StreamDiff routing and conditioning studies |

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
