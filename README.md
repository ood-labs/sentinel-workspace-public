# Sentinel Workspace

An open authoring workspace for building interactive visuals, tools, and control surfaces with Sentinel.

This repository contains ready-to-use Module projects, shared HLSL libraries, agent skills, product knowledge, and portable example shows. It is a focused public snapshot rather than a copy of Sentinel's private development workspace.

## Requirements

- Sentinel 0.5.35 or newer installed in its standard Windows location.
- Windows 10 or 11 with a supported NVIDIA GPU.
- An MCP-capable coding agent when using the included automation and authoring skills.

Sentinel itself is distributed separately. This repository contains authored workspace content, not the Sentinel application or engine source.

## Quick start

1. Clone this repository:

   ```powershell
   git clone https://github.com/ood-labs/sentinel-workspace-public.git
   cd sentinel-workspace-public
   ```

2. Start Sentinel.

3. Open this folder in an MCP-capable agent. The included `.mcp.json` targets the normal Sentinel installation at `C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe`.

4. Confirm the live connection:

   ```text
   sentinel_app action=ping
   sentinel_pipeline action=list_types
   ```

5. Load any standalone project under [`projects/`](projects/), or open [`projects/interaction_lab/interaction_lab.sentinel`](projects/interaction_lab/interaction_lab.sentinel) for the authored UI, selection, spline, and gizmo feature laboratory.

The live MCP catalog is authoritative for the installed Sentinel build. Start with [`AGENTS.md`](AGENTS.md) or [`knowledge/FEATURE-MAP.md`](knowledge/FEATURE-MAP.md) before authoring new content.

## Repository layout

| Path | Contents |
| --- | --- |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Equivalent entry instructions for common coding agents |
| `.agents/skills/`, `.claude/skills/` | Mirrored Sentinel authoring and automation skills |
| `knowledge/` | Focused product and workflow reference documentation |
| `modules/` | Curated Module library and shared HLSL includes |
| `projects/` | Portable saved shows, focused technique collections, and authored visual examples |
| `examples/` | Small blueprint examples for procedural construction |
| `tools/` | Local authoring and validation helpers |

## Interaction Lab

Interaction Lab is a Module-only example containing:

- A monochrome scientific UI kit and live typography/spacing tuner.
- A font-style sampler using the bundled Scientifica glyph data.
- A persistent cubic spline editor connected to a downstream renderer.
- A selectable 3D scene with translate, rotate, and scale gizmos.
- Full-frame Canvas panels whose render resolution follows the panel size.

See the [Interaction Lab guide](projects/interaction_lab/README.md) and the [UI authoring guide](knowledge/ui-authoring.md).

## Example projects

Open any project by loading its `.sentinel` file in Sentinel:

| Project | What it demonstrates |
| --- | --- |
| [`interaction_lab`](projects/interaction_lab/) | Scientific UI controls, responsive Canvas panels, spline editing, selection, and transform gizmos |
| [`living_room_sdf`](projects/living_room_sdf/) | A bundled, data-driven SDF interior assembled from architecture, furnishing, material, lighting, render, and grade modules |
| [`face_collage`](projects/face_collage/) | A tracking-driven StreamDiff collage with persistent accumulation, face cutouts, clone overlays, and editorial finishing |
| [`topographic_hud`](projects/topographic_hud/) | A 15-module topographic interface using texture lanes, structured records, and a control-output signal bus |
| [`desert_totem`](projects/desert_totem/) | A procedural Dada totem with structured layout records and layered SDF domain warping |
| [`strata`](projects/strata/) | A modular abstract composition combining SDF blobs, wire records, marble panels, marks, compositing, and post-processing |
| [`industrial_lattice`](projects/industrial_lattice/) | A compact infinite steel-lattice SDF scene with bundled render/post modules, internal camera controls, quality settings, and extreme domain distortion |
| [`streamdiff_workflows`](projects/streamdiff_workflows/) | Six focused StreamDiff studies covering 2D feedback, depth-parallax motion, video depth conditioning, procedural warp maps, and direct Mux switching |
| [`node_examples`](projects/node_examples/) | Eighteen focused studies covering tracking, analysis, routing, control, authored modules, HLSL post-processing, cameras, and RTX Video SR |

Face Collage and the StreamDiff workflow studies are engine-backed. The remaining aesthetic looks are model-free. Each example is intentionally distributed as a standalone project or focused collection so people can load only the content they want without paying the memory and startup cost of a combined gallery.

## Creating a UI Module

Use the scaffold helper from the repository root:

```powershell
./tools/module-ui.ps1 new modules/my_ui -Name "My UI"
./tools/module-ui.ps1 validate
```

The template uses the shared scientific UI foundation and opts into a full-frame Canvas panel with `follow_panel` resolution.

## Local data

Captures, shader caches, recovery files, provider configuration, and other machine-local artifacts are ignored. Keep provider keys in the ignored `vision.json` file or supported environment variables; never commit them.

## License

Original repository content is available under the [MIT License](LICENSE). Scientifica font data remains covered by its bundled SIL Open Font License notice at [`modules/_shared/fonts/SCIENTIFICA_LICENSE.txt`](modules/_shared/fonts/SCIENTIFICA_LICENSE.txt).
