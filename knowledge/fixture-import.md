# Fixture Import: GDTF and MVR

Sentinel reads GDTF fixture types and MVR scenes natively. A `fixturerig` node owns one rig: it imports an MVR or
starts empty, resolves every fixture type against a folder of GDTFs, and publishes the rig as data that Modules
draw and decode. The `sentinel_fixture` MCP tool inspects GDTFs and MVRs, edits a rig and exports it. Builds whose
`sentinel_pipeline action="list_types"` lists `fixturerig` carry it.

Discover the installed contract first:

```text
sentinel_pipeline action="list_types"
sentinel_app action="capabilities"
```

## GDTF files stay in a library folder

A rig references GDTFs by file in a library folder (`library_dir`); it never copies them on its own. Keep
manufacturer GDTFs outside anything you share or commit, and point `library_dir` at them. **Collect** copies the
GDTFs a rig uses into its rig document, for a show that has to open on a machine without the library; do that
only when the user asks for it, and never in a shipped example.

## Bring in an MVR

```text
sentinel_pipeline action="create" type="fixturerig" name="Rig"
sentinel_state action="set" path="/sentinel/pipelines/Rig/parameters/library_dir" value="C:/gdtf"
sentinel_fixture action="import_mvr" pipeline="Rig" path="C:/shows/rig.mvr"
sentinel_fixture action="validate" pipeline="Rig"
```

`import_mvr` reads the MVR into the rig document and waits for the report: fixtures and objects added, and the
embedded stubs it kept. `mode="merge"` adds the MVR to the current rig; the default `replace` refuses a rig that has
edits unless `confirm=true`. Setting the node's `source_mvr` parameter imports the same way; then wait for
`metadata.import_state` `Ready` in `sentinel_pipeline action="info"` and read `fixture_count`, `type_count` and
`problem_count`. Each
GDTFSpec resolves in order: a GDTF collected into the rig, a binding, the MVR's embedded GDTF when it is a full
type, a library file with the same name, then a library type whose manufacturer and name match. Visualisers often
embed stubs (a GDTF with no real channels); a fixture that resolves only to a stub counts as unresolved and is
named in the node's health reasons. When the library has the type under another name, bind it:

```text
sentinel_fixture action="bind_type" pipeline="Rig" spec="Clay Paky@Tambora Linear 100.gdtf" file="OGSON_fixtures@Clay_Paky_Tambora_Linear_100@ogi_v13.gdtf"
```

The reply lists the fixtures the binding resolved and any problems left. An empty `file` removes the binding.
`bind_type` records the binding in the rig document. The node's `type_bindings` parameter is a separate JSON map
(`{"<GDTFSpec>": "<library file>"}`) that applies when the node imports through `source_mvr`.

Depence writes a multi-break fixture as a host plus `_Generic` pixel and strobe engines; the node folds each engine
into the host's next open break. `sentinel_fixture action="scene" pipeline="Rig"` lists the fixtures with their
types, modes, breaks and stage mounts, and `action="validate"` lists problems (unresolved types and modes,
ambiguous matches, unfoldable engines, a missing break address, a break past channel 512, overlapping channels,
duplicate fixture IDs, a patch stride that suggests the wrong mode), each naming the fixture.

## Build or edit a rig

The node's document is editable. In Sentinel: the node window's plan selects, box-selects, drags, rotates (15 degree
handle), duplicates (Ctrl+D) and deletes (Shift+Delete) fixtures; Properties adds fixtures from the library browser
(hanging or standing), edits the selection's mode, patch and group, and auto-patches. Each gesture is one undo step.
Over MCP:

```text
sentinel_fixture action="add_fixtures" pipeline="Rig" type="Martin_Professional@MAC_One_Beam@20260710NoMeas.gdtf" mode="Basic" count=8 position=[-3.5,6,0] spacing=[1,0,0] mount="hanging"
sentinel_fixture action="edit_fixtures" pipeline="Rig" fixture_ids=[1] rotate_by=90
sentinel_fixture action="duplicate_fixtures" pipeline="Rig" fixture_ids=[1,2] offset=[0,0,2]
sentinel_fixture action="remove_fixtures" pipeline="Rig" fixture_ids=[9]
sentinel_fixture action="auto_patch" pipeline="Rig" start="1.1"
```

`rotation` sets a yaw in degrees and `rotate_by` adds one; `edit_fixtures` also takes `position`, `offset`,
`height`, `mode`, `patch`, `group` and `name`. `duplicate_fixtures` gives the copies fresh UUIDs and FixtureIDs and
auto-patches them (default `offset` [1,0,0] metres); `remove_fixtures` takes a folded bar's engines with it.
`sentinel_app action="capabilities"` gives each action's arguments. Reads through `pipeline` (`scene`, `validate`) see the rig the node last published, so an edit shows
there a few frames after its reply. Edits mark the project modified; the rig document saves beside the project as
`rigs/<project>/<node>.rig`. If the source MVR changes on disk the node shows `SOURCE CHANGED` and waits for
**Re-import**; it never re-imports an edited rig on its own.

## Export and collect

```text
sentinel_fixture action="export_mvr" pipeline="Rig" path="C:/shows/rig_out.mvr" engines="fold"
sentinel_fixture action="collect" pipeline="Rig"
```

Export writes a conformant MVR 1.6 with the GDTFs embedded (`engines="separate"` writes Depence-style engines).
It refuses the node's own source file and an existing file unless `overwrite=true`.

## Frames and addresses

