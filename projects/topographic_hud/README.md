# Topographic Operations

Topographic Operations is a modular survey display built from a shared height field, three distinct transport lanes, editable data records, a cue-aware signal bus, and one Group Output. The original fifteen-node visual graph remains intact; the modernization adds only a Conductor and the final group endpoint.

## What to open

Open `topographic_hud.sentinel`. The complete graph lives in one flat `TOPOGRAPHIC OPERATIONS` Scene Group with no child groups. `Topo_Group_Output` is the sole final endpoint.

## Signal Canvas

Open `signal` to use the full-bleed **Topographic Operations Console**. The
Canvas is a live signal instrument: drag the broad **Performance Energy** and
**Performance Sweep** rails while watching the four transport lanes, resolved
layer meters, authority, cue, terrain, density, and energy readbacks respond.

Exact setup belongs in the node's Properties: Manual / Auto / Conductor
authority, the five cue looks, terrain, node density, palette, four layer gains,
master mix, and the pulse, sweep, beat, and beat-shape rates. Keeping those
ordinary scalar and enum controls in Properties leaves the Canvas focused on
the two gestures that are useful during a performance.

The console publishes sixteen control outputs. Expressions make that authority visible in the graph by driving terrain selection, field detail, node density, layer gains, node pulse, palette, and post color. Manual and Conductor modes are smoothed so changing authority does not pop the scene.

## Editable survey data

`node_gen` is the **Priority Node Editor**. Its first twelve nodes publish stable selection descriptors. Click and drag a highlighted priority node to add a durable 2D offset without changing the downstream node, link, or label data contracts.

`label_gen` is the **Survey Label Editor**. Its first twelve active labels are selectable and can be dragged independently after attachment to their survey nodes.

Both editors use host-owned picking and four-phase edits. Their offset and edit-state buffers persist through project saves, undo, and node presets. `node_gen` includes project presets **Priority Baseline** and **Priority Offset Study** to demonstrate state recall.

## Scene Group presets

- **Survey** — balanced blue contours with orange operational accents.
- **Threat** — denser, brighter warning-state activity.
- **Night Vision** — green-biased low-light survey treatment.
- **Minimal** — restrained grid and reduced information density.
- **Performance** — balanced lower-cost default with Conductor authority.

The group exposes eight stable scene-level controls for terrain frequency and octaves, grid and contour density, viewport radius, atmosphere density, bloom, and vignette. Signal Canvas controls are not duplicated there.

## Remix

Start from **Survey** when changing topology or labeling, **Threat** or **Night
Vision** when exploring palette and density, and **Performance** for the
documented lower-cost live default. Shape exact rates and layer balance in
`signal` Properties, then perform the result from the two Canvas rails. The
Scene Group's eight exposed controls remain the stable show-level surface; they
do not duplicate the signal node's setup parameters.

## Graph lanes

```text
field_gen -> contours / grid / node_gen -> compositor -> post -> Topo_Group_Output
                                       |       ^
node_gen -- Nodes --> link_gen --------+-------+--> label_gen
signal -- control outputs / expressions ---------> visual parameters
Topo_Conductor -- phase + energy ----------------> signal
```

Textures carry continuous images, structured buffers carry nodes/links/labels, and expressions carry scalar animation authority. Keeping those lanes distinct is part of the example.

## Runtime checks

All seventeen contained pipelines should be enabled and healthy. The three semantic data lanes must remain wired, both editors should report twelve selectable objects, and the Scene Group must contain exactly one Group Output. The lightweight graph profiler should report no unexplained hotspots.
