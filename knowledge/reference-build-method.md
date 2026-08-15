# Reference Build Method

Use this when the job is **build an ambitious specific thing, from scratch, in one pass** —
a reference image, a described composition, a "make me X" brief.

This is a different mode from `knowledge/creative-exploration-goals.md`, which evolves an
existing project indefinitely. Here there is a target, the graph starts empty, and the run
ends with a saved, proven show.

Worked examples, each strong in a different place — read the README of whichever is closest:

| Project | Read it for |
| --- | --- |
| `projects/matik_plate/` | the applied form of this method end to end |
| `projects/sunward_corridor/` | a scaffold **tailored** to its subject: plan-over-elevation, path scrub, a correctness readout |
| `projects/soft_vitrine/` | editing flexibility, and a coordinate randomiser that still composes |
| `projects/vitreous_cross/` | a **relational** randomiser, and quality as a shipped preset ladder |

---

## 1. Inventory before you build

Before writing any code, produce five things in the response:

1. **A complete element inventory of the reference.** Every distinct visual family, not a
   summary. Missing a family early is what forces a rewrite late.
2. **The node decomposition.** Name every node and its one responsibility.
3. **The data contract.** The record structs and which node owns each.
4. **The scaffold's projection.** What a draughtsman would draw for this subject, and why one
   view is or is not enough (§2.5).
5. **What a re-roll means.** Which arrangement handles exist, and whether this subject's
   identity is positional or relational (§3).

Do this even when the user did not ask for a plan. The cost is one message; the cost of
discovering the layout authority after building three renderers is the whole build.

Items 4 and 5 are on this list because both are cheap to decide now and expensive to retrofit:
a second projection is one more strip while the schematic is being written and a rewrite
afterwards, and a randomiser that has to preserve relationships wants a parent tree transcribed
at the same time as the positions.

State the archetype out loud (see `modular-scene-authoring`). **Hybrids are normal** — a
dense collage of technical panels plus organic 3D masses is a routing problem *and* an
organic problem. Unify hybrids under one record buffer with a `role` discriminator rather
than running two parallel contracts.

---

## 2. Elect a single plan authority

**One node owns placement. Every other node derives from its records and never re-decides
them.**

This is stronger than "one layout transform at the generator". The transform rule prevents
drift; the authority rule is what makes the finished graph *expressive* — because every
question about "where is anything" has exactly one answer, rearranging becomes a property of
the system rather than a feature you have to build.

Consequences to hold onto:

- Downstream nodes read plate/scene space straight off `uv` or off the records. They apply
  no global offset or scale of their own.
- Anything derivable from the records is derived, not published as a second lane. See the
  coverage rule below.
- The authority's preview becomes the diagnostic surface for the entire system. Invest in it.

Build the authority **first**, in signal-flow order. It is usually not the fun node.

---

## 2.5 Design the scaffold for the subject

**The plan authority is a contract, not a template.** Four things are fixed: single authority,
persistent records, direct manipulation, an honest preview. Everything else — the projection,
the verbs, the readouts — is a design problem you are expected to solve freshly for each
subject, and it is where most of the expressiveness of the finished tool comes from.

The failure to avoid is reflexively reaching for "a plan node that draws a front elevation with
click-select and drag-move". That is one good answer. It became the default because it fits
frontal collages, and it silently becomes the wrong answer the moment the subject is organised
along an axis that a front elevation cannot show.

**Ask what a draughtsman would actually draw for this thing.** Then build that.

| If the subject is organised by… | The scaffold probably wants… |
| --- | --- |
| a frontal arrangement on a plane | one elevation (the classic case) |
| depth or height that carries the composition | two orthographic strips sharing an axis — plan over elevation |
| extent along a path or tunnel | a section scrubbed along that path, plus a route diagram |
| time, cues, or sequence | a timeline with the records on it |
| connection, flow, or dependency | a network/graph view, not a spatial one |
| a repeating period | one period drawn once, with the wrap marked |