`sentinel_fixture action="orientation"` shows how a fixture sits: the GDTF frame, the home beam direction, the pan
and tilt rotation axes with their senses, and the mount in the stage frame. Give it a GDTF `path` and `mode`, or an
MVR `path` with a `fixture_id` and `library_dir`. Check it before writing pan or tilt maths for a new type.

The stage frame is metres, +X audience right, +Y up, +Z toward the audience. MVR (millimetres, Z up, +Y upstage)
converts as `p_stage = A * p_mvr / 1000` with `A = [[1,0,0],[0,0,1],[0,-1,0]]`. GDTF draws fixtures hanging: +Z up,
the beam along -Z, pan about the yoke's Z, tilt about the head's X. Addresses keep MVR's numbering: universe U,
channel 1 to 512, 1-based. A DMX schema v2 port addresses universe U as Art-Net port address U - 1.

## Ports for Modules

Link the node's data outputs to a Module's `data_inputs` with matching schemas (`sentinel_pipeline
action="get_data_schemas"`):

- **`Fixtures`**: one 128-byte record per fixture. `axis_x`, `axis_y`, `axis_z` are the GDTF axes in the stage
  frame (home beam `-axis_z`), `origin` the GDTF origin in metres with w = index + 1 when active; `ids` holds type,
  mode, FixtureIDNumeric and UnitNumber; `dmx01` and `dmx23` hold universe and address per break; `meta` holds
  group, flags, MVR index and CustomId.
- **`SceneObjects`**: one 96-byte record per truss, support, scene object, video screen, projector or focus point:
  the same mount frame, then kind, group, parent, geometry reference and extents in metres.
- **`FixtureTypes`**: the rig's types as 16-byte rows (layout version 1): modes, breaks, channels, functions, sets,
  relations, geometry, wheels, emitters, cells, groups and media.
- **`FixtureRender`**: what the fixture engine draws each type with, derived from its GDTF and its refinement as
  16-byte rows (layout version 1): engine modes and channel tables, emitters with photometry, bodies, faces, cells,
  pan and tilt, and each type's status (renderable, blocked or over an engine cap).

The decode includes read these ports on the GPU. Copy `tools/templates/module-includes/fixtures/` into the Module
(Module includes resolve against the Module's own folder) and include, in order:

```hlsl
#include "gdtf_attributes.hlsli"
#define GDTF_FIXTURES _Data0     // the data input linked to Fixtures
#define GDTF_TYPES _Data1        // the data input linked to FixtureTypes
#include "gdtf_rig.hlsli"
uint GDTF_READ_BYTE(uint universe, uint address) { /* read the DMX byte, universe as MVR numbers it */ }
#include "gdtf_decode.hlsli"
```

`gdtfTablesValid()` checks the layout, `gdtfFixtureDecodable(f)` a fixture, and `gdtfFixtureState(f)` returns its
dimmer, pan, tilt, zoom, colour, shutter, CTO, CTC, colour wheel slot and strobe rate; `gdtfAttribute(f, attr,
cell)` decodes any attribute and `gdtfColour(f, cell)` and `gdtfCellIntensity(f, cell)` work per pixel cell. A new
GDTF type needs no new shader code.

`tools/templates/fixtures/rig_probe/` is a complete Module built this way: link `Fixtures` (slot 0),
`FixtureTypes` (1), a DMX port (2) and `SceneObjects` (3), and it draws any rig in a plan and a front view, with
body boxes from the GDTF models and beams posed, coloured and lit from the decoded DMX. Copy the folder into the
owning project as is; it carries its own copies of the includes.

## Render any type: the fixture engine

`tools/templates/fixtures/fixture_engine/` is the workspace fixture engine's four Modules (FE_Rig, FE_Console,
FE_Decode, FE_Renderer) with their shared includes. Added to a project beside a Fixture Rig node and linked as its
README lists (`Fixtures` to FE_Rig, `FixtureRender` to all four), they draw every fixture of the rig from its GDTF: a
type dragged from the Library browser onto the plan renders within a second, with no per-type code and no recompile,
and FE_Console drives it with looks over DMX.

## Refining a type

Every type the node reads is graded in a readiness report: Blocked (it cannot draw), Generic (it draws on the generic
rules, with open warnings), Refined (each warning corrected or accepted) or Verified (a refined type checked against a
named reference). `sentinel_fixture action="inspect" pipeline=<rig> type=<type>` shows the tier and the warnings; the
Library browser shows the tier on each tile. A **refinement** fixes what the report flags without touching the GDTF:
one JSON file per GDTF, `<sha256>.json`, in the node's `refinements_dir` or the library's `refinements/`, each
override an address, a value, a reason and a source. `sentinel_fixture action="refine"` writes it (`op` set, remove,
accept, verify, carry; `dry_run` lists every value an override changes), and the node applies it within a second with
no recompile. `inspect` with `detail="addresses"` lists what can be addressed and each field's current value, and
`detail="refinement"` lists the overrides with their reasons. The `fixture-refinement` skill is the workflow: read the
report, gather the manufacturer's public documents, answer each warning, check, report.

## Comparing types

`sentinel_fixture action="diff" a=<.gdtf or .json> b=<.gdtf or .json>` compares two types mode by mode: channels,
order, slots, resolution, defaults, functions, physical ranges and pan and tilt senses, each with a severity.
`action="export_type"` writes a GDTF as normalized JSON (`sentinel.gdtf-type`), the format a hand transcription
can be written in for the same comparison.
