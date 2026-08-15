# Imported Mesh Workflow

Sentinel 0.5.59 and newer can import static OBJ, FBX, GLB, and glTF geometry
through the `meshsource` pipeline type. Mesh Source publishes canonical vertex,
index, and submesh buffers as one semantic `Mesh` output.

## Import and inspect

Discover the exact installed contract first:

```text
sentinel_pipeline action="list_types"
sentinel_app action="capabilities"
```

Create the source atomically with an absolute file path:

```text
sentinel_pipeline action="create" type="meshsource" name="Imported Mesh" file_path="C:/assets/model.glb"
```

Then inspect the returned id:

```text
sentinel_pipeline action="info" pipeline_id="Imported_Mesh"
sentinel_pipeline action="get_data_schemas" pipeline_id="Imported_Mesh"
```

Wait for healthy state and confirm non-zero vertex, index, and submesh counts.
Use the Properties controls when the source needs a uniform scale, Y-up or Z-up
conversion, inverted winding, recomputed normals, or a manual refresh.

## Consume one semantic Mesh cable

The normal graph is:

```text
Mesh Source: Mesh -> Renderer Module: Mesh
```

Start the renderer with `sentinel_module action="scaffold_from_ports"` or copy
the exact live schemas from `get_data_schemas`. Declare the three canonical
`data_inputs`, then group them:

```yaml
mesh_inputs:
  - name: Mesh
    vertices: "Mesh Vertices"
    indices: "Mesh Indices"
    submeshes: "Mesh Submeshes"
```

The graph exposes one atomic Mesh pin while the shader continues to bind the
three data slots. Wire by semantic pin name and place the new node visibly:

```text
sentinel_graph action="add_link" from_entity="Imported_Mesh" from_slot="Mesh" to_entity="Mesh_Renderer" to_slot="Mesh"
sentinel_graph action="place_relative" entity="Mesh_Renderer" reference="Imported_Mesh" direction="right"
```

Mesh Unpack is for specialized graphs that require separate raw vertex, index,
and submesh pins. Leave it out of ordinary imported-mesh rendering graphs.

## Save and prove

Save with `bundle_modules=true`. Sentinel copies referenced Module folders and
Mesh Source assets into the project bundle so project paths remain portable.
Reload the saved project and verify:

- Mesh Source is healthy with the expected counts;
- the graph contains one Mesh cable;
- the renderer has a live preview and increasing frame or cook evidence;
- `capture_data_port` returns canonical records when raw inspection is needed;
- `sentinel_graph profile` shows static Mesh Source and eligible static Modules
  settling to idle after import.

Use `execution: on_dirty` on a renderer or geometry processor only when every
pass is time-independent and the Module has no video input. Camera, parameter,
data-generation, viewport, resolution, and recompile changes wake an eligible
Module while its last valid output remains available.