`projects/sunward_corridor/modules/SC_Plan` is the bar for tailoring. Its preview is a
draughtsman's **plan over elevation sharing one z axis** — the plan strip owns lateral drift,
the elevation strip owns rise, and the *same handle* edits both, which is how you draw a
corridor on paper rather than two sliders that disagree. It also carries a correctness readout
the renderer cannot give you: the flight axis drawn as a dashed line that **turns red where it
leaves the tunnel**, so a corridor bent through its own wall is visible in the diagram instead
of being discovered later as a black frame.

Two things to steal from that, whatever you are building:

- **A second projection costs one more strip and pays for itself immediately.** If one view
  cannot show the axis the subject is organised along, the scaffold is hiding its own subject.
  Adding a top view to a front elevation is cheap; discovering that depth was unreadable after
  building three renderers is not.
- **Put the failure mode in the diagram.** Whatever "this arrangement is broken" means for this
  subject — self-intersection, leaving the frame, a gap in a run, a mass outside its container —
  draw it. A scaffold that can only show what *is* is worth less than one that shows what is
  *wrong*.

State the projection choice and its justification in the response before building it, the same
way you state the archetype.

---

## 2.6 Elements must be constructed, and they must belong to something

Two failures look identical from the outside — the work reads as "random" and "lacking
intention" — and they have completely different causes. Diagnose which one you have before
touching anything, because the fix for one does nothing for the other.

### The element itself has no construction

A shape built from a single primitive with one flat fill reads as a blob no matter how good
the silhouette is. Round-capped tapers are the usual culprit: a capsule with a small end
radius is a lozenge, and no amount of tuning makes it a horn.

Whatever else varies, a form has to answer three questions, and a variant that cannot answer
all three is a silhouette rather than a form:

| | |
| --- | --- |
| How does it **meet** its neighbour or host? | a flange, a root chord, a plain cut — never nothing |
| How does it **carry** its length? | a ridge splitting two values, ribs, rings, segments |
| How does it **end**? | a hard point, an open mouth with a visible inner wall, a flat cut face |

Find the elements in the composition that *already* read as objects and ask what they have
that the others do not. It is almost never a more interesting outline — it is an edge
condition and an interior. A ridge dividing two flat values, or a frame with a rim and an
inside, does more than any amount of added detail.

Two corollaries worth knowing in advance:

- **Articulation beats features.** A figure that melts into one mass gets read through its
  face, which is why it reads as "a box with a face attached". Flat-ended members between named
  joints, with the joints *drawn*, make a body legible at forty pixels. Track the nearest and
  second-nearest member and stroke the gap between them: that draws every joint in one pass
  without enumerating any of them.
- **Give each variant its own proportions before you call it a variant.** Drawing one aspect
  ratio for every archetype and calling the difference `kind` is how N archetypes collapse back
  into one blob with decorations.

### The elements are fine but belong to nothing

If placement is a ray from a centre to a hull, that is *scatter with a direction*. Every
element is attached to the mass and none is attached to any other, and no arrangement of
independently-placed elements reads as intentional however well each one is drawn.

Two levers, in this order:

1. **An angle family.** Snap headings to a shared step (90/45/30), with a phase offset so the
   family is not aligned to the frame. Snap **last** — after the transcription blend and the
   variation blend, because the average of two snapped angles is not snapped — and snap
   **again** before anything is derived from the heading, or an element attaches on one bearing
   and points down another. Apply it to every family that leaves the same hull; a family that
   covers half the elements is not a family.
2. **An armature.** A small set of curves derived from the mass, along which elements are
   *strung* rather than sprinkled, with stratified stations so they read as a sequence. Take
   each element's heading from the run's tangent and the motion follows for free — a
   travel-along-own-heading entrance archetype then runs along the armature without the motion
   system being told armatures exist.

