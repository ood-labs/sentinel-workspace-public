# AUTOPSIA
### *Instrument for the Dissection of a Living Signal*

Build target: Sentinel 0.5.48. All nodes authored fresh for this composition (`au_*`).

---

## 1. Concept

**A machine that hallucinates an organism, then dissects what it sees with its own eyes.**

`autopsia` (Gk. *autopsía*) — "the act of seeing for oneself." The composition is a closed
perceptual loop staged as a laboratory instrument:

1. A **specimen** is generated — a living reaction/flow field rendered as contour topography.
   It is not a test pattern; it is an authored organism with masses, membranes and fractures.
2. The instrument **observes** that specimen through the real `features` node, exactly as if the
   specimen were an unknown sample on a plate. Blobs, corners and lines are *findings*, not decoration.
3. Raw findings are noisy and flicker. A **stabilizer** performs temporal association and promotes
   them into persistent *agents* with stable identity, velocity, age and confidence.
4. A **topology planner** infers relationships between agents — confidence-ranked, distance-limited,
   degree-limited — producing the instrument's *hypothesis* about the specimen's structure.
5. **Renderers** re-inscribe that hypothesis onto the plate: constellation, relief engraving,
   accumulated memory strata, measurement annotation.
6. The operator **intervenes** — placing stimuli directly into the specimen through a viewport
   stylus — and the organism reacts, which changes the findings, which changes the hypothesis.

The loop closes. The instrument's own conclusions become visible structure that it then re-observes.

### Aesthetic contract
Technical monochrome scientific instrument. Black field. White and gray geometry, crisp thin
strokes. Contour lines, cells, quantization, registration marks, legible measurement overlays,
restrained typography. **One sparingly used warm amber accent**, reserved for *findings the
instrument considers significant* — never used decoratively. No cyan/magenta gradients, no neon
bloom, no glassy panels, no atmospheric haze.

### Motion language
Slow geological drift in the specimen; sharp quantized snaps in the annotation layer. Agents move
with critically-damped springs (`_shared/anim/anim.hlsli`), never linear lerps. The instrument
should feel like it is *thinking* — long observation, sudden conclusion.

### Interaction contract
Every authored control must cause an immediate, legible change that is better than a Properties
slider. Two interactive surfaces only:
- **Stylus** (viewport, on the specimen): direct spatial intervention — place/drag/erase stimuli.
- **Deck** (canvas panel): performance macros — compound XY pads and look recalls that move many
  parameters at once along curated creative axes.

---

## 2. Data contracts

Frozen early so producers and consumers stay aligned.

**`Stimuli`** (au_stylus → au_specimen) — 48B
`position:float2, direction:float2, radius:float, strength:float, age:float, mode:float, id:uint, flags:uint, pad:float2`

**`Agents`** (au_stabilizer → topology/renderers) — 64B
`position:float2, velocity:float2, scale:float, confidence:float, angle:float, age:float,
stable_id:uint, kind:uint, source_index:uint, flags:uint, aux:float4`

**`Edges`** (au_topology → renderers) — 48B
`a:float2, b:float2, weight:float, phase:float, distance:float, tension:float,
source_a:uint, source_b:uint, kind:uint, flags:uint`

**`Deck`** (au_deck → everything, via control_outputs) — macro scalars 0–1.

---

## 3. Build order — one semantic node at a time

Each node: author → `compile_check` → create → `place_relative` → link → poll compile →
inspect health/frames/schemas → `focus` + `open_window` → exercise controls → capture → only
then move on. A blank/constant/generic/illegible preview is a failure and gets fixed in place.

### Phase A — The specimen and the eye
| # | Node | Role |
|---|------|------|
| A1 | `au_specimen` | Generator. Living contour organism. Outputs Plate + Field. Consumes `Stimuli`. |
| A2 | `au_proxy` | Analysis proxy → 480×270, contrast-shaped so findings are meaningful. Own preview. |
| A3 | `features` | **The real Features node.** Blobs first, then corners, tuned one task at a time against `graph profile`. |
| A4 | `au_stabilizer` | Findings → persistent `Agents`. Temporal association, springs, hysteresis. |

### Phase B — The hypothesis
| # | Node | Role |
|---|------|------|
| B1 | `au_topology` | Agents → ranked `Edges`. Degree limits, distance limits, tension. |
| B2 | `au_plate` | Primary renderer: specimen relief + agent constellation + edge plexus. |
| B3 | `au_memory` | Accumulating strata — where agents have been. The instrument's chart recorder. |

### Phase C — The instrument's face
| # | Node | Role |
|---|------|------|
| C1 | `au_annotate` | Measurement HUD. Every number derived from live agent/edge state, attached to what it describes. |
| C2 | `au_stylus` | Viewport direct manipulation → `Stimuli`. Closes the perceptual loop. |
| C3 | `au_deck` | Canvas performance panel. Macro pads + look recalls → control outputs. |

### Phase B2 — **3D RELIEF HUD** (operator directive)

`au_relief`: raymarched 3D of the specimen as a heightfield, with agents as SDF
markers standing on it, presented as a technical multi-viewport HUD.

Camera contract (`knowledge/internal-camera-template.md`, non-negotiable):
- The module declares `features: [camera]` + `viewport.interactions: [camera]`,
  keeps `camera_ref` empty, saves Fly as default, and builds **every**
  camera-dependent ray from the injected `_InvViewProjMatrix` / `_CameraPos`.
