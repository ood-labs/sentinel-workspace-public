# Portable Scene Groups

A Scene Group can be exported as a standalone `.sentinel` project that carries its Modules, assets, and presets, then imported into another project as a switcher-ready group. The exported file is an ordinary project with an extra `sceneGroupExport` declaration, so older builds still open it as a plain project.

## Export

Over MCP:

```text
sentinel_graph action=export_scene_group entity_id=<group annotation id> path=<destination .sentinel>
```

In the UI, right-click the Scene Group annotation and choose `Export Scene Group`; Sentinel shows the boundary counts before the save dialog opens.

The export response reports every crossing: links that enter or leave the group, expressions that reference nodes outside it, entity-valued parameters that point outside, exposed targets, bind networks, and any source or output the group carries. Read that report before shipping the file. A group with zero crossings imports cleanly anywhere; a group with crossings imports with those crossings left visibly unresolved for deliberate repair.

## Import

Over MCP:

```text
sentinel_app action=import_project path=<file.sentinel>
```

`File > Import Project` and dropping a `.sentinel` file on the graph route through the same operation; a graph drop places the group under the pointer. Import validates the declaration first, brings the carried entities in through the clipboard path with fresh ids, then reconstructs nested Scene Groups from the complete id map. A Mux in Groups mode discovers the reconstructed group immediately.

Every carried source is created as a fresh copy with a collision-safe id, even when the destination already holds an identical one. The response names each such copy:

`Created a new copy of Camera 1; this project already has an identical source.`

Two capture nodes addressing one device will contend for it, which is the honest outcome; consolidate sources yourself after import. The response's `source_exact_match_definition` lists the fields compared per source type.

## Repair after import

Read `scene_group_import.boundary` in the response. Each unresolved link names the imported entity, pin direction, slot, and port. Wire inbound pins to the sources this show uses, connect outbound pins to their consumers, and confirm with `sentinel_graph action=list_links`. Broken expressions stay registered in their broken state so you can see what they referenced; set them again with `sentinel_expression action=set` once the referenced node exists. Partial bind networks are omitted from active binding and listed for the same reason.

The post-import summary in the UI lists the same items; selecting one focuses the live node and pulses the exact pin.

## Scene Group header controls

A Scene Group annotation's header carries a color swatch, an `A` enable button for the whole group, and, when a Groups-mode Mux collects it, a switch control that selects this group on that switcher. The header shows which group the switcher currently holds. Converting an annotation to a Scene Group and reverting it are both undoable.

## What travels and what does not

Group parameters, exposed controls, and group presets travel with the export. Project-level things do not: user input bindings, engine packs, external OSC configuration, and any node outside the group boundary. Every completed export and import appends one local line with a timestamp, action, and group id to `%APPDATA%/Sentinel/logs/portable-scene-groups.jsonl`; no project content leaves the machine.