Both must be **derived from the mass** (its own long axis, its own bounds) so the structure
turns with the architecture instead of staying pinned to a screen direction. Draw the armature
in the plan's diagram, rebuilt from the same records the layout measured rather than from a
published copy — and give it **no seed**, so the diagram can reconstruct exactly what the
layout used. If a structure needs the generator's salt to be drawn, it is not a structure.

Counter-intuitively, draw it **heavier and brighter** than the record hairlines. The
construction-line instinct is to recede, but a skeleton at hairline weight is
indistinguishable from the hundred outlines it exists to explain.

---

## 3. Generate, then override

**The plan authority is a direct-manipulation editor. This is the default, not an option.**

Build it that way unless the user has explicitly said they want a fixed non-interactive
image. "The brief was a picture, not an editor" is **not** a reason to skip it — a plan you
cannot click is a dead end the moment the user wants the composition changed, and changing
the composition is the whole reason the plan authority exists.

**It must produce a complete, good result procedurally, and let interaction override
individual records on top of it.**

- The node is useful and unbroken from the first frame, before anyone touches it.
- Global parameters keep working after hand edits, because edits are deltas, not a
  replacement authoring model.
- "Re-roll this one record", "turn this one off", "cycle this one's kind" become trivially
  expressible, because a record already exists to mutate.
- Persistence stays cheap and meaningful — only the deltas matter.

The failure mode this replaces is the empty editor: a node that renders nothing until the
user authors everything by hand, and whose global controls fight the hand edits. The *other*
failure mode — the one that is easier to ship by accident — is the **opaque plan**: a node
that generates a good composition and then offers nothing but a seed and a variation slider.
It looks finished and it is not.

### When this applies

Whenever the build has **an arrangement worth randomizing or exploring** — which is most
reference work — it gets a plan authority, and that plan authority is manipulable. A plan
whose entire interface is a seed and a variation slider is an **opaque plan**: it looks
finished, and the first time anyone wants *that one element* moved, the system has nothing
to offer.

### The bar, not the template

`projects/soft_vitrine/modules/VT_Plan` is the benchmark. Read it before authoring a new plan
authority — not to clone its record layout or its keymap, but because it is the clearest
example of the bar being cleared: every element reachable and changeable, exploration cheap,
and a randomizer whose draws still read as compositions rather than scatter.

**Design the verbs for the subject.** VT_Plan cycles kind and material because its cast is
kinds and materials; a typographic plate might want to cycle weight and alignment, a
lighting rig to cycle beam shape. Pick the two or three properties that actually define an
element in *this* reference and make those the edits. Click-to-select and drag-to-move are
close to universal; past that, invent what fits.

What is **not** negotiable, because these are correctness properties rather than style:

- **Persistent records.** A `state_buffers` set so edits survive cooks, saves, presets, undo.
- **Signature-driven regeneration.** Structural parameters only (see below).
- **Selection stored once.** Derive every "am I selected" test from that single value rather
  than mirroring a flag onto records and keeping the two in sync.
- **Pick in the same space you draw in.** If the preview and the hit test derive their
  coordinates independently they will disagree, and it will look like a maths bug.
  Smallest-hit-wins, so a small record resting on a large one stays reachable.
- **A preview that shows editor state** — what is selected, what has been hand-edited, what
  has been switched off.
- **Randomness that still composes.** Stratify placement and preserve the size hierarchy so
  a random seed reads as a composition. `variation = 0` should be exactly the transcribed
  reference, so it can never be lost.

Implementation shape:

```
persistent buffer of resolved records + one editor header record
  signature = hash(all STRUCTURAL parameters + algorithm version + reseed salt)
  if (never initialised || signature changed) -> regenerate everything, clear selection
  else                                        -> keep the buffer, apply this frame's edits
  then, every cook: refresh appearance-only fields in place (they must not force a rebuild)
```

Regeneration must be signature-driven, not unconditional, or edits die every cook. Keep
pure-appearance parameters *out* of the signature and republish them each cook instead, or
every colour tweak wipes the user's layout work.

