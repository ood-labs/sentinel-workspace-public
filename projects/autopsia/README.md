# AUTOPSIA

**A machine that hallucinates an organism, then dissects what it sees with its own eyes.**

A modular chain of nine authored nodes, built entirely from custom Modules. Load
`autopsia.sentinel` — all modules are bundled under `modules/`.

`autopsia` (Gk. *autopsía*) — "the act of seeing for oneself."

---

## Graph

```
au_stylus ──Stimuli──▶ au_specimen ──Plate/Field──▶ au_proxy ──Analysis──▶ au_observe
    ▲                                                    │                  [features]
    │                                                    │                      │
    └────────── the loop closes ─────────────────────────┘         Corners + Blobs
                                                                          ▼
                                              au_stabilizer ──Agents──▶ au_census
                                                    │                      │
                                                    ▼                      ▼
                                                au_relief ──────────▶ au_grade ◀── au_deck
```

| Node | Layer | Role |
| --- | --- | --- |
| `au_stylus` | INTERVENTION | Viewport events → `Stimuli`. Mass / incision deposits, plus an automatable probe |
| `au_specimen` | SPECIMEN | Living contour organism with jittered-lattice nucleation. Outputs Plate / Field |
| `au_proxy` | MEASUREMENT | 480×270 analysis lens + live luma histogram. Nucleus top-hat separation |
| `au_observe` | MEASUREMENT | **The real `features` node** — corners + blobs |
| `au_stabilizer` | MEASUREMENT | Temporal association → persistent `Agents` with stable identity |
| `au_census` | INSTRUMENT | Measurement rack: population history, age distribution, heading rose, ledger |
| `au_relief` | INTERPRETATION | Raymarched 3D relief on the internal camera + PLAN / ELEVATION / SECTION |
| `au_grade` | PRESENTATION | Four-look compositor in linear light, film response |
| `au_deck` | INTERFACE | Canvas panel: three compound macro pads + look bank |

## The loop actually closes

This is the point of the piece. The operator deposits a stimulus with the stylus →
the specimen swells around it → the analysis lens re-shapes it → **the real Features
node finds different things** → the agent population changes → the hypothesis,
the relief, the census and the final plate all change.

It is causal, not decorative: depositing a probe moved the largest measured finding
to 7357 px and visibly reorganised the constellation.

## The specimen is designed to be measurable

The first semantic node is an authored generator, never test imagery. A low-frequency
**occupancy envelope** decides where tissue exists at all, so the plate stays truly
black between specimens instead of becoming all-over terrain. Inside the tissue, a
jittered-lattice **nucleation** term creates discrete countable cells — fbm alone is
too smooth to resolve as individual masses.

The interior baseline is deliberately kept low. If the tissue floor sits near 1.0 the
cells clip into a flat plateau and merge back into one connected component; keeping
the floor down lets each nucleus stand as a separate peak.

## The two Features channels do different jobs

Testing proved the blob task resolves **regions**, not points — it would not fragment
at any threshold. So the channels are assigned semantically instead of fighting it:

| Channel | Finding | Typical count |
| --- | --- | --- |
| **Corners** | individual nuclei — point findings with response strength | ~20 |
| **Blobs** | colonies — macro territory, bbox, area | 2–4 |

Agents inherit **colony membership** by testing their position against the blob
bounding boxes, which is what links the two channels back together.

The analysis lens exists to make this possible: raw density welds touching cells into
one component, so the lens subtracts the local mean of the density at roughly one
nucleus radius (a top-hat), isolating each local maximum.

## Data-to-visual contract

| Measured | Drawn as |
| --- | --- |
| Corner, associated across frames | Persistent agent with a stable id that survives |
| Confidence ≥ threshold **and** sustained age | **Amber.** Reserved for findings the instrument considers established — a readout, never decoration |
| Agent age | Rotating tick on the agent ring; ledger ordering; pin height in 3D |
| Matched this frame vs. coasting | Solid ring vs. dashed ring |
| Velocity | Leader line; heading rose petal |
| Colony membership | Region boxes in plan; colony census bars |
| Specimen density | Terrain height in the raymarched relief |
| Operator stimulus | Amber measurement ring with tick marks and a radial leader |

## Interaction

Nothing here duplicates a Properties slider. Numeric shaping stays in Properties.

