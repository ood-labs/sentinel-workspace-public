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

## Performance Gates For Heavy Nodes

Set a target before tuning a heavy node. For an interactive 60 Hz graph, 16.7 ms is the complete frame budget, not the allowance for one detector. Assign the heavy node an explicit share of that budget and include UI responsiveness in the acceptance test. A node that remains technically healthy while making interaction lag is not acceptable.

For Features, tracking, optical flow, inference, readback, or large feedback passes:

1. Profile the graph before enabling the task.
2. Enable or change one task or parameter family at a time.
3. Wait for settled frames, then profile again.
4. Inspect task counts, schemas, preview, and the visible UI response.
5. Revert immediately when wall time or responsiveness jumps unexpectedly.
6. Do not continue building downstream until the graph is back inside budget.

Thresholds are workload controls as well as visual controls. Permissive corner, line, and edge settings can create dense candidate sets before the published `max_count` is applied. A small output count therefore does not by itself prove cheap processing.

If resolution dominates cost, keep the canonical creative chain at its intended resolution and downsample only an analysis branch. For example:

```text
1280x720 source ─────────────────────────────→ 1280x720 renderer
       └→ 480x270 analysis proxy → Features ─→ structured data
```

The proxy's preview must remain meaningful, Features must be previewed directly while tuning, and downstream coordinate consumers must normalize against 480x270. Measure the proxy plus Features together. Do not assume an internal analysis-scale feature exists until `list_types`, `info`, or capabilities for the live build verifies it.

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