### Randomise relationships, not coordinates

Decide what a re-roll *means* while you are still inventorying — it is a layout-time design
decision, not something to bolt on after the renderer works. Name the exploration handles
alongside the node decomposition and the data contract.

Then ask the question that decides the whole design:

> **What relationships make this the thing it is?**

If the honest answer is "none — these are objects arranged on a plane", randomise coordinates.
Stratify the draw, preserve the size hierarchy, and you are done; that is `VT_Plan`, and it is
correct there because a vitrine full of objects genuinely is a scatter.

If the answer names **interlocking, containment, attachment, adjacency, periodicity, or
support**, then coordinates are not what the subject is made of, and drawing them fresh per
record destroys exactly the relationships that make it recognisable. It does not look like a
different arrangement of the same thing; it looks like debris. `vitreous_cross` is a worked
case: a first randomiser drew stratified coordinates for every record and produced bubbles
floating in open air with no glass to lens them, plates detached into space, and volumes that
no longer touched — from code that was, considered per record, perfectly reasonable.

The fix is to randomise each family **against what it actually depends on**:

```
volumes      attach to a PARENT volume, at an offset drawn to guarantee shared solid
inclusions   hosted INSIDE a volume, in groups, radius derived from that volume's extent
plates       hosted INSIDE a volume, extent derived from that volume's face
```

This is the same rule as §4 — derive a magnitude from the upstream record rather than from a
parallel parameter — applied to the randomiser instead of to the renderer. The upstream record
is just the parent element.

Transcribe a **parent tree** from the reference at the same time you transcribe positions. Then
`variation` can lerp each child's *attach offset* from "exactly where the reference put it" to a
free draw, and stay continuous and valid the whole way, with `variation = 0` still exact.

### Guarantee the draw; do not hope for it

A relational randomiser needs explicit guarantees or it fails in ways that look like bugs.
Every one of these was added to `vitreous_cross` because a seed looked broken without it:

| Guarantee | Without it |
| --- | --- |
| Draw attach offsets **below** the touching distance | elements drift apart; the cluster is pieces |
| Clamp **both** ways — out *and* in | clamping only outward lets a small child sit concentric inside a big one and vanish |
| Bias the parent draw toward the root | a transcribed tree is usually a chain, and a chain with random directions grows a straggling procession that walks off frame |
| A **fit pass**: measure the result, apply one uniform similarity transform to recentre and zoom into frame | growth produces a valid cluster but says nothing about where it ends up or how big it is — the single most common way a seed looks broken. Run it *before* dependent families so they inherit the framing free. Uniform, so no proportion changes. |
| Temper extremes toward the record's own mean | the reference's most slender elements read only because the transcribed arrangement packs things across them; a random draw does not, so slivers read as wire |
| Cap a contained family's scale against its container | the mass swallows the container and the composition stops being what it was |

Gate every correction on `variation > 0`. The transcription is valid by construction, and
running a clamp over it will nudge records off their transcribed coordinates — which quietly
breaks the "`variation = 0` is exactly the reference" promise. Verify that promise by reading
records back and comparing against the tables, not by eye.

### Derived records follow their parent

When one record's placement derives from another (chips on a plate, leaves on a branch),
dragging the parent must carry the unedited children with it, while children the user has
hand-moved keep their own position. That is what the per-record `edited` flag is for.

### A generated family is still just records

Some families are cheaper or better to *generate* than to draw — a photoreal hand, a carved
profile, a real leaf. That does not exempt them from the authority rule. Route the generator
through a stamp node that reads the plan's records, so the generated plate supplies **pixels
only** and never decides its own position, size, lean, or side of the depth plane. Done that way
a family's drawn and generated versions occupy identical records, the compositor cannot tell them
apart, and one gain crossfades between them — which also means the drawn version stays as the
fallback when a generation comes back wrong.