**On the Stylus preview** — LMB deposits a mass, RMB an incision, drag paints,
wheel sizes the deposit, `M` toggles mode, `X` clears. A live cursor shows exactly
what the next deposit will be.

**On the Deck panel** — three compound macro pads. Each axis moves several
parameters at once along a curated creative axis, so the extremes are genuinely
different pieces rather than nudges:

| Pad | X | Y |
| --- | --- | --- |
| FIELD | occupancy + mass scale | cell density + cell sharpness |
| RELIEF | relief height | contour bands + surface grid |
| PRINT | ghost gain + registration slip | layer mix + halation |

Plus a look bank: **Impression / Inspection / Register / Sectioned**.

Two project-scoped AU Deck presets provide recoverable starting points:
**Approved Register** restores the reviewed release balance, while
**Dense Relief Study** pushes all three macro pads toward a denser,
more dimensional interpretation. Recalling either preset changes only
the six macro-pad axes.

## Composite looks

| Look | Description |
| --- | --- |
| `Impression` | The rack bleeds into the relief's empty field |
| `Inspection` | A travelling band exposes the analytical layer, with a scan tear |
| **`Register`** | *(default)* Misregistered print — the specimen ghosts under the instrument |
| `Sectioned` | Interlaced strips interleave relief and analysis |

Compositing happens in **linear light**. Every input arrives already display-encoded,
so compositing those values and encoding again lifts the blacks twice and turns a
black-field instrument into flat grey.

## Camera

`au_relief` owns the only navigable camera — Sentinel's **internal** camera, Fly mode,
`camera_ref` empty, every ray built from the injected `_InvViewProjMatrix` / `_CameraPos`.

"Multiple viewpoints" is satisfied without any rival camera node: PLAN, ELEVATION and
SECTION are fixed **orthographic technical projections** of the same world, and PLAN
plots the live internal-camera station and its view cone so you can read where the one
real camera is standing.

## Instrumentation

Every mark in the rack is a reading of the live population — nothing is fabricated
telemetry. Population history is a real persistent 256-sample ring; the ledger names
the eight longest-surviving agents by their actual `stable_id`.

## Two platform gotchas found the hard way

Both are fixed and commented in source; they will bite any Module that uses viewport UI.

- **`type: button` parameters read as a constant `1.0` in HLSL**, whatever the state
  tree reports. Level-testing them makes the last button in the chain win forever;
  edge-detecting them fires everything once and then freezes. The look bank hit-tests
  real click gestures instead (`au_deck/state.hlsl`).
- **Host `xypad` controls are Y-up on both Canvas and Properties.** Publish the
  host value unchanged; only the value-to-pixel mapping accounts for screen Y
  growing downward. Draw pad geometry in **pixel** space — `follow_panel` changes
  the aspect.

A third, cheaper lesson: never `[unroll]` a glyph loop. It replicates the whole font
table per call site and the shader stops compiling in reasonable time.

## Performance

9 nodes, **~6.7 ms** total frame, no hotspots. The `features` node is the dominant
cost at ~3 ms; corners were first enabled at **14.7 ms** and retuned down. Features is
fed from a 480×270 analysis proxy, never the full-resolution plate.

## Status

This is the approved curated state. Captures and internal build notes are not
part of the public project; regenerate live proof from the saved graph when
validating a new Sentinel build.

## Component map

There is no external media source. `au_specimen` is the first semantic image
source, and the reviewed program output is the `au_grade` preview.

| Component | Type | Receives | Publishes or contributes |
| --- | --- | --- | --- |
| `au_stylus` | Module | viewport events | durable `Stimuli` records |
| `au_specimen` | Module | `Stimuli` from `au_stylus` | living Plate and Field textures |
| `au_proxy` | Module | Plate and Field | 480×270 analysis image and histogram |
| `au_observe` | Features | analysis image | corner and blob findings |
| `au_stabilizer` | Module | proxy plus Features records | persistent `Agents` |
| `au_census` | Module | `Agents` | population and distribution instrument |
| `au_relief` | Module | specimen, agents, and proxy | native-camera 3D relief |
| `au_grade` | Module | relief, census, and specimen | final reviewed program texture |
| `au_deck` | Module | authored Canvas gestures | macro control outputs and look selection |

Features is the only live analysis dependency and requires no engine pack.
Study the stabilization boundary and causal loop; invent new source, finding,
rendering, and interface semantics for a new project.