- "Multiple viewpoints" is satisfied WITHOUT extra camera nodes: the main
  perspective view is the internal camera; the additional views are fixed
  **orthographic technical projections** (PLAN / ELEVATION / SECTION) drawn as
  inset panels, each also plotting the live internal-camera position and view
  cone as a marker. They are measured diagrams of the same world, not rival
  cameras. No `camera`/`camswitch` node is created.
- Proof required: operate the camera through real viewport input and capture
  visibly different viewpoints with geometry, relief and overlays staying aligned.

### Phase D — **EXPLORATION LOOP** (the long middle)

Standing operator directives for this phase:
1. **More analysis instrumentation in the histogram family.** The live luma
   histogram proved its worth; extend that language — distributions, running
   counts, rate meters, sorted rankings, residual/error plots, spectral or
   temporal readouts. Every one must plot real live state.
2. **Tie the instrumentation into the composition**, not bolted on. The
   histogram and its siblings become designed elements of the instrument's face,
   sharing the frame with the specimen and the hypothesis.
3. **Explore several distinct layer looks and composite them into new material**
   before wrapping up — do not settle on the first look that works.

Repeat until the composition is genuinely striking. Each iteration:
1. Capture the current program output; run `sentinel_vision eval_pipeline` for an honest read.
2. Name the single weakest thing about the image or the motion.
3. Invent **one new module** or one substantial rework that attacks it — a new analytical lens, a
   new inscription method, a new temporal behaviour, a new material response.
4. Author it, prove it, wire it in, keep it only if it demonstrably improves the piece.
5. Discard anything that reads as generic, redundant, or decorative.

Candidate directions to draw from (not a checklist — a well to draw from):
fracture/fault propagation seeded by corner clusters · spectral archive of agent history ·
parallax depth separation between hypothesis and specimen · engraved raking-light relief ·
orbital census of long-lived agents · quantized shutter/section cuts · anisotropic paper/plate
material · phase-locked measurement choir · dead-agent ossuary · registration drift and re-lock.

Exit criteria: vision eval reads as intentional and striking; motion holds up in a `sweep_record`;
nothing in frame is unexplained; the amber accent still means something.

### Phase E — Polish and hand-off
- Cull weak parameters and weak controls. Test every exposed control live.
- Wrap into a Scene Group with **4–8** curated high-impact controls (no camera params).
- Save node presets for the strong looks.
- `sentinel_graph auto_layout` as an explicit layout checkpoint, verify signal-flow order.
- `proof_bundle` + `checkpoint`; save `projects/autopsia/autopsia.sentinel` with bundled modules.

---

## 3b. BUILD STATUS — delivered

Nine authored nodes, all healthy, **6.7 ms** total frame, zero hotspots.

| Node | Role | Proof |
|---|---|---|
| `au_stylus` | viewport events -> `Stimuli` | bank verified; probe deposit visibly deforms the specimen |
| `au_specimen` | living cellular specimen | contour tissue + nucleation; controls verified |
| `au_proxy` | analysis lens + live histogram | candidate mask, nucleus top-hat separation |
| `au_observe` | **the real Features node** | corners = nuclei (~20), blobs = colonies; 3.1 ms measured |
| `au_stabilizer` | findings -> persistent `Agents` | stable ids, 12 s+ lifetimes, colony membership |
| `au_census` | measurement rack | population history ring, age dist, heading rose, ledger |
| `au_relief` | 3D raymarched instrument | internal camera, PLAN/ELEVATION/SECTION, agent pins |
| `au_grade` | 4-look compositor | linear-light composite, Register look selected |
| `au_deck` | performance macros | 3 compound pads + look bank, proven at both extremes |

**Known gap (honest):** the pointer/keyboard path of `au_stylus` and the pads of
`au_deck` are host-owned viewport controls. Their bindings publish correctly and
the full downstream contract is proven via the parameter-driven probe, but
delivering an actual mouse press requires a hand on the pointer — MCP cannot
inject one. Click either preview to focus it and the events flow.

**Two platform gotchas found the hard way (both fixed, both commented in source):**
- `type: button` parameters read as a constant `1.0` in HLSL no matter what the
  state tree says. Level-testing them makes the last button in the chain win
  forever; edge-detecting them fires everything once then freezes. The look bank
  now hit-tests real click gestures in `au_deck/state.hlsl`.
- Host `xypad` controls store Y increasing DOWNWARD. Flip it exactly once, at
  publish time, so "up = more" survives without mirroring the reticle.
  Draw all pad geometry in pixel space — `follow_panel` changes the aspect.

Camera contract: `au_relief` owns the only navigable camera (internal, Fly,
`camera_ref` empty). Verified by two visibly different viewpoints with geometry,
relief and overlays staying aligned. Operating it by RMB+WASD needs real input.

## 4. Proof criteria

- The real `features` node is in the live signal path and its findings measurably drive downstream
  geometry — provable by changing a specimen parameter and seeing the constellation reorganize.
- Every renderer node has a legible preview of its *own* state, not just the final image.
- Graph profile stays within an interactive budget; Features tuned one task at a time.
- Every on-screen number traces to real live state.
- Both interactive surfaces provably respond to real viewport input.
