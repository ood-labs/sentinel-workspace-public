# Module Pipeline

Pipeline type: `module`

Modules are authored shader projects with a `manifest.yaml`. They can be generators, post-processors, data consumers, data producers, control-output producers, or multi-pass renderers.

## When To Use A Module

Use a Module when you need:

- a custom HLSL visual effect;
- a shader parameter surface exposed to MCP and the UI;
- a typed data input from tracking or detection;
- a typed data output for another node;
- a scalar control output that can drive expressions;
- persistent buffers or multi-pass feedback.

For simple one-file post-processing, `hlslshader` may be enough.

## Fast Scaffold From Tracking Data

Use `sentinel_module action=scaffold_from_ports` when a Module should consume tracking, detection, blob, corner, line, or landmark data. Pass the upstream pipeline id and optional data port name. The tool writes `modules/<module_name>/manifest.yaml` and `render.hlsl` in the launched workspace, using the live schema from `get_data_schemas`.

The generated Module starts with modern controls: color palette pickers, a `point2D` composition pad, grouped toggles, and an `enum` button grid. Treat it as the starting point for creative shaping, then run `sentinel_pipeline action=compile_check project_dir=<generated_dir>` before creating the Module node.

## Parameters

Module manifest parameters become normal Sentinel parameters. They appear in `sentinel_pipeline info` and can be changed with `sentinel_state set` or driven with `sentinel_expression action=set`.

Supported parameter types include:

- float
- int
- bool
- enum
- color
- vec2 / point2D
- vec3
- vec4

## Data Ports

Modules can declare `data_inputs` and `data_outputs`. These are structured buffers, wired through `sentinel_graph add_link`.

Use data inputs for landmarks, detections, blobs, corners, lines, or records produced by another module.

`sentinel_pipeline action=get_data_schemas` reports the data schema and, when the graph node exists, the matching graph pin name and slot. Use that reported pin name with `sentinel_graph action=add_link` instead of guessing singular/plural labels.

## Control Outputs

Modules can publish scalar values under:

```text
/sentinel/pipelines/<module_id>/control_outputs/<name>
```

Other parameters can read them with:

```text
ref("module_lfo/control_outputs/rate")
```

## Shared Motion And Audit Libraries

For authored motion, include `#include "../_shared/anim/anim.hlsli"` and use `an_spring`, `an_spring_v`, the `an_stagger_*` family, `an_anticipate`, `an_squash`, and `an_loop_noise` instead of hand-rolled easing. The same equations exist in expressions (`spring`, `stagger`, ...). Rate-driven values integrate phase; never multiply a live rate by absolute time. See `knowledge/motion-choreography.md`.

For measured geometry assertions on SDF modules, `modules/_shared/sdf/sdf_audit.hlsli` provides bisection dimension measurement, bounds clearance, and overlap sampling; results publish through a structured data output that `sentinel_blueprint action=audit` reads. See `knowledge/precise-construction.md`.

## Compile And Reload

Module creation with `project_dir` is atomic. The response reports whether manifest parsing started cleanly. Shader compilation is async, so poll:

```text
sentinel_pipeline action=compile_status pipeline_id=<id>
```

Use `force_reload` after changing files or recovering from a compile error.

## Authoring Order

When writing a module project programmatically, write shader files first and `manifest.yaml` last. The file watcher reacts to manifest saves, so saving the manifest before its shader files exist can create a temporary compile failure.

## Output Resolution

By default, modules match input slot 0. A manifest can select generator mode or explicit resolutions. Multi-pass modules can use per-pass resolution rules.

For fixed generator visuals, use an explicit or generator resolution. For video effects, match the input.