The generator-side craft — why to generate photoreal on black even for a drawn look, why prompt
lighting words decide mattability, why exposure must be measured rather than tuned, and the
feedback hygiene that stops held stills degrading — is in `knowledge/streamdiff.md`
("Generated Subjects In An Authored Composition").

### You will not be able to machine-prove the gestures — build them anyway

Injected input does not reach Module viewport events, so click/drag/key paths generally
cannot be verified over MCP. **This is a reporting obligation, not a reason to omit the
feature.** Build the full gesture set, verify everything reachable (buffer persistence,
signature behaviour, pick maths against known record coordinates, the preview's selection
readout), then say plainly which gestures the user needs to exercise by hand.

---

## 4. Derive magnitudes from upstream records, never from a parallel parameter

If a downstream node needs a size, a spacing, or an extent that *relates* to something an
upstream node already decided, compute it from the upstream record geometry.

Worked case: the organism grower sized its trees from the reserve radius the plan authority
had already cleared for them. One control then moved the clearing, the growth, and the panel
layout coherently.

The alternative — giving the downstream node its own independent size parameter — produces
two numbers that must be kept in agreement by hand, forever, and that silently disagree at
every setting the author did not personally test.

---

## 5. Coverage and masking authority

Masks have the same single-authority problem as placement.

- **Derive the mask from the records** wherever the records determine it. A compositor that
  recomputes panel coverage from the same records the panels were drawn from cannot drift
  out of registration with them.
- **Publish a real coverage lane only where colour genuinely cannot carry the information.**
  An opaque black shape on a black background is indistinguishable by colour; that needs its
  own lane.

Do not smuggle coverage into a colour lane's alpha to avoid adding an output. It makes the
node's own preview read wrong, which violates the honest-preview contract.

---

## 6. Exploration as shipped presets

When exploring alternatives, **do not build throwaway variants**. Build the exploration axis
as a permanent `enum` parameter on the node that owns it, then:

1. Sweep it and capture each value.
2. Judge from the images and pick a winner.
3. Bake the winner as the manifest default.
4. **Repair the losers instead of deleting them.**

Exploration cost converts directly into product features, and the user keeps every direction
that was investigated. A preset that lost on this reference is often the right answer for the
next one.

Record the verdict and the reasoning in the project README so the next agent does not repeat
the search.

Two to four axes is the useful range. Good axes change structure (layout strategy, mesh
style, growth mode). Palette and grade are not exploration axes.

### The transcription is the floor, not the ceiling

Matching the reference is the point at which the interesting work *starts*, not the point at
which it stops. Once it is transcribed, proven and saved — so the match can always be recovered
— push past it. The randomiser and the arrangement enums exist partly for this: they are the
cheapest possible way to find out what else the system you just built can do.

The order matters. Explore *after* the reference is locked and recoverable, never instead of
reaching it, and never so far that the saved default drifts off the brief. `variation = 0` and
the baked manifest defaults are what make the exploration free — you can go anywhere because
you can always come back.

### A preset is not a handle

A shipped `enum` answers *"which of these arrangements do you want?"*. It does not answer
*"less of that one"*, and when a user asks the second question, offering the first again is
not a smaller version of the right answer — it is the wrong kind of control.

The tell is a user asking for the same thing more than once while presets keep arriving. When
you hear "I want to reduce", "get rid of", "how much of each", "as X as possible", the ask is
a **continuous weight per category**, and it should compose with the presets rather than
replace them:

- Define a small set of categories over the vocabulary — four is usually right. Nine variants
  is too many to give one handle each; four axes is what somebody actually reaches for.
- Make the weights **multiply** whatever the preset chose. At 1.0 across the board the preset
  behaves exactly as authored, so nothing that already worked changes.
- Implement it as **rejection and redraw**, not by reweighting the table. A cast table is a
  fixed sequence, and the only way to honour "none of these" against a fixed sequence is to
  refuse the draw and take another from the categories still wanted.
