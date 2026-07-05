# Performance And Proof

Use live runtime evidence when reviewing a graph. Screenshots show what it looks like; profile and proof bundles show whether it is actually running and where time is going.

## Graph Profile

Call:

```text
sentinel_graph action=profile summary=true sort_by=wall_time_ms
```

Useful `sort_by` values:

- `wall_time_ms`: per-node CPU wall time around the latest graph `process()` call.
- `avg_frame_ms`: the pipeline's own rolling average from `PipelineStats`.
- `frame_time_ms`: the pipeline's latest reported frame time.
- `frames_processed`: nodes that are actually advancing.
- `id`: stable alphabetical listing.

The profile returns:

- frame breakdown: input, pipeline graph, output, UI/present, total
- per-node wall time
- pipeline health and frame stats
- graph link counts, including data links
- hotspot reasons such as unhealthy, no frames, process failure, or high wall time

This is a lightweight profiler. It uses CPU wall-clock timing around graph node processing. It does not split GPU kernel time, inference time, CPU readback, queue wait, or synchronization yet.

## Proof Bundle

For creative-task handoff, use:

```text
sentinel_capture action=proof_bundle pipeline_id=<final_node>
```

The bundle writes `graph_profile.json` and includes a Performance section in `summary.md`. Use it after the graph is wired and frames are climbing.

## Triage Pattern

1. Run `sentinel_pipeline info` on the final node and any suspected upstream node.
2. Run `sentinel_graph profile summary=true sort_by=wall_time_ms`.
3. If a node is expensive, inspect its parameters and data outputs.
4. If a node is unhealthy or has no frames, fix wiring, missing engines, or compile errors before tuning visuals.
5. Capture a final `proof_bundle` when the graph is visually correct and the profile is acceptable.
