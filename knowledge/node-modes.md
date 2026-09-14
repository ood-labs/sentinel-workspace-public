# Node Modes: Normal, Freeze, And Bypass

Every pipeline node has an operator mode. Normal runs the node as usual. Freeze holds the node's last completed output and stops processing. Bypass passes the node's inputs straight through to its outputs with type-aware routing for video, data, and Mesh ports. The mode lives at `/sentinel/pipelines/<id>/operator_mode` with the values `normal`, `freeze`, and `bypass`, and `sentinel_pipeline action=info` reports it.

## Setting a mode

Over MCP:

```text
sentinel_pipeline action=set_mode pipeline_id=<id> mode=freeze
sentinel_pipeline action=set_mode pipeline_id=<id> mode=normal
```

In the graph, each node header carries three buttons: `F` for Freeze, `B` for Bypass, and `P` for preview. The `F` and `B` keys toggle the same modes for the selected nodes, and `P` toggles their previews. Pressing a mode key on a mixed selection sets every selected node to that mode; pressing it again returns them to Normal. `Ctrl+Z` undoes a mode change as one step.

## What each mode does

- Freeze keeps publishing the node's last frame and skips its processing. Downstream consumers keep receiving that frame. A frozen StreamDiff stops generating; a frozen Module stops cooking.
- Bypass maps compatible inputs to outputs. A node with no compatible connected input shows why it cannot bypass in its status. Pure data sinks such as `dmxout` have nothing to pass through, so Bypass on them only stops the sender.
- A node that a Groups-mode Mux has not selected is held by the switcher rather than by its own mode. Mode buttons on those nodes wait until the group is selected or the switcher releases it.

## Frozen outputs persist

Frozen outputs save with the project as sidecar files next to it and restore byte-identical on reload, so a held look survives a quit and relaunch. Saving does not stall the render loop, and an unchanged frozen node skips its readback on later saves. Refreezing a node regenerates only that node's sidecar. Deleting a project's sidecars is safe; the node simply cooks live on the next load.

## When to use which

- Use Freeze to hold an expensive node at a good frame while you build around it, or to lock a StreamDiff look during a show.
- Use Bypass to audition a graph without one stage, or to route a source past a node that is not ready.
- Use the Scene Switcher, not per-node modes, to hold whole looks; it freezes unselected groups for you.

Prove a mode change the same way as any other state: read `operator_mode` back through `info`, then capture the node's output before and after with `sentinel_capture`.
