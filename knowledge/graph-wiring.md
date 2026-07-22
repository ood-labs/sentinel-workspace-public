# Graph Wiring

Sentinel graphs contain video links, data-port links, control outputs, and expression drivers. Use the right mechanism for each signal type.

## Video Inputs

Use `sentinel_pipeline action=set_input` for texture/video input slots.

Typical flow:

1. Create a source with `sentinel_pipeline action=create_source`.
2. Create a pipeline with `sentinel_pipeline action=create`.
3. Connect source to pipeline with `sentinel_pipeline action=set_input`.
4. Place the new node relative to its neighbor, focus it, and open its pipeline window.
5. Inspect the live preview and health before creating another node.

Pattern sources are deterministic and useful for tests. Spout and NDI sources receive external live video.

## Data Ports

Data ports are typed structured buffers. They are not video textures.

Use `sentinel_graph action=add_link` to connect a producer data output to a consumer data input. If a link fails, the error lists available pins and slot numbers. Pin names are safer than numeric slots when available.

Examples of data ports:

- MediaPipe `Hand Landmarks`
- MediaPipe `Face Landmarks`
- Pose `Keypoints`
- Detection `Detections`
- Features `Blobs`, `Corners`, and `Lines`
- Module-authored data ports

## Control Outputs

Control outputs are scalar values published after a pipeline processes a frame. They are read by expressions through `ref()`.

Examples:

- `mediapipe_0/control_outputs/pinch_primary`
- `features_0/control_outputs/largest_x`
- `module_lfo/control_outputs/rate`

Do not wire control outputs with `set_input`. Use `sentinel_expression action=set` on the target parameter.

## Auto Layout

Whole-graph auto layout is for an explicitly requested batch workflow or a non-creative smoke test:

```text
sentinel_graph action=auto_layout
```

During visible creative construction, do not build a pile and auto-layout it afterward. Place each new node as it is created with create-time `relative_to` placement or `place_relative`. Use `layout_neighborhood` for local cleanup without disturbing the evolving graph.

## Health Checks

After wiring, inspect:

- `sentinel_pipeline action=info`
- `stats.healthy`
- `stats.health_reasons`
- `stats.framesProcessed`
- `stats.statusMessage`
- `has_preview_srv`

Real proof is a healthy node with frames climbing, not just a successful create call.

## Visible Construction Loop

Build creative graphs one semantic node at a time. Do not pre-author all planned Module projects, concurrently create multiple nodes, or hide creation in a batch or loop. Complete the current node from authoring through live proof before starting the next one:

1. Author or select and compile-check only the current node.
2. Create only that node and place it relative to its neighbor immediately.
3. Add its known links and verify compile, health, frames, schemas, and data.
4. Call `sentinel_graph action=focus`.
5. Call `sentinel_pipeline action=open_window` and inspect the live preview/Properties.
6. Exercise an important control and require a meaningful visible response.
7. Fix the node or its preview before moving downstream.

`has_preview_srv` only proves that the pipeline published a preview texture. It does not prove that the preview communicates useful state. Every generator, layout, plan, assembly, and data-transform node needs an independently useful preview; a final renderer cannot substitute for missing intermediate previews.