- Give the *degree* its own control alongside the *share*. "Fewer curved ones" and "less
  curved" are different requests, and a vocabulary is only steerable when both exist.
- Never let a muted set produce an undefined result. If every weight is zero the element still
  has to be something — fall back to the most neutral category.

### A design control must reach the setting the work ships at

A parameter that only takes effect once a layout is being generated is unreachable at
`variation = 0`, which is exactly where a transcribed reference sits. This bites twice in a
normal build — once when a structural control is folded into the variation blend, and once
when an explicit design choice is gated behind the same randomness it is meant to override.

The rule: **randomization controls may key off `variation`; design choices must not.** Give an
explicit choice its own axis, defaulted so the transcription is unchanged, and let it apply at
every variation including zero. `pink_monolith` has two of these — `armature_pull` and
`blade_cast` — and both were initially wrong in the same way.

---

## 7. Judge from the image after every change

Capture and actually look after every material edit. Do not reason your way to a fix.

Structural systems typically need several wrong iterations before they are right, and each
wrong one is diagnosable from a single capture in seconds and nearly undiagnosable from
theory. In the worked example the growth model took four attempts:

| Symptom in the capture | Cause | Fix |
| --- | --- | --- |
| Clusters collapse into knots | bond length followed radius decay geometrically | constant bond length, radius tapers then holds |
| Clusters fuse into featureless balls | children scattered back across the parent | outward direction persistence |
| Clusters march off the canvas | unconstrained persistence | soft containment steering inside the reserve |
| Clusters grow one-sided | root inherited a default up-vector | distribute first generation evenly on a sphere |

None of these were visible from the code. All were obvious from the picture.

---

## 8. Converge and hand over

Before reporting done:

- **Bake tuned values into the manifests** (`sentinel_module action=bake_defaults`) so the
  saved project reopens in the state you tuned, not in the state you first guessed.
- **Ship narrow-scoped node presets.** A preset that saves everything is a snapshot; a preset
  that saves one concern is a tool. Save to project scope with an explicit `params` list.
  - **A frame contract** on the renderer, camera parameters *alone*. The internal camera is
    meant to be flown, so the composed pose is lost the first time anyone explores it and is
    recoverable from nothing else in the project. Save it as soon as the pose is chosen — not
    at the end, by which point it may already be gone.
  - **A quality ladder** on any heavy node, quality parameters *alone* — Draft / Live / Beauty /
    Hero. Bake a rung you can comfortably work in as the manifest default; never the top one.
    Make the top rung explicitly capture-only, because past some cost a setting stops being slow
    and starts making the whole application unusable, which is a worse failure than looking
    slightly worse. Prefer buying quality along the axis the *image* is about rather than
    reflexively supersampling: for a dispersive subject, two more wavelengths beat four times
    the rays at a sixth of the cost.
  - Measure every rung **in one sitting** and publish the numbers as ratios. Identical presets
    measured 3–5× apart in this workspace depending only on how many node previews were open;
    a number quoted without its conditions is not a measurement.
- Save with `save_project bundle_modules=true` so the show travels with its Module files.
- Curate the Scene Group surface to 4–8 high-impact controls and **test every one through
  the group path**, confirming it reaches the member parameter.
- Profile the graph and confirm every node is healthy with frames advancing.
- Write a project README covering the route, the contracts, the traps, and the exploration
  verdicts.
- Produce proof: a final capture, a motion clip if anything animates, a proof bundle.

**Report what you could not verify.** Injected input does not reach Module viewport events,
so an authored click/drag/key path usually cannot be machine-proven — say so plainly and say
what the user needs to exercise. An honest gap costs nothing; a silent one costs trust.

---

## 9. Momentum

Work the visible one-node-at-a-time cycle continuously without asking for approval between
nodes. The contract is *visible incremental construction*, not stop-and-confirm gating. Ask
only when two readings of the brief would produce materially different work.

Do not narrate options you are not going to take. Choose, build, capture, judge, continue.
