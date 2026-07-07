# Graph Wiring

Sentinel graphs contain video links, data-port links, control outputs, and expression drivers. Use the right mechanism for each signal type.

## Video Inputs

Use `sentinel_pipeline action=set_input` for texture/video input slots.

Typical flow:

1. Create a source with `sentinel_pipeline action=create_source`.
2. Create a pipeline with `sentinel_pipeline action=create`.
3. Connect source to pipeline with `sentinel_pipeline action=set_input`.
4. Run `sentinel_graph action=auto_layout`.
5. Inspect health with `sentinel_pipeline action=info`.

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

After creating and wiring brand-new nodes, call:

```text
sentinel_graph action=auto_layout
```

Use this mainly to unstack nodes that spawned at the same coordinate. For authored modular scenes, follow it with explicit positions:

```text
sentinel_graph action=set_node_geometry entity_id=<node> x=<graph_x> y=<graph_y>
```

Readable graph layout is part of the scene contract:

- Columns should reflect responsibility: generators/plans, renderers/expanders, compositors, post/output.
- Repeated branches should keep the same vertical order through every column.
- Compositor inlet order should match the visible branch order. If slot 0 is `Background` and slots 1-4 are `Sunflower`, `Poppy`, `Lotus`, `Iris`, lay out those producers and renderers top-to-bottom in that same order.
- Use pin names for `add_link` when possible, then confirm the numeric slot order with `sentinel_graph action=get summary=true`.
- For large hand-arranged graphs, use `layout_neighborhood dry_run=true` first. If the dry run would disturb a clean semantic layout, use manual `set_node_geometry`.
- Add annotations manually with explicit bounds after node sizes are available. Group-wrap annotation helpers are convenient, but explicit `x/y/width/height` produces cleaner boxes for polished graphs.

Proof checklist for graph layout:

1. `sentinel_graph action=get summary=true` shows the intended links and coordinates.
2. `sentinel_pipeline action=get_data_schemas` shows structured producers expose the expected ports.
3. `sentinel_pipeline action=capture_data_port` returns active records for each data branch.
4. Capture the final pipeline output.
5. Screenshot the real Sentinel window using the exact window title when possible, for example `Sentinel - Untitled`.

## Health Checks

After wiring, inspect:

- `sentinel_pipeline action=info`
- `stats.healthy`
- `stats.health_reasons`
- `stats.framesProcessed`
- `stats.statusMessage`
- `has_preview_srv`

Real proof is a healthy node with frames climbing, not just a successful create call.
