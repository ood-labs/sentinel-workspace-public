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

After creating and wiring nodes, call:

```text
sentinel_graph action=auto_layout
```

For large hand-arranged graphs, use `layout_neighborhood` instead of rearranging the whole graph.

## Health Checks

After wiring, inspect:

- `sentinel_pipeline action=info`
- `stats.healthy`
- `stats.health_reasons`
- `stats.framesProcessed`
- `stats.statusMessage`
- `has_preview_srv`

Real proof is a healthy node with frames climbing, not just a successful create call.
