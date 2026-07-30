# Sentinel Workspace

An open authoring workspace for building interactive visuals, tools, and control surfaces with Sentinel.

This repository contains ready-to-use Module projects, shared HLSL libraries, agent skills, product knowledge, and portable example shows. It is a focused public snapshot rather than a copy of Sentinel's private development workspace.

## Requirements

- Sentinel 0.5.49 or newer installed in its standard Windows location.
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

5. Load [`projects/interaction_lab/interaction_lab.sentinel`](projects/interaction_lab/interaction_lab.sentinel) to explore authored controls, responsive Canvas panels, spline editing, selection, and multi-object transform gizmos.

The live MCP catalog is authoritative for the installed Sentinel build. Start with [`AGENTS.md`](AGENTS.md) or [`knowledge/FEATURE-MAP.md`](knowledge/FEATURE-MAP.md) before authoring new content.

## Repository layout

| Path | Contents |
| --- | --- |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Equivalent entry instructions for common coding agents |
| `.agents/skills/`, `.claude/skills/` | Mirrored Sentinel authoring and automation skills |
| `knowledge/` | Focused product and workflow reference documentation |
| `projects/` | Portable saved shows, focused technique collections, and their bundled Module dependencies |
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
| [`industrial_lattice`](projects/industrial_lattice/) | A compact infinite steel-lattice SDF scene with its approved renderer and monochrome post pass bundled inside the project |
| [`strata`](projects/strata/) | A modular abstract composition combining SDF blobs, wire records, marble panels, marks, compositing, and post-processing |
| [`face_collage`](projects/face_collage/) | A tracked-face editorial collage with persistent accumulation, restrained overlays, and project-scoped performance controls |
| [`living_room_sdf`](projects/living_room_sdf/) | A bundled, data-driven SDF interior assembled from architecture, furnishing, material, lighting, render, and grade modules |
| [`camera_reference`](projects/camera_reference/) | A focused native Fly/Orbit camera reference with a thin antialiased grid and aligned color/depth outputs |
| [`touchdesigner_new_project`](projects/touchdesigner_new_project/) | A beginner-oriented recreation of a TouchDesigner starter network using typed signals, texture conversion, displacement, and an interactive geometry pass |
| [`streamdiff_workflows`](projects/streamdiff_workflows/) | Six focused StreamDiff studies covering 2D feedback, depth-parallax motion, video depth conditioning, procedural warp maps, and direct Mux switching |
| [`cloth_lab`](projects/cloth_lab/) | An audio-reactive XPBD cloth instrument with native camera interaction, tearing, grabbing, and reusable audio-band analysis |
| [`scientific_organism`](projects/scientific_organism/) | A modular scientific-instrument composition spanning source, analysis, temporal memory, topology, rendering, and performance control |
| [`autopsia`](projects/autopsia/) | A forensic relief instrument with tracked features, durable stylus editing, native camera navigation, and a compact macro deck |
| [`streamdiff_canvas`](projects/streamdiff_canvas/) | A photographic StreamDiff collage canvas with persistent paint, pattern stamps, depth fields, and generation controls |

## Creating a UI Module

Use the scaffold helper from the repository root:

```powershell
./tools/module-ui.ps1 new projects/my_project/modules/my_ui -Name "My UI"
./tools/module-ui.ps1 validate projects/my_project/modules/my_ui
```

The template uses the shared scientific UI foundation and opts into a full-frame Canvas panel with `follow_panel` resolution.

## Local data

Captures, shader caches, recovery files, provider configuration, and other machine-local artifacts are ignored. Keep provider keys in the ignored `vision.json` file or supported environment variables; never commit them.

## License

Original repository content is available under the [MIT License](LICENSE). Scientifica font data remains covered by its bundled SIL Open Font License notices inside the projects that use it, for example [`projects/interaction_lab/modules/_shared/fonts/SCIENTIFICA_LICENSE.txt`](projects/interaction_lab/modules/_shared/fonts/SCIENTIFICA_LICENSE.txt).
