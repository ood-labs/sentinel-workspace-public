# Bundle Links: One Cable For Video Plus Data

A **Bundle** is one graph connection that carries a video texture plus any
number of named data and texture channels, all from the same cook of the same
producer. Use it when a look has more than a picture: a projector image and
the laser paths drawn with it, a video plus a matte, a render plus fixture
records. Scene Groups, Group Output and the Mux pass bundles whole, so when
the show switches looks, the projector and the lasers switch together and a
consumer never sees one look's image with another look's laser paths.

Bundles carry GPU data only. Signals, Events and control outputs stay on their
own cables.

Bundle pins draw as a double circle, and a bundle cable is thick with a
coloured core stripe. Hover a bundle cable to list its channels with their
keys, counts and a validity light. The node menu's **Bundle Channels** shows
the same list as a strip under a node's preview.

## Publishing a bundle from a Module

A Module declares `bundle_outputs` over outputs and data ports it already
has. HLSL does not change.

```yaml
bundle_outputs:
  - name: Laser Look
    video: Pixels
    channels:
      - {key: laser.a.scan, data: Scan Signal, header_records: 1, transition: {mode: handoff, at: mid}, neutral: empty}
      - {key: matte.person, texture: Matte}
```

- `key` is a dotted name unique within the bundle, such as `laser.a.scan`,
  `laser.b.scan` or `light.fixtures`.
- `header_records: 1` marks the Scan Signal header record, which is never
  blended.
- `transition` says how the channel changes when a Mux switches looks (below).
- `neutral` is what a channel shows when one side of a fade lacks it:
  `empty` (a valid empty signal), `zero`, or a per-field map such as
  `{dimmer: 0}`.

A Module can take a bundle with `bundle_inputs`, binding channels by key onto
its own inputs:

```yaml
bundle_inputs:
  - name: Look
    video: Input
    channels:
      - {key: laser.a.scan, data: World Scan}
```

Channels resolve by key every frame. A key with no matching channel shows
amber `(N unresolved)` on the pin and binds nothing.

## Nodes that make and break bundles

- **Bundle Pack** (`bundlepack`): one `Video` input plus up to eight rows, each
  an input pin named by its key. Use it to bundle outputs from nodes that are
  not Modules, such as Laser Trace's Scan Signal with the video it traced.
- **Bundle Split** (`bundlesplit`): a `Bundle` input, the video on `Out`, and
  one data output per key. Use it to feed a bundle channel to a node that is
  not a Module, such as one Laser Out per laser.

Plain cables also work where they make sense: a bundle into a plain video
input connects the video; a bundle into a data input binds the channel whose
key matches the input's name, so a Laser Out `Scan Signal` input takes
`laser.scan` straight from a Mux.

## Looks: Scene Groups, Group Output and the Mux

Build each look as a Scene Group whose Group Output takes the look's bundle on
its `Bundle` input. A Mux in Groups mode collects the groups wirelessly and
publishes the selected look's bundle on its `Bundle` output; a Mux in Wired
mode takes bundles on its inputs when **Bundle Inputs** is on. `laser_mapping_lab`
shows the whole pattern: three looks each publish a bundle (two Modules
publish a Laser Look directly, and Laser Trace's output goes through Bundle
Pack), the Look_Select Mux picks one, Bundle Split peels off `laser.a.scan` for the
mapping and Laser Out, and the video goes to the projector.

When the Mux fades between looks (`fade_time`), each channel follows its
transition:

| Mode | Behaviour |
|---|---|
| `crossfade` | GPU blend; the default for video and texture channels |
| `snap` with `at` (`start`, `mid`, `end`, or 0 to 1) | Switches the whole channel at that point; the default for data channels |
| `follow: <key>` | Switches on the same frame as another key |
| `handoff` with `at` | The outgoing side goes to `neutral` at the fade start and the incoming side appears at `at`; the right choice for laser paths |
| `lerp` | Interpolates record fields on the GPU, with `match: <field>` to pair records by id and per-field `lerp`, `snap`, `angle` or `htp` |

Laser paths should use `handoff` with `neutral: empty`: the outgoing path
blanks when the fade starts and the incoming one appears at `at`, and Laser
Out's protection bounds the first move. Never crossfade two laser paths.
Blend lighting as fixture-level records (`light.fixtures` with `lerp`) and
convert to DMX universes after the Mux; raw universes always snap.

Override a channel's policy on the Mux with its **Channel Policies** table in
Properties, or the `channel_policies` parameter as JSON, for example
`{"laser.a.scan": {"mode": "snap", "at": "end"}}`.

## Automation

- `sentinel_graph action=add_link` accepts Bundle pins by name; `list_links`
  reports a bundle link as one link with any `unresolved_keys`.
- `sentinel_pipeline action=info` lists bundle outputs and inputs with their
  channels; on a Mux it adds the resolved policies and any warnings.
- `sentinel_pipeline action=capture_data_port port_name="<bundle>/<key>"`
  captures one channel.
- `sentinel_graph action=auto_layout` can move nodes out of their Scene Group
  frames, and a Mux then shows `!` on those looks. When you build grouped
  looks by automation, place the nodes with `set_node_geometry` or
  `layout_neighborhood` instead.
